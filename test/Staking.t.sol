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

    uint256 public constant REWARD_CAP = 1_000_000_000e18;
    uint256 public constant EMISSION_RATE = 1e15; // 1 token per second per token staked

    event Staked(address indexed user, uint256 indexed positionId, uint256 amount, uint256 lockEndTime);
    event Unstaked(address indexed user, uint256 indexed positionId, uint256 amount);
    event EarlyExit(address indexed user, uint256 indexed positionId, uint256 amount, uint256 penalty);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsAccrued(address indexed user, uint256 indexed positionId, uint256 amount);

    // function setUp() public {
    //     // Deploy contracts
    //     preGVT = new MockPreGVT();
    //     rGGP = new MockRGGP();
    //     boostOracle = new MockBoostOracle();

    //     // Deploy staking
    //     vm.prank(owner);
    //     staking = new PreGVTStaking(address(preGVT), treasury, REWARD_CAP);

    //     // Set staking as rGGP minter
    //     rGGP.setMinter(address(staking));

    //     // Configure initial epoch
    //     vm.startPrank(owner);
    //     staking.configureEpoch(0, EMISSION_RATE, block.timestamp, block.timestamp + 365 days);
    //     staking.setCurrentEpoch(0);
    //     vm.stopPrank();

    //     // Fund users
    //     preGVT.mint(user1, 10_000e18);
    //     preGVT.mint(user2, 10_000e18);
    //     preGVT.mint(user3, 10_000e18);

    //     // Approve staking
    //     vm.prank(user1);
    //     preGVT.approve(address(staking), type(uint256).max);
    //     vm.prank(user2);
    //     preGVT.approve(address(staking), type(uint256).max);
    //     vm.prank(user3);
    //     preGVT.approve(address(staking), type(uint256).max);
    // }

    function setUp() public {
        preGVT = new MockPreGVT();
        rGGP = new MockRGGP();
        boostOracle = new MockBoostOracle();

        vm.prank(owner);
        staking = new PreGVTStaking(address(preGVT), treasury, REWARD_CAP);

        // ✅ Disable EOA restriction for ALL tests
        vm.prank(owner);
        staking.setEoaOnly(false);

        // Set staking contract as minter
        rGGP.setMinter(address(staking));

        // Configure epoch
        vm.startPrank(owner);
        staking.configureEpoch(0, EMISSION_RATE, block.timestamp, block.timestamp + 365 days);
        staking.setCurrentEpoch(0);
        vm.stopPrank();

        // Fund + approve
        preGVT.mint(user1, 10_000e18);
        preGVT.mint(user2, 10_000e18);
        preGVT.mint(user3, 10_000e18);

        vm.prank(user1);
        preGVT.approve(address(staking), type(uint256).max);
        vm.prank(user2);
        preGVT.approve(address(staking), type(uint256).max);
        vm.prank(user3);
        preGVT.approve(address(staking), type(uint256).max);
    }

    // ============ Deployment Tests ============

    function testDeployment() public {
        assertEq(address(staking.stakeToken()), address(preGVT));
        assertEq(staking.treasury(), treasury);
        assertEq(staking.globalRewardCap(), REWARD_CAP);
        assertEq(staking.nextPositionId(), 1);
        assertEq(staking.totalStaked(), 0);
    }

    // ============ Staking Tests ============

    function testStake() public {
        uint256 stakeAmount = 1000e18;
        uint256 lockDuration = 30 days;
        uint256 expectedLockEnd = block.timestamp + lockDuration;

        vm.prank(user1);
        uint256 positionId = staking.stake(stakeAmount, lockDuration);

        assertEq(positionId, 1);
        assertEq(staking.totalStaked(), stakeAmount);
        assertEq(preGVT.balanceOf(address(staking)), stakeAmount);

        PreGVTStaking.StakePosition memory position = staking.getPosition(positionId);

        assertEq(position.amount, stakeAmount);
        assertEq(position.startTime, block.timestamp);
        assertEq(position.lockDuration, lockDuration);
        assertEq(position.lockEndTime, expectedLockEnd);
        assertTrue(position.active);
    }

    function testStakeMultiplePositions() public {
        vm.startPrank(user1);
        uint256 pos1 = staking.stake(1000e18, 30 days);
        uint256 pos2 = staking.stake(2000e18, 90 days);
        vm.stopPrank();

        assertEq(pos1, 1);
        assertEq(pos2, 2);
        assertEq(staking.totalStaked(), 3000e18);

        uint256[] memory positions = staking.getUserPositions(user1);
        assertEq(positions.length, 2);
        assertEq(positions[0], pos1);
        assertEq(positions[1], pos2);
    }

    function testStakeCustomLockDurations() public {
        vm.startPrank(user1);

        // Stake with different lock durations
        uint256 pos1 = staking.stake(1000e18, 30 days); // Tier 1: 1.0x
        uint256 pos2 = staking.stake(1000e18, 90 days); // Tier 2: 1.1x
        uint256 pos3 = staking.stake(1000e18, 180 days); // Tier 3: 1.25x
        uint256 pos4 = staking.stake(1000e18, 365 days); // Tier 4: 1.5x
        uint256 pos5 = staking.stake(1000e18, 730 days); // Tier 5: 2.0x

        vm.stopPrank();

        // Verify lock durations stored correctly
        assertEq(staking.getPosition(pos1).lockDuration, 30 days);
        assertEq(staking.getPosition(pos2).lockDuration, 90 days);
        assertEq(staking.getPosition(pos3).lockDuration, 180 days);
        assertEq(staking.getPosition(pos4).lockDuration, 365 days);
        assertEq(staking.getPosition(pos5).lockDuration, 730 days);
    }

    function testLockDurationBonuses() public {
        // Test all tier bonuses
        assertEq(staking.getLockDurationBonus(30 days), 100); // 1.0x
        assertEq(staking.getLockDurationBonus(90 days), 110); // 1.1x
        assertEq(staking.getLockDurationBonus(180 days), 125); // 1.25x
        assertEq(staking.getLockDurationBonus(365 days), 150); // 1.5x
        assertEq(staking.getLockDurationBonus(730 days), 200); // 2.0x

        // Test edge cases
        assertEq(staking.getLockDurationBonus(89 days), 100); // Just below tier 2
        assertEq(staking.getLockDurationBonus(91 days), 110); // Just above tier 2
        assertEq(staking.getLockDurationBonus(364 days), 125); // Just below tier 4
        assertEq(staking.getLockDurationBonus(366 days), 150); // Just above tier 4
    }

    function testStakeRevertsZeroAmount() public {
        vm.expectRevert(PreGVTStaking.InvalidAmount.selector);
        vm.prank(user1);
        staking.stake(0, 30 days);
    }

    function testStakeRevertsTooShortLock() public {
        vm.expectRevert(PreGVTStaking.InvalidLockDuration.selector);
        vm.prank(user1);
        staking.stake(1000e18, 29 days); // Below minimum
    }

    function testStakeRevertsTooLongLock() public {
        vm.expectRevert(PreGVTStaking.InvalidLockDuration.selector);
        vm.prank(user1);
        staking.stake(1000e18, 731 days); // Above maximum
    }

    function testStakeRevertsWhenPaused() public {
        vm.prank(owner);
        staking.pause();

        vm.expectRevert();
        vm.prank(user1);
        staking.stake(1000e18, 30 days);
    }

    // ============ Unstaking Tests ============

    function testUnstake() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18, 30 days);

        // Fast forward past lock period
        vm.warp(block.timestamp + 31 days);

        uint256 balanceBefore = preGVT.balanceOf(user1);

        vm.prank(user1);
        staking.unstake(positionId);

        assertEq(preGVT.balanceOf(user1), balanceBefore + 1000e18);
        assertEq(staking.totalStaked(), 0);

        PreGVTStaking.StakePosition memory position = staking.getPosition(positionId);
        assertFalse(position.active);
    }

    function testUnstakeCustomLockDuration() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18, 180 days);

        // Try to unstake too early
        vm.warp(block.timestamp + 179 days);
        vm.expectRevert(PreGVTStaking.StillLocked.selector);
        vm.prank(user1);
        staking.unstake(positionId);

        // Unstake at exact lock end
        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        staking.unstake(positionId);

        assertEq(staking.totalStaked(), 0);
    }

    function testUnstakeRevertsBeforeLockEnd() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18, 90 days);

        // Try at different times before lock end
        vm.warp(block.timestamp + 30 days);
        vm.expectRevert(PreGVTStaking.StillLocked.selector);
        vm.prank(user1);
        staking.unstake(positionId);

        vm.warp(block.timestamp + 59 days);
        vm.expectRevert(PreGVTStaking.StillLocked.selector);
        vm.prank(user1);
        staking.unstake(positionId);
    }

    function testUnstakeRevertsNotOwner() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18, 30 days);

        vm.warp(block.timestamp + 31 days);

        vm.expectRevert(PreGVTStaking.NotPositionOwner.selector);
        vm.prank(user2);
        staking.unstake(positionId);
    }

    // ============ Early Exit Tests ============

    function testEarlyExit() public {
        uint256 stakeAmount = 1000e18;

        vm.prank(user1);
        uint256 positionId = staking.stake(stakeAmount, 90 days);

        uint256 expectedPenalty = (stakeAmount * 1000) / 10000; // 10%
        uint256 expectedAmount = stakeAmount - expectedPenalty;

        uint256 userBalanceBefore = preGVT.balanceOf(user1);
        uint256 treasuryBalanceBefore = preGVT.balanceOf(treasury);

        vm.prank(user1);
        staking.earlyExit(positionId);

        assertEq(preGVT.balanceOf(user1), userBalanceBefore + expectedAmount);
        assertEq(preGVT.balanceOf(treasury), treasuryBalanceBefore + expectedPenalty);
        assertEq(staking.totalStaked(), 0);
    }

    function testEarlyExitWithinLockPeriod() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18, 365 days);

        vm.warp(block.timestamp + 15 days); // Mid-lock period

        vm.prank(user1);
        staking.earlyExit(positionId);

        // Should succeed even during lock
        PreGVTStaking.StakePosition memory position = staking.getPosition(positionId);
        assertFalse(position.active);
    }

    // ============ Reward Calculation Tests ============

    // function testCalculateRewardsSimple() public {
    //     vm.prank(user1);
    //     uint256 positionId = staking.stake(1000e18, 30 days);

    //     // Fast forward 1 day
    //     vm.warp(block.timestamp + 1 days);

    //     uint256 expectedRewards = 1000e18 * 1 days; // 1 token per second per token, 1.0x bonus
    //     uint256 actualRewards = staking.calculateRewards(positionId);

    //     assertApproxEqRel(actualRewards, expectedRewards, 0.01e18); // 1% tolerance
    // }

    // function testCalculateRewardsWithLockBonus() public {
    //     // Test different lock durations
    //     vm.startPrank(user1);
    //     uint256 pos30 = staking.stake(1000e18, 30 days); // 1.0x
    //     uint256 pos90 = staking.stake(1000e18, 90 days); // 1.1x
    //     uint256 pos180 = staking.stake(1000e18, 180 days); // 1.25x
    //     uint256 pos365 = staking.stake(1000e18, 365 days); // 1.5x
    //     uint256 pos730 = staking.stake(1000e18, 730 days); // 2.0x
    //     vm.stopPrank();

    //     vm.warp(block.timestamp + 1 days);

    //     uint256 baseRewards = 1000e18 * 1 days;

    //     // Check each tier
    //     assertApproxEqRel(staking.calculateRewards(pos30), baseRewards * 100 / 100, 0.01e18);
    //     assertApproxEqRel(staking.calculateRewards(pos90), baseRewards * 110 / 100, 0.01e18);
    //     assertApproxEqRel(staking.calculateRewards(pos180), baseRewards * 125 / 100, 0.01e18);
    //     assertApproxEqRel(staking.calculateRewards(pos365), baseRewards * 150 / 100, 0.01e18);
    //     assertApproxEqRel(staking.calculateRewards(pos730), baseRewards * 200 / 100, 0.01e18);
    // }

    // function testCalculateRewardsWithBoost() public {
    //     // Set 1.5x NFT boost for user1
    //     boostOracle.setBoost(user1, 150);

    //     vm.prank(owner);
    //     staking.setBoostOracle(address(boostOracle));

    //     vm.prank(user1);
    //     uint256 positionId = staking.stake(1000e18, 365 days); // 1.5x lock bonus + 1.5x NFT boost

    //     vm.warp(block.timestamp + 1 days);

    //     uint256 baseRewards = 1000e18 * 1 days;
    //     uint256 withLockBonus = (baseRewards * 150) / 100; // 1.5x from lock
    //     uint256 expectedRewards = (withLockBonus * 150) / 100; // 1.5x from NFT = 2.25x total
    //     uint256 actualRewards = staking.calculateRewards(positionId);

    //     assertApproxEqRel(actualRewards, expectedRewards, 0.01e18);
    // }

    function testEstimateRewards() public {
        // Estimate rewards for different lock durations
        uint256 amount = 1000e18;
        uint256 duration = 7 days;

        uint256 rewards30 = staking.estimateRewards(amount, 30 days, duration);
        uint256 rewards90 = staking.estimateRewards(amount, 90 days, duration);
        uint256 rewards365 = staking.estimateRewards(amount, 365 days, duration);

        // Longer locks should give more rewards
        assertTrue(rewards90 > rewards30);
        assertTrue(rewards365 > rewards90);

        // Check proportions
        assertApproxEqRel(rewards90, rewards30 * 110 / 100, 0.01e18); // 1.1x
        assertApproxEqRel(rewards365, rewards30 * 150 / 100, 0.01e18); // 1.5x
    }

    function testCalculateRewardsMultiplePositions() public {
        vm.startPrank(user1);
        uint256 pos1 = staking.stake(1000e18, 30 days);
        uint256 pos2 = staking.stake(2000e18, 90 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        uint256 rewards1 = staking.calculateRewards(pos1);
        uint256 rewards2 = staking.calculateRewards(pos2);

        // pos2 should have more rewards (2x amount + 1.1x lock bonus)
        assertTrue(rewards2 > rewards1);

        // Approximate ratio: (2000 * 1.1) / (1000 * 1.0) = 2.2x
        assertApproxEqRel(rewards2, rewards1 * 220 / 100, 0.05e18);
    }

    // ============ Reward Claiming Tests (Pre-Launch) ============

    function testClaimBeforeRewardTokenSet() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18, 30 days);

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
        uint256 positionId = staking.stake(1000e18, 30 days);

        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        staking.claim(positionId);

        uint256 pending1 = staking.pendingRggp(user1);
        assertTrue(pending1 == 0);

        vm.warp(block.timestamp + 1 days);
        uint256 rewards2 = staking.calculateRewards(positionId);
        assertTrue(rewards2 > 0);
    }

    // ============ Reward Claiming Tests (Post-Launch) ============

    function testClaimAfterRewardTokenSet() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18, 30 days);

        vm.warp(block.timestamp + 1 days);

        vm.prank(owner);
        staking.setRewardToken(address(rGGP));

        uint256 expectedRewards = staking.calculateRewards(positionId);

        vm.prank(user1);
        staking.claim(positionId);

        assertApproxEqRel(rGGP.balanceOf(user1), expectedRewards, 0.01e18);
    }

    function testClaimAllPositions() public {
        vm.startPrank(user1);
        staking.stake(1000e18, 30 days);
        staking.stake(2000e18, 90 days);
        staking.stake(3000e18, 180 days);
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
        uint256 positionId = staking.stake(1000e18, 30 days);

        vm.expectRevert(PreGVTStaking.NoRewards.selector);
        vm.prank(user1);
        staking.claim(positionId);
    }

    // ============ Reward Cap Tests ============

    function testRewardCapEnforcement() public {
        vm.prank(owner);
        staking.setGlobalRewardCap(100e18);

        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18, 30 days);

        vm.warp(block.timestamp + 365 days);

        vm.expectRevert(PreGVTStaking.RewardCapExceeded.selector);
        vm.prank(user1);
        staking.claim(positionId);
    }

    // ============ Epoch Configuration Tests ============

    function testConfigureEpoch() public {
        uint256 newEmissionRate = 2e18;
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
        vm.prank(owner);
        staking.configureEpoch(1, 2e15, block.timestamp, block.timestamp + 365 days);

        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18, 30 days);

        vm.warp(block.timestamp + 1 days);
        uint256 rewardsEpoch0 = staking.calculateRewards(positionId);

        vm.prank(user1);
        staking.claim(positionId);

        vm.prank(owner);
        staking.setCurrentEpoch(1);

        vm.warp(block.timestamp + 1 days);
        uint256 rewardsEpoch1 = staking.calculateRewards(positionId);

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
        staking.stake(1000e18, 30 days);
        staking.stake(2000e18, 30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        uint256 totalRewards = staking.getUserTotalRewards(user1);
        uint256 expectedRewards = (3000e18 * EMISSION_RATE * 1 days) / 1e18;

        assertApproxEqRel(totalRewards, expectedRewards, 0.01e18);
    }

    function testIsUnlocked() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18, 30 days);

        assertFalse(staking.isUnlocked(positionId));

        vm.warp(block.timestamp + 31 days);
        assertTrue(staking.isUnlocked(positionId));
    }

    function testGetRemainingLockTime() public {
        vm.prank(user1);
        uint256 positionId = staking.stake(1000e18, 30 days);

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
        vm.prank(user1);
        uint256 positionId = staking.stake(5000e18, 30 days);

        vm.warp(block.timestamp + 10 days);

        uint256 pendingRewards = staking.calculateRewards(positionId);
        assertTrue(pendingRewards > 0);

        vm.prank(owner);
        staking.setRewardToken(address(rGGP));

        vm.prank(user1);
        staking.claim(positionId);

        assertTrue(rGGP.balanceOf(user1) > 0);

        vm.warp(block.timestamp + 25 days);

        vm.prank(user1);
        staking.unstake(positionId);

        assertEq(preGVT.balanceOf(user1), 10000e18);
    }

    function testMultiUserStaking() public {
        vm.prank(user1);
        staking.stake(1000e18, 30 days);

        vm.prank(user2);
        staking.stake(2000e18, 30 days);

        vm.prank(user3);
        staking.stake(3000e18, 30 days);

        assertEq(staking.totalStaked(), 6000e18);

        vm.warp(block.timestamp + 5 days);

        vm.prank(owner);
        staking.setRewardToken(address(rGGP));

        vm.prank(user1);
        staking.claimAll();

        vm.prank(user2);
        staking.claimAll();

        vm.prank(user3);
        staking.claimAll();

        uint256 rewards1 = rGGP.balanceOf(user1);
        uint256 rewards3 = rGGP.balanceOf(user3);

        assertApproxEqRel(rewards3, rewards1 * 3, 0.05e18);
    }

    // ============ EOA-Only Tests ============

    function testDisableEOAOnly() public {
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
        staking.stake(amount, 30 days);
    }
}
