// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {QurbanNFT} from "../src/QurbanNFT.sol";
import {Qurban} from "../src/Qurban.sol";

contract DeployQurban is Script {
    QurbanNFT nft;
    Qurban qurban;

    function run() external returns (Qurban) {
        vm.startBroadcast();

        nft = new QurbanNFT();
        qurban = new Qurban(address(nft));

        nft.transferOwnership(address(qurban));

        vm.stopBroadcast();

        return qurban;
    }
}
