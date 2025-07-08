// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Qurban} from "../src/Qurban.sol";
import {DeployQurban} from "../script/DeployQurban.s.sol";

contract TestQurban is Test {
    Qurban qurban;

    function setup() external {
        DeployQurban deployQurban = new DeployQurban();
        qurban = deployQurban.run();
    }
}
