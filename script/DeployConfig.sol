// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {QurbanNFT} from "../src/qurban/QurbanNFT.sol";
import {QrbnToken} from "../src/dao/QrbnToken.sol";
import {QrbnGov} from "../src/dao/QrbnGov.sol";
import {Qurban} from "../src/qurban/Qurban.sol";
import {Constants} from "../src/lib/Constants.sol";

contract DeployConfig is Script {
    struct NetworkConfig {
        address usdcTokenAddress;
    }

    NetworkConfig private _networkConfig;

    constructor() {
        if (block.chainid == Constants.LISK_CHAINID) {
            _networkConfig = getLiskNetworkConfig();
        } else if (block.chainid == Constants.LISK_SEPOLIA_CHAINID) {
            _networkConfig = getLiskSepoliaNetworkConfig();
        } else {
            _networkConfig = getLocalNetworkConfig();
        }
    }

    function getNetworkConfig() public view returns (NetworkConfig memory) {
        return _networkConfig;
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
        if (_networkConfig.usdcTokenAddress != address(0)) {
            return _networkConfig;
        }

        vm.startBroadcast();
        MockUSDC mockUSDC = new MockUSDC(msg.sender, msg.sender);
        vm.stopBroadcast();

        return NetworkConfig({usdcTokenAddress: address(mockUSDC)});
    }
}
