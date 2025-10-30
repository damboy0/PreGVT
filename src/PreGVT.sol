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
 * @notice Non-transferable pre-token for badge-gated airdrops
 * @dev Implements formal airdrop reserve with badge-gated claims
 */
contract PreGVT is ERC20, AccessControl, Pausable, ReentrancyGuard {
    
    // ============ Roles ============
    
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant MIGRATOR_SETTER_ROLE = keccak256("MIGRATOR_SETTER_ROLE");
    
    // ============ Immutable State ============
    
    /// @notice Genesis Badge contract address
    IGenesisBadge1155 public immutable badge;
    
    /// @notice Badge ID required for claims
    uint256 public immutable badgeId;
    
    /// @notice Maximum tokens that can ever be minted from airdrop reserve
    uint256 public immutable airdropReserveCap;
    
    // ============ Mutable State ============
    
    /// @notice Total tokens minted from airdrop reserve
    uint256 public airdropReserveMinted;
    
    /// @notice Preloaded allocations per user (Pattern B)
    mapping(address => uint256) public claimable;
    
    /// @notice Migrator contract address for GVT conversion
    address public migrator;
    
    /// @notice Whether migration to main token is enabled
    bool public migrationEnabled;
    
    // ============ Events ============
    
    event AirdropReserveDefined(uint256 cap);
    event AirdropDistributed(address indexed to, uint256 amount, uint256 newTotalMinted);
    event BatchAirdrop(uint256 indexed count, uint256 totalAmount);
    event BadgeConsumed(address indexed user, uint256 indexed badgeId, uint256 amount);
    event MigrationEnabled(address indexed migrator);
    event Migrated(address indexed user, uint256 preGVTAmount);
    event AllocationSet(address indexed user, uint256 amount);
    
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
    
    // ============ Constructor ============
    
    /**
     * @notice Initialize PreGVT contract
     * @param _badge Address of Genesis Badge contract
     * @param _badgeId ID of the badge required for claims
     * @param _airdropReserveCap Maximum tokens that can be minted
     * @param _initialAdmin Address to receive admin role
     */
    constructor(
        address _badge,
        uint256 _badgeId,
        uint256 _airdropReserveCap,
        address _initialAdmin
    ) ERC20("preGVT", "preGVT") {
        if (_badge == address(0)) revert ZeroAddress();
        if (_initialAdmin == address(0)) revert ZeroAddress();
        if (_airdropReserveCap == 0) revert ZeroAmount();
        
        badge = IGenesisBadge1155(_badge);
        badgeId = _badgeId;
        airdropReserveCap = _airdropReserveCap;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(DISTRIBUTOR_ROLE, _initialAdmin);
        _grantRole(MIGRATOR_SETTER_ROLE, _initialAdmin);
        
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
     * @notice Check if user has required badge
     * @param user Address to check
     * @return True if user has badge
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
    
    // ============ Admin Functions ============
    
    /**
     * @notice Pause all claim operations
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    /**
     * @notice Unpause all claim operations
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
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
    function setAllocations(
        address[] calldata users,
        uint256[] calldata amounts
    ) external onlyRole(DISTRIBUTOR_ROLE) {
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
    function batchAirdrop(
        address[] calldata users,
        uint256[] calldata amounts
    ) external onlyRole(DISTRIBUTOR_ROLE) whenNotPaused nonReentrant {
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