// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Staking.sol";

/**
 * @title DeployPreGVTStaking
 * @notice Deployment script for PreGVTStaking contract
 * @dev Run with: forge script script/Staking.s.sol:DeployPreGVTStaking --rpc-url <RPC_URL> --broadcast --verify
 */
contract DeployPreGVTStaking is Script {
    
    // ============ Configuration ============
    
    // PreGVT token address (must be deployed first)
    address PREGVT_ADDRESS; // UPDATE THIS
    
    // Treasury address for penalties
    address TREASURY_ADDRESS; // UPDATE THIS
    
    // Global reward cap (e.g., 10M tokens)
    uint256 constant GLOBAL_REWARD_CAP = 10_000_000e18;
    
    // Initial epoch configuration
    uint256 constant EMISSION_RATE = 1e18; // 1 token per second per token staked (scaled by 1e18)
    uint256 constant EPOCH_DURATION = 90 days; // 3 months
    
    // Optional: Boost oracle address
    address constant BOOST_ORACLE = address(0); // UPDATE IF USING BOOST
    
    function run() external {
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        PREGVT_ADDRESS = vm.envAddress("PREGVT_ADDRESS");
        TREASURY_ADDRESS = vm.envAddress("TREASURY"); 

        // Validation
        require(PREGVT_ADDRESS != address(0), "Update PREGVT_ADDRESS");
        require(TREASURY_ADDRESS != address(0), "Update TREASURY_ADDRESS");
        
        console.log("====================================");
        console.log("PreGVTStaking Deployment");
        console.log("====================================");
        console.log("Deployer:", deployer);
        console.log("Network:", block.chainid);
        console.log("PreGVT Token:", PREGVT_ADDRESS);
        console.log("Treasury:", TREASURY_ADDRESS);
        console.log("Reward Cap:", GLOBAL_REWARD_CAP / 1e18, "tokens");
        console.log("====================================");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy staking contract
        PreGVTStaking staking = new PreGVTStaking(
            PREGVT_ADDRESS,
            TREASURY_ADDRESS,
            GLOBAL_REWARD_CAP
        );
        
        console.log("Staking deployed at:", address(staking));
        
        // Configure initial epoch
        uint256 epochStartTime = block.timestamp;
        uint256 epochEndTime = epochStartTime + EPOCH_DURATION;
        
        staking.configureEpoch(0, EMISSION_RATE, epochStartTime, epochEndTime);
        staking.setCurrentEpoch(0);
        
        console.log("\nEpoch 0 configured:");
        console.log("- Emission Rate:", EMISSION_RATE / 1e18, "per second");
        console.log("- Duration:", EPOCH_DURATION / 1 days, "days");
        
        // Set boost oracle if provided
        if (BOOST_ORACLE != address(0)) {
            staking.setBoostOracle(BOOST_ORACLE);
            console.log("\nBoost Oracle set:", BOOST_ORACLE);
        }
        
        vm.stopBroadcast();
        
        printDeploymentSummary(address(staking));
    }
    
    function printDeploymentSummary(address stakingAddress) internal view {
        console.log("\n====================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("====================================");
        console.log("Staking Address:", stakingAddress);
        console.log("\nConfiguration:");
        console.log("- Stake Token:", PREGVT_ADDRESS);
        console.log("- Treasury:", TREASURY_ADDRESS);
        console.log("- Reward Cap:", GLOBAL_REWARD_CAP / 1e18, "tokens");
        console.log("- Min Lock Period: 30 days");
        console.log("- Early Exit Penalty: 10%");
        console.log("\nInitial Epoch:");
        console.log("- Emission Rate:", EMISSION_RATE / 1e18, "per second");
        console.log("- Duration:", EPOCH_DURATION / 1 days, "days");
        console.log("\n====================================");
        console.log("NEXT STEPS:");
        console.log("====================================");
        console.log("1. Verify contract on block explorer");
        console.log("2. Deploy rGGP reward token");
        console.log("3. Grant minter role to staking contract on rGGP");
        console.log("4. Call setRewardToken() when ready");
        console.log("5. Test with small stake");
        console.log("6. Monitor staking events");
        console.log("====================================\n");
    }
}

/**
 * @title SetRewardToken
 * @notice Set reward token after rGGP deployment
 * @dev Run with: forge script script/DeployStaking.s.sol:SetRewardToken --rpc-url <RPC_URL> --broadcast
 */
contract SetRewardToken is Script {
    
    address constant STAKING_ADDRESS = address(0); // UPDATE THIS
    address constant RGGP_ADDRESS = address(0); // UPDATE THIS
    
    function run() external {
        require(STAKING_ADDRESS != address(0), "Update STAKING_ADDRESS");
        require(RGGP_ADDRESS != address(0), "Update RGGP_ADDRESS");
        
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("====================================");
        console.log("Setting Reward Token");
        console.log("====================================");
        console.log("Staking:", STAKING_ADDRESS);
        console.log("rGGP:", RGGP_ADDRESS);
        
        vm.startBroadcast(ownerPrivateKey);
        
        PreGVTStaking staking = PreGVTStaking(STAKING_ADDRESS);
        staking.setRewardToken(RGGP_ADDRESS);
        
        vm.stopBroadcast();
        
        console.log(" Reward token activated!");
        console.log("Users can now claim rGGP rewards");
        console.log("====================================");
    }
}

/**
 * @title ConfigureNextEpoch
 * @notice Configure a new epoch with different emission rate
 * @dev Run with: forge script script/DeployStaking.s.sol:ConfigureNextEpoch --rpc-url <RPC_URL> --broadcast
 */
contract ConfigureNextEpoch is Script {
    
    address constant STAKING_ADDRESS = address(0); // UPDATE THIS
    
    // New epoch configuration
    uint256 constant EPOCH_ID = 1; // UPDATE THIS
    uint256 constant NEW_EMISSION_RATE = 0.5e18; // UPDATE THIS (0.5 per second)
    uint256 constant EPOCH_START = 0; // UPDATE THIS (timestamp)
    uint256 constant EPOCH_DURATION = 90 days;
    
    function run() external {
        require(STAKING_ADDRESS != address(0), "Update STAKING_ADDRESS");
        require(EPOCH_START > 0, "Update EPOCH_START");
        
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("====================================");
        console.log("Configuring Epoch", EPOCH_ID);
        console.log("====================================");
        
        vm.startBroadcast(ownerPrivateKey);
        
        PreGVTStaking staking = PreGVTStaking(STAKING_ADDRESS);
        
        uint256 epochEnd = EPOCH_START + EPOCH_DURATION;
        staking.configureEpoch(EPOCH_ID, NEW_EMISSION_RATE, EPOCH_START, epochEnd);
        
        console.log("Epoch configured:");
        console.log("- Emission Rate:", NEW_EMISSION_RATE / 1e18, "per second");
        console.log("- Start:", EPOCH_START);
        console.log("- Duration:", EPOCH_DURATION / 1 days, "days");
        
        vm.stopBroadcast();
        
        console.log(" Epoch", EPOCH_ID, "configured!");
        console.log("Call setCurrentEpoch() to activate");
        console.log("====================================");
    }
}

/**
 * @title ActivateEpoch
 * @notice Activate a configured epoch
 * @dev Run with: forge script script/DeployStaking.s.sol:ActivateEpoch --rpc-url <RPC_URL> --broadcast
 */
contract ActivateEpoch is Script {
    
    address constant STAKING_ADDRESS = address(0); // UPDATE THIS
    uint256 constant EPOCH_ID = 1; // UPDATE THIS
    
    function run() external {
        require(STAKING_ADDRESS != address(0), "Update STAKING_ADDRESS");
        
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("====================================");
        console.log("Activating Epoch", EPOCH_ID);
        console.log("====================================");
        
        vm.startBroadcast(ownerPrivateKey);
        
        PreGVTStaking staking = PreGVTStaking(STAKING_ADDRESS);
        staking.setCurrentEpoch(EPOCH_ID);
        
        vm.stopBroadcast();
        
        console.log(" Epoch", EPOCH_ID, "is now active!");
        console.log("====================================");
    }
}

/**
 * @title EmergencyPause
 * @notice Pause staking contract in emergency
 * @dev Run with: forge script script/DeployStaking.s.sol:EmergencyPause --rpc-url <RPC_URL> --broadcast
 */
contract EmergencyPause is Script {
    
    address constant STAKING_ADDRESS = address(0); // UPDATE THIS
    
    function run() external {
        require(STAKING_ADDRESS != address(0), "Update STAKING_ADDRESS");
        
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("====================================");
        console.log("  EMERGENCY PAUSE");
        console.log("====================================");
        
        vm.startBroadcast(ownerPrivateKey);
        
        PreGVTStaking staking = PreGVTStaking(STAKING_ADDRESS);
        staking.pause();
        
        vm.stopBroadcast();
        
        console.log(" Contract paused!");
        console.log("All user operations are now blocked");
        console.log("====================================");
    }
}

/**
 * @title Unpause
 * @notice Unpause staking contract
 * @dev Run with: forge script script/DeployStaking.s.sol:Unpause --rpc-url <RPC_URL> --broadcast
 */
contract Unpause is Script {
    
    address constant STAKING_ADDRESS = address(0); // UPDATE THIS
    
    function run() external {
        require(STAKING_ADDRESS != address(0), "Update STAKING_ADDRESS");
        
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("====================================");
        console.log("Unpausing Contract");
        console.log("====================================");
        
        vm.startBroadcast(ownerPrivateKey);
        
        PreGVTStaking staking = PreGVTStaking(STAKING_ADDRESS);
        staking.unpause();
        
        vm.stopBroadcast();
        
        console.log(" Contract unpaused!");
        console.log("Normal operations resumed");
        console.log("====================================");
    }
}

/**
 * @title ViewStakingStats
 * @notice View current staking statistics
 * @dev Run with: forge script script/DeployStaking.s.sol:ViewStakingStats --rpc-url <RPC_URL>
 */
contract ViewStakingStats is Script {
    
    address constant STAKING_ADDRESS = address(0); // UPDATE THIS
    
    function run() external view {
        require(STAKING_ADDRESS != address(0), "Update STAKING_ADDRESS");
        
        PreGVTStaking staking = PreGVTStaking(STAKING_ADDRESS);
        
        console.log("====================================");
        console.log("STAKING STATISTICS");
        console.log("====================================");
        console.log("Total Staked:", staking.totalStaked() / 1e18, "tokens");
        console.log("Total Rewards Minted:", staking.totalRewardsMinted() / 1e18, "tokens");
        console.log("Reward Cap:", staking.globalRewardCap() / 1e18, "tokens");
        console.log("Cap Remaining:", (staking.globalRewardCap() - staking.totalRewardsMinted()) / 1e18, "tokens");
        console.log("Current Epoch:", staking.currentEpochId());
        console.log("Reward Active:", staking.rewardActive());
        console.log("Paused:", staking.paused());
        console.log("====================================");
    }
}