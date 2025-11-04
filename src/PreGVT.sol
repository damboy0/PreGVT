// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title IGenesisBadge1155
 * @notice Interface for Genesis Badge contract
 */
interface IGenesisBadge1155 {
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function redeem(uint256 id, uint256 amount) external;
    function redeemByOperator(address owner, uint256 id, uint256 amount) external;
}

/**
 * @title PreGVT
 * @notice Non-transferable pre-token for badge-gated airdrops with presale
 * @dev Implements formal airdrop reserve with badge-gated claims and public presale
 */
contract PreGVT is ERC20, AccessControl, Pausable, ReentrancyGuard {
    // ============ Roles ============

    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant MIGRATOR_SETTER_ROLE = keccak256("MIGRATOR_SETTER_ROLE");
    bytes32 public constant PRICE_MANAGER_ROLE = keccak256("PRICE_MANAGER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    // ============ Immutable State ============

    /// @notice Genesis Badge contract address
    IGenesisBadge1155 public immutable badge;

    /// @notice Badge ID required for claims
    uint256 public immutable badgeId;

    /// @notice Maximum tokens that can ever be minted from airdrop reserve
    uint256 public immutable airdropReserveCap;

    /// @notice Maximum tokens that can be sold in presale
    uint256 public immutable presaleSupplyCap;

    /// @notice Payment token (USDT) address
    IERC20 public immutable paymentToken;

    /// @notice Treasury address for receiving funds
    address public immutable treasury;

    // ============ Mutable State ============

    /// @notice Total tokens minted from airdrop reserve
    uint256 public airdropReserveMinted;

    /// @notice Total tokens sold in presale
    uint256 public presaleSold;

    /// @notice Preloaded allocations per user (Pattern B)
    mapping(address => uint256) public claimable;

    /// @notice Migrator contract address for GVT conversion
    address public migrator;

    /// @notice Whether migration to main token is enabled
    bool public migrationEnabled;

    /// @notice Price per token in wei (e.g., 0.01 ETH = 10000000000000000)
    uint256 public pricePerToken;

    /// @notice Whether presale is active
    bool public presaleActive;

    /// @notice Whether badge is required for purchasing
    bool public badgeRequiredForPurchase;

    /// @notice Per-user purchase limit (0 = no limit)
    uint256 public perUserPurchaseLimit;

    /// @notice Track user purchases for limit enforcement
    mapping(address => uint256) public userPurchases;

    // ============ Events ============

    event AirdropReserveDefined(uint256 cap);
    event AirdropDistributed(address indexed to, uint256 amount, uint256 newTotalMinted);
    event BatchAirdrop(uint256 indexed count, uint256 totalAmount);
    event BadgeConsumed(address indexed user, uint256 indexed badgeId, uint256 amount);
    event MigrationEnabled(address indexed migrator);
    event Migrated(address indexed user, uint256 preGVTAmount);
    event AllocationSet(address indexed user, uint256 amount);
    event PresaleConfigured(uint256 pricePerToken, bool badgeRequired, uint256 perUserLimit);
    event PresaleStatusChanged(bool active);
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost);
    event PriceUpdated(uint256 newPrice);
    event FundsWithdrawn(address indexed to, uint256 amount);

    // ============ Errors ============

    error TransferNotAllowed();
    error ApprovalNotAllowed();
    error ReserveCapExceeded();
    error NoBadge();
    error NoAllocation();
    error InvalidMigrator();
    error MigrationNotEnabled();
    error ArrayLengthMismatch();
    error ZeroAddress();
    error ZeroAmount();
    error PresaleNotActive();
    error PresaleCapExceeded();
    error InsufficientPayment();
    error InvalidPrice();
    error PurchaseLimitExceeded();
    error BadgeRequiredForPurchase();
    error TreasuryNotSet();
    // error PurchaseLimitExceeded();
    // error BadgeRequiredForPurchase();
    error PaymentTransferFailed();

    // ============ Constructor ============

    /**
     * @notice Initialize PreGVT contract
     * @param _badge Address of Genesis Badge contract
     * @param _badgeId ID of the badge required for claims
     * @param _airdropReserveCap Maximum tokens that can be minted from airdrop
     * @param _presaleSupplyCap Maximum tokens that can be sold in presale
     * @param _treasury Treasury address for receiving funds
     * @param _initialAdmin Address to receive admin role
     */
    constructor(
        address _badge,
        uint256 _badgeId,
        uint256 _airdropReserveCap,
        uint256 _presaleSupplyCap,
        address _treasury,
        address _paymentToken,
        address _initialAdmin
    ) ERC20("preGVT", "preGVT") {
        if (_badge == address(0)) revert ZeroAddress();
        if (_paymentToken == address(0)) revert ZeroAddress();
        // if (_treasury == address(0)) revert ZeroAddress();
        if (_initialAdmin == address(0)) revert ZeroAddress();
        if (_airdropReserveCap == 0) revert ZeroAmount();

        badge = IGenesisBadge1155(_badge);
        badgeId = _badgeId;
        airdropReserveCap = _airdropReserveCap;
        presaleSupplyCap = _presaleSupplyCap;
        treasury = _treasury;
        paymentToken = IERC20(_paymentToken);

        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(DISTRIBUTOR_ROLE, _initialAdmin);
        _grantRole(MIGRATOR_SETTER_ROLE, _initialAdmin);
        _grantRole(PRICE_MANAGER_ROLE, _initialAdmin);
        _grantRole(TREASURY_ROLE, _initialAdmin);

        emit AirdropReserveDefined(_airdropReserveCap);
    }

    // ============ View Functions ============

    /**
     * @notice Get remaining airdrop reserve
     * @return Tokens still available in reserve
     */
    function airdropReserveRemaining() external view returns (uint256) {
        return airdropReserveCap - airdropReserveMinted;
    }

    /**
     * @notice Get remaining presale supply
     * @return Tokens still available for presale
     */
    function presaleRemaining() external view returns (uint256) {
        return presaleSupplyCap - presaleSold;
    }

    /**
     * @notice Check if user has required badge
     * @param user Address to check
     * @return True if user has badge
     * @dev External call in loop (batchAirdrop) — caller must limit batch size.
     */
    function hasBadge(address user) public view returns (bool) {
        return badge.balanceOf(user, badgeId) > 0;
    }

    /**
     * @notice Get user's preloaded allocation
     * @param user Address to check
     * @return Allocated amount
     */
    function allowanceOf(address user) external view returns (uint256) {
        return claimable[user];
    }

    /**
     * @notice Calculate cost for purchasing amount of tokens
     * @param amount Number of tokens to purchase
     * @return cost Total cost in wei
     */
    function calculateCost(uint256 amount) public view returns (uint256 cost) {
        return amount * pricePerToken / 1e18;
    }

    /**
     * @notice Get remaining purchase limit for user
     * @param user Address to check
     * @return remaining Remaining tokens user can purchase
     */
    function remainingPurchaseLimit(address user) external view returns (uint256) {
        if (perUserPurchaseLimit == 0) return type(uint256).max;
        uint256 purchased = userPurchases[user];
        return purchased >= perUserPurchaseLimit ? 0 : perUserPurchaseLimit - purchased;
    }

    // ============ Admin Functions ============

    /**
     * @notice Pause all claim and purchase operations
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause all claim and purchase operations
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Configure presale parameters
     * @param _pricePerToken Price per token in wei
     * @param _badgeRequired Whether badge is required for purchase
     * @param _perUserLimit Per-user purchase limit (0 = no limit)
     */
    function configurePresale(uint256 _pricePerToken, bool _badgeRequired, uint256 _perUserLimit)
        external
        onlyRole(PRICE_MANAGER_ROLE)
    {
        if (_pricePerToken == 0) revert InvalidPrice();

        pricePerToken = _pricePerToken;
        badgeRequiredForPurchase = _badgeRequired;
        perUserPurchaseLimit = _perUserLimit;

        emit PresaleConfigured(_pricePerToken, _badgeRequired, _perUserLimit);
    }

    /**
     * @notice Update token price
     * @param _pricePerToken New price per token in wei
     */
    function updatePrice(uint256 _pricePerToken) external onlyRole(PRICE_MANAGER_ROLE) {
        if (_pricePerToken == 0) revert InvalidPrice();
        pricePerToken = _pricePerToken;
        emit PriceUpdated(_pricePerToken);
    }

    /**
     * @notice Enable or disable presale
     * @param _active Whether presale should be active
     */
    function setPresaleActive(bool _active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        presaleActive = _active;
        emit PresaleStatusChanged(_active);
    }

    /**
     * @notice Withdraw accumulated funds to treasury
     */
    function withdrawFunds() external onlyRole(TREASURY_ROLE) nonReentrant {
        if (treasury == address(0)) revert TreasuryNotSet();

        uint256 balance = paymentToken.balanceOf(address(this));
        if (balance == 0) revert ZeroAmount();

        bool success = paymentToken.transfer(treasury, balance);
        if (!success) revert PaymentTransferFailed();

        emit FundsWithdrawn(treasury, balance);
    }

    /**
     * @notice Set migrator contract address (one-time)
     * @param _migrator Address of migrator contract
     */
    function setMigrator(address _migrator) external onlyRole(MIGRATOR_SETTER_ROLE) {
        if (_migrator == address(0)) revert InvalidMigrator();
        if (migrator != address(0)) revert InvalidMigrator(); // Can only be set once

        migrator = _migrator;
        migrationEnabled = true;

        emit MigrationEnabled(_migrator);
    }

    /**
     * @notice Preload allocations for multiple users (Pattern B)
     * @param users Array of user addresses
     * @param amounts Array of allocation amounts
     */
    function setAllocations(address[] calldata users, uint256[] calldata amounts) external onlyRole(DISTRIBUTOR_ROLE) {
        if (users.length != amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == address(0)) revert ZeroAddress();
            claimable[users[i]] += amounts[i];
            emit AllocationSet(users[i], amounts[i]);
        }
    }

    /**
     * @notice Direct batch airdrop to multiple users
     * @param users Array of recipient addresses
     * @param amounts Array of airdrop amounts
     * @dev All recipients must have badges
     */
    function batchAirdrop(address[] calldata users, uint256[] calldata amounts)
        external
        onlyRole(DISTRIBUTOR_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (users.length != amounts.length) revert ArrayLengthMismatch();

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == address(0)) revert ZeroAddress();
            if (!hasBadge(users[i])) revert NoBadge();

            totalAmount += amounts[i];
            _mintFromReserve(users[i], amounts[i]);
        }

        emit BatchAirdrop(users.length, totalAmount);
    }

    // ============ User Functions ============

    /**
     * @notice Buy tokens at presale price using USDT
     * @param amount Number of tokens to purchase
     */
    function buy(uint256 amount) external whenNotPaused nonReentrant {
        if (!presaleActive) revert PresaleNotActive();
        if (amount == 0) revert ZeroAmount();
        if (badgeRequiredForPurchase && !hasBadge(msg.sender)) revert BadgeRequiredForPurchase();

        // Check presale cap
        if (presaleSold + amount > presaleSupplyCap) revert PresaleCapExceeded();

        // Check per-user limit
        if (perUserPurchaseLimit > 0) {
            if (userPurchases[msg.sender] + amount > perUserPurchaseLimit) {
                revert PurchaseLimitExceeded();
            }
        }

        // Calculate cost
        uint256 cost = calculateCost(amount);
        if (cost == 0) revert ZeroAmount();

        // Transfer payment tokens from user to contract
        bool success = paymentToken.transferFrom(msg.sender, address(this), cost);
        if (!success) revert PaymentTransferFailed();

        // Update state
        presaleSold += amount;
        userPurchases[msg.sender] += amount;

        // Mint tokens
        _mint(msg.sender, amount);

        emit TokensPurchased(msg.sender, amount, cost);
    }

    /**
     * @notice Claim preloaded allocation (Pattern B)
     * @dev Requires badge and consumes it via operator burn
     */
    function claimAllocated() external whenNotPaused nonReentrant {
        uint256 amount = claimable[msg.sender];
        if (amount == 0) revert NoAllocation();
        if (!hasBadge(msg.sender)) revert NoBadge();

        // Clear allocation before external call
        claimable[msg.sender] = 0;

        // Try to burn badge via operator (single-tx UX)
        try badge.redeemByOperator(msg.sender, badgeId, 1) {
            emit BadgeConsumed(msg.sender, badgeId, 1);
        } catch {
            // If operator burn fails, user must have burned badge manually (two-tx UX)
            // This allows backward compatibility
        }

        _mintFromReserve(msg.sender, amount);
    }

    /**
     * @notice Claim with badge for fixed amount (Pattern A)
     * @param amount Amount to claim
     * @dev Requires badge and consumes it
     */
    function claimWithBadge(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (!hasBadge(msg.sender)) revert NoBadge();

        // Try to burn badge via operator
        try badge.redeemByOperator(msg.sender, badgeId, 1) {
            emit BadgeConsumed(msg.sender, badgeId, 1);
        } catch {
            revert NoBadge(); // For Pattern A, operator burn must succeed
        }

        _mintFromReserve(msg.sender, amount);
    }

    /**
     * @notice Migrate preGVT to main GVT token
     * @dev Burns preGVT and emits event for migrator to process
     */
    function migrateToGVT() external nonReentrant {
        if (!migrationEnabled) revert MigrationNotEnabled();
        if (migrator == address(0)) revert InvalidMigrator();

        uint256 amount = balanceOf(msg.sender);
        if (amount == 0) revert ZeroAmount();

        _burn(msg.sender, amount);

        emit Migrated(msg.sender, amount);
    }

    // ============ Internal Functions ============

    /**
     * @notice Internal mint function with reserve cap enforcement
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function _mintFromReserve(address to, uint256 amount) internal {
        if (airdropReserveMinted + amount > airdropReserveCap) {
            revert ReserveCapExceeded();
        }

        airdropReserveMinted += amount;
        _mint(to, amount);

        emit AirdropDistributed(to, amount, airdropReserveMinted);
    }

    // ============ Non-Transferable Overrides ============

    /**
     * @notice Transfer disabled - token is non-transferable
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert TransferNotAllowed();
    }

    /**
     * @notice TransferFrom disabled - token is non-transferable
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TransferNotAllowed();
    }

    /**
     * @notice Approve disabled - token is non-transferable
     */
    function approve(address, uint256) public pure override returns (bool) {
        revert ApprovalNotAllowed();
    }

    /**
     * @notice IncreaseAllowance disabled - token is non-transferable
     */
    function increaseAllowance(address, uint256) public pure returns (bool) {
        revert ApprovalNotAllowed();
    }

    /**
     * @notice DecreaseAllowance disabled - token is non-transferable
     */
    function decreaseAllowance(address, uint256) public pure returns (bool) {
        revert ApprovalNotAllowed();
    }
}
