// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract Utils is AccessControl {
    bytes32 public constant GOVERNER_ROLE = keccak256("GOVERNER_ROLE");
    uint16 public constant LISK_CHAINID = 1135;
    uint256 public constant PLATFORM_FEE_BPS = 250; // 2.5%
    uint8 public constant MAX_SHARES = 20;
    uint256 public constant BPS_BASE = 10000;

    function grantGovernerRole(
        address _governerAddress,
        address _qurbanAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(GOVERNER_ROLE, _governerAddress);
        _grantRole(GOVERNER_ROLE, _qurbanAddress);
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
