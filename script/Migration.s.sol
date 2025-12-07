// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Migration.sol";

/**
 * @title DeployMigration
 * @notice Deploy the PreGVT migration contract
 */
contract DeployMigration is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address oldPreGVT = vm.envAddress("OLD_PREGVT");
        address newPreGVT = vm.envAddress("NEW_PREGVT");

        console.log("====================================");
        console.log("Deploying PreGVT Migration Contract");
        console.log("====================================");
        console.log("Old PreGVT:", oldPreGVT);
        console.log("New PreGVT:", newPreGVT);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        PreGVTMigration migration = new PreGVTMigration(oldPreGVT, newPreGVT);

        vm.stopBroadcast();

        console.log("====================================");
        console.log("Migration Contract Deployed!");
        console.log("====================================");
        console.log("Address:", address(migration));
        console.log("");
        console.log("Next steps:");
        console.log("1. Set this address as MIGRATION_CONTRACT in .env");
        console.log("2. Run: ConfigureMigration script");
        console.log("====================================");
    }
}

/**
 * @title ConfigureMigration
 * @notice Configure the new PreGVT contract to work with migration
 */
contract ConfigureMigration is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address newPreGVT = vm.envAddress("NEW_PREGVT");
        address migrationContract = vm.envAddress("MIGRATION_CONTRACT");

        console.log("====================================");
        console.log("Configuring Migration");
        console.log("====================================");
        console.log("New PreGVT:", newPreGVT);
        console.log("Migration Contract:", migrationContract);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Set migration contract in new PreGVT (grants MINTER_ROLE)
        (bool success,) = newPreGVT.call(abi.encodeWithSignature("setMigrationContract(address)", migrationContract));

        require(success, "Failed to set migration contract");

        vm.stopBroadcast();

        console.log("====================================");
        console.log("Configuration Complete!");
        console.log("====================================");
        console.log("Migration contract can now mint new PreGVT");
        console.log("");
        console.log("Users can now migrate by:");
        console.log("1. Approving migration contract to spend old PreGVT");
        console.log("2. Calling migrate(amount) on migration contract");
        console.log("====================================");
    }
}
