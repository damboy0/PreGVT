// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PreGVT.sol";

/**
 * @title MockGenesisBadge
 * @notice Mock implementation of Genesis Badge for testing
 */
contract MockGenesisBadge is IGenesisBadge1155 {
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
 * @title PreGVTTest
 * @notice Comprehensive test suite for PreGVT contract
 */
contract PreGVTTest is Test {
    PreGVT public preGVT;
    MockGenesisBadge public badge;

    address public admin = address(1);
    address public distributor = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    address public user3 = address(5);
    address public migrator = address(6);

    uint256 public constant BADGE_ID = 1;
    uint256 public constant AIRDROP_RESERVE_CAP = 1_000_000e18; // 1M tokens
    uint256 public constant PRESALE_RESERVE_CAP = 1_000_000e18; // 1M tokens


    event AirdropReserveDefined(uint256 cap);
    event AirdropDistributed(address indexed to, uint256 amount, uint256 newTotalMinted);
    event BatchAirdrop(uint256 indexed count, uint256 totalAmount);
    event BadgeConsumed(address indexed user, uint256 indexed badgeId, uint256 amount);
    event MigrationEnabled(address indexed migrator);
    event Migrated(address indexed user, uint256 preGVTAmount);
    event AllocationSet(address indexed user, uint256 amount);

    function setUp() public {
        // Deploy mock badge
        badge = new MockGenesisBadge();

        // Deploy PreGVT
        vm.prank(admin);
        preGVT = new PreGVT(address(badge), BADGE_ID, AIRDROP_RESERVE_CAP,PRESALE_RESERVE_CAP, admin);

        // Set PreGVT as operator on badge
        badge.setOperator(address(preGVT), true);

        // Setup roles
        vm.startPrank(admin);
        preGVT.grantRole(preGVT.DISTRIBUTOR_ROLE(), distributor);
        vm.stopPrank();

        // Mint badges to test users
        badge.mint(user1, BADGE_ID, 1);
        badge.mint(user2, BADGE_ID, 1);
        badge.mint(user3, BADGE_ID, 1);
    }

    // ============ Deployment Tests ============

    function testDeployment() public {
        assertEq(address(preGVT.badge()), address(badge));
        assertEq(preGVT.badgeId(), BADGE_ID);
        assertEq(preGVT.airdropReserveCap(), AIRDROP_RESERVE_CAP);
        //  assertEq(preGVT.presaleReserveCap(), PRESALE_RESERVE_CAP);
        assertEq(preGVT.airdropReserveMinted(), 0);
        assertTrue(preGVT.hasRole(preGVT.DEFAULT_ADMIN_ROLE(), admin));
    }

    // function testDeploymentEmitsEvent() public {
    //     vm.expectEmit(true, true, true, true);
    //     emit AirdropReserveDefined(RESERVE_CAP);

    //     vm.prank(admin);
    //     new PreGVT(address(badge), BADGE_ID, RESERVE_CAP, admin);
    // }

    // function testDeploymentRevertsZeroAddress() public {
    //     vm.expectRevert(PreGVT.ZeroAddress.selector);
    //     new PreGVT(address(0), BADGE_ID, RESERVE_CAP, admin);

    //     vm.expectRevert(PreGVT.ZeroAddress.selector);
    //     new PreGVT(address(badge), BADGE_ID, RESERVE_CAP, address(0));
    // }

    // function testDeploymentRevertsZeroAmount() public {
    //     vm.expectRevert(PreGVT.ZeroAmount.selector);
    //     new PreGVT(address(badge), BADGE_ID, 0, admin);
    // }

    // ============ View Function Tests ============

    function testAirdropReserveRemaining() public {
        assertEq(preGVT.airdropReserveRemaining(), AIRDROP_RESERVE_CAP);

        // Mint some tokens
        vm.startPrank(distributor);
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user1;
        amounts[0] = 1000e18;
        preGVT.batchAirdrop(users, amounts);
        vm.stopPrank();

        assertEq(preGVT.airdropReserveRemaining(), AIRDROP_RESERVE_CAP - 1000e18);
    }

    function testHasBadge() public {
        assertTrue(preGVT.hasBadge(user1));
        assertFalse(preGVT.hasBadge(address(999)));
    }

    function testAllowanceOf() public {
        assertEq(preGVT.allowanceOf(user1), 0);

        // Set allocation
        vm.startPrank(distributor);
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user1;
        amounts[0] = 500e18;
        preGVT.setAllocations(users, amounts);
        vm.stopPrank();

        assertEq(preGVT.allowanceOf(user1), 500e18);
    }

    // ============ Admin Function Tests ============

    function testPauseUnpause() public {
        vm.startPrank(admin);
        preGVT.pause();
        assertTrue(preGVT.paused());

        preGVT.unpause();
        assertFalse(preGVT.paused());
        vm.stopPrank();
    }

    function testPauseRevertsNonAdmin() public {
        vm.expectRevert();
        vm.prank(user1);
        preGVT.pause();
    }

    function testSetMigrator() public {
        vm.expectEmit(true, true, true, true);
        emit MigrationEnabled(migrator);

        vm.prank(admin);
        preGVT.setMigrator(migrator);

        assertEq(preGVT.migrator(), migrator);
        assertTrue(preGVT.migrationEnabled());
    }

    function testSetMigratorOnlyOnce() public {
        vm.startPrank(admin);
        preGVT.setMigrator(migrator);

        vm.expectRevert(PreGVT.InvalidMigrator.selector);
        preGVT.setMigrator(address(7));
        vm.stopPrank();
    }

    function testSetMigratorRevertsZeroAddress() public {
        vm.expectRevert(PreGVT.InvalidMigrator.selector);
        vm.prank(admin);
        preGVT.setMigrator(address(0));
    }

    // ============ SetAllocations Tests ============

    function testSetAllocations() public {
        address[] memory users = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        users[0] = user1;
        users[1] = user2;
        amounts[0] = 1000e18;
        amounts[1] = 2000e18;

        vm.expectEmit(true, true, true, true);
        emit AllocationSet(user1, 1000e18);
        vm.expectEmit(true, true, true, true);
        emit AllocationSet(user2, 2000e18);

        vm.prank(distributor);
        preGVT.setAllocations(users, amounts);

        assertEq(preGVT.claimable(user1), 1000e18);
        assertEq(preGVT.claimable(user2), 2000e18);
    }

    function testSetAllocationsAccumulates() public {
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user1;
        amounts[0] = 1000e18;

        vm.startPrank(distributor);
        preGVT.setAllocations(users, amounts);
        assertEq(preGVT.claimable(user1), 1000e18);

        preGVT.setAllocations(users, amounts);
        assertEq(preGVT.claimable(user1), 2000e18);
        vm.stopPrank();
    }

    function testSetAllocationsRevertsArrayMismatch() public {
        address[] memory users = new address[](2);
        uint256[] memory amounts = new uint256[](1);

        vm.expectRevert(PreGVT.ArrayLengthMismatch.selector);
        vm.prank(distributor);
        preGVT.setAllocations(users, amounts);
    }

    function testSetAllocationsRevertsZeroAddress() public {
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = address(0);
        amounts[0] = 1000e18;

        vm.expectRevert(PreGVT.ZeroAddress.selector);
        vm.prank(distributor);
        preGVT.setAllocations(users, amounts);
    }

    function testSetAllocationsRevertsNonDistributor() public {
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        vm.expectRevert();
        vm.prank(user1);
        preGVT.setAllocations(users, amounts);
    }

    // ============ BatchAirdrop Tests ============

    function testBatchAirdrop() public {
        address[] memory users = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        users[0] = user1;
        users[1] = user2;
        amounts[0] = 1000e18;
        amounts[1] = 2000e18;

        vm.expectEmit(true, true, true, true);
        emit AirdropDistributed(user1, 1000e18, 1000e18);
        vm.expectEmit(true, true, true, true);
        emit AirdropDistributed(user2, 2000e18, 3000e18);
        vm.expectEmit(true, true, true, true);
        emit BatchAirdrop(2, 3000e18);

        vm.prank(distributor);
        preGVT.batchAirdrop(users, amounts);

        assertEq(preGVT.balanceOf(user1), 1000e18);
        assertEq(preGVT.balanceOf(user2), 2000e18);
        assertEq(preGVT.airdropReserveMinted(), 3000e18);
    }

    function testBatchAirdropRevertsNoBadge() public {
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = address(999); // No badge
        amounts[0] = 1000e18;

        vm.expectRevert(PreGVT.NoBadge.selector);
        vm.prank(distributor);
        preGVT.batchAirdrop(users, amounts);
    }

    function testBatchAirdropRevertsCapExceeded() public {
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user1;
        amounts[0] = AIRDROP_RESERVE_CAP + 1;

        vm.expectRevert(PreGVT.ReserveCapExceeded.selector);
        vm.prank(distributor);
        preGVT.batchAirdrop(users, amounts);
    }

    function testBatchAirdropRevertsWhenPaused() public {
        vm.prank(admin);
        preGVT.pause();

        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user1;
        amounts[0] = 1000e18;

        vm.expectRevert();
        vm.prank(distributor);
        preGVT.batchAirdrop(users, amounts);
    }

    // ============ ClaimAllocated Tests ============

    function testClaimAllocated() public {
        // Set allocation
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user1;
        amounts[0] = 5000e18;

        vm.prank(distributor);
        preGVT.setAllocations(users, amounts);

        uint256 initialBadgeBalance = badge.balanceOf(user1, BADGE_ID);

        vm.expectEmit(true, true, true, true);
        emit BadgeConsumed(user1, BADGE_ID, 1);
        vm.expectEmit(true, true, true, true);
        emit AirdropDistributed(user1, 5000e18, 5000e18);

        vm.prank(user1);
        preGVT.claimAllocated();

        assertEq(preGVT.balanceOf(user1), 5000e18);
        assertEq(preGVT.claimable(user1), 0);
        assertEq(badge.balanceOf(user1, BADGE_ID), initialBadgeBalance - 1);
    }

    function testClaimAllocatedRevertsNoAllocation() public {
        vm.expectRevert(PreGVT.NoAllocation.selector);
        vm.prank(user1);
        preGVT.claimAllocated();
    }

    function testClaimAllocatedRevertsNoBadge() public {
        // Set allocation but remove badge
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = address(999);
        amounts[0] = 1000e18;

        vm.prank(distributor);
        preGVT.setAllocations(users, amounts);

        vm.expectRevert(PreGVT.NoBadge.selector);
        vm.prank(address(999));
        preGVT.claimAllocated();
    }

    // ============ ClaimWithBadge Tests ============

    function testClaimWithBadge() public {
        uint256 claimAmount = 7500e18;
        uint256 initialBadgeBalance = badge.balanceOf(user1, BADGE_ID);

        vm.expectEmit(true, true, true, true);
        emit BadgeConsumed(user1, BADGE_ID, 1);
        vm.expectEmit(true, true, true, true);
        emit AirdropDistributed(user1, claimAmount, claimAmount);

        vm.prank(user1);
        preGVT.claimWithBadge(claimAmount);

        assertEq(preGVT.balanceOf(user1), claimAmount);
        assertEq(badge.balanceOf(user1, BADGE_ID), initialBadgeBalance - 1);
    }

    function testClaimWithBadgeRevertsZeroAmount() public {
        vm.expectRevert(PreGVT.ZeroAmount.selector);
        vm.prank(user1);
        preGVT.claimWithBadge(0);
    }

    function testClaimWithBadgeRevertsNoBadge() public {
        vm.expectRevert(PreGVT.NoBadge.selector);
        vm.prank(address(999));
        preGVT.claimWithBadge(1000e18);
    }

    // ============ Migration Tests ============

    function testMigrateToGVT() public {
        // Setup: give user1 some preGVT
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user1;
        amounts[0] = 10000e18;

        vm.prank(distributor);
        preGVT.batchAirdrop(users, amounts);

        // Enable migration
        vm.prank(admin);
        preGVT.setMigrator(migrator);

        uint256 balanceBefore = preGVT.balanceOf(user1);

        vm.expectEmit(true, true, true, true);
        emit Migrated(user1, balanceBefore);

        vm.prank(user1);
        preGVT.migrateToGVT();

        assertEq(preGVT.balanceOf(user1), 0);
    }

    function testMigrateRevertsNotEnabled() public {
        vm.expectRevert(PreGVT.MigrationNotEnabled.selector);
        vm.prank(user1);
        preGVT.migrateToGVT();
    }

    function testMigrateRevertsZeroBalance() public {
        vm.prank(admin);
        preGVT.setMigrator(migrator);

        vm.expectRevert(PreGVT.ZeroAmount.selector);
        vm.prank(user1);
        preGVT.migrateToGVT();
    }

    // ============ Non-Transferable Tests ============

    function testTransferReverts() public {
        // Give user1 some tokens
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user1;
        amounts[0] = 1000e18;

        vm.prank(distributor);
        preGVT.batchAirdrop(users, amounts);

        vm.expectRevert(PreGVT.TransferNotAllowed.selector);
        vm.prank(user1);
        preGVT.transfer(user2, 500e18);
    }

    function testTransferFromReverts() public {
        vm.expectRevert(PreGVT.TransferNotAllowed.selector);
        vm.prank(user1);
        preGVT.transferFrom(user1, user2, 500e18);
    }

    function testApproveReverts() public {
        vm.expectRevert(PreGVT.ApprovalNotAllowed.selector);
        vm.prank(user1);
        preGVT.approve(user2, 1000e18);
    }

    function testIncreaseAllowanceReverts() public {
        vm.expectRevert(PreGVT.ApprovalNotAllowed.selector);
        vm.prank(user1);
        preGVT.increaseAllowance(user2, 1000e18);
    }

    function testDecreaseAllowanceReverts() public {
        vm.expectRevert(PreGVT.ApprovalNotAllowed.selector);
        vm.prank(user1);
        preGVT.decreaseAllowance(user2, 1000e18);
    }

    // ============ Reserve Cap Tests ============

    function testReserveCapEnforcement() public {
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user1;
        amounts[0] = AIRDROP_RESERVE_CAP / 2;

        vm.startPrank(distributor);
        preGVT.batchAirdrop(users, amounts);

        amounts[0] = AIRDROP_RESERVE_CAP / 2 + 1;
        vm.expectRevert(PreGVT.ReserveCapExceeded.selector);
        preGVT.batchAirdrop(users, amounts);
        vm.stopPrank();
    }

    // ============ Integration Tests ============

    function testFullClaimFlow() public {
        // 1. Admin sets allocations
        address[] memory users = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        amounts[0] = 1000e18;
        amounts[1] = 2000e18;
        amounts[2] = 3000e18;

        vm.prank(distributor);
        preGVT.setAllocations(users, amounts);

        // 2. Users claim
        vm.prank(user1);
        preGVT.claimAllocated();

        vm.prank(user2);
        preGVT.claimAllocated();

        vm.prank(user3);
        preGVT.claimAllocated();

        // 3. Verify balances
        assertEq(preGVT.balanceOf(user1), 1000e18);
        assertEq(preGVT.balanceOf(user2), 2000e18);
        assertEq(preGVT.balanceOf(user3), 3000e18);
        assertEq(preGVT.airdropReserveMinted(), 6000e18);

        // 4. Setup migration
        vm.prank(admin);
        preGVT.setMigrator(migrator);

        // 5. Users migrate
        vm.prank(user1);
        preGVT.migrateToGVT();

        assertEq(preGVT.balanceOf(user1), 0);
    }

    function testMixedClaimPatterns() public {
        // Pattern B: Preloaded allocation
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user1;
        amounts[0] = 5000e18;

        vm.prank(distributor);
        preGVT.setAllocations(users, amounts);

        vm.prank(user1);
        preGVT.claimAllocated();

        // Pattern A: Direct claim with badge
        badge.mint(user2, BADGE_ID, 1); // Give another badge
        vm.prank(user2);
        preGVT.claimWithBadge(3000e18);

        assertEq(preGVT.balanceOf(user1), 5000e18);
        assertEq(preGVT.balanceOf(user2), 3000e18);
        assertEq(preGVT.airdropReserveMinted(), 8000e18);
    }
}
