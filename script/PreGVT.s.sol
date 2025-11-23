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
    address constant USDT_ADDRESS = 0x55d398326f99059fF775485246999027B3197955; // USDT token address

    // Badge ID required for claims
    uint256 constant BADGE_ID = 1;

    // Airdrop reserve cap
    uint256 constant RESERVE_CAP = 30_000_000e18; // 30 million tokens

    // NEW: Presale supply cap
    uint256 constant PRESALE_CAP = 70_000_000e18; // 70 million tokens

    // Admin addresses (update these)
    address INITIAL_ADMIN;
    address DISTRIBUTOR;
    address MIGRATOR_SETTER;

    // NEW: Treasury and price manager addresses
    address TREASURY;
    address PRICE_MANAGER;

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

        // NEW: Load treasury and price manager from environment
        TREASURY = vm.envAddress("TREASURY");
        PRICE_MANAGER = vm.envOr("PRICE_MANAGER", INITIAL_ADMIN); // Default to admin if not set

        // Validation
        require(BADGE_ADDRESS != address(0), "Update BADGE_ADDRESS");
        require(INITIAL_ADMIN != address(0), "Update INITIAL_ADMIN");
        require(DISTRIBUTOR != address(0), "Update DISTRIBUTOR");
        require(MIGRATOR_SETTER != address(0), "Update MIGRATOR_SETTER");
        require(TREASURY != address(0), "Update TREASURY"); // NEW

        console.log("====================================");
        console.log("PreGVT Deployment");
        console.log("====================================");
        console.log("Deployer:", deployer);
        console.log("Network:", block.chainid);
        console.log("Badge Address:", BADGE_ADDRESS);
        console.log("Badge ID:", BADGE_ID);
        console.log("Reserve Cap:", RESERVE_CAP / 1e18, "tokens");
        console.log("Presale Cap:", PRESALE_CAP / 1e18, "tokens"); // NEW
        console.log("====================================");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy PreGVT with NEW presale cap parameter
        PreGVT preGVT = new PreGVT(
            BADGE_ADDRESS,
            BADGE_ID,
            RESERVE_CAP,
            PRESALE_CAP, // NEW
            TREASURY,
            USDT_ADDRESS,
            INITIAL_ADMIN
        );

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

        // NEW: Grant PRICE_MANAGER_ROLE
        if (PRICE_MANAGER != address(0) && !preGVT.hasRole(preGVT.PRICE_MANAGER_ROLE(), PRICE_MANAGER)) {
            preGVT.grantRole(preGVT.PRICE_MANAGER_ROLE(), PRICE_MANAGER);
            console.log("Granted PRICE_MANAGER_ROLE to:", PRICE_MANAGER);
        }

        // NEW: Grant TREASURY_ROLE
        if (TREASURY != address(0) && !preGVT.hasRole(preGVT.TREASURY_ROLE(), TREASURY)) {
            preGVT.grantRole(preGVT.TREASURY_ROLE(), TREASURY);
            console.log("Granted TREASURY_ROLE to:", TREASURY);
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
        console.log("- Presale Cap:", PRESALE_CAP / 1e18, "tokens"); // NEW
        console.log("\nRoles:");
        console.log("- Admin:", INITIAL_ADMIN);
        console.log("- Distributor:", DISTRIBUTOR);
        console.log("- Migrator Setter:", MIGRATOR_SETTER);
        console.log("- Treasury:", TREASURY); // NEW
        console.log("- Price Manager:", PRICE_MANAGER); // NEW
        console.log("\n====================================");
        console.log("NEXT STEPS:");
        console.log("====================================");
        console.log("1. Verify contract on block explorer");
        console.log("2. Grant OPERATOR_ROLE on Badge contract to PreGVT");
        console.log("3. Configure presale via ConfigurePresale script"); // NEW
        console.log("4. Set treasury via SetupPreGVT script"); // NEW
        console.log("5. Load allocations via setAllocations()");
        console.log("6. Activate presale when ready"); // NEW
        console.log("7. Unpause contract when ready for claims");
        console.log("8. Monitor AirdropDistributed and TokensPurchased events"); // UPDATED
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
    address payable PREGVT_ADDRESS = payable(0x21cCA8546B1550ee47134AF86AE929C1fA3671c9); // UPDATE THIS
    address BADGE_ADDRESS = 0xd1215311b1CabDb911BCaAAc2ebcB291C7659cdc; // UPDATE THIS
    address payable TREASURY_ADDRESS = payable(0xeA7BD7f0DeB88d1E54d0850aA8909B8AF93Cb3f1);

    function run() external {
        require(PREGVT_ADDRESS != address(0), "Update PREGVT_ADDRESS");
        require(BADGE_ADDRESS != address(0), "Update BADGE_ADDRESS");
        require(TREASURY_ADDRESS != address(0), "Update TREASURY_ADDRESS"); // NEW

        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("====================================");
        console.log("PreGVT Post-Deployment Setup");
        console.log("====================================");

        vm.startBroadcast(adminPrivateKey);

        address payable preGvtAddress = payable(0x21cCA8546B1550ee47134AF86AE929C1fA3671c9);
        PreGVT preGVT = PreGVT(preGvtAddress);

        // NEW: Set treasury
        // preGVT.setTreasury(TREASURY_ADDRESS);
        // console.log("Treasury set to:", TREASURY_ADDRESS);

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
 * @title ConfigurePresale
 * @notice NEW: Configure presale parameters
 * @dev Run with: forge script script/DeployPreGVT.s.sol:ConfigurePresale --rpc-url <RPC_URL> --broadcast
 */
contract ConfigurePresale is Script {
    address payable PREGVT_ADDRESS = payable(0x21cCA8546B1550ee47134AF86AE929C1fA3671c9); // UPDATE THIS

    // Presale configuration - UPDATE THESE
    uint256 constant PRICE_PER_TOKEN = 5e15; // 0.005 USDT per token (add 18 decimals)
    bool constant BADGE_REQUIRED = false; // Set to true if badge holders only
    uint256 constant PER_USER_LIMIT = 0; // 10,000 tokens per user (0 = no limit)

    function run() external {
        require(PREGVT_ADDRESS != address(0), "Update PREGVT_ADDRESS");
        require(PRICE_PER_TOKEN > 0, "Update PRICE_PER_TOKEN");

        uint256 priceManagerPrivateKey = vm.envUint("PRIVATE_KEY");

        address payable preGvtAddress = payable(vm.envAddress("PREGVT_ADDRESS"));
        PreGVT preGVT = PreGVT(preGvtAddress);

        console.log("====================================");
        console.log("Configuring Presale");
        console.log("====================================");
        console.log("Price per token:", PRICE_PER_TOKEN);
        console.log("Badge required:", BADGE_REQUIRED);
        console.log("Per user limit:", PER_USER_LIMIT / 1e18, "tokens");

        vm.startBroadcast(priceManagerPrivateKey);

        preGVT.configurePresale(PRICE_PER_TOKEN, BADGE_REQUIRED, PER_USER_LIMIT);

        vm.stopBroadcast();

        console.log("Presale configured!");
        console.log("====================================");
    }
}

/**
 * @title ActivatePresale
 * @notice NEW: Activate or deactivate presale
 * @dev Run with: forge script script/DeployPreGVT.s.sol:ActivatePresale --rpc-url <RPC_URL> --broadcast
 */
contract ActivatePresale is Script {
    address payable PREGVT_ADDRESS = payable(0x21cCA8546B1550ee47134AF86AE929C1fA3671c9); // UPDATE THIS
    bool constant ACTIVATE = true; // Set to false to deactivate

    function run() external {
        require(PREGVT_ADDRESS != address(0), "Update PREGVT_ADDRESS");

        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");

        PreGVT preGVT = PreGVT(PREGVT_ADDRESS);

        console.log("====================================");
        console.log(ACTIVATE ? "Activating Presale" : "Deactivating Presale");
        console.log("====================================");

        vm.startBroadcast(adminPrivateKey);

        preGVT.setPresaleActive(ACTIVATE);

        vm.stopBroadcast();

        console.log("Presale status updated to:", ACTIVATE);
        console.log("====================================");
    }
}

/**
 * @title UpdatePrice
 * @notice NEW: Update presale price
 * @dev Run with: forge script script/DeployPreGVT.s.sol:UpdatePrice --rpc-url <RPC_URL> --broadcast
 */
contract UpdatePrice is Script {
    address payable PREGVT_ADDRESS = payable(0x3B4300D9139bAB1e5F604811F412B6588D0e81e6);
    uint256 constant NEW_PRICE = 5e15; // ADD 18 DECIMALS TO USDT AMOUNT

    function run() external {
        require(PREGVT_ADDRESS != address(0), "Update PREGVT_ADDRESS");
        require(NEW_PRICE > 0, "Update NEW_PRICE");

        uint256 priceManagerPrivateKey = vm.envUint("PRIVATE_KEY");

        PreGVT preGVT = PreGVT(PREGVT_ADDRESS);

        console.log("====================================");
        console.log("Updating Price");
        console.log("====================================");
        console.log("New price per token:", NEW_PRICE);

        vm.startBroadcast(priceManagerPrivateKey);

        preGVT.updatePrice(NEW_PRICE);

        vm.stopBroadcast();

        console.log("Price updated!");
        console.log("====================================");
    }
}

/**
 * @title WithdrawFunds
 * @notice NEW: Withdraw accumulated ETH to treasury
 * @dev Run with: forge script script/DeployPreGVT.s.sol:WithdrawFunds --rpc-url <RPC_URL> --broadcast
 */
contract WithdrawFunds is Script {
    address payable PREGVT_ADDRESS;

    function run() external {
        require(PREGVT_ADDRESS != address(0), "Update PREGVT_ADDRESS");

        uint256 treasuryPrivateKey = vm.envUint("TREASURY_PRIVATE_KEY");

        PreGVT preGVT = PreGVT(PREGVT_ADDRESS);

        console.log("====================================");
        console.log("Withdrawing Funds");
        console.log("====================================");
        console.log("Contract balance:", address(preGVT).balance);

        vm.startBroadcast(treasuryPrivateKey);

        preGVT.withdrawFunds();

        vm.stopBroadcast();

        console.log("Funds withdrawn to treasury!");
        console.log("====================================");
    }
}

/**
 * @title LoadAllocations
 * @notice Load CSV allocations on-chain
 * @dev Run with: forge script script/DeployPreGVT.s.sol:LoadAllocations --rpc-url <RPC_URL> --broadcast
 */
contract LoadAllocations is Script {
    address payable PREGVT_ADDRESS;

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
    address payable PREGVT_ADDRESS;

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

// Add these contracts to the END of your DeployPreGVT.s.sol file
// Right after the BatchAirdropScript contract

/**
 * @title LoadAllocationsFromCSV
 * @notice Load allocations from tier3_wallets.csv
 * @dev Run with: forge script script/DeployPreGVT.s.sol:LoadAllocationsFromCSV --rpc-url <RPC_URL> --broadcast
 */
contract LoadAllocationsFromCSV is Script {
    address payable constant PREGVT_ADDRESS = payable(0x21cCA8546B1550ee47134AF86AE929C1fA3671c9);
    uint256 constant AMOUNT_PER_WALLET = 500e18;
    uint256 constant BATCH_SIZE = 50;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        PreGVT preGVT = PreGVT(PREGVT_ADDRESS);

        console.log("====================================");
        console.log("Loading Tier 3 Allocations");
        console.log("====================================");
        console.log("File: tier3_wallets.csv");
        console.log("Amount per wallet: 500 tokens");
        console.log("====================================\n");

        // Read the CSV file
        string memory csvContent = vm.readFile("tier3_wallets.csv");
        string[] memory lines = vm.split(csvContent, "\n");

        console.log("Total lines read:", lines.length);

        // Parse addresses
        address[] memory addresses = new address[](lines.length);
        uint256 validCount = 0;

        for (uint256 i = 0; i < lines.length; i++) {
            string memory line = vm.trim(lines[i]);

            // Skip empty lines and headers
            if (bytes(line).length == 0) continue;
            if (vm.indexOf(line, "address") != type(uint256).max) continue;
            if (vm.indexOf(line, "wallet") != type(uint256).max) continue;

            if (bytes(line).length >= 42) {
                string[] memory parts = vm.split(line, ",");
                string memory addrStr = vm.trim(parts[0]);

                try vm.parseAddress(addrStr) returns (address addr) {
                    addresses[validCount] = addr;
                    validCount++;
                } catch {
                    console.log("Warning: Invalid address:", addrStr);
                }
            }
        }

        console.log("Valid addresses found:", validCount);

        if (validCount == 0) {
            console.log("ERROR: No valid addresses found!");
            return;
        }

        // Resize to actual size
        address[] memory finalAddresses = new address[](validCount);
        for (uint256 i = 0; i < validCount; i++) {
            finalAddresses[i] = addresses[i];
        }

        console.log("\nStarting batch loading...\n");

        vm.startBroadcast(pk);

        uint256 totalBatches = (validCount + BATCH_SIZE - 1) / BATCH_SIZE;

        for (uint256 batch = 0; batch < totalBatches; batch++) {
            uint256 start = batch * BATCH_SIZE;
            uint256 end = start + BATCH_SIZE > validCount ? validCount : start + BATCH_SIZE;
            uint256 batchLength = end - start;

            address[] memory batchUsers = new address[](batchLength);
            uint256[] memory batchAmounts = new uint256[](batchLength);

            for (uint256 i = 0; i < batchLength; i++) {
                batchUsers[i] = finalAddresses[start + i];
                batchAmounts[i] = AMOUNT_PER_WALLET;
            }

            preGVT.setAllocations(batchUsers, batchAmounts);

            // console.log("Batch", batch + 1, , totalBatches, "completed -", batchLength, "addresses");
        }

        vm.stopBroadcast();

        console.log("\n====================================");
        console.log("SUCCESS!");
        console.log("====================================");
        console.log("Total addresses loaded:", validCount);
        console.log("Total tokens allocated:", (validCount * AMOUNT_PER_WALLET) / 1e18);
        console.log("====================================");
    }
}

/**
 * @title VerifyTier2Allocations
 * @notice Verify all tier 2 allocations were loaded correctly
 * @dev Run with: forge script script/DeployPreGVT.s.sol:VerifyTier2Allocations --rpc-url <RPC_URL>
 */
contract VerifyTier2Allocations is Script {
    address payable constant PREGVT_ADDRESS = payable(0x21cCA8546B1550ee47134AF86AE929C1fA3671c9);
    uint256 constant EXPECTED_AMOUNT = 1000e18;

    function run() external view {
        PreGVT preGVT = PreGVT(PREGVT_ADDRESS);

        console.log("====================================");
        console.log("Verifying Tier 2 Allocations");
        console.log("====================================");

        string memory csvContent = vm.readFile("tier3_wallets.csv");
        string[] memory lines = vm.split(csvContent, "\n");

        uint256 correctCount = 0;
        uint256 incorrectCount = 0;

        for (uint256 i = 0; i < lines.length; i++) {
            string memory line = vm.trim(lines[i]);

            if (bytes(line).length == 0) continue;
            if (vm.indexOf(line, "address") != type(uint256).max) continue;
            if (vm.indexOf(line, "wallet") != type(uint256).max) continue;

            if (bytes(line).length >= 42) {
                string[] memory parts = vm.split(line, ",");
                string memory addrStr = vm.trim(parts[0]);

                try vm.parseAddress(addrStr) returns (address addr) {
                    uint256 allocation = preGVT.allowanceOf(addr);

                    if (allocation == EXPECTED_AMOUNT) {
                        correctCount++;
                    } else {
                        console.log("Incorrect:", addr);
                        console.log("  Expected: 1000, Got:", allocation / 1e18);
                        incorrectCount++;
                    }
                } catch {}
            }
        }

        console.log("\n====================================");
        console.log("Verification Results");
        console.log("====================================");
        console.log("Correct allocations:", correctCount);
        console.log("Incorrect allocations:", incorrectCount);
        console.log("Total checked:", correctCount + incorrectCount);

        if (incorrectCount == 0) {
            console.log(" ALL CORRECT!");
        }
        console.log("====================================");
    }
}

/**
 * @title PreviewTier2CSV
 * @notice Preview first 10 addresses from CSV
 * @dev Run with: forge script script/DeployPreGVT.s.sol:PreviewTier2CSV --rpc-url <RPC_URL>
 */
contract PreviewTier2CSV is Script {
    function run() external view {
        console.log("====================================");
        console.log("CSV Preview - tier3_wallets.csv");
        console.log("====================================");

        string memory csvContent = vm.readFile("tier3_wallets.csv");
        string[] memory lines = vm.split(csvContent, "\n");

        console.log("Total lines:", lines.length);
        console.log("\nFirst 10 addresses:");

        uint256 count = 0;
        for (uint256 i = 0; i < lines.length && count < 10; i++) {
            string memory line = vm.trim(lines[i]);

            if (bytes(line).length == 0) continue;
            if (vm.indexOf(line, "address") != type(uint256).max) continue;
            if (vm.indexOf(line, "wallet") != type(uint256).max) continue;

            if (bytes(line).length >= 42) {
                string[] memory parts = vm.split(line, ",");
                string memory addrStr = vm.trim(parts[0]);

                try vm.parseAddress(addrStr) returns (address addr) {
                    console.log(count + 1, ":", addr);
                    count++;
                } catch {
                    console.log("Invalid:", addrStr);
                }
            }
        }

        console.log("====================================");
    }
}
