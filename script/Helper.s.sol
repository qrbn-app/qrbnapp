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

    uint16 public constant LISK_CHAINID = 1135;
    uint16 public constant LISK_SEPOLIA_CHAINID = 4202;

    constructor() {
        if (block.chainid == LISK_CHAINID) {
            s_networkConfig = getLiskNetworkConfig();
        } else if (block.chainid == LISK_SEPOLIA_CHAINID) {
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
