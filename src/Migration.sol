// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Burnable {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function burn(uint256 amount) external;
}

interface INewPreGVT {
    function mint(address to, uint256 amount) external;
}

/**
 * @title PreGVTMigration
 * @notice Migrates old PreGVT to new PreGVT (1:1 ratio)
 * @dev Users deposit old tokens, contract burns them, mints new tokens
 */
contract PreGVTMigration {
    IERC20Burnable public immutable oldPreGVT;
    INewPreGVT public immutable newPreGVT;

    address public owner;
    bool public migrationActive;

    // Track migrations
    mapping(address => uint256) public migrated;
    uint256 public totalMigrated;

    // Events
    event TokensMigrated(address indexed user, uint256 amount);
    event MigrationStatusChanged(bool active);
    event EmergencyWithdraw(address indexed token, uint256 amount);

    // Errors
    error MigrationNotActive();
    error ZeroAmount();
    error TransferFailed();
    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _oldPreGVT, address _newPreGVT) {
        require(_oldPreGVT != address(0), "Zero old PreGVT");
        require(_newPreGVT != address(0), "Zero new PreGVT");

        oldPreGVT = IERC20Burnable(_oldPreGVT);
        newPreGVT = INewPreGVT(_newPreGVT);
        owner = msg.sender;
        migrationActive = true;

        emit MigrationStatusChanged(true);
    }

    /**
     * @notice Migrate old PreGVT to new PreGVT (1:1 ratio)
     * @dev Burns old tokens and mints new tokens
     * @param amount Amount of old PreGVT to migrate
     */
    function migrate(uint256 amount) external {
        if (!migrationActive) revert MigrationNotActive();
        if (amount == 0) revert ZeroAmount();

        // Transfer old PreGVT from user to this contract
        bool success = oldPreGVT.transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();

        // Burn old PreGVT
        oldPreGVT.burn(amount);

        // Mint new PreGVT to user (1:1)
        newPreGVT.mint(msg.sender, amount);

        // Track migration
        migrated[msg.sender] += amount;
        totalMigrated += amount;

        emit TokensMigrated(msg.sender, amount);
    }

    /**
     * @notice Get migration info for a user
     */
    function getMigrationInfo(address user)
        external
        view
        returns (uint256 userMigrated, uint256 oldBalance, uint256 totalMigratedAmount)
    {
        return (migrated[user], oldPreGVT.balanceOf(user), totalMigrated);
    }

    // ============ Admin Functions ============

    function pauseMigration() external onlyOwner {
        migrationActive = false;
        emit MigrationStatusChanged(false);
    }

    function resumeMigration() external onlyOwner {
        migrationActive = true;
        emit MigrationStatusChanged(true);
    }

    function closeMigration() external onlyOwner {
        migrationActive = false;
        emit MigrationStatusChanged(false);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }
}
