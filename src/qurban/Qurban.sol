// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Governed} from "../dao/Governed.sol";
import {QurbanErrors} from "./QurbanErrors.sol";

contract Qurban is Governed {
    enum AnimalType {
        SHEEP,
        COW,
        GOAT,
        CAMEL
    }
    enum AnimalStatus {
        PENDING,
        AVAILABLE,
        SOLD,
        SACRIFICED
    }

    struct Animal {
        uint256 id;
        string name;
        AnimalType animalType;
        uint8 totalShares;
        uint8 availableShares;
        uint256 pricePerShare;
        string location;
        string image;
        string description;
        string breed;
        uint16 weight;
        uint16 age;
        string farmName;
        uint256 sacrificeDate;
        AnimalStatus status;
        address vendorAddress;
        uint256 createdAt;
    }

    struct Vendor {
        uint256 id;
        address walletAddress;
        string name;
        string contactInfo;
        string location;
        bool isVerified;
        uint256 totalSales;
        uint256 registeredAt;
    }

    struct Transaction {
        uint256 id;
        uint256 animalId;
        uint256 nftCertificateId;
        uint256 pricePerShare;
        uint256 totalPaid;
        uint256 timestamp;
        uint8 shareAmount;
        address buyer;
    }

    uint256 private _nextAnimalId;
    uint256 private _nextTransactionId;
    uint256 private _nextVendorId;

    uint256 public s_platformFeeBps = 250; // 2.5%
    uint8 public s_maxShares = 7;
    uint256 public constant BPS_BASE = 10000;

    mapping(address => Vendor) public s_vendors;
    mapping(address => bool) public s_registeredVendors;
    mapping(uint256 => Animal) public s_animals;
    mapping(uint256 => Transaction) public s_buyerTransactions;
    mapping(address => uint256[]) public s_buyerTransactionIds;
    mapping(address => uint256[]) public s_vendorAnimalIds;

    IERC20 public immutable i_usdc;

    event VendorRegistered(
        address indexed vendorAddress,
        uint256 indexed vendorId,
        string vendorName
    );
    event VendorEdited(
        address indexed vendorAddress,
        uint256 indexed vendorId,
        string vendorName
    );
    event VendorVerifyUpdated(
        address indexed vendorAddress,
        uint256 indexed vendorId,
        bool isVerified
    );
    event AnimalAdded(
        uint256 indexed animalId,
        address vendorAddress,
        string animalName
    );
    event AnimalUpdated(
        uint256 indexed animalId,
        address vendorAddress,
        string animalName
    );
    event AnimalStatusUpdated(
        uint256 indexed animalId,
        AnimalStatus animalStatus
    );
    event AnimalPurchased(
        address indexed buyer,
        uint256 animalId,
        uint256 transactionId
    );

    constructor(
        address _usdcTokenAddress,
        address _timelockAddress,
        address _tempAdminAddress
    ) Governed(_timelockAddress, _tempAdminAddress) {
        i_usdc = IERC20(_usdcTokenAddress);
    }

    modifier checkVendor(address _vendorAddress) {
        if (_vendorAddress == address(0))
            revert QurbanErrors.AddressZero("vendorAddress");
        if (!s_registeredVendors[_vendorAddress])
            revert QurbanErrors.NotRegistered("vendor");
        if (!s_vendors[_vendorAddress].isVerified)
            revert QurbanErrors.NotVerified("vendor");
        _;
    }

    function registerVendor(
        address _vendorAddress,
        string calldata _name,
        string calldata _contactInfo,
        string calldata _location
    ) external onlyRole(GOVERNER_ROLE) {
        if (_vendorAddress == address(0))
            revert QurbanErrors.AddressZero("vendorAddress");
        if (s_registeredVendors[_vendorAddress])
            revert QurbanErrors.AlreadyRegistered("vendor");
        if (bytes(_name).length == 0) revert QurbanErrors.EmptyString("name");

        uint256 vendorId = _nextVendorId++;

        s_vendors[_vendorAddress] = Vendor({
            id: vendorId,
            walletAddress: _vendorAddress,
            name: _name,
            contactInfo: _contactInfo,
            location: _location,
            isVerified: true,
            totalSales: 0,
            registeredAt: block.timestamp
        });

        s_registeredVendors[_vendorAddress] = true;

        emit VendorRegistered(_vendorAddress, vendorId, _name);
    }

    function editVendor(
        address _vendorAddress,
        string calldata _name,
        string calldata _contactInfo,
        string calldata _location
    ) external onlyRole(GOVERNER_ROLE) {
        if (_vendorAddress == address(0))
            revert QurbanErrors.AddressZero("vendorAddress");
        if (!s_registeredVendors[_vendorAddress])
            revert QurbanErrors.NotRegistered("vendor");
        if (bytes(_name).length == 0) revert QurbanErrors.EmptyString("name");

        Vendor storage vendor = s_vendors[_vendorAddress];

        vendor.name = _name;
        vendor.contactInfo = _contactInfo;
        vendor.location = _location;

        emit VendorEdited(_vendorAddress, vendor.id, _name);
    }

    function verifyVendor(
        address _vendorAddress
    ) external onlyRole(GOVERNER_ROLE) {
        if (!s_registeredVendors[_vendorAddress])
            revert QurbanErrors.NotRegistered("vendor");

        Vendor storage vendor = s_vendors[_vendorAddress];

        if (vendor.isVerified) revert QurbanErrors.AlreadyVerified("vendor");

        vendor.isVerified = true;

        emit VendorVerifyUpdated(
            vendor.walletAddress,
            vendor.id,
            vendor.isVerified
        );
    }

    function unverifyVendor(
        address _vendorAddress
    ) external onlyRole(GOVERNER_ROLE) {
        if (!s_registeredVendors[_vendorAddress])
            revert QurbanErrors.NotRegistered("vendor");

        Vendor storage vendor = s_vendors[_vendorAddress];

        if (!vendor.isVerified) revert QurbanErrors.AlreadyUnverified("vendor");

        vendor.isVerified = false;

        emit VendorVerifyUpdated(
            vendor.walletAddress,
            vendor.id,
            vendor.isVerified
        );
    }

    function addAnimal(
        address _vendorAddress,
        string calldata _name,
        AnimalType _animalType,
        uint8 _totalShares,
        uint256 _pricePerShare,
        string calldata _location,
        string calldata _image,
        string calldata _description,
        string calldata _breed,
        uint16 _weight,
        uint16 _age,
        string calldata _farmName,
        uint256 _sacrificeDate
    ) external onlyRole(GOVERNER_ROLE) checkVendor(_vendorAddress) {
        if (bytes(_name).length == 0) revert QurbanErrors.EmptyString("name");
        if (bytes(_location).length == 0)
            revert QurbanErrors.EmptyString("location");
        if (bytes(_image).length == 0) revert QurbanErrors.EmptyString("image");
        if (bytes(_description).length == 0)
            revert QurbanErrors.EmptyString("description");
        if (bytes(_breed).length == 0) revert QurbanErrors.EmptyString("breed");
        if (bytes(_farmName).length == 0)
            revert QurbanErrors.EmptyString("farmName");
        if (_totalShares == 0 || _totalShares > s_maxShares)
            revert QurbanErrors.InvalidAmount("totalShares");
        if (_pricePerShare == 0)
            revert QurbanErrors.InvalidAmount("pricePerShare");
        if (_weight == 0) revert QurbanErrors.InvalidAmount("weight");
        if (_age == 0) revert QurbanErrors.InvalidAmount("age");
        if (_sacrificeDate <= block.timestamp)
            revert QurbanErrors.InvalidDate("sacrificeDate");

        uint256 animalId = _nextAnimalId++;

        s_animals[animalId] = Animal({
            id: animalId,
            name: _name,
            animalType: _animalType,
            totalShares: _totalShares,
            availableShares: _totalShares,
            pricePerShare: _pricePerShare,
            location: _location,
            image: _image,
            description: _description,
            breed: _breed,
            weight: _weight,
            age: _age,
            farmName: _farmName,
            sacrificeDate: _sacrificeDate,
            status: AnimalStatus.AVAILABLE,
            vendorAddress: _vendorAddress,
            createdAt: block.timestamp
        });

        s_vendorAnimalIds[_vendorAddress].push(animalId);

        emit AnimalAdded(animalId, _vendorAddress, _name);
    }

    function editAnimal(
        address _vendorAddress,
        uint256 _animalId,
        string calldata _name,
        AnimalType _animalType,
        uint8 _totalShares,
        uint256 _pricePerShare,
        string calldata _location,
        string calldata _image,
        string calldata _description,
        string calldata _breed,
        uint16 _weight,
        uint16 _age,
        string calldata _farmName,
        uint256 _sacrificeDate
    ) external onlyRole(GOVERNER_ROLE) checkVendor(_vendorAddress) {
        if (s_animals[_animalId].vendorAddress != _vendorAddress)
            revert QurbanErrors.Forbidden("vendorAddress");
        if (bytes(_name).length == 0) revert QurbanErrors.EmptyString("name");
        if (bytes(_location).length == 0)
            revert QurbanErrors.EmptyString("location");
        if (bytes(_image).length == 0) revert QurbanErrors.EmptyString("image");
        if (bytes(_description).length == 0)
            revert QurbanErrors.EmptyString("description");
        if (bytes(_breed).length == 0) revert QurbanErrors.EmptyString("breed");
        if (bytes(_farmName).length == 0)
            revert QurbanErrors.EmptyString("farmName");
        if (_totalShares == 0 || _totalShares > s_maxShares)
            revert QurbanErrors.InvalidAmount("totalShares");
        if (_pricePerShare == 0)
            revert QurbanErrors.InvalidAmount("pricePerShare");
        if (_weight == 0) revert QurbanErrors.InvalidAmount("weight");
        if (_age == 0) revert QurbanErrors.InvalidAmount("age");
        if (_sacrificeDate <= block.timestamp)
            revert QurbanErrors.InvalidDate("sacrificeDate");

        Animal storage animal = s_animals[_animalId];

        animal.name = _name;
        animal.animalType = _animalType;
        animal.totalShares = _totalShares;
        animal.availableShares = _totalShares;
        animal.pricePerShare = _pricePerShare;
        animal.location = _location;
        animal.image = _image;
        animal.description = _description;
        animal.breed = _breed;
        animal.weight = _weight;
        animal.age = _age;
        animal.farmName = _farmName;
        animal.sacrificeDate = _sacrificeDate;

        emit AnimalUpdated(_animalId, msg.sender, _name);
    }

    function approveAnimal(uint256 _animalId) external onlyRole(GOVERNER_ROLE) {
        Animal storage animal = s_animals[_animalId];
        if (animal.status == AnimalStatus.AVAILABLE)
            revert QurbanErrors.AlreadyAvailable("animal");

        animal.status = AnimalStatus.AVAILABLE;
        emit AnimalStatusUpdated(_animalId, AnimalStatus.AVAILABLE);
    }

    function unapproveAnimal(
        uint256 _animalId
    ) external onlyRole(GOVERNER_ROLE) {
        Animal storage animal = s_animals[_animalId];
        if (animal.status == AnimalStatus.PENDING)
            revert QurbanErrors.AlreadyPending("animal");
        if (animal.availableShares < animal.totalShares)
            revert QurbanErrors.AlreadyPurchased("animal");

        animal.status = AnimalStatus.PENDING;
        emit AnimalStatusUpdated(_animalId, AnimalStatus.PENDING);
    }

    function purchaseAnimalShares(
        uint256 _animalId,
        uint8 _shareAmount
    ) external {
        Animal storage animal = s_animals[_animalId];

        if (animal.status != AnimalStatus.AVAILABLE)
            revert QurbanErrors.NotAvailable("animal");
        if (_shareAmount == 0 || animal.availableShares < _shareAmount)
            revert QurbanErrors.InvalidAmount("shareAmount");

        uint256 totalPaid = _shareAmount * animal.pricePerShare;
        uint256 platformFee = (totalPaid * s_platformFeeBps) / BPS_BASE;
        uint256 vendorShare = totalPaid - platformFee;

        i_usdc.transferFrom(msg.sender, address(this), totalPaid);

        s_vendors[animal.vendorAddress].totalSales += vendorShare;
        animal.availableShares -= _shareAmount;

        if (animal.availableShares == 0) {
            animal.status = AnimalStatus.SOLD;
        }

        uint256 transactionId = _nextTransactionId++;
        s_buyerTransactions[transactionId] = Transaction({
            id: transactionId,
            animalId: _animalId,
            nftCertificateId: 0,
            pricePerShare: animal.pricePerShare,
            totalPaid: totalPaid,
            timestamp: block.timestamp,
            shareAmount: _shareAmount,
            buyer: msg.sender
        });

        s_buyerTransactionIds[msg.sender].push(transactionId);

        emit AnimalPurchased(msg.sender, _animalId, transactionId);
    }
}
