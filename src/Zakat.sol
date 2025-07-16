// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ZakatNFT} from "./ZakatNFT.sol";

contract Zakat is AccessControl {
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");

    IERC20 public immutable usdc;
    ZakatNFT public immutable zakatNFT;

    uint256 public totalZakatReceived;
    uint256 public totalZakatDistributed;

    struct Donation {
        uint256 amount;
        bool distributed;
        bool nftMinted;
    }

    mapping(address => Donation[]) public userDonations;

    event ZakatDeposited(address indexed donor, uint256 indexed donationIndex, uint256 amount);
    event ZakatDistributed(address indexed zakatOrg, uint256 amount);
    event ZakatNFTMinted(address indexed recipient, uint256 tokenId, string uri);

    constructor(
        address _usdc,
        address _zakatNFT,
        address _admin
    ) {
        usdc = IERC20(_usdc);
        zakatNFT = ZakatNFT(_zakatNFT);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function donateZakat(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        usdc.transferFrom(msg.sender, address(this), amount);

        userDonations[msg.sender].push(Donation({
            amount: amount,
            distributed: false,
            nftMinted: false
        }));

        totalZakatReceived += amount;
        emit ZakatDeposited(msg.sender, userDonations[msg.sender].length - 1, amount);
    }

    function distributeZakat(address zakatOrg, uint256 amount) external onlyRole(DAO_ROLE) {
        require(amount > 0 && amount <= usdc.balanceOf(address(this)), "Insufficient funds");
        usdc.transfer(zakatOrg, amount);
        totalZakatDistributed += amount;
        emit ZakatDistributed(zakatOrg, amount);
    }

    function markDonationDistributed(address donor, uint256 donationIndex) external onlyRole(DAO_ROLE) {
        require(donationIndex < userDonations[donor].length, "Invalid donation index");
        Donation storage donation = userDonations[donor][donationIndex];
        require(!donation.distributed, "Already distributed");

        donation.distributed = true;
    }

    function mintZakatNFT(address donor, uint256 donationIndex, string calldata tokenUri) external onlyRole(DAO_ROLE) {
        require(donationIndex < userDonations[donor].length, "Invalid donation index");
        Donation storage donation = userDonations[donor][donationIndex];
        require(donation.distributed, "Zakat not yet distributed");
        require(!donation.nftMinted, "NFT already minted");

        donation.nftMinted = true;

        uint256 tokenId = zakatNFT.safeMint(donor, tokenUri);
        emit ZakatNFTMinted(donor, tokenId, tokenUri);
    }

    function getZakatBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
}
