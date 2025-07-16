// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {QurbanNFT} from "../src/QurbanNFT.sol";
import {QurbanToken} from "../src/QurbanToken.sol";
import {QurbanGov} from "../src/QurbanGov.sol";
import {Qurban} from "../src/Qurban.sol";

contract DeployQurban is Script {
    function run(
        address _initialFounder,
        address _initialSyariahCouncil,
        address _initialCommunityRep,
        address _initialOrgRep
    ) public returns (Qurban, QurbanGov, QurbanToken, QurbanNFT) {
        HelperConfig helperConfig = new HelperConfig();
        address usdcTokenAddress = helperConfig.s_networkConfig();

        vm.startBroadcast();
        address deployer = msg.sender;

        QurbanNFT qurbanNFT = new QurbanNFT(deployer, deployer);

        QurbanToken qurbanToken = new QurbanToken(
            _initialFounder,
            _initialSyariahCouncil,
            _initialCommunityRep,
            _initialOrgRep,
            deployer
        );

        QurbanGov qurbanGov = new QurbanGov(qurbanToken);
        qurbanToken.setAuthority(address(qurbanGov));

        Qurban qurban = new Qurban(
            usdcTokenAddress,
            address(qurbanNFT),
            address(qurbanToken),
            address(qurbanGov)
        );

        vm.stopBroadcast();

        return (qurban, qurbanGov, qurbanToken, qurbanNFT);
    }
}
