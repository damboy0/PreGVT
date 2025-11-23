// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * DEPLOYMENT GUIDE FOR SHADOWGVT
 *
 * This file contains example scripts for Foundry (forge script) and Hardhat.
 * Choose the framework your project uses.
 *
 * === FOUNDRY SCRIPTS ===
 * Place these files in: script/
 */

// ============================================================
// FILE: script/DeployShadowGVT.s.sol
// ============================================================

import "forge-std/Script.sol";
import "../src/ShadowGVT.sol";

contract DeployShadowGVT is Script {
    function run() public {
        // Get private key from environment
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        // Target Safe Multisig address (replace with actual)
        address safeMultisig = vm.envAddress("SAFE_MULTISIG");

        require(safeMultisig != address(0), "SAFE_MULTISIG not set");

        vm.startBroadcast(deployerKey);

        // Step 1: Deploy ShadowGVT with deployer as temporary admin
        ShadowGVT shadowGVT = new ShadowGVT(msg.sender);
        console.log("ShadowGVT deployed at:", address(shadowGVT));

        // Step 2: Grant ADMIN_ROLE to Safe Multisig
        shadowGVT.grantRole(shadowGVT.ADMIN_ROLE(), safeMultisig);
        console.log("ADMIN_ROLE granted to Safe:", safeMultisig);

        // Step 3: Revoke temporary deployer admin rights
        shadowGVT.revokeRole(shadowGVT.DEFAULT_ADMIN_ROLE(), msg.sender);
        console.log("Deployer admin role revoked");

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("ShadowGVT:", address(shadowGVT));
        console.log("Admin (Safe Multisig):", safeMultisig);
        console.log("\nNext steps:");
        console.log("1. Verify on BscScan: npx hardhat verify --network bsc <ADDRESS>");
        console.log("2. Use Safe multisig to mint initial LP supply");
        console.log("3. Create LP pool on PancakeSwap V2");
    }
}

// ============================================================
// FILE: script/MintAndDeployLP.s.sol
// ============================================================

import "forge-std/Script.sol";
import "../src/ShadowGVT.sol";

interface IPancakeRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function factory() external pure returns (address);
}

interface IERC20Mint {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract MintAndDeployLP is Script {
    // BNB Chain addresses
    address PANCAKE_ROUTER = vm.envAddress("PRIVATE_KEY");
    address constant USDT_BNB = 0x55d398326f99059fF775485246999027B3197955;

    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address shadowGVTAddr = vm.envAddress("SHADOW_GVT");
        address safeMultisig = vm.envAddress("SAFE_MULTISIG");

        require(shadowGVTAddr != address(0), "SHADOW_GVT not set");
        require(safeMultisig != address(0), "SAFE_MULTISIG not set");

        ShadowGVT shadowGVT = ShadowGVT(shadowGVTAddr);

        vm.startBroadcast(deployerKey);

        // Using deployer as LP provider (in production, use Safe/Treasury)
        address lpProvider = msg.sender;

        // Step 1: Mint LP supply (20 sGVT tokens)
        uint256 lpAmount = 20e18;
        shadowGVT.mint(lpProvider, lpAmount);
        console.log("Minted", lpAmount / 1e18, "sGVT to LP provider");

        // Step 2: Approve USDT spending
        IERC20Mint usdt = IERC20Mint(USDT_BNB);
        uint256 usdtAmount = 10e18; // 10 USDT equivalent
        usdt.approve(PANCAKE_ROUTER, usdtAmount);
        console.log("Approved", usdtAmount / 1e18, "USDT for router");

        // Step 3: Approve sGVT spending
        shadowGVT.approve(PANCAKE_ROUTER, lpAmount);
        console.log("Approved", lpAmount / 1e18, "sGVT for router");

        // Step 4: Add liquidity
        IPancakeRouter router = IPancakeRouter(PANCAKE_ROUTER);
        (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(
            shadowGVTAddr,
            USDT_BNB,
            lpAmount,
            usdtAmount,
            lpAmount, // min 1:1
            usdtAmount, // min 1:1
            safeMultisig, // LP tokens to Safe (optional)
            block.timestamp + 300
        );

        console.log("\n=== LP DEPLOYMENT COMPLETE ===");
        console.log("sGVT added:", amountA / 1e18);
        console.log("USDT added:", amountB / 1e18);
        console.log("Liquidity minted:", liquidity);

        vm.stopBroadcast();
    }
}

// ============================================================
// HARDHAT SCRIPTS (TypeScript)
// Place in: scripts/
// ============================================================

/**
 * FILE: scripts/deployments/01_deploy_shadow_gvt.ts
 *
 * Usage:
 *   npx hardhat run scripts/deployments/01_deploy_shadow_gvt.ts --network bsc
 */

/*
import { ethers } from "hardhat";

async function main() {
  console.log("Deploying ShadowGVT...");

  // Get accounts
  const [deployer] = await ethers.getSigners();
  const safeMultisig = process.env.SAFE_MULTISIG!;

  console.log("Deployer:", deployer.address);
  console.log("Safe Multisig:", safeMultisig);

  // Deploy
  const ShadowGVT = await ethers.getContractFactory("ShadowGVT");
  const shadowGVT = await ShadowGVT.deploy(deployer.address);
  await shadowGVT.deployed();

  console.log("ShadowGVT deployed to:", shadowGVT.address);

  // Grant ADMIN_ROLE to Safe
  const ADMIN_ROLE = ethers.utils.id("ADMIN_ROLE");
  const tx1 = await shadowGVT.grantRole(ADMIN_ROLE, safeMultisig);
  await tx1.wait();
  console.log("ADMIN_ROLE granted to Safe");

  // Revoke deployer admin
  const DEFAULT_ADMIN_ROLE = ethers.constants.HashZero;
  const tx2 = await shadowGVT.revokeRole(DEFAULT_ADMIN_ROLE, deployer.address);
  await tx2.wait();
  console.log("Deployer admin role revoked");

  // Verify
  console.log("\nVerify with:");
  console.log(
    `npx hardhat verify --network bsc ${shadowGVT.address} "${deployer.address}"`
  );

  return shadowGVT.address;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
*/

// ============================================================
// ENVIRONMENT FILE TEMPLATE
// Create .env file with:
// ============================================================

/*
PRIVATE_KEY=0x...
SAFE_MULTISIG=0x...
SHADOW_GVT=0x...
BNB_RPC_URL=https://bsc-dataseed.binance.org/
*/

// ============================================================
// DEPLOYMENT CHECKLIST
// ============================================================

/**
 * PRE-DEPLOYMENT:
 * [ ] Have BNB in deployer wallet (for gas)
 * [ ] Set PRIVATE_KEY, SAFE_MULTISIG in .env
 * [ ] Verify Safe multisig address is correct
 * [ ] Test on testnet first
 *
 * DEPLOYMENT STEPS (Foundry):
 * [ ] Step 1: Deploy contract
 *     $ source .env && forge script script/DeployShadowGVT.s.sol --rpc-url $BNB_RPC_URL --broadcast
 *
 * [ ] Step 2: Verify on BscScan
 *     $ forge verify-contract --chain-id 56 --constructor-args $(cast abi-encode "constructor(address)" "<deployer>") <ADDRESS> src/ShadowGVT.sol:ShadowGVT
 *
 * [ ] Step 3: Verify deployment
 *     - Check BscScan that Safe is admin
 *     - Check total supply is 0
 *
 * [ ] Step 4: Multisig mints and creates LP (via Safe)
 *     - Mint: 20 sGVT
 *     - Add LP on PancakeSwap V2
 *
 * [ ] Step 5: Publish addresses
 *     - GitHub repository
 *     - AGV documentation
 *     - BscScan token page
 *
 * POST-DEPLOYMENT:
 * [ ] Share contract address with wallets/dashboards
 * [ ] Monitor LP price on DEX for accuracy
 * [ ] Keep Safe keys secure
 * [ ] Do NOT mint beyond LP supply
 * [ ] Document on AGV website
 */

// Note: This is a configuration/documentation file.
// Extract the Foundry scripts above into separate files in your project.
