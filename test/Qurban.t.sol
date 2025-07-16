// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Qurban} from "../src/Qurban.sol";
import {QurbanNFT} from "../src/QurbanNFT.sol";
import {QurbanToken} from "../src/QurbanToken.sol";
import {QurbanGov} from "../src/QurbanGov.sol";
import {DeployQurban} from "../script/Qurban.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract TestQurban is Test {
    QurbanNFT i_qurbanNFT;
    QurbanToken i_qurbanToken;
    QurbanGov i_qurbanGov;
    Qurban i_qurban;

    address testContract = address(this);
    address founder = makeAddr("founder");
    address syariahCouncil = makeAddr("syariahCouncil");
    address communityRep = makeAddr("communityRep");
    address orgRep = makeAddr("orgRep");

    function setUp() public {
        HelperConfig helperConfig = new HelperConfig();
        address usdcTokenAddress = helperConfig.s_networkConfig();

        i_qurbanNFT = new QurbanNFT(testContract, testContract);

        i_qurbanToken = new QurbanToken(
            founder,
            syariahCouncil,
            communityRep,
            orgRep,
            testContract
        );

        i_qurbanGov = new QurbanGov(i_qurbanToken);
        i_qurbanToken.setAuthority(address(i_qurbanGov));

        i_qurban = new Qurban(
            usdcTokenAddress,
            address(i_qurbanNFT),
            address(i_qurbanToken),
            address(i_qurbanGov)
        );
    }

    function testGovernerRole() public view {
        assertEq(
            i_qurban.hasRole(i_qurban.GOVERNER_ROLE(), address(i_qurbanGov)),
            true
        );
    }
}
