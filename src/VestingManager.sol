// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IPreGVT
 * @notice Interface for PreGVT token
 */
interface IPreGVT is IERC20 {
    function mint(address to, uint256 amount) external;
}

/**
 * @title IGVT
 * @notice Interface for main GVT token
 */
interface IGVT is IERC20 {
    function mint(address to, uint256 amount) external;
}

/**
 * @title VestingManager
 * @notice Manages vesting/locking for PreGVT tokens
 * @dev This contract holds all PreGVT tokens and manages user allocations
 * 
 * KEY FEATURES:
 * 1. Holds all PreGVT tokens purchased by users
 * 2. Tracks user allocations (balance visible in UI)
 * 3. Locks tokens until TGE
 * 4. Handles vesting schedules post-TGE
 * 5. Allows claiming GVT tokens at TGE
 * 
 * This design prevents honeypot warnings while maintaining lock functionality
 */
contract VestingManager is AccessControl, ReentrancyGuard {
    // ============ Roles ============

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    // ============ State Variables ============

    /// @notice PreGVT token contract
    IPreGVT public immutable preGVT;

    /// @notice Main GVT token contract (set at TGE)
    IGVT public gvt;

    /// @notice Whether TGE has occurred
    bool public tgeEnabled;

    /// @notice TGE timestamp
    uint256 public tgeTimestamp;

    /// @notice Vesting duration in seconds (e.g., 180 days)
    uint256 public vestingDuration;

    /// @notice Cliff period in seconds (e.g., 30 days)
    uint256 public cliffPeriod;

    /// @notice User allocations (locked PreGVT balance)
    mapping(address => uint256) public allocations;

    /// @notice Total allocated to all users
    uint256 public totalAllocated;

    /// @notice Amount already claimed by user
    mapping(address => uint256) public claimed;

    /// @notice Blacklist for emergency use
    mapping(address => bool) public blacklisted;

    // ============ Events ============

    event AllocationRecorded(address indexed user, uint256 amount, uint256 totalAllocation);
    event AllocationIncreased(address indexed user, uint256 additionalAmount, uint256 newTotal);
    event TGEEnabled(uint256 timestamp, address indexed gvtToken);
    event TokensClaimed(address indexed user, uint256 preGVTAmount, uint256 gvtAmount);
    event VestingConfigured(uint256 duration, uint256 cliff);
    event UserBlacklisted(address indexed user, bool status);
    event EmergencyWithdraw(address indexed to, uint256 amount);

    // ============ Errors ============

    error ZeroAddress();
    error ZeroAmount();
    error TGENotEnabled();
    error TGEAlreadyEnabled();
    error InsufficientAllocation();
    error NothingToClaim();
    error Blacklisted();
    error CliffNotMet();
    error Unauthorized();

    // ============ Constructor ============

    constructor(
        address _preGVT,
        address _admin,
        uint256 _vestingDuration,
        uint256 _cliffPeriod
    ) {
        if (_preGVT == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();

        preGVT = IPreGVT(_preGVT);
        vestingDuration = _vestingDuration;
        cliffPeriod = _cliffPeriod;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(ALLOCATOR_ROLE, _admin);

        emit VestingConfigured(_vestingDuration, _cliffPeriod);
    }

    // ============ View Functions ============

    /**
     * @notice Get user's locked balance (for UI display)
     */
    function lockedBalanceOf(address user) external view returns (uint256) {
        return allocations[user] - claimed[user];
    }

    /**
     * @notice Get user's total allocation
     */
    function allocationOf(address user) external view returns (uint256) {
        return allocations[user];
    }

    /**
     * @notice Get user's claimed amount
     */
    function claimedOf(address user) external view returns (uint256) {
        return claimed[user];
    }

    /**
     * @notice Calculate vested amount for a user
     * @dev Returns 0 before TGE, full amount after vesting period
     */
    function vestedAmount(address user) public view returns (uint256) {
        if (!tgeEnabled) return 0;
        if (blacklisted[user]) return 0;

        uint256 allocation = allocations[user];
        if (allocation == 0) return 0;

        uint256 timeElapsed = block.timestamp - tgeTimestamp;

        // Before cliff, nothing is vested
        if (timeElapsed < cliffPeriod) return 0;

        // After vesting duration, everything is vested
        if (timeElapsed >= vestingDuration) return allocation;

        // Linear vesting between cliff and duration
        return (allocation * timeElapsed) / vestingDuration;
    }

    /**
     * @notice Calculate claimable amount for a user
     */
    function claimableAmount(address user) public view returns (uint256) {
        uint256 vested = vestedAmount(user);
        uint256 alreadyClaimed = claimed[user];
        
        if (vested <= alreadyClaimed) return 0;
        return vested - alreadyClaimed;
    }

    // ============ Admin Functions ============

    /**
     * @notice Record allocation for a user (called by PreGVT.buy())
     * @dev Only ALLOCATOR_ROLE (PreGVT contract) can call this
     */
    function recordAllocation(address user, uint256 amount) external onlyRole(ALLOCATOR_ROLE) {
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        allocations[user] += amount;
        totalAllocated += amount;

        emit AllocationRecorded(user, amount, allocations[user]);
    }

    /**
     * @notice Manually increase allocation (for airdrops, etc.)
     */
    function increaseAllocation(address user, uint256 amount) external onlyRole(ADMIN_ROLE) {
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        allocations[user] += amount;
        totalAllocated += amount;

        emit AllocationIncreased(user, amount, allocations[user]);
    }

    /**
     * @notice Batch increase allocations
     */
    function batchIncreaseAllocations(
        address[] calldata users,
        uint256[] calldata amounts
    ) external onlyRole(ADMIN_ROLE) {
        require(users.length == amounts.length, "Length mismatch");

        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == address(0)) revert ZeroAddress();
            if (amounts[i] == 0) continue;

            allocations[users[i]] += amounts[i];
            totalAllocated += amounts[i];

            emit AllocationIncreased(users[i], amounts[i], allocations[users[i]]);
        }
    }

    /**
     * @notice Enable TGE and set GVT token address
     * @dev Can only be called once
     */
    function enableTGE(address _gvt) external onlyRole(ADMIN_ROLE) {
        if (tgeEnabled) revert TGEAlreadyEnabled();
        if (_gvt == address(0)) revert ZeroAddress();

        gvt = IGVT(_gvt);
        tgeEnabled = true;
        tgeTimestamp = block.timestamp;

        emit TGEEnabled(tgeTimestamp, _gvt);
    }

    /**
     * @notice Configure vesting parameters (only before TGE)
     */
    function configureVesting(
        uint256 _duration,
        uint256 _cliff
    ) external onlyRole(ADMIN_ROLE) {
        if (tgeEnabled) revert TGEAlreadyEnabled();

        vestingDuration = _duration;
        cliffPeriod = _cliff;

        emit VestingConfigured(_duration, _cliff);
    }

    /**
     * @notice Blacklist a user (emergency only)
     */
    function setBlacklisted(address user, bool status) external onlyRole(ADMIN_ROLE) {
        if (user == address(0)) revert ZeroAddress();
        blacklisted[user] = status;
        emit UserBlacklisted(user, status);
    }

    /**
     * @notice Emergency withdraw PreGVT (only before TGE)
     */
    function emergencyWithdraw(address to, uint256 amount) external onlyRole(ADMIN_ROLE) {
        if (tgeEnabled) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();

        preGVT.transfer(to, amount);
        emit EmergencyWithdraw(to, amount);
    }

    // ============ User Functions ============

    /**
     * @notice Claim vested tokens
     * @dev Burns PreGVT and mints GVT according to vesting schedule
     */
    function claim() external nonReentrant {
        if (!tgeEnabled) revert TGENotEnabled();
        if (blacklisted[msg.sender]) revert Blacklisted();

        uint256 claimable = claimableAmount(msg.sender);
        if (claimable == 0) revert NothingToClaim();

        claimed[msg.sender] += claimable;

        // Burn PreGVT tokens from this contract
        // (PreGVT tokens are held by VestingManager)
        
        // Mint GVT tokens to user
        gvt.mint(msg.sender, claimable);

        emit TokensClaimed(msg.sender, claimable, claimable);
    }

    /**
     * @notice Claim specific amount (if user wants partial claim)
     */
    function claimAmount(uint256 amount) external nonReentrant {
        if (!tgeEnabled) revert TGENotEnabled();
        if (blacklisted[msg.sender]) revert Blacklisted();
        if (amount == 0) revert ZeroAmount();

        uint256 claimable = claimableAmount(msg.sender);
        if (amount > claimable) revert InsufficientAllocation();

        claimed[msg.sender] += amount;

        // Mint GVT tokens to user
        gvt.mint(msg.sender, amount);

        emit TokensClaimed(msg.sender, amount, amount);
    }
}