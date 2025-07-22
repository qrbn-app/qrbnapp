// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {DeployConfig} from "./DeployConfig.sol";
import {QurbanNFT} from "../src/qurban/QurbanNFT.sol";
import {QrbnToken} from "../src/dao/QrbnToken.sol";
import {QrbnGov} from "../src/dao/QrbnGov.sol";
import {QrbnTimelock} from "../src/dao/QrbnTimelock.sol";
import {Qurban} from "../src/qurban/Qurban.sol";
import {QrbnTreasury} from "../src/dao/QrbnTreasury.sol";
import {Constants} from "../src/lib/Constants.sol";

contract DeployQrbn is Script {
    function run(
        address _founderAddress,
        address _syariahCouncilAddress,
        address _orgRepAddress,
        address _communityRepAddress
    )
        public
        returns (
            QrbnTimelock,
            QrbnGov,
            QrbnToken,
            Qurban,
            QurbanNFT,
            QrbnTreasury
        )
    {
        DeployConfig deployConfig = new DeployConfig();
        DeployConfig.NetworkConfig memory networkConfig = deployConfig
            .getNetworkConfig();

        return
            runDeploy(
                networkConfig.usdcTokenAddress,
                _founderAddress,
                _syariahCouncilAddress,
                _orgRepAddress,
                _communityRepAddress,
                false
            );
    }

    function runDeploy(
        address _usdcTokenAddress,
        address _founderAddress,
        address _syariahCouncilAddress,
        address _orgRepAddress,
        address _communityRepAddress,
        bool _isTest
    )
        public
        returns (
            QrbnTimelock,
            QrbnGov,
            QrbnToken,
            Qurban,
            QurbanNFT,
            QrbnTreasury
        )
    {
        uint256 minExecutionDelay;
        uint48 votingDelay;
        uint32 votingPeriod;
        uint64 proposalThreshold = 1;
        uint256 quorumFraction = 75;

        if (block.chainid == Constants.LISK_CHAINID) {
            minExecutionDelay = 2 days;
            votingDelay = 1 days;
            votingPeriod = 1 weeks;
        } else {
            minExecutionDelay = 5 minutes;
            votingDelay = 1 minutes;
            votingPeriod = 10 minutes;
        }
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        if (_isTest) {
            vm.startPrank(msg.sender);
        } else {
            vm.startBroadcast();
        }

        // DAO
        QrbnTimelock timelock = new QrbnTimelock(
            minExecutionDelay,
            proposers,
            executors,
            msg.sender
        );
        QrbnToken token = new QrbnToken(address(timelock), msg.sender);
        QrbnGov gov = new QrbnGov(
            token,
            timelock,
            votingDelay,
            votingPeriod,
            proposalThreshold,
            quorumFraction
        );

        // QURBAN & TREASURY
        QurbanNFT qurbanNFT = new QurbanNFT(address(timelock), msg.sender);
        QrbnTreasury treasury = new QrbnTreasury(
            address(timelock),
            msg.sender,
            _usdcTokenAddress
        );
        Qurban qurban = new Qurban(
            _usdcTokenAddress,
            address(treasury),
            address(timelock),
            msg.sender
        );

        // GRANTS
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(gov));
        timelock.grantRole(timelock.CANCELLER_ROLE(), _syariahCouncilAddress);
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), msg.sender);

        token.grantRole(token.GOVERNER_ROLE(), msg.sender);

        token.mint(_founderAddress, 1 * 10 ** token.decimals());
        token.mint(_syariahCouncilAddress, 1 * 10 ** token.decimals());
        token.mint(_orgRepAddress, 1 * 10 ** token.decimals());
        token.mint(_communityRepAddress, 1 * 10 ** token.decimals());

        token.revokeRole(token.GOVERNER_ROLE(), msg.sender);
        token.revokeRole(token.DEFAULT_ADMIN_ROLE(), msg.sender);

        qurbanNFT.grantRole(qurbanNFT.GOVERNER_ROLE(), address(qurban));

        // TREASURY CONFIGURATION
        treasury.grantRole(treasury.GOVERNER_ROLE(), msg.sender);
        treasury.authorizeDepositor(address(qurban));
        treasury.revokeRole(treasury.GOVERNER_ROLE(), msg.sender);
        treasury.revokeRole(treasury.DEFAULT_ADMIN_ROLE(), msg.sender);

        if (block.chainid == Constants.LISK_CHAINID) {
            qurban.revokeRole(qurban.DEFAULT_ADMIN_ROLE(), msg.sender);
            qurbanNFT.revokeRole(qurbanNFT.DEFAULT_ADMIN_ROLE(), msg.sender);
        } else {
            qurban.grantRole(qurban.GOVERNER_ROLE(), msg.sender);
            qurbanNFT.grantRole(qurbanNFT.GOVERNER_ROLE(), msg.sender);
        }

        if (_isTest) {
            vm.stopPrank();
        } else {
            vm.stopBroadcast();
        }

        return (timelock, gov, token, qurban, qurbanNFT, treasury);
    }
}
