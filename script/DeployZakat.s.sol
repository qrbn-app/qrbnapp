// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {ZakatNFT} from "../src/zakat/ZakatNFT.sol";
import {Zakat} from "../src/zakat/Zakat.sol";
import {QrbnTreasury} from "../src/dao/QrbnTreasury.sol";
import {Constants} from "../src/lib/Constants.sol";

contract DeployZakat is Script {
    address constant TIMELOCK_ADDRESS = 0xD480E4394b1Df72b39eAdBb0ce36ccB19dB5867C;
    address constant TREASURY_ADDRESS = 0x841e2afAAfE341e172Ec1a080898D98302F6bb80;
    
    // USDC addresses
    address constant LISK_USDC = 0xF242275d3a6527d877f2c927a82D9b057609cc71;
    
    // Existing ZakatNFT address (using deployed ZakatNFT address)
    address constant EXISTING_ZAKAT_NFT = 0x2A628BACF45cb6b9Dcf8305A2615693023068B1A;
    
    function run() public returns (Zakat zakat, ZakatNFT zakatNFT) {
        address usdcAddress;
        
        if (block.chainid == Constants.LISK_CHAINID) {
            usdcAddress = LISK_USDC;
        } else if (block.chainid == Constants.LISK_SEPOLIA_CHAINID || block.chainid == Constants.ANVIL_CHAINID) {
            console.log("Warning: Using testnet - make sure to set correct USDC address");
            usdcAddress = LISK_USDC; 
        } else {
            revert("Unsupported network");
        }
        
        console.log("Deploying Zakat contracts...");
        console.log("Using USDC address:", usdcAddress);
        console.log("Using Treasury address:", TREASURY_ADDRESS);
        console.log("Using Timelock address:", TIMELOCK_ADDRESS);
        
        vm.startBroadcast();
        
        // Use existing ZakatNFT if address is provided, otherwise deploy new one
        if (EXISTING_ZAKAT_NFT != address(0)) {
            console.log("Using existing ZakatNFT at:", EXISTING_ZAKAT_NFT);
            zakatNFT = ZakatNFT(EXISTING_ZAKAT_NFT);
        } else {
            // Deploy ZakatNFT 
            console.log("Deploying ZakatNFT...");
            zakatNFT = new ZakatNFT(TIMELOCK_ADDRESS, msg.sender);
            console.log("ZakatNFT deployed at:", address(zakatNFT));
        }
        
        // Deploy Zakat contract
        console.log("Deploying Zakat...");
        zakat = new Zakat(
            usdcAddress,
            TREASURY_ADDRESS,
            TIMELOCK_ADDRESS,
            address(zakatNFT),
            msg.sender
        );
        console.log("Zakat deployed at:", address(zakat));
        
        // Grant ZakatNFT minting permission to Zakat contract
        console.log("Granting NFT minting permission to Zakat contract...");
        try zakatNFT.grantRole(zakatNFT.GOVERNER_ROLE(), address(zakat)) {
            console.log("Successfully granted GOVERNER_ROLE to Zakat contract");
        } catch {
            console.log("Failed to grant GOVERNER_ROLE - you may need to do this manually");
        }
        
        // Handle treasury authorization based on network
        QrbnTreasury treasury = QrbnTreasury(TREASURY_ADDRESS);
        
        if (block.chainid != Constants.LISK_CHAINID) {
            // For testnets, try to authorize if deployer has permission
            console.log("Testnet detected - attempting to authorize Zakat as treasury depositor...");
            try treasury.authorizeDepositor(address(zakat)) {
                console.log("Successfully authorized Zakat as treasury depositor");
            } catch {
                console.log("Failed to authorize - you may need to do this manually");
            }
            
            // Grant governor roles for testing
            zakat.grantRole(zakat.GOVERNER_ROLE(), msg.sender);
            zakatNFT.grantRole(zakatNFT.GOVERNER_ROLE(), msg.sender);
            console.log("Granted governor roles to deployer for testing");
        } else {
            // For mainnet, revoke admin roles for security
            console.log("Mainnet detected - revoking admin roles for security...");
            zakat.revokeRole(zakat.DEFAULT_ADMIN_ROLE(), msg.sender);
            zakatNFT.revokeRole(zakatNFT.DEFAULT_ADMIN_ROLE(), msg.sender);
            console.log("Admin roles revoked. Treasury authorization requires governance proposal.");
        }
        
        vm.stopBroadcast();
        
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Zakat:", address(zakat));
        console.log("ZakatNFT:", address(zakatNFT));
        
        if (block.chainid == Constants.LISK_CHAINID) {
            console.log("IMPORTANT: Create governance proposal to authorize Zakat contract in Treasury:");
            console.log("Call: treasury.authorizeDepositor(%s)", address(zakat));
        }
        
        return (zakat, zakatNFT);
    }
}