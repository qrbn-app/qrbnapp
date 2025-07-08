// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract QurbanNFT is ERC721, Ownable {
    uint256 private _tokenIdCounter;
    mapping(uint256 => string) public tokenMetadata;

    event NFTMinted(address indexed to, uint256 indexed tokenId);

    constructor() ERC721("QurbanNFT", "QRB") Ownable(msg.sender) {}

    function mint(address to) public onlyOwner {
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        _safeMint(to, tokenId);
        // tokenMetadata[tokenId] = metadata;

        emit NFTMinted(to, tokenId);
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter;
    }

    function getTokenMetadata(
        uint256 tokenId
    ) public view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return tokenMetadata[tokenId];
    }
}
