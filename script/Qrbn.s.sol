// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {Helper} from "./Helper.s.sol";
import {QrbnNFT} from "../src/QrbnNFT.sol";
import {QrbnToken} from "../src/QrbnToken.sol";
import {QrbnGov} from "../src/QrbnGov.sol";
import {Qurban} from "../src/Qurban.sol";

contract DeployQrbn is Script {
    function run(
        address _initialFounder,
        address _initialSyariahCouncil,
        address _initialCommunityRep
    ) public returns (Qurban, QrbnGov, QrbnToken, QrbnNFT) {
        Helper helper = new Helper();
        address usdcTokenAddress = helper.s_networkConfig();

        vm.startBroadcast();

        QrbnNFT qrbnNFT = new QrbnNFT();

        QrbnToken qrbnToken = new QrbnToken(
            _initialFounder,
            _initialSyariahCouncil,
            _initialCommunityRep
        );

        QrbnGov qrbnGov = new QrbnGov(qrbnToken);

        Qurban qurban = new Qurban(
            usdcTokenAddress,
            address(qrbnNFT),
            address(qrbnToken),
            address(qrbnGov)
        );

        qrbnNFT.grantGovernerRole(address(qrbnGov), address(qurban));
        qrbnToken.grantGovernerRole(address(qrbnGov), address(qurban));

        vm.stopBroadcast();

        return (qurban, qrbnGov, qrbnToken, qrbnNFT);
    }
}
