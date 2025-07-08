// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./QurbanNFT.sol";

contract Qurban {
    struct Animal {
        string name;
        uint256 age;
        uint256 price;
        bool available;
        string animalType; // "goat", "cow", "sheep", etc.
    }

    QurbanNFT public qurbanNFT;
    Animal[] public animals;

    mapping(address => uint256[]) public userPurchases; // user => animal IDs
    mapping(uint256 => address) public animalOwners; // animal ID => owner

    event AnimalPurchased(
        address indexed buyer,
        uint256 indexed animalId,
        uint256 nftTokenId,
        string animalName
    );

    constructor(address _qurbanNFTAddress) {
        qurbanNFT = QurbanNFT(_qurbanNFTAddress);
    }

    function addAnimal(
        string memory _name,
        uint256 _age,
        uint256 _price,
        string memory _animalType
    ) public {
        animals.push(
            Animal({
                name: _name,
                age: _age,
                price: _price,
                available: true,
                animalType: _animalType
            })
        );
    }

    function purchaseAnimal(uint256 _animalId) public payable {
        require(_animalId < animals.length, "Animal does not exist");
        require(animals[_animalId].available, "Animal not available");
        require(msg.value >= animals[_animalId].price, "Insufficient payment");

        // Mark animal as sold
        animals[_animalId].available = false;
        animalOwners[_animalId] = msg.sender;
        userPurchases[msg.sender].push(_animalId);

        // Mint NFT for the buyer
        qurbanNFT.mint(msg.sender);

        // Get the token ID that was just minted (assuming sequential minting)
        uint256 nftTokenId = qurbanNFT.totalSupply() - 1;

        emit AnimalPurchased(
            msg.sender,
            _animalId,
            nftTokenId,
            animals[_animalId].name
        );

        // Refund excess payment
        if (msg.value > animals[_animalId].price) {
            payable(msg.sender).transfer(msg.value - animals[_animalId].price);
        }
    }

    function getUserPurchases(
        address _user
    ) public view returns (uint256[] memory) {
        return userPurchases[_user];
    }

    function getAvailableAnimals() public view returns (uint256[] memory) {
        uint256 availableCount = 0;

        // Count available animals
        for (uint256 i = 0; i < animals.length; i++) {
            if (animals[i].available) {
                availableCount++;
            }
        }

        // Create array of available animal IDs
        uint256[] memory availableIds = new uint256[](availableCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < animals.length; i++) {
            if (animals[i].available) {
                availableIds[currentIndex] = i;
                currentIndex++;
            }
        }

        return availableIds;
    }
}
