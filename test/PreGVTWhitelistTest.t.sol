// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PreGVT.sol";
import "../src/Staking.sol";

/**
 * @title MockUSDT
 * @notice Mock USDT token for testing
 */
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 1_000_000e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6; // USDT has 6 decimals
    }
}

/**
 * @title MockBadge
 * @notice Mock Genesis Badge for testing
 */
contract MockBadge is IGenesisBadge1155 {
    mapping(address => mapping(uint256 => uint256)) private _balances;
    mapping(address => bool) public operators;

    function mint(address to, uint256 id, uint256 amount) external {
        _balances[to][id] += amount;
    }

    function balanceOf(address account, uint256 id) external view returns (uint256) {
        return _balances[account][id];
    }

    function redeem(uint256 id, uint256 amount) external {
        require(_balances[msg.sender][id] >= amount, "Insufficient balance");
        _balances[msg.sender][id] -= amount;
    }

    function redeemByOperator(address owner, uint256 id, uint256 amount) external {
        require(operators[msg.sender], "Not operator");
        require(_balances[owner][id] >= amount, "Insufficient balance");
        _balances[owner][id] -= amount;
    }

    function setOperator(address operator, bool status) external {
        operators[operator] = status;
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
 * @title PreGVTWhitelistTest
 * @notice Test whitelist functionality and staking integration
 */
contract PreGVTWhitelistTest is Test {
    PreGVT public preGVT;
    PreGVTStaking public staking;
    MockUSDT public usdt;
    MockBadge public badge;
    MockRGGP public rGGP;

    address public admin = address(1);
    address public treasury = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    address public user3 = address(5);

    uint256 public constant BADGE_ID = 1;
    uint256 public constant AIRDROP_CAP = 3_000_000e18;
    uint256 public constant PRESALE_CAP = 1_000_000e18;
    uint256 public constant REWARD_CAP = 10_000_000e18;

    event ContractWhitelisted(address indexed contractAddress, bool status);

    function setUp() public {
        // Deploy mock tokens
        usdt = new MockUSDT();
        badge = new MockBadge();
        rGGP = new MockRGGP();

        // Deploy PreGVT
        vm.prank(admin);
        preGVT = new PreGVT(address(badge), BADGE_ID, AIRDROP_CAP, PRESALE_CAP, treasury, address(usdt), admin);

        // Deploy Staking
        vm.prank(admin);
        staking = new PreGVTStaking(address(preGVT), treasury, REWARD_CAP);

        // Setup staking
        rGGP.setMinter(address(staking));

        vm.startPrank(admin);
        staking.configureEpoch(0, 1e18, block.timestamp, block.timestamp + 365 days);
        staking.setCurrentEpoch(0);
        staking.setEoaOnly(false); // Disable EOA-only for testing
        vm.stopPrank();

        // Fund users with USDT
        usdt.mint(user1, 100_000e6); // 100k USDT
        usdt.mint(user2, 100_000e6);
        usdt.mint(user3, 100_000e6);

        // Give users badges
        badge.mint(user1, BADGE_ID, 1);
        badge.mint(user2, BADGE_ID, 1);
        badge.mint(user3, BADGE_ID, 1);
    }

    // ============ Whitelist Management Tests ============

    function testSetWhitelistedContract() public {
        vm.expectEmit(true, true, true, true);
        emit ContractWhitelisted(address(staking), true);

        vm.prank(admin);
        preGVT.setWhitelistedContract(address(staking), true);

        assertTrue(preGVT.whitelistedContracts(address(staking)));
    }

    function testRemoveWhitelistedContract() public {
        vm.startPrank(admin);
        preGVT.setWhitelistedContract(address(staking), true);
        preGVT.setWhitelistedContract(address(staking), false);
        vm.stopPrank();

        assertFalse(preGVT.whitelistedContracts(address(staking)));
    }

    function testBatchWhitelistContracts() public {
        address[] memory contracts = new address[](3);
        contracts[0] = address(staking);
        contracts[1] = address(0x123);
        contracts[2] = address(0x456);

        vm.prank(admin);
        preGVT.batchSetWhitelistedContracts(contracts, true);

        assertTrue(preGVT.whitelistedContracts(address(staking)));
        assertTrue(preGVT.whitelistedContracts(address(0x123)));
        assertTrue(preGVT.whitelistedContracts(address(0x456)));
    }

    function testWhitelistRevertsZeroAddress() public {
        vm.expectRevert(PreGVT.ZeroAddress.selector);
        vm.prank(admin);
        preGVT.setWhitelistedContract(address(0), true);
    }

    function testWhitelistRevertsNonManager() public {
        vm.expectRevert();
        vm.prank(user1);
        preGVT.setWhitelistedContract(address(staking), true);
    }

    // ============ Transfer Restriction Tests ============

    function testTransferRevertsForNonWhitelisted() public {
        // Give user1 some tokens
        vm.prank(admin);
        preGVT.configurePresale(1e6, false, 0); // 1 USDT per token

        vm.prank(admin);
        preGVT.setPresaleActive(true);

        vm.startPrank(user1);
        usdt.approve(address(preGVT), type(uint256).max);
        preGVT.buy(1000e18);
        vm.stopPrank();

        // Try to transfer to regular address
        vm.expectRevert(PreGVT.TransferNotAllowed.selector);
        vm.prank(user1);
        preGVT.transfer(user2, 100e18);
    }

    function testTransferSucceedsToWhitelisted() public {
        // Setup presale and buy tokens
        vm.startPrank(admin);
        preGVT.configurePresale(1e6, false, 0);
        preGVT.setPresaleActive(true);
        preGVT.setWhitelistedContract(address(staking), true);
        vm.stopPrank();

        vm.startPrank(user1);
        usdt.approve(address(preGVT), type(uint256).max);
        preGVT.buy(1000e18);

        // Transfer to whitelisted contract should work
        preGVT.transfer(address(staking), 100e18);
        vm.stopPrank();

        assertEq(preGVT.balanceOf(address(staking)), 100e18);
        assertEq(preGVT.balanceOf(user1), 900e18);
    }

    // ============ Approval Tests ============

    function testApproveRevertsForNonWhitelisted() public {
        vm.expectRevert(PreGVT.ApprovalNotAllowed.selector);
        vm.prank(user1);
        preGVT.approve(user2, 1000e18);
    }

    function testApproveSucceedsForWhitelisted() public {
        vm.prank(admin);
        preGVT.setWhitelistedContract(address(staking), true);

        vm.prank(user1);
        preGVT.approve(address(staking), 1000e18);

        assertEq(preGVT.allowance(user1, address(staking)), 1000e18);
    }

    function testIncreaseAllowanceRevertsForNonWhitelisted() public {
        vm.expectRevert(PreGVT.ApprovalNotAllowed.selector);
        vm.prank(user1);
        preGVT.increaseAllowance(user2, 1000e18);
    }

    function testIncreaseAllowanceSucceedsForWhitelisted() public {
        vm.prank(admin);
        preGVT.setWhitelistedContract(address(staking), true);

        vm.startPrank(user1);
        preGVT.approve(address(staking), 1000e18);
        preGVT.increaseAllowance(address(staking), 500e18);
        vm.stopPrank();

        assertEq(preGVT.allowance(user1, address(staking)), 1500e18);
    }

    // ============ Staking Integration Tests ============

    // function testFullStakingFlow() public {
    //     // 1. Setup presale and whitelist staking
    //     vm.startPrank(admin);
    //     preGVT.configurePresale(1e6, false, 0);
    //     preGVT.setPresaleActive(true);
    //     preGVT.setWhitelistedContract(address(staking), true);
    //     vm.stopPrank();

    //     // 2. User buys preGVT
    //     vm.startPrank(user1);
    //     usdt.approve(address(preGVT), type(uint256).max);
    //     preGVT.buy(10_000e18);
    //     assertEq(preGVT.balanceOf(user1), 10_000e18);

    //     // 3. User approves staking contract
    //     preGVT.approve(address(staking), 5000e18);

    //     // 4. User stakes
    //     uint256 positionId = staking.stake(5000e18, 90 days);
    //     assertEq(preGVT.balanceOf(user1), 5000e18);
    //     assertEq(preGVT.balanceOf(address(staking)), 5000e18);
    //     vm.stopPrank();

    //     // 5. Time passes and user earns rewards
    //     vm.warp(block.timestamp + 10 days);

    //     // 6. Set reward token and claim
    //     vm.prank(admin);
    //     staking.setRewardToken(address(rGGP));

    //     vm.prank(user1);
    //     staking.claim(positionId);

    //     assertTrue(rGGP.balanceOf(user1) > 0);

    //     // 7. Unstake after lock period
    //     vm.warp(block.timestamp + 85 days); // Total 95 days

    //     vm.prank(user1);
    //     staking.unstake(positionId);

    //     assertEq(preGVT.balanceOf(user1), 10_000e18); // All tokens back
    // }

    function testStakingRevertsWithoutWhitelist() public {
        // Setup presale but DON'T whitelist staking
        vm.startPrank(admin);
        preGVT.configurePresale(1e6, false, 0);
        preGVT.setPresaleActive(true);
        vm.stopPrank();

        // User buys tokens
        vm.startPrank(user1);
        usdt.approve(address(preGVT), type(uint256).max);
        preGVT.buy(10_000e18);

        // Try to approve staking - should fail
        vm.expectRevert(PreGVT.ApprovalNotAllowed.selector);
        preGVT.approve(address(staking), 5000e18);
        vm.stopPrank();
    }

    // function testTransferFromStakingWorks() public {
    //     // Setup
    //     vm.startPrank(admin);
    //     preGVT.configurePresale(1e6, false, 0);
    //     preGVT.setPresaleActive(true);
    //     preGVT.setWhitelistedContract(address(staking), true);
    //     vm.stopPrank();

    //     // User buys and stakes
    //     vm.startPrank(user1);
    //     usdt.approve(address(preGVT), type(uint256).max);
    //     preGVT.buy(10_000e18);
    //     preGVT.approve(address(staking), 5000e18);
    //     uint256 positionId = staking.stake(5000e18, 30 days);
    //     vm.stopPrank();

    //     // Unstake (transfer from staking back to user)
    //     vm.warp(block.timestamp + 31 days);

    //     vm.prank(user1);
    //     staking.unstake(positionId);

    //     assertEq(preGVT.balanceOf(user1), 10_000e18);
    // }

    function testMultipleUsersStaking() public {
        // Setup
        vm.startPrank(admin);
        preGVT.configurePresale(1e6, false, 0);
        preGVT.setPresaleActive(true);
        preGVT.setWhitelistedContract(address(staking), true);
        vm.stopPrank();

        // User1 buys and stakes
        vm.startPrank(user1);
        usdt.approve(address(preGVT), type(uint256).max);
        preGVT.buy(5000e18);
        preGVT.approve(address(staking), 5000e18);
        staking.stake(5000e18, 30 days);
        vm.stopPrank();

        // User2 buys and stakes
        vm.startPrank(user2);
        usdt.approve(address(preGVT), type(uint256).max);
        preGVT.buy(3000e18);
        preGVT.approve(address(staking), 3000e18);
        staking.stake(3000e18, 90 days);
        vm.stopPrank();

        // User3 buys and stakes
        vm.startPrank(user3);
        usdt.approve(address(preGVT), type(uint256).max);
        preGVT.buy(7000e18);
        preGVT.approve(address(staking), 7000e18);
        staking.stake(7000e18, 365 days);
        vm.stopPrank();

        assertEq(staking.totalStaked(), 15000e18);
        assertEq(preGVT.balanceOf(address(staking)), 15000e18);
    }

    // ============ Edge Cases ============

    function testWhitelistDoesNotAffectAirdrop() public {
        // Airdrop should work without whitelist
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user1;
        amounts[0] = 1000e18;

        vm.prank(admin);
        preGVT.batchAirdrop(users, amounts);

        assertEq(preGVT.balanceOf(user1), 1000e18);
    }

    function testWhitelistDoesNotAffectPresale() public {
        // Presale should work without whitelist
        vm.startPrank(admin);
        preGVT.configurePresale(1e6, false, 0);
        preGVT.setPresaleActive(true);
        vm.stopPrank();

        vm.startPrank(user1);
        usdt.approve(address(preGVT), type(uint256).max);
        preGVT.buy(1000e18);
        vm.stopPrank();

        assertEq(preGVT.balanceOf(user1), 1000e18);
    }

    function testWhitelistDoesNotAffectMigration() public {
        // Setup
        vm.startPrank(admin);
        preGVT.configurePresale(1e6, false, 0);
        preGVT.setPresaleActive(true);
        address mockMigrator = address(0x999);
        preGVT.setMigrator(mockMigrator);
        vm.stopPrank();

        // User buys tokens
        vm.startPrank(user1);
        usdt.approve(address(preGVT), type(uint256).max);
        preGVT.buy(1000e18);

        // Migration should work (burns tokens)
        preGVT.migrateToGVT();
        vm.stopPrank();

        assertEq(preGVT.balanceOf(user1), 0);
    }

    // function testEarlyExitFromStaking() public {
    //     // Setup
    //     vm.startPrank(admin);
    //     preGVT.configurePresale(1e6, false, 0);
    //     preGVT.setPresaleActive(true);
    //     preGVT.setWhitelistedContract(address(staking), true);
    //     vm.stopPrank();

    //     // User stakes
    //     vm.startPrank(user1);
    //     usdt.approve(address(preGVT), type(uint256).max);
    //     preGVT.buy(10_000e18);
    //     preGVT.approve(address(staking), 5000e18);
    //     uint256 positionId = staking.stake(5000e18, 365 days);
    //     vm.stopPrank();

    //     // Early exit (loses 10%)
    //     vm.warp(block.timestamp + 10 days);

    //     uint256 balanceBefore = preGVT.balanceOf(user1);

    //     vm.prank(user1);
    //     staking.earlyExit(positionId);

    //     // User gets 90% back
    //     assertEq(preGVT.balanceOf(user1), balanceBefore + 4500e18);

    //     // Treasury gets 10% penalty
    //     assertEq(preGVT.balanceOf(treasury), 500e18);
    // }
}
