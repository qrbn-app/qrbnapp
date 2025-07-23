// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

abstract contract Governed is AccessControl {
    bytes32 public constant GOVERNER_ROLE = keccak256("GOVERNER_ROLE");

    constructor(address _timelockAddress, address _tempAdminAddress) {
        _grantRole(GOVERNER_ROLE, _timelockAddress);

        if (_tempAdminAddress != address(0)) {
            _grantRole(DEFAULT_ADMIN_ROLE, _tempAdminAddress);
        }
    }
}
