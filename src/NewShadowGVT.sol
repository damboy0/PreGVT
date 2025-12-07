// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ShadowGVT
 * @notice Transferable preview token for on-chain price visibility before TGE
 * @dev Standard ERC-20 with no transfer restrictions (per technical requirements)
 *
 * Key properties:
 * - Standard ERC-20 token (FULLY TRANSFERABLE)
 * - Minting controlled by ADMIN_ROLE (Safe multisig)
 * - No transfer blocking (to avoid wallet risk warnings)
 * - Static reference price displayed via metadata
 * - No liquidity pool (price set via metadata, not market)
 * - Designed for institutional accounting and price visibility
 * - NOT A TRADING TOKEN - accounting certificate only
 */
contract ShadowGVT is ERC20, AccessControl {
    // ============ Roles ============

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ============ Immutable Metadata ============

    string public constant AGV_NOTICE =
        "ShadowGVT is a transferable preview token for price visibility and institutional accounting. NOT A TRADING TOKEN.";

    /// @notice Static reference price in USD (scaled by 1e18)
    /// @dev This is for display purposes only, updated via metadata
    uint256 public referencePrice;

    // ============ Events ============

    event MintedByAdmin(address indexed to, uint256 amount);
    event BurnedByAdmin(address indexed from, uint256 amount);
    event ReferencePriceUpdated(uint256 newPrice);

    // ============ Constructor ============

    /**
     * @param _initialAdmin Address to grant ADMIN_ROLE and DEFAULT_ADMIN_ROLE
     * @param _referencePrice Initial reference price (e.g., 0.52614 * 1e18)
     */
    constructor(address _initialAdmin, uint256 _referencePrice) ERC20("Shadow GVT", "sGVT") {
        require(_initialAdmin != address(0), "Invalid admin address");
        require(_referencePrice > 0, "Invalid reference price");

        referencePrice = _referencePrice;

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

    /**
     * @notice Get the reference price in USD (scaled by 1e18)
     * @dev This is for display purposes - not a market price
     */
    function getReferencePrice() external view returns (uint256) {
        return referencePrice;
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

    /**
     * @notice Batch mint varying amounts of tokens to multiple recipients
     * @param recipients List of wallet addresses
     * @param amounts List of token amounts per address
     */
    function batchMint(address[] calldata recipients, uint256[] calldata amounts) external onlyRole(ADMIN_ROLE) {
        require(recipients.length == amounts.length, "Length mismatch");

        for (uint256 i = 0; i < recipients.length; i++) {
            address to = recipients[i];
            require(to != address(0), "Cannot mint to zero");

            uint256 amount = amounts[i];
            require(amount > 0, "Amount must be positive");

            _mint(to, amount);
            emit MintedByAdmin(to, amount);
        }
    }

    /**
     * @notice Update reference price - ADMIN_ROLE only
     * @dev This updates the static reference price for display purposes
     * @param _newPrice New reference price in USD (scaled by 1e18)
     */
    function setReferencePrice(uint256 _newPrice) external onlyRole(ADMIN_ROLE) {
        require(_newPrice > 0, "Invalid price");
        referencePrice = _newPrice;
        emit ReferencePriceUpdated(_newPrice);
    }

    // ============ Standard ERC-20 Logic ============

    /**
     * @notice Standard ERC-20 _update - NO RESTRICTIONS
     * @dev All transfers allowed per technical requirements
     * 
     * IMPORTANT: This token is FULLY TRANSFERABLE to avoid wallet warnings.
     * Non-transferability is handled through:
     * 1. No liquidity pool (no market to sell on)
     * 2. Institutional accounting use only
     * 3. Static price via metadata (not market-driven)
     * 
     * This follows industry standards for:
     * - RWA bookkeeping tokens
     * - Staking receipt tokens
     * - Internal accounting certificates
     */
    function _update(address from, address to, uint256 value) internal override {
        // Standard ERC-20 behavior - no restrictions
        // This prevents wallet risk warnings
        super._update(from, to, value);
    }
}