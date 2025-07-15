// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {QurbanNFT} from "./QurbanNFT.sol";

contract Qurban is AccessControl {
    error AlreadyRegistered(string entity);
    error NotRegistered(string entity);
    error EmptyString(string field);
    error AlreadyVerified(string entity);
    error AlreadyUnverified(string entity);
    error InvalidAmount(string field);
    error InvalidDate(string field);
    error NotAvailable(string entity);
    error AlreadyAvailable(string entity);
    error AlreadyPending(string entity);
    error AlreadyPurchased(string entity);

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
        address vendor;
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

    uint256 private constant PLATFORM_FEE_BPS = 250; // 2.5%
    uint8 private constant MAX_SHARES = 20;
    uint256 public constant BPS_BASE = 10000;

    uint256 private _nextAnimalId;
    uint256 private _nextTransactionId;
    uint256 private _nextVendorId;

    mapping(address => Vendor) public s_vendors;
    mapping(address => bool) public s_registeredVendors;
    mapping(uint256 => Animal) public s_animals;
    mapping(uint256 => Transaction) public s_buyerTransactions;
    mapping(address => uint256[]) public s_buyerTransactionIds;
    mapping(address => uint256[]) public s_vendorAnimalIds;

    IERC20 public immutable i_usdc;
    QurbanNFT public immutable i_qurbanNFT;

    bytes32 public constant VENDOR_ROLE = keccak256("VENDOR");

    event VendorRegistered(
        address indexed vendorAddress,
        uint256 indexed vendorId,
        string vendorName
    );
    event VendorVerified(
        address indexed vendorAddress,
        uint256 indexed vendorId,
        string vendorName
    );
    event VendorUnverified(
        address indexed vendorAddress,
        uint256 indexed vendorId,
        string vendorName
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
        address _qurbanNFTAddress,
        address _defaultAdminAddress
    ) {
        i_usdc = IERC20(_usdcTokenAddress);
        i_qurbanNFT = QurbanNFT(_qurbanNFTAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdminAddress);
    }

    function registerVendor(
        string calldata _name,
        string calldata _contactInfo,
        string calldata _location
    ) external {
        if (s_registeredVendors[msg.sender]) revert AlreadyRegistered("vendor");
        if (bytes(_name).length == 0) revert EmptyString("name");

        uint256 vendorId = _nextVendorId++;

        s_vendors[msg.sender] = Vendor({
            id: vendorId,
            walletAddress: msg.sender,
            name: _name,
            contactInfo: _contactInfo,
            location: _location,
            isVerified: false,
            totalSales: 0,
            registeredAt: block.timestamp
        });

        s_registeredVendors[msg.sender] = true;

        emit VendorRegistered(msg.sender, vendorId, _name);
    }

    function verifyVendor(
        address _vendorAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!s_registeredVendors[_vendorAddress])
            revert NotRegistered("vendor");

        Vendor storage vendor = s_vendors[_vendorAddress];

        if (vendor.isVerified) revert AlreadyVerified("vendor");

        vendor.isVerified = true;
        _grantRole(VENDOR_ROLE, vendor.walletAddress);

        emit VendorVerified(vendor.walletAddress, vendor.id, vendor.name);
    }

    function unverifyVendor(
        address _vendorAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!s_registeredVendors[_vendorAddress])
            revert NotRegistered("vendor");

        Vendor storage vendor = s_vendors[_vendorAddress];

        if (!vendor.isVerified) revert AlreadyUnverified("vendor");

        vendor.isVerified = false;
        _revokeRole(VENDOR_ROLE, vendor.walletAddress);

        emit VendorUnverified(vendor.walletAddress, vendor.id, vendor.name);
    }

    function addAnimal(
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
    ) external onlyRole(VENDOR_ROLE) {
        if (bytes(_name).length == 0) revert EmptyString("name");
        if (bytes(_location).length == 0) revert EmptyString("location");
        if (bytes(_image).length == 0) revert EmptyString("image");
        if (bytes(_description).length == 0) revert EmptyString("description");
        if (bytes(_breed).length == 0) revert EmptyString("breed");
        if (bytes(_farmName).length == 0) revert EmptyString("farmName");
        if (_totalShares == 0 || _totalShares > MAX_SHARES)
            revert InvalidAmount("totalShares");
        if (_pricePerShare == 0) revert InvalidAmount("pricePerShare");
        if (_weight == 0) revert InvalidAmount("weight");
        if (_age == 0) revert InvalidAmount("age");
        if (_sacrificeDate <= block.timestamp)
            revert InvalidDate("sacrificeDate");

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
            status: AnimalStatus.PENDING,
            vendor: msg.sender,
            createdAt: block.timestamp
        });

        s_vendorAnimalIds[msg.sender].push(animalId);

        emit AnimalAdded(animalId, msg.sender, _name);
    }

    function editAnimal(
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
    ) external onlyRole(VENDOR_ROLE) {
        if (bytes(_name).length == 0) revert EmptyString("name");
        if (bytes(_location).length == 0) revert EmptyString("location");
        if (bytes(_image).length == 0) revert EmptyString("image");
        if (bytes(_description).length == 0) revert EmptyString("description");
        if (bytes(_breed).length == 0) revert EmptyString("breed");
        if (bytes(_farmName).length == 0) revert EmptyString("farmName");
        if (_totalShares == 0 || _totalShares > MAX_SHARES)
            revert InvalidAmount("totalShares");
        if (_pricePerShare == 0) revert InvalidAmount("pricePerShare");
        if (_weight == 0) revert InvalidAmount("weight");
        if (_age == 0) revert InvalidAmount("age");
        if (_sacrificeDate <= block.timestamp)
            revert InvalidDate("sacrificeDate");

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

    function approveAnimal(
        uint256 _animalId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Animal storage animal = s_animals[_animalId];
        if (animal.status == AnimalStatus.AVAILABLE)
            revert AlreadyAvailable("animal");

        animal.status = AnimalStatus.AVAILABLE;
        emit AnimalStatusUpdated(_animalId, AnimalStatus.AVAILABLE);
    }

    function unapproveAnimal(
        uint256 _animalId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Animal storage animal = s_animals[_animalId];
        if (animal.status == AnimalStatus.PENDING)
            revert AlreadyPending("animal");
        if (animal.availableShares < animal.totalShares)
            revert AlreadyPurchased("animal");

        animal.status = AnimalStatus.PENDING;
        emit AnimalStatusUpdated(_animalId, AnimalStatus.PENDING);
    }

    function purchaseAnimalShares(
        uint256 _animalId,
        uint8 _shareAmount
    ) external {
        Animal storage animal = s_animals[_animalId];

        if (animal.status != AnimalStatus.AVAILABLE)
            revert NotAvailable("animal");
        if (_shareAmount == 0 || animal.availableShares < _shareAmount)
            revert InvalidAmount("shareAmount");

        uint256 totalPaid = _shareAmount * animal.pricePerShare;
        uint256 platformFee = (totalPaid * PLATFORM_FEE_BPS) / BPS_BASE;
        uint256 vendorShare = totalPaid - platformFee;

        i_usdc.transferFrom(msg.sender, address(this), totalPaid);

        s_vendors[animal.vendor].totalSales += vendorShare;
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
