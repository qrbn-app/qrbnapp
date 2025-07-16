// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract GovUtils is AccessControl {
    bytes32 public constant GOVERNER_ROLE = keccak256("GOVERNER_ROLE");

    function grantGovernerRole(
        address _governerAddress,
        address _qurbanAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(GOVERNER_ROLE, _governerAddress);
        _grantRole(GOVERNER_ROLE, _qurbanAddress);
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
