// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ShadowGVT
 * @notice Non-transferable preview token for on-chain price visibility before TGE
 *
 *
 * Key properties:
 * - ERC20 token with transfers disabled (except mint/burn)
 * - Minting controlled by ADMIN_ROLE (Safe multisig)
 * - No upgradeability, no complex features
 * - Designed for price visibility only - NOT A REAL TOKEN
 */
contract ShadowGVT is ERC20, AccessControl {
    // ============ Roles ============

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ============ Immutable Metadata ============

    string public constant AGV_NOTICE =
        "ShadowGVT is a non-transferable preview token for price visibility only. NOT A REAL TOKEN.";

    // ============ Events ============

    event MintedByAdmin(address indexed to, uint256 amount);
    event BurnedByAdmin(address indexed burner, uint256 amount);

    // ============ Errors ============

    error TransferNotAllowed();
    error ApproveNotAllowed();

    // ============ Constructor ============

    /**
     * @param _initialAdmin Address to grant ADMIN_ROLE and DEFAULT_ADMIN_ROLE
     */
    constructor(address _initialAdmin) ERC20("Shadow GVT", "sGVT") {
        require(_initialAdmin != address(0), "Invalid admin address");
        // Grant both roles so admin can manage other admins
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(ADMIN_ROLE, _initialAdmin);
    }

    // ============ View Functions ============

    /**
     * @notice Get the AGV notice about this token
     */
    function getNotice() external pure returns (string memory) {
        return AGV_NOTICE;
    }

    /**
     * @notice Check if address has admin role
     */
    function isAdmin(address account) external view returns (bool) {
        return hasRole(ADMIN_ROLE, account);
    }

    // ============ Admin Functions ============

    /**
     * @notice Mint tokens - ADMIN_ROLE only
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be positive");
        _mint(to, amount);
        emit MintedByAdmin(to, amount);
    }

    /**
     * @notice Burn tokens - ADMIN_ROLE only
     * @param amount Amount to burn from caller
     */
    function burn(uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(amount > 0, "Amount must be positive");
        _burn(msg.sender, amount);
        emit BurnedByAdmin(msg.sender, amount);
    }

    /**
     * @notice Burn tokens from any address - ADMIN_ROLE only
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burnFrom(address from, uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(from != address(0), "Cannot burn from zero address");
        require(amount > 0, "Amount must be positive");
        require(balanceOf(from) >= amount, "Insufficient balance");
        _burn(from, amount);
        emit BurnedByAdmin(from, amount);
    }

    // ============ Transfer Blocking Logic ============

    /**
     * @notice Override _update to block all transfers except mint/burn
     * @dev Mint: from == address(0)
     *      Burn: to == address(0)
     *      Transfer: from != address(0) && to != address(0) → REVERT
     */
    function _update(address from, address to, uint256 value) internal override {
        // Allow minting (from == 0x0)
        if (from == address(0)) {
            super._update(from, to, value);
            return;
        }

        // Allow burning (to == 0x0)
        if (to == address(0)) {
            super._update(from, to, value);
            return;
        }

        // Block all other transfers
        revert TransferNotAllowed();
    }

    /**
     * @notice Block approve - transfers are disabled
     */
    function approve(address, uint256) public pure override returns (bool) {
        revert ApproveNotAllowed();
    }

    /**
     * @notice Block increaseAllowance
     */
    function increaseAllowance(address, uint256) public pure returns (bool) {
        revert ApproveNotAllowed();
    }

    /**
     * @notice Block decreaseAllowance
     */
    function decreaseAllowance(address, uint256) public pure returns (bool) {
        revert ApproveNotAllowed();
    }

    /**
     * @notice Block transferFrom
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TransferNotAllowed();
    }

    /**
     * @notice Block transfer
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert TransferNotAllowed();
    }
}
