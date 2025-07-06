// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract SingleAnimal {
    struct Animal {
        string name;
        uint256 age;
    }

    Animal public animal;

    function setAnimal(string memory _name, uint256 _age) public {
        animal = Animal(_name, _age);
    }

    function getAnimal() public view returns (string memory, uint256) {
        return (animal.name, animal.age);
    }
}