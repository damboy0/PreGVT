// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ShadowGVT.sol";

contract ShadowGVTTest is Test {
    ShadowGVT public shadowGVT;
    address public admin;
    address public user1;
    address public user2;
    address public user3;

    event MintedByAdmin(address indexed to, uint256 amount);
    event BurnedByAdmin(address indexed burner, uint256 amount);

    function setUp() public {
        admin = address(0xAD);
        user1 = address(0x1111);
        user2 = address(0x2222);
        user3 = address(0x3333);

        shadowGVT = new ShadowGVT(admin);
        vm.label(address(shadowGVT), "ShadowGVT");
        vm.label(admin, "Admin");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
    }

    // ============ Setup & Initialization ============

    function test_InitialState() public view {
        assertEq(shadowGVT.name(), "Shadow GVT");
        assertEq(shadowGVT.symbol(), "sGVT");
        assertEq(shadowGVT.totalSupply(), 0);
        assertTrue(shadowGVT.hasRole(shadowGVT.ADMIN_ROLE(), admin));
    }

    function test_AdminCanMint() public {
        vm.prank(admin);
        shadowGVT.mint(user1, 100e18);
        assertEq(shadowGVT.balanceOf(user1), 100e18);
        assertEq(shadowGVT.totalSupply(), 100e18);
    }

    function test_NonAdminCannotMint() public {
        vm.prank(user1);
        vm.expectRevert();
        shadowGVT.mint(user2, 100e18);
    }

    // ============ Minting Tests ============

    function test_MintEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit MintedByAdmin(user1, 50e18);
        shadowGVT.mint(user1, 50e18);
    }

    function test_BatchMintMultipleUsers() public {
        vm.prank(admin);
        shadowGVT.mint(user1, 100e18);

        vm.prank(admin);
        shadowGVT.mint(user2, 200e18);

        vm.prank(admin);
        shadowGVT.mint(user3, 150e18);

        assertEq(shadowGVT.balanceOf(user1), 100e18);
        assertEq(shadowGVT.balanceOf(user2), 200e18);
        assertEq(shadowGVT.balanceOf(user3), 150e18);
        assertEq(shadowGVT.totalSupply(), 450e18);
    }

    function test_MintToZeroAddressReverts() public {
        vm.prank(admin);
        vm.expectRevert("Cannot mint to zero address");
        shadowGVT.mint(address(0), 100e18);
    }

    function test_MintZeroAmountReverts() public {
        vm.prank(admin);
        vm.expectRevert("Amount must be positive");
        shadowGVT.mint(user1, 0);
    }

    function test_MintLargeAmounts() public {
        uint256 largeAmount = 1_000_000e18;
        vm.prank(admin);
        shadowGVT.mint(user1, largeAmount);
        assertEq(shadowGVT.balanceOf(user1), largeAmount);
    }

    // ============ Burn Tests ============

    function test_AdminCanBurn() public {
        vm.prank(admin);
        shadowGVT.mint(admin, 100e18);

        vm.prank(admin);
        shadowGVT.burn(50e18);

        assertEq(shadowGVT.balanceOf(admin), 50e18);
        assertEq(shadowGVT.totalSupply(), 50e18);
    }

    function test_AdminCanBurnFromOtherAddress() public {
        vm.prank(admin);
        shadowGVT.mint(user1, 100e18);

        vm.prank(admin);
        shadowGVT.burnFrom(user1, 60e18);

        assertEq(shadowGVT.balanceOf(user1), 40e18);
        assertEq(shadowGVT.totalSupply(), 40e18);
    }

    function test_BurnEmitsEvent() public {
        vm.prank(admin);
        shadowGVT.mint(admin, 100e18);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit BurnedByAdmin(admin, 50e18);
        shadowGVT.burn(50e18);
    }

    function test_BurnZeroAmountReverts() public {
        vm.prank(admin);
        vm.expectRevert("Amount must be positive");
        shadowGVT.burn(0);
    }

    function test_BurnMoreThanBalanceReverts() public {
        vm.prank(admin);
        shadowGVT.mint(admin, 50e18);

        vm.prank(admin);
        vm.expectRevert("Insufficient balance");
        shadowGVT.burnFrom(admin, 100e18);
    }

    function test_NonAdminCannotBurn() public {
        vm.prank(admin);
        shadowGVT.mint(user1, 100e18);

        vm.prank(user1);
        vm.expectRevert();
        shadowGVT.burn(50e18);
    }

    // ============ Transfer Blocking Tests ============

    function test_DirectTransferReverts() public {
        vm.prank(admin);
        shadowGVT.mint(user1, 100e18);

        vm.prank(user1);
        vm.expectRevert(ShadowGVT.TransferNotAllowed.selector);
        shadowGVT.transfer(user2, 50e18);
    }

    function test_TransferFromReverts() public {
        vm.prank(admin);
        shadowGVT.mint(user1, 100e18);

        vm.prank(user1);
        vm.expectRevert(ShadowGVT.ApproveNotAllowed.selector);
        shadowGVT.approve(user2, 50e18);

        vm.prank(user2);
        vm.expectRevert(ShadowGVT.TransferNotAllowed.selector);
        shadowGVT.transferFrom(user1, user2, 50e18);
    }

    function test_ApproveReverts() public {
        vm.prank(user1);
        vm.expectRevert(ShadowGVT.ApproveNotAllowed.selector);
        shadowGVT.approve(user2, 100e18);
    }

    function test_IncreaseAllowanceReverts() public {
        vm.prank(user1);
        vm.expectRevert(ShadowGVT.ApproveNotAllowed.selector);
        shadowGVT.increaseAllowance(user2, 50e18);
    }

    function test_DecreaseAllowanceReverts() public {
        vm.prank(user1);
        vm.expectRevert(ShadowGVT.ApproveNotAllowed.selector);
        shadowGVT.decreaseAllowance(user2, 50e18);
    }

    // ============ Metadata Tests ============

    function test_GetNotice() public view {
        string memory notice = shadowGVT.getNotice();
        assertTrue(bytes(notice).length > 0);
        assertEq(notice, shadowGVT.AGV_NOTICE());
    }

    function test_IsAdmin() public view {
        assertTrue(shadowGVT.isAdmin(admin));
        assertFalse(shadowGVT.isAdmin(user1));
        assertFalse(shadowGVT.isAdmin(user2));
    }

    // ============ ERC20 Compliance Tests ============

    function test_TokenDecimals() public view {
        assertEq(shadowGVT.decimals(), 18);
    }

    function test_BalanceOfReturnsCorrectAmount() public {
        vm.prank(admin);
        shadowGVT.mint(user1, 123456e18);
        assertEq(shadowGVT.balanceOf(user1), 123456e18);
    }

    function test_AllowanceAlwaysZero() public {
        vm.prank(admin);
        shadowGVT.mint(user1, 100e18);
        assertEq(shadowGVT.allowance(user1, user2), 0);
    }

    // ============ Fuzz Tests ============

    function testFuzz_MintVariousAmounts(uint256 amount) public {
        amount = bound(amount, 1, type(uint96).max);

        vm.prank(admin);
        shadowGVT.mint(user1, amount);

        assertEq(shadowGVT.balanceOf(user1), amount);
        assertEq(shadowGVT.totalSupply(), amount);
    }

    function testFuzz_CannotTransferRandomAmounts(uint256 amount) public {
        amount = bound(amount, 1, type(uint96).max);

        vm.prank(admin);
        shadowGVT.mint(user1, amount);

        vm.prank(user1);
        vm.expectRevert(ShadowGVT.TransferNotAllowed.selector);
        shadowGVT.transfer(user2, amount);
    }

    function testFuzz_BurnAfterMint(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 1, type(uint96).max);
        burnAmount = bound(burnAmount, 1, mintAmount);

        vm.prank(admin);
        shadowGVT.mint(admin, mintAmount);

        vm.prank(admin);
        shadowGVT.burn(burnAmount);

        assertEq(shadowGVT.balanceOf(admin), mintAmount - burnAmount);
        assertEq(shadowGVT.totalSupply(), mintAmount - burnAmount);
    }

    // ============ Invariant Tests ============

    function test_InvariantTotalSupplyMatchesSum() public {
        vm.prank(admin);
        shadowGVT.mint(user1, 100e18);
        vm.prank(admin);
        shadowGVT.mint(user2, 200e18);
        vm.prank(admin);
        shadowGVT.mint(user3, 150e18);

        uint256 sum = shadowGVT.balanceOf(user1) + shadowGVT.balanceOf(user2) + shadowGVT.balanceOf(user3);
        assertEq(shadowGVT.totalSupply(), sum);
    }

    function test_InvariantBurnDecreasesTotalSupply() public {
        vm.prank(admin);
        shadowGVT.mint(admin, 1000e18);

        uint256 initialSupply = shadowGVT.totalSupply();

        vm.prank(admin);
        shadowGVT.burn(300e18);

        assertEq(shadowGVT.totalSupply(), initialSupply - 300e18);
    }

    function test_InvariantOnlyAdminCanModifySupply() public {
        vm.prank(admin);
        shadowGVT.mint(user1, 100e18);

        uint256 supplyAfterAdminMint = shadowGVT.totalSupply();

        vm.prank(user2);
        vm.expectRevert();
        shadowGVT.mint(user3, 50e18);

        assertEq(shadowGVT.totalSupply(), supplyAfterAdminMint);
    }

    // ============ Access Control Tests ============

    // function test_GrantADMINRoleByDefaultAdmin() public {
    //     // Only DEFAULT_ADMIN_ROLE can grant ADMIN_ROLE
    //     vm.prank(admin);
    //     shadowGVT.grantRole(shadowGVT.ADMIN_ROLE(), user1);
    //     assertTrue(shadowGVT.hasRole(shadowGVT.ADMIN_ROLE(), user1));

    //     // Verify new admin can mint
    //     vm.prank(user1);
    //     shadowGVT.mint(user2, 100e18);
    //     assertEq(shadowGVT.balanceOf(user2), 100e18);
    // }

    // function test_RevokeADMINRoleByDefaultAdmin() public {
    //     // Grant ADMIN_ROLE first
    //     vm.prank(admin);
    //     shadowGVT.grantRole(shadowGVT.ADMIN_ROLE(), user1);
    //     assertTrue(shadowGVT.hasRole(shadowGVT.ADMIN_ROLE(), user1));

    //     // Revoke it
    //     vm.prank(admin);
    //     shadowGVT.revokeRole(shadowGVT.ADMIN_ROLE(), user1);
    //     assertFalse(shadowGVT.hasRole(shadowGVT.ADMIN_ROLE(), user1));

    //     // Verify revoked user cannot mint
    //     vm.prank(user1);
    //     vm.expectRevert();
    //     shadowGVT.mint(user2, 100e18);
    // }

    // function test_NonDefaultAdminCannotGrantRole() public {
    //     // user1 should not be able to grant roles
    //     vm.prank(user1);
    //     vm.expectRevert();
    //     shadowGVT.grantRole(shadowGVT.ADMIN_ROLE(), user2);
    // }
}
