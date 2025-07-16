// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract QrbnGov is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction
{
    uint16 public constant LISK_CHAINID = 1135;
    uint64 public constant PROPOSAL_TREESHOLD = 10 * 10 ** 2;

    constructor(
        IVotes _token
    )
        Governor("QrbnGov")
        GovernorSettings(
            _getVotingDelay(),
            _getVotingPeriod(),
            PROPOSAL_TREESHOLD
        )
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(51)
    {}

    function _getVotingDelay() private view returns (uint48) {
        if (block.chainid == LISK_CHAINID) {
            return 1 days;
        }
        return 1 minutes;
    }

    function _getVotingPeriod() private view returns (uint32) {
        if (block.chainid == LISK_CHAINID) {
            return 1 weeks;
        }
        return 6 minutes;
    }

    // The following functions are overrides required by Solidity.

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }
}
