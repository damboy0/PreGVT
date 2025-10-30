// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PreGVT.sol";

/**
 * @title DeployPreGVT
 * @notice Deployment script with initial admin setup
 * @dev Run with: forge script script/DeployPreGVT.s.sol:DeployPreGVT --rpc-url <RPC_URL> --broadcast --verify
 */
contract DeployPreGVT is Script {
    // ============ Configuration ============

    // Genesis Badge contract address (update for your network)
    address constant BADGE_ADDRESS = 0xd1215311b1CabDb911BCaAAc2ebcB291C7659cdc;

    // Badge ID required for claims
    uint256 constant BADGE_ID = 1;

    // Airdrop reserve cap (e.g., 3% of 100M = 3M tokens)
    uint256 constant RESERVE_CAP = 3_000_000e18; // 3 million tokens

    // Admin addresses (update these)
    address INITIAL_ADMIN;
    address DISTRIBUTOR;
    address MIGRATOR_SETTER;

    // Optional: Additional distributors to grant role
    address[] additionalDistributors;

    // ============ Deployment ============

    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        INITIAL_ADMIN = vm.envAddress("ADMIN");
        DISTRIBUTOR = vm.envAddress("DISTRIBUTOR");
        MIGRATOR_SETTER = vm.envAddress("MIGRATOR_SETTER");

        // Validation
        require(BADGE_ADDRESS != address(0), "Update BADGE_ADDRESS");
        require(INITIAL_ADMIN != address(0), "Update INITIAL_ADMIN");
        require(DISTRIBUTOR != address(0), "Update DISTRIBUTOR");
        require(MIGRATOR_SETTER != address(0), "Update MIGRATOR_SETTER");

        console.log("====================================");
        console.log("PreGVT Deployment");
        console.log("====================================");
        console.log("Deployer:", deployer);
        console.log("Network:", block.chainid);
        console.log("Badge Address:", BADGE_ADDRESS);
        console.log("Badge ID:", BADGE_ID);
        console.log("Reserve Cap:", RESERVE_CAP / 1e18, "tokens");
        console.log("====================================");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy PreGVT
        PreGVT preGVT = new PreGVT(BADGE_ADDRESS, BADGE_ID, RESERVE_CAP, INITIAL_ADMIN);

        console.log("PreGVT deployed at:", address(preGVT));

        // If deployer is admin, setup roles
        if (INITIAL_ADMIN == deployer) {
            setupRoles(preGVT);
        } else {
            console.log("Deployer is not admin - roles must be set by admin:", INITIAL_ADMIN);
        }

        vm.stopBroadcast();

        // Print deployment summary
        printDeploymentSummary(address(preGVT));
    }

    // ============ Role Setup ============

    function setupRoles(PreGVT preGVT) internal {
        console.log("\n====================================");
        console.log("Setting up roles...");
        console.log("====================================");

        // Grant DISTRIBUTOR_ROLE
        if (DISTRIBUTOR != address(0) && !preGVT.hasRole(preGVT.DISTRIBUTOR_ROLE(), DISTRIBUTOR)) {
            preGVT.grantRole(preGVT.DISTRIBUTOR_ROLE(), DISTRIBUTOR);
            console.log("Granted DISTRIBUTOR_ROLE to:", DISTRIBUTOR);
        }

        // Grant additional distributors if any
        for (uint256 i = 0; i < additionalDistributors.length; i++) {
            if (!preGVT.hasRole(preGVT.DISTRIBUTOR_ROLE(), additionalDistributors[i])) {
                preGVT.grantRole(preGVT.DISTRIBUTOR_ROLE(), additionalDistributors[i]);
                console.log("Granted DISTRIBUTOR_ROLE to:", additionalDistributors[i]);
            }
        }

        // Grant MIGRATOR_SETTER_ROLE (if different from admin)
        if (MIGRATOR_SETTER != INITIAL_ADMIN && !preGVT.hasRole(preGVT.MIGRATOR_SETTER_ROLE(), MIGRATOR_SETTER)) {
            preGVT.grantRole(preGVT.MIGRATOR_SETTER_ROLE(), MIGRATOR_SETTER);
            console.log("Granted MIGRATOR_SETTER_ROLE to:", MIGRATOR_SETTER);
        }

        console.log("Role setup complete!");
    }

    // ============ Deployment Summary ============

    function printDeploymentSummary(address preGVTAddress) internal view {
        console.log("\n====================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("====================================");
        console.log("PreGVT Address:", preGVTAddress);
        console.log("\nConfiguration:");
        console.log("- Badge Address:", BADGE_ADDRESS);
        console.log("- Badge ID:", BADGE_ID);
        console.log("- Reserve Cap:", RESERVE_CAP / 1e18, "tokens");
        console.log("\nRoles:");
        console.log("- Admin:", INITIAL_ADMIN);
        console.log("- Distributor:", DISTRIBUTOR);
        console.log("- Migrator Setter:", MIGRATOR_SETTER);
        console.log("\n====================================");
        console.log("NEXT STEPS:");
        console.log("====================================");
        console.log("1. Verify contract on block explorer");
        console.log("2. Grant OPERATOR_ROLE on Badge contract to PreGVT");
        console.log("3. Load allocations via setAllocations()");
        console.log("4. Unpause contract when ready for claims");
        console.log("5. Monitor AirdropDistributed events");
        console.log("====================================\n");
    }
}

/**
 * @title SetupPreGVT
 * @notice Post-deployment setup script
 * @dev Run with: forge script script/DeployPreGVT.s.sol:SetupPreGVT --rpc-url <RPC_URL> --broadcast
 */
contract SetupPreGVT is Script {
    // Update these after deployment
    address constant PREGVT_ADDRESS = address(0); // UPDATE THIS
    address constant BADGE_ADDRESS = address(0); // UPDATE THIS

    function run() external {
        require(PREGVT_ADDRESS != address(0), "Update PREGVT_ADDRESS");
        require(BADGE_ADDRESS != address(0), "Update BADGE_ADDRESS");

        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");

        console.log("====================================");
        console.log("PreGVT Post-Deployment Setup");
        console.log("====================================");

        vm.startBroadcast(adminPrivateKey);

        PreGVT preGVT = PreGVT(PREGVT_ADDRESS);

        // Unpause if needed
        if (preGVT.paused()) {
            preGVT.unpause();
            console.log("Contract unpaused");
        }

        vm.stopBroadcast();

        console.log("Setup complete!");
        console.log("====================================");
    }
}

/**
 * @title LoadAllocations
 * @notice Load CSV allocations on-chain
 * @dev Run with: forge script script/DeployPreGVT.s.sol:LoadAllocations --rpc-url <RPC_URL> --broadcast
 */
contract LoadAllocations is Script {
    address constant PREGVT_ADDRESS = address(0); // UPDATE THIS

    // Batch size for gas optimization (adjust based on network)
    uint256 constant BATCH_SIZE = 100;

    function run() external {
        require(PREGVT_ADDRESS != address(0), "Update PREGVT_ADDRESS");

        uint256 distributorPrivateKey = vm.envUint("DISTRIBUTOR_PRIVATE_KEY");

        PreGVT preGVT = PreGVT(PREGVT_ADDRESS);

        console.log("====================================");
        console.log("Loading Allocations");
        console.log("====================================");

        // Example allocations - replace with your CSV data
        address[] memory users = new address[](3);
        uint256[] memory amounts = new uint256[](3);

        users[0] = 0x1234567890123456789012345678901234567890; // UPDATE
        users[1] = 0x2234567890123456789012345678901234567890; // UPDATE
        users[2] = 0x3234567890123456789012345678901234567890; // UPDATE

        amounts[0] = 1000e18; // UPDATE
        amounts[1] = 2000e18; // UPDATE
        amounts[2] = 3000e18; // UPDATE

        vm.startBroadcast(distributorPrivateKey);

        // Load allocations in batches
        for (uint256 i = 0; i < users.length; i += BATCH_SIZE) {
            uint256 end = i + BATCH_SIZE > users.length ? users.length : i + BATCH_SIZE;
            uint256 batchLength = end - i;

            address[] memory batchUsers = new address[](batchLength);
            uint256[] memory batchAmounts = new uint256[](batchLength);

            for (uint256 j = 0; j < batchLength; j++) {
                batchUsers[j] = users[i + j];
                batchAmounts[j] = amounts[i + j];
            }

            preGVT.setAllocations(batchUsers, batchAmounts);
            console.log("Loaded batch", i / BATCH_SIZE + 1, "- users:", batchLength);
        }

        vm.stopBroadcast();

        console.log("All allocations loaded!");
        console.log("Total users:", users.length);
        console.log("====================================");
    }
}

/**
 * @title BatchAirdropScript
 * @notice Execute batch airdrop to badge holders
 * @dev Run with: forge script script/DeployPreGVT.s.sol:BatchAirdropScript --rpc-url <RPC_URL> --broadcast
 */
contract BatchAirdropScript is Script {
    address constant PREGVT_ADDRESS = address(0); // UPDATE THIS

    function run() external {
        require(PREGVT_ADDRESS != address(0), "Update PREGVT_ADDRESS");

        uint256 distributorPrivateKey = vm.envUint("DISTRIBUTOR_PRIVATE_KEY");

        PreGVT preGVT = PreGVT(PREGVT_ADDRESS);

        console.log("====================================");
        console.log("Batch Airdrop");
        console.log("====================================");

        // Example batch - replace with your data
        address[] memory users = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        users[0] = 0x1234567890123456789012345678901234567890; // UPDATE
        users[1] = 0x2234567890123456789012345678901234567890; // UPDATE

        amounts[0] = 5000e18; // UPDATE
        amounts[1] = 7500e18; // UPDATE

        vm.startBroadcast(distributorPrivateKey);

        preGVT.batchAirdrop(users, amounts);

        vm.stopBroadcast();

        console.log("Airdrop complete!");
        console.log("Recipients:", users.length);
        console.log("====================================");
    }
}

/**
 * @title EnableMigration
 * @notice Enable migration to main GVT token
 * @dev Run with: forge script script/DeployPreGVT.s.sol:EnableMigration --rpc-url <RPC_URL> --broadcast
 */
contract EnableMigration is Script {
    address constant PREGVT_ADDRESS = address(0); // UPDATE THIS
    address constant MIGRATOR_ADDRESS = address(0); // UPDATE THIS - after migrator is deployed

    function run() external {
        require(PREGVT_ADDRESS != address(0), "Update PREGVT_ADDRESS");
        require(MIGRATOR_ADDRESS != address(0), "Update MIGRATOR_ADDRESS");

        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");

        PreGVT preGVT = PreGVT(PREGVT_ADDRESS);

        console.log("====================================");
        console.log("Enabling Migration");
        console.log("====================================");
        console.log("PreGVT:", PREGVT_ADDRESS);
        console.log("Migrator:", MIGRATOR_ADDRESS);

        vm.startBroadcast(adminPrivateKey);

        preGVT.setMigrator(MIGRATOR_ADDRESS);

        vm.stopBroadcast();

        console.log("Migration enabled!");
        console.log("Users can now call migrateToGVT()");
        console.log("====================================");
    }
}
