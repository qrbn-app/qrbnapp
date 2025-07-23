// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Governed} from "../dao/Governed.sol";
import {Errors} from "../lib/Errors.sol";

interface IQrbnTreasury {
    function depositFees(address token, uint256 amount) external;
}

interface IQurbanNFT {
    function safeMint(address to, string memory uri) external returns (uint256);
}

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
        uint256 fee;
        uint256 vendorShare;
        uint256 timestamp;
        uint8 shareAmount;
        address buyer;
    }

    uint256 private _nextAnimalId;
    uint256 private _nextTransactionId;
    uint256 private _nextVendorId;

    uint256 public s_totalCollectedFunds;
    uint256 public s_totalCollectedFees;
    uint256 public s_vendorSharesPool;

    uint256 public s_platformFeeBps = 250; // 2.5%
    uint8 public s_maxShares = 7;
    uint256 public constant BPS_BASE = 10000;

    mapping(address => Vendor) public s_vendors;
    mapping(address => bool) public s_registeredVendors;
    mapping(uint256 => Animal) public s_animals;
    mapping(uint256 => Transaction) public s_buyerTransactions;
    mapping(address => uint256[]) public s_buyerTransactionIds;
    mapping(address => uint256[]) public s_vendorAnimalIds;
    mapping(uint256 => address[]) public s_animalBuyers;
    mapping(uint256 => mapping(address => uint256[]))
        public s_animalBuyerTransactionIds;

    IERC20 public immutable i_usdc;
    IQrbnTreasury public immutable i_treasury;
    IQurbanNFT public immutable i_qurbanNFT;

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
    event TreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );
    event PlatformFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event FeesDeposited(address indexed treasury, uint256 amount);
    event AnimalSacrificed(
        uint256 indexed animalId,
        uint256 sacrificeTimestamp
    );
    event NFTCertificatesMinted(
        uint256 indexed animalId,
        uint256 totalCertificates
    );
    event AnimalRefunded(
        uint256 indexed animalId,
        uint256 totalRefunded,
        string reason
    );
    event BuyerRefunded(
        address indexed buyer,
        uint256 animalId,
        uint256 amount,
        string reason
    );
    event VendorShareDistributed(
        address indexed vendor,
        uint256 indexed animalId,
        uint256 amount
    );

    constructor(
        address _usdcTokenAddress,
        address _treasuryAddress,
        address _timelockAddress,
        address _qurbanNFTAddress,
        address _tempAdminAddress
    ) Governed(_timelockAddress, _tempAdminAddress) {
        i_usdc = IERC20(_usdcTokenAddress);
        i_treasury = IQrbnTreasury(_treasuryAddress);
        i_qurbanNFT = IQurbanNFT(_qurbanNFTAddress);
    }

    modifier checkVendor(address _vendorAddress) {
        if (_vendorAddress == address(0))
            revert Errors.AddressZero("vendorAddress");
        if (!isVendorRegistered(_vendorAddress))
            revert Errors.NotRegistered("vendor");
        if (!s_vendors[_vendorAddress].isVerified)
            revert Errors.NotVerified("vendor");
        _;
    }

    function registerVendor(
        address _vendorAddress,
        string calldata _name,
        string calldata _contactInfo,
        string calldata _location
    ) external onlyRole(GOVERNER_ROLE) {
        if (_vendorAddress == address(0))
            revert Errors.AddressZero("vendorAddress");
        if (s_registeredVendors[_vendorAddress])
            revert Errors.AlreadyRegistered("vendor");
        if (bytes(_name).length == 0) revert Errors.EmptyString("name");

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
            revert Errors.AddressZero("vendorAddress");
        if (!s_registeredVendors[_vendorAddress])
            revert Errors.NotRegistered("vendor");
        if (bytes(_name).length == 0) revert Errors.EmptyString("name");

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
            revert Errors.NotRegistered("vendor");

        Vendor storage vendor = s_vendors[_vendorAddress];

        if (vendor.isVerified) revert Errors.AlreadyVerified("vendor");

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
            revert Errors.NotRegistered("vendor");

        Vendor storage vendor = s_vendors[_vendorAddress];

        if (!vendor.isVerified) revert Errors.AlreadyUnverified("vendor");

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
        if (bytes(_name).length == 0) revert Errors.EmptyString("name");
        if (bytes(_location).length == 0) revert Errors.EmptyString("location");
        if (bytes(_image).length == 0) revert Errors.EmptyString("image");
        if (bytes(_description).length == 0)
            revert Errors.EmptyString("description");
        if (bytes(_breed).length == 0) revert Errors.EmptyString("breed");
        if (bytes(_farmName).length == 0) revert Errors.EmptyString("farmName");
        if (_totalShares == 0 || _totalShares > s_maxShares)
            revert Errors.InvalidAmount("totalShares");
        if (_pricePerShare == 0) revert Errors.InvalidAmount("pricePerShare");
        if (_weight == 0) revert Errors.InvalidAmount("weight");
        if (_age == 0) revert Errors.InvalidAmount("age");
        if (_sacrificeDate <= block.timestamp)
            revert Errors.InvalidDate("sacrificeDate");

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
            revert Errors.Forbidden("vendorAddress");
        if (bytes(_name).length == 0) revert Errors.EmptyString("name");
        if (bytes(_location).length == 0) revert Errors.EmptyString("location");
        if (bytes(_image).length == 0) revert Errors.EmptyString("image");
        if (bytes(_description).length == 0)
            revert Errors.EmptyString("description");
        if (bytes(_breed).length == 0) revert Errors.EmptyString("breed");
        if (bytes(_farmName).length == 0) revert Errors.EmptyString("farmName");
        if (_totalShares == 0 || _totalShares > s_maxShares)
            revert Errors.InvalidAmount("totalShares");
        if (_pricePerShare == 0) revert Errors.InvalidAmount("pricePerShare");
        if (_weight == 0) revert Errors.InvalidAmount("weight");
        if (_age == 0) revert Errors.InvalidAmount("age");
        if (_sacrificeDate <= block.timestamp)
            revert Errors.InvalidDate("sacrificeDate");

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
            revert Errors.AlreadyAvailable("animal");

        animal.status = AnimalStatus.AVAILABLE;
        emit AnimalStatusUpdated(_animalId, AnimalStatus.AVAILABLE);
    }

    function unapproveAnimal(
        uint256 _animalId
    ) external onlyRole(GOVERNER_ROLE) {
        Animal storage animal = s_animals[_animalId];
        if (animal.status == AnimalStatus.PENDING)
            revert Errors.AlreadyPending("animal");
        if (animal.availableShares < animal.totalShares)
            revert Errors.AlreadyPurchased("animal");

        animal.status = AnimalStatus.PENDING;
        emit AnimalStatusUpdated(_animalId, AnimalStatus.PENDING);
    }

    function purchaseAnimalShares(
        uint256 _animalId,
        uint8 _shareAmount
    ) external {
        Animal storage animal = s_animals[_animalId];

        if (animal.status != AnimalStatus.AVAILABLE)
            revert Errors.NotAvailable("animal");
        if (_shareAmount == 0 || animal.availableShares < _shareAmount)
            revert Errors.InvalidAmount("shareAmount");

        uint256 totalPaid = _shareAmount * animal.pricePerShare;
        uint256 platformFee = (totalPaid * s_platformFeeBps) / BPS_BASE;
        uint256 vendorShare = totalPaid - platformFee;

        i_usdc.transferFrom(msg.sender, address(this), totalPaid);

        s_vendors[animal.vendorAddress].totalSales += vendorShare;
        animal.availableShares -= _shareAmount;

        if (animal.availableShares == 0) {
            animal.status = AnimalStatus.SOLD;
        }

        s_totalCollectedFunds += totalPaid;
        s_vendorSharesPool += vendorShare;

        uint256 transactionId = _nextTransactionId++;
        s_buyerTransactions[transactionId] = Transaction({
            id: transactionId,
            animalId: _animalId,
            nftCertificateId: 0,
            pricePerShare: animal.pricePerShare,
            totalPaid: totalPaid,
            fee: platformFee,
            vendorShare: vendorShare,
            timestamp: block.timestamp,
            shareAmount: _shareAmount,
            buyer: msg.sender
        });

        s_buyerTransactionIds[msg.sender].push(transactionId);

        if (s_animalBuyerTransactionIds[_animalId][msg.sender].length == 0) {
            s_animalBuyers[_animalId].push(msg.sender);
        }
        s_animalBuyerTransactionIds[_animalId][msg.sender].push(transactionId);

        emit AnimalPurchased(msg.sender, _animalId, transactionId);
    }

    function markAnimalSacrificedAndMintCertificates(
        uint256 _animalId,
        string calldata _certificateURI
    ) external onlyRole(GOVERNER_ROLE) {
        Animal storage animal = s_animals[_animalId];

        if (animal.status != AnimalStatus.SOLD)
            revert Errors.NotAvailable("animal for sacrifice");
        if (bytes(_certificateURI).length == 0)
            revert Errors.EmptyString("certificateURI");

        animal.status = AnimalStatus.SACRIFICED;

        uint256 totalVendorShare;
        uint256 totalFee;
        uint256 totalCertificates;
        address[] memory buyers = s_animalBuyers[_animalId];

        // Mint NFT certificates for all buyers
        for (uint256 i = 0; i < buyers.length; i++) {
            address buyer = buyers[i];
            uint256[] memory transactionIds = s_animalBuyerTransactionIds[
                _animalId
            ][buyer];

            for (uint256 j = 0; j < transactionIds.length; j++) {
                uint256 txnId = transactionIds[j];
                Transaction storage txn = s_buyerTransactions[txnId];

                if (txn.nftCertificateId == 0) {
                    string memory uniqueURI = string(
                        abi.encodePacked(
                            _certificateURI,
                            "/",
                            _animalId,
                            "/",
                            txnId
                        )
                    );

                    uint256 nftCertificateId = i_qurbanNFT.safeMint(
                        buyer,
                        uniqueURI
                    );
                    txn.nftCertificateId = nftCertificateId;
                    totalCertificates++;
                    totalFee += txn.fee;
                    totalVendorShare += txn.vendorShare;
                }
            }
        }

        if (totalFee > 0) {
            if (i_usdc.balanceOf(address(this)) < totalFee)
                revert Errors.InsufficientBalance(
                    address(i_usdc),
                    i_usdc.balanceOf(address(this)),
                    totalFee
                );

            i_usdc.approve(address(i_treasury), totalFee);
            i_treasury.depositFees(address(i_usdc), totalFee);
            s_totalCollectedFees += totalFee;
            emit FeesDeposited(address(i_treasury), totalFee);
        }

        if (totalVendorShare > 0) {
            if (s_vendorSharesPool < totalVendorShare)
                revert Errors.InsufficientBalance(
                    address(i_usdc),
                    s_vendorSharesPool,
                    totalVendorShare
                );
            if (i_usdc.balanceOf(address(this)) < totalVendorShare)
                revert Errors.InsufficientBalance(
                    address(i_usdc),
                    i_usdc.balanceOf(address(this)),
                    totalVendorShare
                );

            i_usdc.transfer(animal.vendorAddress, totalVendorShare);
            s_vendorSharesPool -= totalVendorShare;
            emit VendorShareDistributed(
                animal.vendorAddress,
                _animalId,
                totalVendorShare
            );
        }

        emit AnimalSacrificed(_animalId, block.timestamp);
        emit NFTCertificatesMinted(_animalId, totalCertificates);
    }

    function refundAnimalPurchases(
        uint256 _animalId,
        string calldata _reason
    ) external onlyRole(GOVERNER_ROLE) {
        Animal storage animal = s_animals[_animalId];

        if (animal.status != AnimalStatus.SOLD)
            revert Errors.NotAvailable("animal for refund");
        if (bytes(_reason).length == 0) revert Errors.EmptyString("reason");

        address[] memory buyers = s_animalBuyers[_animalId];
        uint256 totalRefunded;

        for (uint256 i = 0; i < buyers.length; i++) {
            address buyer = buyers[i];
            uint256[] memory transactionIds = s_animalBuyerTransactionIds[
                _animalId
            ][buyer];
            uint256 buyerRefundAmount;
            uint256 vendorShareToDeduct;

            for (uint256 j = 0; j < transactionIds.length; j++) {
                uint256 txnId = transactionIds[j];
                Transaction storage txn = s_buyerTransactions[txnId];

                if (txn.animalId == _animalId && txn.nftCertificateId == 0) {
                    buyerRefundAmount += txn.totalPaid;
                    vendorShareToDeduct += txn.vendorShare;

                    // Mark transaction as refunded by setting a special nftCertificateId
                    txn.nftCertificateId = type(uint256).max; // Use max uint256 to indicate refund
                }
            }

            if (buyerRefundAmount > 0) {
                s_vendors[animal.vendorAddress]
                    .totalSales -= vendorShareToDeduct;

                s_totalCollectedFunds -= buyerRefundAmount;
                s_vendorSharesPool -= vendorShareToDeduct;

                i_usdc.transfer(buyer, buyerRefundAmount);
                totalRefunded += buyerRefundAmount;

                emit BuyerRefunded(
                    buyer,
                    _animalId,
                    buyerRefundAmount,
                    _reason
                );
            }
        }

        animal.status = AnimalStatus.PENDING;
        animal.availableShares = animal.totalShares;

        emit AnimalRefunded(_animalId, totalRefunded, _reason);
    }

    function setPlatformFee(
        uint256 _newFeeBps
    ) external onlyRole(GOVERNER_ROLE) {
        if (_newFeeBps > 1000) {
            // Maximum 10% fee
            revert Errors.InvalidAmount("platformFee");
        }

        uint256 oldFeeBps = s_platformFeeBps;
        s_platformFeeBps = _newFeeBps;
        emit PlatformFeeUpdated(oldFeeBps, _newFeeBps);
    }

    function getAnimalsByStatus(
        AnimalStatus _status
    ) external view returns (uint256[] memory) {
        uint256 statusCount = 0;
        for (uint256 i = 0; i < _nextAnimalId; i++) {
            if (s_animals[i].status == _status) {
                statusCount++;
            }
        }

        uint256[] memory animals = new uint256[](statusCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < _nextAnimalId; i++) {
            if (s_animals[i].status == _status) {
                animals[currentIndex] = i;
                currentIndex++;
            }
        }

        return animals;
    }

    function getVendorAnimalsByStatus(
        address _vendorAddress,
        AnimalStatus _status
    ) external view returns (uint256[] memory) {
        uint256[] memory vendorAnimals = s_vendorAnimalIds[_vendorAddress];

        uint256 statusCount = 0;
        for (uint256 i = 0; i < vendorAnimals.length; i++) {
            if (s_animals[vendorAnimals[i]].status == _status) {
                statusCount++;
            }
        }

        uint256[] memory filteredAnimals = new uint256[](statusCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < vendorAnimals.length; i++) {
            uint256 animalId = vendorAnimals[i];
            if (s_animals[animalId].status == _status) {
                filteredAnimals[currentIndex] = animalId;
                currentIndex++;
            }
        }

        return filteredAnimals;
    }

    function getTotalAnimalsCount() external view returns (uint256) {
        return _nextAnimalId;
    }

    function getVendorAnimals(
        address _vendorAddress
    ) external view returns (uint256[] memory) {
        return s_vendorAnimalIds[_vendorAddress];
    }

    function getAnimalById(
        uint256 _animalId
    ) external view returns (Animal memory) {
        return s_animals[_animalId];
    }

    function getAnimalBuyers(
        uint256 _animalId
    ) external view returns (address[] memory) {
        return s_animalBuyers[_animalId];
    }

    function getAnimalBuyerTransactionsIds(
        uint256 _animalId,
        address _buyer
    ) external view returns (uint256[] memory) {
        return s_animalBuyerTransactionIds[_animalId][_buyer];
    }

    function getBuyerTransactionIds(
        address _buyer
    ) external view returns (uint256[] memory) {
        return s_buyerTransactionIds[_buyer];
    }

    function isVendorRegistered(
        address _vendorAddress
    ) public view returns (bool) {
        return s_registeredVendors[_vendorAddress];
    }
}
