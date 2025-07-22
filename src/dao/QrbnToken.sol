// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Governed} from "./Governed.sol";

contract QrbnToken is
    ERC20,
    ERC20Burnable,
    ERC20Pausable,
    ERC20Permit,
    ERC20Votes,
    Governed
{
    error TokenNotTransferrable();

    constructor(
        address _timelockAddress,
        address _tempAdminAddress
    )
        ERC20("QRBN", "QRBN")
        ERC20Permit("QRBN")
        Governed(_timelockAddress, _tempAdminAddress)
    {}

    function decimals() public pure override returns (uint8) {
        return 2;
    }

    function pause() public onlyRole(GOVERNER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(GOVERNER_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyRole(GOVERNER_ROLE) {
        _mint(to, amount);
        _delegate(to, to);
    }

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    // The following functions are overrides required by Solidity.

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable, ERC20Votes) {
        if (from != address(0) && to != address(0)) {
            revert TokenNotTransferrable();
        }

        super._update(from, to, value);
    }

    function nonces(
        address owner
    ) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
