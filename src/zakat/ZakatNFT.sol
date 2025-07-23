// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Governed} from "../dao/Governed.sol";

/**
 * @title ZakatNFT
 * @author QRBN Team
 * @notice NFT contract for Zakat donation certificates
 * @dev This contract mints NFT certificates to Zakat donors as proof of their charitable contributions.
 *      Each NFT represents a Zakat donation and includes metadata about the donation and distribution.
 *
 * @custom:security-contact security@qrbn.app
 */
contract ZakatNFT is ERC721, ERC721Enumerable, ERC721URIStorage, Governed {
    uint256 private _nextTokenId = 1;

    /// @notice Emitted when a new Zakat certificate NFT is minted
    event ZakatCertificateMinted(
        address indexed donor,
        uint256 indexed tokenId,
        string tokenURI
    );

    /**
     * @notice Initialize the ZakatNFT contract
     * @param _timelockAddress Address of the timelock contract (governance)
     * @param _tempAdminAddress Temporary admin address for initial setup
     */
    constructor(
        address _timelockAddress,
        address _tempAdminAddress
    )
        ERC721("Zakat Donation Certificate NFT", "ZAKATNFT")
        Governed(_timelockAddress, _tempAdminAddress)
    {}

    /**
     * @notice Mint a new Zakat certificate NFT
     * @param to Address to mint the NFT to (the donor)
     * @param uri Metadata URI for the NFT
     * @return tokenId The ID of the newly minted token
     * @dev Only contracts with GOVERNER_ROLE can mint NFTs
     */
    function safeMint(
        address to,
        string memory uri
    ) public onlyRole(GOVERNER_ROLE) returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        
        emit ZakatCertificateMinted(to, tokenId, uri);
        return tokenId;
    }

    /**
     * @notice Get the next token ID that will be minted
     * @return The next token ID
     */
    function getNextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    /**
     * @notice Get all token IDs owned by an address
     * @param owner The address to query
     * @return Array of token IDs owned by the address
     */
    function getTokensByOwner(address owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](tokenCount);
        
        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        
        return tokenIds;
    }

    // The following functions are overrides required by Solidity.

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}