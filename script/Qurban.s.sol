// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {QurbanNFT} from "../src/QurbanNFT.sol";
import {Qurban} from "../src/Qurban.sol";

contract DeployQurban is Script {
    function run() external returns (Qurban) {
        HelperConfig helperConfig = new HelperConfig();
        address usdcTokenAddress = helperConfig.s_networkConfig();

        vm.startBroadcast();

        QurbanNFT nft = new QurbanNFT(msg.sender, msg.sender);
        Qurban qurban = new Qurban(usdcTokenAddress, address(nft), msg.sender);

        vm.stopBroadcast();

        return qurban;
    }
}
