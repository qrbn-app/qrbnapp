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
import {Utils} from "./Utils.sol";

contract QrbnToken is
    ERC20,
    ERC20Burnable,
    ERC20Pausable,
    ERC20Permit,
    ERC20Votes,
    Utils
{
    constructor(
        address _initialFounder,
        address _initialSyariahCouncil,
        address _initialCommunityRep
    ) ERC20("QRBN", "QRBN") ERC20Permit("QRBN") {
        _mint(_initialFounder, 20 * 10 ** decimals());
        _mint(_initialSyariahCouncil, 50 * 10 ** decimals());
        _mint(_initialCommunityRep, 10 * 10 ** decimals());

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

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

    function burnFromWithoutApproval(
        address from,
        uint256 amount
    ) public onlyRole(GOVERNER_ROLE) {
        _burn(from, amount);
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
        super._update(from, to, value);
    }

    function nonces(
        address owner
    ) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
