// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract AnimalPool {
    struct Animal {
        string name;
        uint256 age;
    }

    Animal[] public animals;

    function addAnimal(string memory _name, uint256 _age) public {
        animals.push(Animal(_name, _age));
    }

    function getAnimal(uint256 _index) public view returns (string memory, uint256) {
        require(_index < animals.length, "Animal does not exist");
        Animal storage animal = animals[_index];
        return (animal.name, animal.age);
    }

    function getTotalAnimals() public view returns (uint256) {
        return animals.length;
    }
}