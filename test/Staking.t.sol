// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Staking.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockPreGVT
 * @notice Mock preGVT token for testing
 */
contract MockPreGVT is ERC20 {
    constructor() ERC20("preGVT", "preGVT") {
        _mint(msg.sender, 10_000_000e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title MockRGGP
 * @notice Mock rGGP reward token for testing
 */
contract MockRGGP is ERC20 {
    address public minter;

    constructor() ERC20("rGGP", "rGGP") {
        minter = msg.sender;
    }

    function setMinter(address _minter) external {
        minter = _minter;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "Not minter");
        _mint(to, amount);
    }
}

/**
 * @title MockBoostOracle
 * @notice Mock NFT boost oracle for testing
 */
contract MockBoostOracle {
    mapping(address => uint256) public boosts;

    function setBoost(address user, uint256 multiplier) external {
        boosts[user] = multiplier;
    }

    function getBoostMultiplier(address user) external view returns (uint256) {
        uint256 boost = boosts[user];
        return boost == 0 ? 100 : boost; // Default 100% (no boost)
    }
}

/**
 * @title PreGVTStakingTest
 * @notice Comprehensive test suite for PreGVTStaking
 */
contract PreGVTStakingTest is Test {
    PreGVTStaking public staking;
    MockPreGVT public preGVT;
    MockRGGP public rGGP;
    MockBoostOracle public boostOracle;

    address public owner = address(1);
    address public treasury = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    address public user3 = address(5);

    uint256 public constant REWARD_CAP = 1_000_000_000e18; // 1 billion tokens
    uint256 public constant EMISSION_RATE = 1e15; // 0.001 token per second per token staked (reduced from 1e18)

    event Staked(address indexed user, uint256 indexed positionId, uint256 amount, uint256 lockEndTime);
    event Unstaked(address indexed user, uint256 indexed positionId, uint256 amount);
    event EarlyExit(address indexed user, uint256 indexed positionId, uint256 amount, uint256 penalty);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsAccrued(address indexed user, uint256 indexed positionId, uint256 amount);

    function setUp() public {
        // Deploy contracts
        preGVT = new MockPreGVT();
        rGGP = new MockRGGP();
        boostOracle = new MockBoostOracle();

        // Deploy staking
        vm.prank(owner);
        staking = new PreGVTStaking(address(preGVT), treasury, REWARD_CAP);

        // Disable EOA-only for testing
        vm.prank(owner);
        staking.setEoaOnly(false);

        // Set staking as rGGP minter
        rGGP.setMinter(address(staking));

        // Configure initial epoch
        vm.startPrank(owner);
        staking.configureEpoch(0, EMISSION_RATE, block.timestamp, block.timestamp + 365 days);
        staking.setCurrentEpoch(0);
        vm.stopPrank();

        // Fund users
        preGVT.mint(user1, 10_000e18);
        preGVT.mint(user2, 10_000e18);
        preGVT.mint(user3, 10_000e18);

        // Approve staking
        vm.prank(user1);
        preGVT.approve(address(staking), type(uint256).max);
        vm.prank(user2);
        preGVT.approve(address(staking), type(uint256).max);
        vm.prank(user3);
        preGVT.approve(address(staking), type(uint256).max);
    }

    // ============ Deployment Tests ============

    function testDeployment() public view {
        assertEq(address(staking.stakeToken()), address(preGVT));
        assertEq(staking.treasury(), treasury);
        assertEq(staking.globalRewardCap(), REWARD_CAP);
        assertEq(staking.nextPositionId(), 1);
        assertEq(staking.totalStaked(), 0);
    }

    // ============ Staking Tests ============

    function testStake() public {
        uint256 stakeAmount = 1000e18;
        uint256 expectedLockEnd = block.timestamp + 30 days;

        vm.prank(user1);
        uint256 positionId = staking.stake(stakeAmount);

        assertEq(positionId, 1);
        assertEq(staking.totalStaked(), stakeAmount);
        assertEq(preGVT.balanceOf(address(staking)), stakeAmount);

        (uint256 amount, uint256 startTime, uint256 lockEndTime,,, bool active) = staking.positions(positionId);

        assertEq(amount, stakeAmount);
        assertEq(startTime, block.timestamp);
        assertEq(lockEndTime, expectedLockEnd);
        assertTrue(active);
    }

    function testStakeMultiplePositions() public {
        vm.startPrank(user1);
        uint256 pos1 = staking.stake(1000e18);
        uint256 pos2 = staking.stake(2000e18);
        vm.stopPrank();

        assertEq(pos1, 1);
        assertEq(pos2, 2);
        assertEq(staking.totalStaked(), 3000e18);

        uint256[] memory positions = staking.getUserPositions(user1);
        assertEq(positions.length, 2);
        assertEq(positions[0], pos1);
        assertEq(positions[1], pos2);
    }

    function testStakeRevertsZeroAmount() public {
        vm.expectRevert(PreGVTStaking.InvalidAmount.selector);
        vm.prank(user1);
        staking.stake(0);
    }

    function testStakeRevertsWhenPaused() public {
        vm.prank(owner);
        staking.pause();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(user1);
        staking.stake(1000e18);
    }

    // ============ Unstaking Tests ============

    function testUnstake() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18);

        // Fast forward past lock period
        vm.warp(block.timestamp + 31 days);

        uint256 balanceBefore = preGVT.balanceOf(user1);

        vm.prank(user1);
        staking.unstake(positionId);

        assertEq(preGVT.balanceOf(user1), balanceBefore + 1000e18);
        assertEq(staking.totalStaked(), 0);

        (,,,,, bool active) = staking.positions(positionId);
        assertFalse(active);
    }

    function testUnstakeRevertsBeforeLockEnd() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18);

        vm.expectRevert(PreGVTStaking.StillLocked.selector);
        vm.prank(user1);
        staking.unstake(positionId);
    }

    function testUnstakeRevertsNotOwner() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18);

        vm.warp(block.timestamp + 31 days);

        vm.expectRevert(PreGVTStaking.NotPositionOwner.selector);
        vm.prank(user2);
        staking.unstake(positionId);
    }

    // ============ Early Exit Tests ============

    function testEarlyExit() public {
        uint256 stakeAmount = 1000e18;

        vm.prank(user1);
        uint256 positionId = staking.stake(stakeAmount);

        uint256 expectedPenalty = (stakeAmount * 1000) / 10000; // 10%
        uint256 expectedAmount = stakeAmount - expectedPenalty;

        uint256 userBalanceBefore = preGVT.balanceOf(user1);
        uint256 treasuryBalanceBefore = preGVT.balanceOf(treasury);

        vm.expectEmit(true, true, true, true);
        emit EarlyExit(user1, positionId, expectedAmount, expectedPenalty);

        vm.prank(user1);
        staking.earlyExit(positionId);

        assertEq(preGVT.balanceOf(user1), userBalanceBefore + expectedAmount);
        assertEq(preGVT.balanceOf(treasury), treasuryBalanceBefore + expectedPenalty);
        assertEq(staking.totalStaked(), 0);
    }

    function testEarlyExitWithinLockPeriod() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18);

        vm.warp(block.timestamp + 15 days); // Mid-lock period

        vm.prank(user1);
        staking.earlyExit(positionId);

        // Should succeed even during lock
        (,,,,, bool active) = staking.positions(positionId);
        assertFalse(active);
    }

    // ============ Reward Calculation Tests ============

    function testCalculateRewardsSimple() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18);

        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);

        uint256 expectedRewards = (1000e18 * EMISSION_RATE * 1 days) / 1e18;
        uint256 actualRewards = staking.calculateRewards(positionId);

        assertApproxEqRel(actualRewards, expectedRewards, 0.01e18); // 1% tolerance
    }

    function testCalculateRewardsWithBoost() public {
        // Set 1.5x boost for user1
        boostOracle.setBoost(user1, 150);

        vm.prank(owner);
        staking.setBoostOracle(address(boostOracle));

        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18);

        vm.warp(block.timestamp + 1 days);

        uint256 baseRewards = (1000e18 * EMISSION_RATE * 1 days) / 1e18;
        uint256 expectedRewards = (baseRewards * 150) / 100; // 1.5x boost
        uint256 actualRewards = staking.calculateRewards(positionId);

        assertApproxEqRel(actualRewards, expectedRewards, 0.01e18);
    }

    function testCalculateRewardsMultiplePositions() public {
        vm.startPrank(user1);
        uint256 pos1 = staking.stake(1000e18);
        uint256 pos2 = staking.stake(2000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        uint256 rewards1 = staking.calculateRewards(pos1);
        uint256 rewards2 = staking.calculateRewards(pos2);

        // pos2 should have ~2x rewards of pos1
        assertApproxEqRel(rewards2, rewards1 * 2, 0.01e18);
    }

    // ============ Reward Claiming Tests (Pre-Launch) ============

    function testClaimBeforeRewardTokenSet() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18);

        vm.warp(block.timestamp + 1 days);

        uint256 expectedRewards = staking.calculateRewards(positionId);

        vm.prank(user1);
        staking.claim(positionId);

        // Rewards tracked but not transferred
        assertEq(staking.pendingRggp(user1), 0); // Claimed
        assertEq(rGGP.balanceOf(user1), 0); // No tokens yet
    }

    function testAccrueRewardsOverTime() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18);

        // Day 1
        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        staking.claim(positionId);

        uint256 pending1 = staking.pendingRggp(user1);
        assertTrue(pending1 == 0); // Already claimed

        // Day 2 - more rewards accrue
        vm.warp(block.timestamp + 1 days);
        uint256 rewards2 = staking.calculateRewards(positionId);
        assertTrue(rewards2 > 0);
    }

    // ============ Reward Claiming Tests (Post-Launch) ============

    function testClaimAfterRewardTokenSet() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18);

        vm.warp(block.timestamp + 1 days);

        // Set reward token
        vm.prank(owner);
        staking.setRewardToken(address(rGGP));

        uint256 expectedRewards = staking.calculateRewards(positionId);

        vm.prank(user1);
        staking.claim(positionId);

        // Should receive actual tokens
        assertApproxEqRel(rGGP.balanceOf(user1), expectedRewards, 0.01e18);
    }

    function testClaimAllPositions() public {
        vm.startPrank(user1);
        staking.stake(1000e18);
        staking.stake(2000e18);
        staking.stake(3000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        vm.prank(owner);
        staking.setRewardToken(address(rGGP));

        uint256 totalRewards = staking.getUserTotalRewards(user1);

        vm.prank(user1);
        staking.claimAll();

        assertApproxEqRel(rGGP.balanceOf(user1), totalRewards, 0.01e18);
    }

    function testClaimRevertsNoRewards() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18);

        // Try to claim immediately (no time passed)
        vm.expectRevert(PreGVTStaking.NoRewards.selector);
        vm.prank(user1);
        staking.claim(positionId);
    }

    // ============ Reward Cap Tests ============

    function testRewardCapEnforcement() public {
        // Set low cap for testing
        vm.prank(owner);
        staking.setGlobalRewardCap(100e18); // Very low cap

        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18);

        // Fast forward to generate rewards over cap
        vm.warp(block.timestamp + 365 days);

        vm.expectRevert(PreGVTStaking.RewardCapExceeded.selector);
        vm.prank(user1);
        staking.claim(positionId);
    }

    // ============ Epoch Configuration Tests ============

    function testConfigureEpoch() public {
        uint256 newEmissionRate = 2e15;
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 30 days;

        vm.prank(owner);
        staking.configureEpoch(1, newEmissionRate, startTime, endTime);

        (uint256 rate, uint256 start, uint256 end) = staking.epochs(1);
        assertEq(rate, newEmissionRate);
        assertEq(start, startTime);
        assertEq(end, endTime);
    }

    function testEpochSwitch() public {
        // Configure epoch 1 with double rewards
        vm.prank(owner);
        staking.configureEpoch(1, 2e15, block.timestamp, block.timestamp + 365 days);

        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18);

        // Get rewards in epoch 0
        vm.warp(block.timestamp + 1 days);
        uint256 rewardsEpoch0 = staking.calculateRewards(positionId);

        // Claim to reset
        vm.prank(user1);
        staking.claim(positionId);

        // Switch to epoch 1
        vm.prank(owner);
        staking.setCurrentEpoch(1);

        // Get rewards in epoch 1
        vm.warp(block.timestamp + 1 days);
        uint256 rewardsEpoch1 = staking.calculateRewards(positionId);

        // Epoch 1 should have ~2x rewards
        assertApproxEqRel(rewardsEpoch1, rewardsEpoch0 * 2, 0.01e18);
    }

    // ============ Admin Function Tests ============

    function testSetRewardToken() public {
        vm.prank(owner);
        staking.setRewardToken(address(rGGP));

        assertEq(address(staking.rewardToken()), address(rGGP));
        assertTrue(staking.rewardActive());
    }

    function testSetRewardTokenOnlyOnce() public {
        vm.startPrank(owner);
        staking.setRewardToken(address(rGGP));

        vm.expectRevert(PreGVTStaking.RewardTokenAlreadySet.selector);
        staking.setRewardToken(address(rGGP));
        vm.stopPrank();
    }

    function testSetTreasury() public {
        address newTreasury = address(999);

        vm.prank(owner);
        staking.setTreasury(newTreasury);

        assertEq(staking.treasury(), newTreasury);
    }

    function testSetBoostOracle() public {
        vm.prank(owner);
        staking.setBoostOracle(address(boostOracle));

        assertEq(address(staking.boostOracle()), address(boostOracle));
    }

    function testPauseUnpause() public {
        vm.startPrank(owner);
        staking.pause();
        assertTrue(staking.paused());

        staking.unpause();
        assertFalse(staking.paused());
        vm.stopPrank();
    }

    // ============ View Function Tests ============

    function testGetUserTotalRewards() public {
        vm.startPrank(user1);
        staking.stake(1000e18);
        staking.stake(2000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        uint256 totalRewards = staking.getUserTotalRewards(user1);
        uint256 expectedRewards = (3000e18 * EMISSION_RATE * 1 days) / 1e18;

        assertApproxEqRel(totalRewards, expectedRewards, 0.01e18);
    }

    function testIsUnlocked() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18);

        assertFalse(staking.isUnlocked(positionId));

        vm.warp(block.timestamp + 31 days);
        assertTrue(staking.isUnlocked(positionId));
    }

    function testGetRemainingLockTime() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18);

        uint256 remaining = staking.getRemainingLockTime(positionId);
        assertEq(remaining, 30 days);

        vm.warp(block.timestamp + 15 days);
        remaining = staking.getRemainingLockTime(positionId);
        assertEq(remaining, 15 days);

        vm.warp(block.timestamp + 20 days);
        remaining = staking.getRemainingLockTime(positionId);
        assertEq(remaining, 0);
    }

    // ============ Integration Tests ============

    function testFullStakingCycle() public {
        // 1. Stake
        vm.prank(user1);
        uint256 positionId = staking.stake(5000e18);

        // 2. Accrue rewards (pre-launch)
        vm.warp(block.timestamp + 10 days);

        uint256 pendingRewards = staking.calculateRewards(positionId);
        assertTrue(pendingRewards > 0);

        // 3. Set reward token
        vm.prank(owner);
        staking.setRewardToken(address(rGGP));

        // 4. Claim rewards
        vm.prank(user1);
        staking.claim(positionId);

        assertTrue(rGGP.balanceOf(user1) > 0);

        // 5. Unstake after lock
        vm.warp(block.timestamp + 25 days); // Total 35 days

        vm.prank(user1);
        staking.unstake(positionId);

        assertEq(preGVT.balanceOf(user1), 10000e18);
    }

    function testMultiUserStaking() public {
        // Multiple users stake
        vm.prank(user1);
        staking.stake(1000e18);

        vm.prank(user2);
        staking.stake(2000e18);

        vm.prank(user3);
        staking.stake(3000e18);

        assertEq(staking.totalStaked(), 6000e18);

        // Time passes
        vm.warp(block.timestamp + 5 days);

        // Set reward token
        vm.prank(owner);
        staking.setRewardToken(address(rGGP));

        // All users claim
        vm.prank(user1);
        staking.claimAll();

        vm.prank(user2);
        staking.claimAll();

        vm.prank(user3);
        staking.claimAll();

        // User3 should have ~3x rewards of user1
        uint256 rewards1 = rGGP.balanceOf(user1);
        uint256 rewards3 = rGGP.balanceOf(user3);

        assertApproxEqRel(rewards3, rewards1 * 3, 0.05e18); // 5% tolerance
    }

    // ============ EOA-Only Tests ============

    function testEOAOnlyEnforcement() public {
        // Re-enable EOA-only
        vm.prank(owner);
        staking.setEoaOnly(true);

        // Contract trying to stake should fail
        MockStaker mockStaker = new MockStaker(address(staking), address(preGVT));
        preGVT.mint(address(mockStaker), 1000e18);

        vm.expectRevert(PreGVTStaking.OnlyEOA.selector);
        mockStaker.attemptStake(1000e18);
    }

    function testDisableEOAOnly() public {
        // Already disabled in setUp, but let's test the flow
        vm.prank(owner);
        staking.setEoaOnly(false);

        // Now contract can stake
        MockStaker mockStaker = new MockStaker(address(staking), address(preGVT));
        preGVT.mint(address(mockStaker), 1000e18);

        mockStaker.attemptStake(1000e18);
        assertTrue(staking.totalStaked() > 0);
    }
}

/**
 * @title MockStaker
 * @notice Helper contract to test EOA-only enforcement
 */
contract MockStaker {
    PreGVTStaking public staking;
    IERC20 public preGVT;

    constructor(address _staking, address _preGVT) {
        staking = PreGVTStaking(_staking);
        preGVT = IERC20(_preGVT);
    }

    function attemptStake(uint256 amount) external {
        preGVT.approve(address(staking), amount);
        staking.stake(amount);
    }
}
