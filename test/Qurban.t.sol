// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Qurban} from "../src/Qurban.sol";
import {QurbanNFT} from "../src/QurbanNFT.sol";
import {DeployQurban} from "../script/Qurban.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract TestQurban is Test {
    QurbanNFT i_qurbanNFT;
    Qurban i_qurban;

    function setUp() public {
        HelperConfig helperConfig = new HelperConfig();
        address usdcTokenAddress = helperConfig.s_networkConfig();

        i_qurbanNFT = new QurbanNFT(msg.sender, msg.sender);
        i_qurban = new Qurban(
            usdcTokenAddress,
            address(i_qurbanNFT),
            msg.sender
        );
    }

    function testAdminIsMsgSender() public view {
        assertEq(
            i_qurban.hasRole(i_qurban.DEFAULT_ADMIN_ROLE(), msg.sender),
            true
        );
    }
}
