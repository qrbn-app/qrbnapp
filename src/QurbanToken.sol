// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

contract QurbanToken is
    ERC20,
    ERC20Burnable,
    ERC20Pausable,
    AccessManaged,
    ERC20Permit,
    ERC20Votes
{
    constructor(
        address initialFounder,
        address initialSyariahCouncil,
        address initialCommunityRep,
        address initialOrgRep,
        address initialAuthority
    )
        ERC20("QurbanToken", "QRT")
        AccessManaged(initialAuthority)
        ERC20Permit("QurbanToken")
    {
        _mint(initialFounder, 20e18);
        _mint(initialSyariahCouncil, 50e18);
        _mint(initialCommunityRep, 10e18);
        _mint(initialOrgRep, 15e18);
    }

    function pause() public restricted {
        _pause();
    }

    function unpause() public restricted {
        _unpause();
    }

    function mint(address to, uint256 amount) public restricted {
        _mint(to, amount);
        _delegate(to, to);
    }

    function burnFromWithoutApproval(
        address from,
        uint256 amount
    ) public restricted {
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
