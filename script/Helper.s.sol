// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {QrbnNFT} from "../src/QrbnNFT.sol";
import {QrbnToken} from "../src/QrbnToken.sol";
import {QrbnGov} from "../src/QrbnGov.sol";
import {Qurban} from "../src/Qurban.sol";

contract Helper is Script {
    struct NetworkConfig {
        address usdcTokenAddress;
    }
    NetworkConfig public s_networkConfig;

    constructor() {
        // Lisk
        if (block.chainid == 1135) {
            s_networkConfig = getLiskNetworkConfig();
        }
        // Lisk Sepolia
        else if (block.chainid == 4202) {
            s_networkConfig = getLiskSepoliaNetworkConfig();
        } else {
            s_networkConfig = getLocalNetworkConfig();
        }
    }

    function getLiskNetworkConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                usdcTokenAddress: 0xF242275d3a6527d877f2c927a82D9b057609cc71
            });
    }

    function getLiskSepoliaNetworkConfig()
        public
        pure
        returns (NetworkConfig memory)
    {
        return
            NetworkConfig({
                usdcTokenAddress: 0x0E82fDDAd51cc3ac12b69761C45bBCB9A2Bf3C83
            });
    }

    function getLocalNetworkConfig() public returns (NetworkConfig memory) {
        if (s_networkConfig.usdcTokenAddress != address(0)) {
            return s_networkConfig;
        }

        vm.startBroadcast();
        MockUSDC mockUSDC = new MockUSDC(msg.sender, msg.sender);
        vm.stopBroadcast();

        return NetworkConfig({usdcTokenAddress: address(mockUSDC)});
    }
}
