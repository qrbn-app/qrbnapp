// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {DeployConfig} from "./DeployConfig.sol";
import {QurbanNFT} from "../src/qurban/QurbanNFT.sol";
import {QrbnToken} from "../src/dao/QrbnToken.sol";
import {QrbnGov} from "../src/dao/QrbnGov.sol";
import {QrbnTimelock} from "../src/dao/QrbnTimelock.sol";
import {Qurban} from "../src/qurban/Qurban.sol";
import {Constants} from "../src/lib/Constants.sol";

contract DeployQrbn is Script, DeployConfig {
    function run(
        address _founderAddress,
        address _syariahCouncilAddress,
        address _orgRepAddress,
        address _communityRepAddress
    ) public {
        NetworkConfig memory networkConfig = getNetworkConfig();
        address usdcTokenAddress = networkConfig.usdcTokenAddress;

        uint256 minExecutionDelay;
        uint48 votingDelay;
        uint32 votingPeriod;
        uint64 proposalThreshold = 1;
        uint256 quorumFraction = 75;

        vm.startBroadcast();
        address tempAdmin = msg.sender;

        if (block.chainid == Constants.LISK_CHAINID) {
            minExecutionDelay = 2 days;
            votingDelay = 1 days;
            votingPeriod = 1 weeks;
        } else {
            minExecutionDelay = 5 minutes;
            votingDelay = 1 minutes;
            votingPeriod = 10 minutes;
        }

        // DAO
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        QrbnTimelock timelock = new QrbnTimelock(
            minExecutionDelay,
            proposers,
            executors,
            tempAdmin
        );
        // QrbnToken token = new QrbnToken(address(timelock), tempAdmin);
        // QrbnGov gov = new QrbnGov(
        //     token,
        //     timelock,
        //     votingDelay,
        //     votingPeriod,
        //     proposalThreshold,
        //     quorumFraction
        // );

        // timelock.grantRole(timelock.PROPOSER_ROLE(), address(gov));
        // timelock.grantRole(timelock.CANCELLER_ROLE(), _syariahCouncilAddress);
        // timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), tempAdmin);

        // token.grantRole(token.GOVERNER_ROLE(), tempAdmin);
        // token.mint(_founderAddress, 1 * 10 ** token.decimals());
        // token.mint(_syariahCouncilAddress, 1 * 10 ** token.decimals());
        // token.mint(_orgRepAddress, 1 * 10 ** token.decimals());
        // token.mint(_communityRepAddress, 1 * 10 ** token.decimals());
        // token.revokeRole(token.GOVERNER_ROLE(), tempAdmin);
        // token.revokeRole(token.DEFAULT_ADMIN_ROLE(), tempAdmin);

        // QURBAN
        // Qurban qurban = new Qurban(
        //     usdcTokenAddress,
        //     address(timelock),
        //     tempAdmin
        // );
        // QurbanNFT qurbanNFT = new QurbanNFT(address(timelock), tempAdmin);

        // qurbanNFT.grantRole(qurbanNFT.GOVERNER_ROLE(), address(qurban));

        // if (block.chainid == Constants.LISK_CHAINID) {
        //     qurban.revokeRole(qurban.DEFAULT_ADMIN_ROLE(), tempAdmin);
        //     qurbanNFT.revokeRole(qurbanNFT.DEFAULT_ADMIN_ROLE(), tempAdmin);
        // }

        vm.stopBroadcast();

        // return (timelock, gov, token, qurban, qurbanNFT);
    }
}
