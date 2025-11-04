// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title IRewardToken
 * @notice Interface for rGGP reward token (mintable)
 */
interface IRewardToken is IERC20 {
    function mint(address to, uint256 amount) external;
}

/**
 * @title INFTBoostOracle
 * @notice Optional NFT boost oracle interface
 */
interface INFTBoostOracle {
    function getBoostMultiplier(address user) external view returns (uint256);
}

/**
 * @title PreGVTStaking
 * @notice Staking contract for preGVT with rGGP rewards
 * @dev Supports pre-launch reward tracking and post-launch claiming
 */
contract PreGVTStaking is Ownable(msg.sender), Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Structs ============

    struct StakePosition {
        uint256 amount; // Amount of preGVT staked
        uint256 startTime; // Stake start timestamp
        uint256 lockEndTime; // Lock end timestamp (startTime + MIN_LOCK_PERIOD)
        uint256 lastRewardTime; // Last reward calculation timestamp
        uint256 accruedRewards; // Accumulated rewards not yet claimed
        bool active; // Position active status
    }

    struct EpochConfig {
        uint256 emissionRate; // Rewards per second for this epoch
        uint256 startTime; // Epoch start time
        uint256 endTime; // Epoch end time
    }

    // ============ Constants ============

    uint256 public constant MIN_LOCK_PERIOD = 30 days;
    uint256 public constant EARLY_EXIT_PENALTY_BPS = 1000; // 10%
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant BOOST_BASE = 100; // 100% = no boost, 150% = 1.5x

    // ============ State Variables ============

    /// @notice Stake token (preGVT)
    IERC20 public immutable stakeToken;

    /// @notice Reward token (rGGP) - set after launch
    IRewardToken public rewardToken;

    /// @notice Treasury address for penalties
    address public treasury;

    /// @notice NFT boost oracle (optional)
    INFTBoostOracle public boostOracle;

    /// @notice Reward distribution active flag
    bool public rewardActive;

    /// @notice Total staked amount
    uint256 public totalStaked;

    /// @notice Global reward cap
    uint256 public globalRewardCap;

    /// @notice Total rewards minted/accrued
    uint256 public totalRewardsMinted;

    /// @notice Next position ID
    uint256 public nextPositionId;

    /// @notice Current epoch ID
    uint256 public currentEpochId;

    /// @notice User position IDs
    mapping(address => uint256[]) public userPositions;

    /// @notice Position data
    mapping(uint256 => StakePosition) public positions;

    /// @notice Position owner
    mapping(uint256 => address) public positionOwner;

    /// @notice Pending rGGP rewards per user (pre-launch tracking)
    mapping(address => uint256) public pendingRggp;

    /// @notice Epoch configurations
    mapping(uint256 => EpochConfig) public epochs;

    /// @notice EOA-only flag
    bool public eoaOnly = true;

    // ============ Events ============

    event Staked(address indexed user, uint256 indexed positionId, uint256 amount, uint256 lockEndTime);
    event Unstaked(address indexed user, uint256 indexed positionId, uint256 amount);
    event EarlyExit(address indexed user, uint256 indexed positionId, uint256 amount, uint256 penalty);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsAccrued(address indexed user, uint256 indexed positionId, uint256 amount);
    event RewardTokenSet(address indexed rewardToken);
    event EpochConfigured(uint256 indexed epochId, uint256 emissionRate, uint256 startTime, uint256 endTime);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event BoostOracleUpdated(address indexed boostOracle);
    event GlobalRewardCapUpdated(uint256 newCap);

    // ============ Errors ============

    error OnlyEOA();
    error InvalidAmount();
    error InvalidAddress();
    error PositionNotFound();
    error PositionNotActive();
    error NotPositionOwner();
    error StillLocked();
    error NoRewards();
    error RewardCapExceeded();
    error RewardTokenNotSet();
    error RewardTokenAlreadySet();
    error InvalidEpochConfig();

    // ============ Modifiers ============

    modifier onlyEOA() {
        if (eoaOnly && msg.sender != tx.origin) revert OnlyEOA();
        _;
    }

    modifier validPosition(uint256 positionId) {
        if (positionOwner[positionId] == address(0)) revert PositionNotFound();
        if (positionOwner[positionId] != msg.sender) revert NotPositionOwner();
        if (!positions[positionId].active) revert PositionNotActive();
        _;
    }

    // ============ Constructor ============

    constructor(address _stakeToken, address _treasury, uint256 _globalRewardCap) {
        if (_stakeToken == address(0)) revert InvalidAddress();
        if (_treasury == address(0)) revert InvalidAddress();

        stakeToken = IERC20(_stakeToken);
        treasury = _treasury;
        globalRewardCap = _globalRewardCap;

        nextPositionId = 1; // Start from 1
    }

    // ============ Staking Functions ============

    /**
     * @notice Stake preGVT tokens
     * @param amount Amount to stake
     * @return positionId Created position ID
     */
    function stake(uint256 amount) external whenNotPaused nonReentrant onlyEOA returns (uint256 positionId) {
        if (amount == 0) revert InvalidAmount();

        positionId = nextPositionId++;

        uint256 lockEndTime = block.timestamp + MIN_LOCK_PERIOD;

        positions[positionId] = StakePosition({
            amount: amount,
            startTime: block.timestamp,
            lockEndTime: lockEndTime,
            lastRewardTime: block.timestamp,
            accruedRewards: 0,
            active: true
        });

        positionOwner[positionId] = msg.sender;
        userPositions[msg.sender].push(positionId);

        totalStaked += amount;

        stakeToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, positionId, amount, lockEndTime);
    }

    /**
     * @notice Unstake tokens after lock period
     * @param positionId Position to unstake
     */
    function unstake(uint256 positionId) external whenNotPaused nonReentrant validPosition(positionId) {
        StakePosition storage position = positions[positionId];

        if (block.timestamp < position.lockEndTime) revert StillLocked();

        // Update rewards before unstaking
        _updateRewards(positionId);

        uint256 amount = position.amount;

        position.active = false;
        totalStaked -= amount;

        stakeToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, positionId, amount);
    }

    /**
     * @notice Early exit with penalty
     * @param positionId Position to exit early
     */
    function earlyExit(uint256 positionId) external whenNotPaused nonReentrant validPosition(positionId) {
        StakePosition storage position = positions[positionId];

        // Update rewards before exit
        _updateRewards(positionId);

        uint256 amount = position.amount;
        uint256 penalty = (amount * EARLY_EXIT_PENALTY_BPS) / BASIS_POINTS;
        uint256 amountAfterPenalty = amount - penalty;

        position.active = false;
        totalStaked -= amount;

        // Transfer penalty to treasury
        stakeToken.safeTransfer(treasury, penalty);

        // Transfer remaining to user
        stakeToken.safeTransfer(msg.sender, amountAfterPenalty);

        emit EarlyExit(msg.sender, positionId, amountAfterPenalty, penalty);
    }

    // ============ Reward Functions ============

    /**
     * @notice Claim accumulated rewards
     * @param positionId Position to claim rewards for
     */
    function claim(uint256 positionId) external whenNotPaused nonReentrant validPosition(positionId) {
        _updateRewards(positionId);

        uint256 reward = pendingRggp[msg.sender];
        if (reward == 0) revert NoRewards();

        pendingRggp[msg.sender] = 0;

        if (rewardActive && address(rewardToken) != address(0)) {
            // Mint and transfer rewards
            rewardToken.mint(msg.sender, reward);
        }
        // If not active, rewards remain tracked on-chain

        emit RewardsClaimed(msg.sender, reward);
    }

    /**
     * @notice Claim rewards for all user positions
     */
    function claimAll() external whenNotPaused nonReentrant {
        uint256[] memory userPositionIds = userPositions[msg.sender];

        for (uint256 i = 0; i < userPositionIds.length; i++) {
            uint256 positionId = userPositionIds[i];
            if (positions[positionId].active) {
                _updateRewards(positionId);
            }
        }

        uint256 reward = pendingRggp[msg.sender];
        if (reward == 0) revert NoRewards();

        pendingRggp[msg.sender] = 0;

        if (rewardActive && address(rewardToken) != address(0)) {
            rewardToken.mint(msg.sender, reward);
        }

        emit RewardsClaimed(msg.sender, reward);
    }

    /**
     * @notice Update rewards for a position
     * @param positionId Position to update
     */
    function _updateRewards(uint256 positionId) internal {
        StakePosition storage position = positions[positionId];
        if (!position.active) return;

        uint256 pendingReward = calculateRewards(positionId);

        if (pendingReward > 0) {
            // Check global cap
            if (totalRewardsMinted + pendingReward > globalRewardCap) {
                revert RewardCapExceeded();
            }

            address owner = positionOwner[positionId];
            position.accruedRewards += pendingReward;
            pendingRggp[owner] += pendingReward;
            totalRewardsMinted += pendingReward;

            emit RewardsAccrued(owner, positionId, pendingReward);
        }

        position.lastRewardTime = block.timestamp;
    }

    /**
     * @notice Calculate pending rewards for a position
     * @param positionId Position to calculate
     * @return Pending reward amount
     */
    function calculateRewards(uint256 positionId) public view returns (uint256) {
        StakePosition memory position = positions[positionId];
        if (!position.active) return 0;

        uint256 timeElapsed = block.timestamp - position.lastRewardTime;
        if (timeElapsed == 0) return 0;

        // Get current epoch emission rate
        EpochConfig memory epoch = epochs[currentEpochId];
        if (epoch.emissionRate == 0) return 0;

        // Base rewards
        uint256 baseReward = (position.amount * epoch.emissionRate * timeElapsed) / 1e18;

        // Apply boost if oracle is set
        uint256 boost = BOOST_BASE;
        if (address(boostOracle) != address(0)) {
            try boostOracle.getBoostMultiplier(positionOwner[positionId]) returns (uint256 multiplier) {
                boost = multiplier;
            } catch {
                // Fallback to base if oracle fails
                boost = BOOST_BASE;
            }
        }

        return (baseReward * boost) / BOOST_BASE;
    }

    // ============ View Functions ============

    /**
     * @notice Get user's total pending rewards
     * @param user User address
     * @return Total pending rewards
     */
    function getUserTotalRewards(address user) external view returns (uint256) {
        uint256 total = pendingRggp[user];
        uint256[] memory userPositionIds = userPositions[user];

        for (uint256 i = 0; i < userPositionIds.length; i++) {
            if (positions[userPositionIds[i]].active) {
                total += calculateRewards(userPositionIds[i]);
            }
        }

        return total;
    }

    /**
     * @notice Get all user positions
     * @param user User address
     * @return Array of position IDs
     */
    function getUserPositions(address user) external view returns (uint256[] memory) {
        return userPositions[user];
    }

    /**
     * @notice Get position details
     * @param positionId Position ID
     * @return Position struct
     */
    function getPosition(uint256 positionId) external view returns (StakePosition memory) {
        return positions[positionId];
    }

    /**
     * @notice Check if position is unlocked
     * @param positionId Position ID
     * @return True if unlocked
     */
    function isUnlocked(uint256 positionId) external view returns (bool) {
        return block.timestamp >= positions[positionId].lockEndTime;
    }

    /**
     * @notice Get remaining lock time
     * @param positionId Position ID
     * @return Seconds remaining (0 if unlocked)
     */
    function getRemainingLockTime(uint256 positionId) external view returns (uint256) {
        StakePosition memory position = positions[positionId];
        if (block.timestamp >= position.lockEndTime) return 0;
        return position.lockEndTime - block.timestamp;
    }

    // ============ Admin Functions ============

    /**
     * @notice Set reward token (one-time after launch)
     * @param _rewardToken Reward token address
     */
    function setRewardToken(address _rewardToken) external onlyOwner {
        if (address(rewardToken) != address(0)) revert RewardTokenAlreadySet();
        if (_rewardToken == address(0)) revert InvalidAddress();

        rewardToken = IRewardToken(_rewardToken);
        rewardActive = true;

        emit RewardTokenSet(_rewardToken);
    }

    /**
     * @notice Configure epoch emission rate
     * @param epochId Epoch ID
     * @param emissionRate Rewards per second (scaled by 1e18)
     * @param startTime Epoch start time
     * @param endTime Epoch end time
     */
    function configureEpoch(uint256 epochId, uint256 emissionRate, uint256 startTime, uint256 endTime)
        external
        onlyOwner
    {
        if (endTime <= startTime) revert InvalidEpochConfig();

        epochs[epochId] = EpochConfig({emissionRate: emissionRate, startTime: startTime, endTime: endTime});

        emit EpochConfigured(epochId, emissionRate, startTime, endTime);
    }

    /**
     * @notice Set current epoch
     * @param epochId New current epoch ID
     */
    function setCurrentEpoch(uint256 epochId) external onlyOwner {
        currentEpochId = epochId;
    }

    /**
     * @notice Update treasury address
     * @param _treasury New treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert InvalidAddress();

        address oldTreasury = treasury;
        treasury = _treasury;

        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    /**
     * @notice Set boost oracle
     * @param _boostOracle Boost oracle address
     */
    function setBoostOracle(address _boostOracle) external onlyOwner {
        boostOracle = INFTBoostOracle(_boostOracle);
        emit BoostOracleUpdated(_boostOracle);
    }

    /**
     * @notice Update global reward cap
     * @param _newCap New reward cap
     */
    function setGlobalRewardCap(uint256 _newCap) external onlyOwner {
        globalRewardCap = _newCap;
        emit GlobalRewardCapUpdated(_newCap);
    }

    /**
     * @notice Toggle EOA-only requirement
     * @param _eoaOnly New EOA-only status
     */
    function setEoaOnly(bool _eoaOnly) external onlyOwner {
        eoaOnly = _eoaOnly;
    }

    /**
     * @notice Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdraw (only when paused)
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(paused(), "Must be paused");
        IERC20(token).safeTransfer(owner(), amount);
    }
}
