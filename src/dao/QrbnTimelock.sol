// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract QrbnTimelock is TimelockController {
    constructor(
        uint256 _minDelay,
        address[] memory _proposers, // QrbnGov
        address[] memory _executors, // anyone/address(0)
        address _tempAdminAddress
    )
        TimelockController(_minDelay, _proposers, _executors, _tempAdminAddress)
    {}
}
