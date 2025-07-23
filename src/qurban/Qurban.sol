// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Governed} from "../dao/Governed.sol";
import {Errors} from "../lib/Errors.sol";

/**
 * @title IQrbnTreasury
 * @notice Interface for the QRBN Treasury contract
 * @dev Used to deposit platform fees collected from animal purchases
 */
interface IQrbnTreasury {
    function depositFees(address token, uint256 amount) external;
}

/**
 * @title IQurbanNFT
 * @notice Interface for the Qurban NFT contract
 * @dev Used to mint sacrifice certificates as NFTs for buyers
 */
interface IQurbanNFT {
    function safeMint(address to, string memory uri) external returns (uint256);
}

/**
 * @title Qurban
 * @author QRBN Team
 * @notice Main contract for the Qurban (animal sacrifice) platform
 * @dev This contract manages:
 *      - Vendor registration and verification
 *      - Animal listing and management
 *      - Share-based animal purchases
 *      - Fee collection and distribution
 *      - NFT certificate minting upon sacrifice
 *      - Purchase refunds when needed
 *
 * @custom:security-contact security@qrbn.app
 */
contract Qurban is Governed {
    // ============ ENUMS ============

    /**
     * @notice Types of animals available for sacrifice
     * @dev Used to categorize animals in the platform
     */
    enum AnimalType {
        SHEEP,
        COW,
        GOAT,
        CAMEL
    }

    /**
     * @notice Status of animals in the platform lifecycle
     * @dev Controls the availability and state of animals
     */
    enum AnimalStatus {
        PENDING,
        AVAILABLE,
        SOLD,
        SACRIFICED
    }

    // ============ STRUCTS ============

    /**
     * @notice Complete information about an animal
     * @dev Stores all metadata and state for animals in the platform
     */
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

    /**
     * @notice Information about registered vendors
     * @dev Stores vendor profile and verification status
     */
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

    /**
     * @notice Transaction record for animal share purchases
     * @dev Stores complete purchase information for accounting and NFT minting
     */
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

    // ============ STATE VARIABLES ============

    // ID Counters (private to prevent direct access)
    uint256 private _nextAnimalId; // Next animal ID to be assigned
    uint256 private _nextTransactionId; // Next transaction ID to be assigned
    uint256 private _nextVendorId; // Next vendor ID to be assigned

    // Financial Tracking (public for transparency)
    uint256 public s_totalCollectedFunds; // Total USDC collected from all purchases
    uint256 public s_totalCollectedFees; // Total platform fees collected
    uint256 public s_vendorSharesPool; // Total vendor shares pending distribution

    // Platform Configuration (public for transparency)
    uint256 public s_platformFeeBps = 250; // Platform fee in basis points (2.5%)
    uint8 public s_maxShares = 7; // Maximum shares allowed per animal
    uint256 public constant BPS_BASE = 10000; // Basis points denominator (100%)

    // Core Data Storage
    mapping(address => Vendor) public s_vendors; // Vendor info by address
    mapping(address => bool) public s_registeredVendors; // Quick vendor registration check
    mapping(uint256 => Animal) public s_animals; // Animal info by ID
    mapping(uint256 => Transaction) public s_buyerTransactions; // Transaction info by ID

    // Relationship Mappings for efficient queries
    mapping(address => uint256[]) public s_buyerTransactionIds; // Buyer → Transaction IDs
    mapping(address => uint256[]) public s_vendorAnimalIds; // Vendor → Animal IDs
    mapping(uint256 => address[]) public s_animalBuyers; // Animal ID → Buyer addresses
    mapping(uint256 => mapping(address => uint256[]))
        public s_animalBuyerTransactionIds; // Animal ID → Buyer → Transaction IDs

    // External Contract References (immutable for security)
    IERC20 public immutable i_usdc; // USDC token contract
    IQrbnTreasury public immutable i_treasury; // Treasury contract for fee management
    IQurbanNFT public immutable i_qurbanNFT; // NFT contract for certificates

    // ============ EVENTS ============

    /// @notice Emitted when a new vendor is registered
    event VendorRegistered(
        address indexed vendorAddress,
        uint256 indexed vendorId,
        string vendorName
    );

    /// @notice Emitted when vendor information is updated
    event VendorEdited(
        address indexed vendorAddress,
        uint256 indexed vendorId,
        string vendorName
    );

    /// @notice Emitted when vendor verification status changes
    event VendorVerifyUpdated(
        address indexed vendorAddress,
        uint256 indexed vendorId,
        bool isVerified
    );

    /// @notice Emitted when a new animal is added to the platform
    event AnimalAdded(
        uint256 indexed animalId,
        address vendorAddress,
        string animalName
    );

    /// @notice Emitted when animal information is updated
    event AnimalUpdated(
        uint256 indexed animalId,
        address vendorAddress,
        string animalName
    );

    /// @notice Emitted when animal status changes
    event AnimalStatusUpdated(
        uint256 indexed animalId,
        AnimalStatus animalStatus
    );

    /// @notice Emitted when animal shares are purchased
    event AnimalPurchased(
        address indexed buyer,
        uint256 animalId,
        uint256 transactionId
    );

    /// @notice Emitted when treasury address is updated
    event TreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );

    /// @notice Emitted when platform fee is updated
    event PlatformFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);

    /// @notice Emitted when fees are deposited to treasury
    event FeesDeposited(address indexed treasury, uint256 amount);

    /// @notice Emitted when an animal is marked as sacrificed
    event AnimalSacrificed(
        uint256 indexed animalId,
        uint256 sacrificeTimestamp
    );

    /// @notice Emitted when NFT certificates are minted for buyers
    event NFTCertificatesMinted(
        uint256 indexed animalId,
        uint256 totalCertificates
    );

    /// @notice Emitted when animal purchases are refunded
    event AnimalRefunded(
        uint256 indexed animalId,
        uint256 totalRefunded,
        string reason
    );

    /// @notice Emitted when individual buyer is refunded
    event BuyerRefunded(
        address indexed buyer,
        uint256 animalId,
        uint256 amount,
        string reason
    );

    /// @notice Emitted when vendor receives their share after sacrifice
    event VendorShareDistributed(
        address indexed vendor,
        uint256 indexed animalId,
        uint256 amount
    );

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initialize the Qurban contract
     * @param _usdcTokenAddress Address of the USDC token contract
     * @param _treasuryAddress Address of the treasury contract
     * @param _timelockAddress Address of the timelock contract (governance)
     * @param _qurbanNFTAddress Address of the QurbanNFT contract
     * @param _tempAdminAddress Temporary admin address for initial setup
     */
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

    // ============ MODIFIERS ============

    /**
     * @notice Ensures vendor is registered, verified, and valid
     * @param _vendorAddress Address of the vendor to check
     * @dev Used to validate vendor operations
     */
    modifier checkVendor(address _vendorAddress) {
        if (_vendorAddress == address(0))
            revert Errors.AddressZero("vendorAddress");
        if (!isVendorRegistered(_vendorAddress))
            revert Errors.NotRegistered("vendor");
        if (!s_vendors[_vendorAddress].isVerified)
            revert Errors.NotVerified("vendor");
        _;
    }

    // ============ VENDOR MANAGEMENT FUNCTIONS ============

    /**
     * @notice Register a new vendor on the platform
     * @param _vendorAddress Wallet address of the vendor
     * @param _name Display name of the vendor
     * @param _contactInfo Contact information (phone, email, etc.)
     * @param _location Physical location of the vendor
     * @dev Only governance can register vendors. Vendors are automatically verified upon registration.
     * @custom:access-control Only GOVERNER_ROLE can call this function
     */
    function registerVendor(
        address _vendorAddress,
        string calldata _name,
        string calldata _contactInfo,
        string calldata _location
    ) external onlyRole(GOVERNER_ROLE) {
        // Input validation
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

    /**
     * @notice Update vendor information
     * @param _vendorAddress Address of the vendor to update
     * @param _name New display name
     * @param _contactInfo New contact information
     * @param _location New location
     * @dev Only governance can edit vendor information
     * @custom:access-control Only GOVERNER_ROLE can call this function
     */
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

    /**
     * @notice Verify a previously unverified vendor
     * @param _vendorAddress Address of the vendor to verify
     * @dev Only governance can verify vendors. Verified vendors can list animals.
     * @custom:access-control Only GOVERNER_ROLE can call this function
     */
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

    /**
     * @notice Remove verification from a vendor
     * @param _vendorAddress Address of the vendor to unverify
     * @dev Unverified vendors cannot list new animals or edit existing ones
     * @custom:access-control Only GOVERNER_ROLE can call this function
     */
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

    // ============ ANIMAL MANAGEMENT FUNCTIONS ============

    /**
     * @notice Add a new animal to the platform
     * @param _vendorAddress Address of the verified vendor listing the animal
     * @param _name Display name of the animal
     * @param _animalType Type/species of animal (SHEEP, COW, GOAT, CAMEL)
     * @param _totalShares Total number of shares for this animal (max 7)
     * @param _pricePerShare Price per share in USDC (6 decimals)
     * @param _location Physical location where animal is kept
     * @param _image IPFS hash or URL for animal image
     * @param _description Detailed description of the animal
     * @param _breed Specific breed information
     * @param _weight Weight of the animal in kg
     * @param _age Age of the animal in months
     * @param _farmName Name of the farm where animal is located
     * @param _sacrificeDate Planned sacrifice date (must be in future)
     * @dev Only governance can add animals. Vendor must be registered and verified.
     * @custom:access-control Only GOVERNER_ROLE can call this function
     */
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

    /**
     * @notice Edit an existing animal's information
     * @param _vendorAddress Address of the vendor (must match animal's vendor)
     * @param _animalId ID of the animal to edit
     * @param _name New display name of the animal
     * @param _animalType New type/species of animal
     * @param _totalShares New total number of shares (resets availability)
     * @param _pricePerShare New price per share in USDC
     * @param _location New physical location
     * @param _image New IPFS hash or URL for animal image
     * @param _description New detailed description
     * @param _breed New breed information
     * @param _weight New weight in kg
     * @param _age New age in months
     * @param _farmName New farm name
     * @param _sacrificeDate New planned sacrifice date
     * @dev Only the original vendor can edit their animals. Resets available shares to total shares.
     * @custom:access-control Only GOVERNER_ROLE can call this function
     */
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

    /**
     * @notice Approve a pending animal for purchase
     * @param _animalId ID of the animal to approve
     * @dev Changes status from PENDING to AVAILABLE, allowing purchases
     * @custom:access-control Only GOVERNER_ROLE can call this function
     */
    function approveAnimal(uint256 _animalId) external onlyRole(GOVERNER_ROLE) {
        Animal storage animal = s_animals[_animalId];

        if (animal.status == AnimalStatus.AVAILABLE)
            revert Errors.AlreadyAvailable("animal");

        animal.status = AnimalStatus.AVAILABLE;
        emit AnimalStatusUpdated(_animalId, AnimalStatus.AVAILABLE);
    }

    /**
     * @notice Remove approval from an animal, making it unavailable for purchase
     * @param _animalId ID of the animal to unapprove
     * @dev Changes status from AVAILABLE to PENDING. Cannot unapprove if shares already purchased.
     * @custom:access-control Only GOVERNER_ROLE can call this function
     */
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

    // ============ PURCHASE MANAGEMENT FUNCTIONS ============

    /**
     * @notice Purchase shares of an animal
     * @param _animalId ID of the animal to purchase shares from
     * @param _shareAmount Number of shares to purchase (must be > 0 and <= available)
     * @dev Buyer must approve USDC spending before calling this function.
     *      Platform fee is deducted from the total payment.
     *      Vendor share is tracked but not distributed until sacrifice.
     * @custom:security Reentrancy protection via external token transfer
     */
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

    /**
     * @notice Mark an animal as sacrificed and mint NFT certificates for all buyers
     * @param _animalId ID of the animal that was sacrificed
     * @param _certificateURI Base URI for the NFT certificates
     * @dev This function:
     *      1. Validates animal is sold and ready for sacrifice
     *      2. Mints unique NFT certificates for all buyers
     *      3. Deposits platform fees to treasury
     *      4. Distributes vendor shares
     *      5. Updates animal status to SACRIFICED
     * @custom:access-control Only GOVERNER_ROLE can call this function
     * @custom:security Handles multiple token transfers and external calls
     */
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

    /**
     * @notice Refunds all purchases for a specific animal and resets its status.
     * @dev Only callable by GOVERNER_ROLE. Refunds all buyers who purchased shares of the animal,
     *      deducts the vendor's share, and resets the animal's status to PENDING and availableShares to totalShares.
     *      Marks refunded transactions by setting their nftCertificateId to max uint256.
     *      Emits BuyerRefunded for each buyer and AnimalRefunded for the animal.
     * @param _animalId The ID of the animal to refund purchases for.
     * @param _reason The reason for the refund (must be non-empty).
     */
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

    // ============ CONFIGURATION FUNCTIONS ============

    /**
     * @notice Update the platform fee percentage
     * @param _newFeeBps New fee in basis points (e.g., 250 = 2.5%)
     * @dev Maximum fee is capped at 10% (1000 basis points) for protection
     * @custom:access-control Only GOVERNER_ROLE can call this function
     */
    function setPlatformFee(
        uint256 _newFeeBps
    ) external onlyRole(GOVERNER_ROLE) {
        if (_newFeeBps > 1000) {
            // Maximum 10% fee (1000 basis points)
            revert Errors.InvalidAmount("platformFee");
        }

        // Update fee and emit event
        uint256 oldFeeBps = s_platformFeeBps;
        s_platformFeeBps = _newFeeBps;
        emit PlatformFeeUpdated(oldFeeBps, _newFeeBps);
    }

    // ============ VIEW FUNCTIONS ============
    // These functions provide read-only access to contract data for frontends and analytics

    /**
     * @notice Get all animal IDs with a specific status
     * @param _status The status to filter by (PENDING, AVAILABLE, SOLD, SACRIFICED)
     * @return Array of animal IDs matching the status
     * @dev Iterates through all animals, may be gas-intensive for large datasets
     */
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

    /**
     * @notice Get all animal IDs for a specific vendor with a given status
     * @param _vendorAddress The address of the vendor
     * @param _status The status to filter animals by (PENDING, AVAILABLE, SOLD, SACRIFICED)
     * @return Array of animal IDs belonging to the vendor with the specified status
     * @dev Iterates through the vendor's animals and filters by status
     */
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

    /**
     * @notice Get the total number of animals ever added to the platform
     * @return The total count of animals (including all statuses)
     */
    function getTotalAnimalsCount() external view returns (uint256) {
        return _nextAnimalId;
    }

    /**
     * @notice Get all animal IDs listed by a specific vendor
     * @param _vendorAddress The address of the vendor
     * @return Array of animal IDs listed by the vendor
     */
    function getVendorAnimals(
        address _vendorAddress
    ) external view returns (uint256[] memory) {
        return s_vendorAnimalIds[_vendorAddress];
    }

    /**
     * @notice Get complete information about an animal by its ID
     * @param _animalId The animal's unique identifier
     * @return Animal struct containing all animal information
     */
    function getAnimalById(
        uint256 _animalId
    ) external view returns (Animal memory) {
        return s_animals[_animalId];
    }

    /**
     * @notice Get the list of buyers for a specific animal
     * @param _animalId The animal's unique identifier
     * @return Array of addresses of buyers who purchased shares of the animal
     */
    function getAnimalBuyers(
        uint256 _animalId
    ) external view returns (address[] memory) {
        return s_animalBuyers[_animalId];
    }

    /**
     * @notice Get all transaction IDs for a specific animal and buyer
     * @param _animalId The animal's unique identifier
     * @param _buyer The address of the buyer
     * @return Array of transaction IDs for the buyer and animal
     */
    function getAnimalBuyerTransactionsIds(
        uint256 _animalId,
        address _buyer
    ) external view returns (uint256[] memory) {
        return s_animalBuyerTransactionIds[_animalId][_buyer];
    }

    /**
     * @notice Get all transaction IDs for a specific buyer
     * @param _buyer The address of the buyer
     * @return Array of transaction IDs for the buyer
     */
    function getBuyerTransactionIds(
        address _buyer
    ) external view returns (uint256[] memory) {
        return s_buyerTransactionIds[_buyer];
    }

    /**
     * @notice Check if a vendor is registered on the platform
     * @param _vendorAddress The address of the vendor
     * @return True if the vendor is registered, false otherwise
     */
    function isVendorRegistered(
        address _vendorAddress
    ) public view returns (bool) {
        return s_registeredVendors[_vendorAddress];
    }

    /**
     * @notice Get the next animal ID that will be assigned
     * @return The next animal ID
     */
    function getNextAnimalId() external view returns (uint256) {
        return _nextAnimalId;
    }

    /**
     * @notice Get the next transaction ID that will be assigned
     * @return The next transaction ID
     */
    function getNextTransactionId() external view returns (uint256) {
        return _nextTransactionId;
    }

    /**
     * @notice Get the next vendor ID that will be assigned
     * @return The next vendor ID
     */
    function getNextVendorId() external view returns (uint256) {
        return _nextVendorId;
    }

    /**
     * @notice Get vendor information by address
     * @param _vendorAddress The vendor's wallet address
     * @return Vendor struct containing all vendor information
     */
    function getVendorInfo(
        address _vendorAddress
    ) external view returns (Vendor memory) {
        return s_vendors[_vendorAddress];
    }

    /**
     * @notice Get transaction information by transaction ID
     * @param _transactionId The transaction ID
     * @return Transaction struct containing all transaction information
     */
    function getTransactionInfo(
        uint256 _transactionId
    ) external view returns (Transaction memory) {
        return s_buyerTransactions[_transactionId];
    }

    /**
     * @notice Get the number of buyers for a specific animal
     * @param _animalId The animal ID
     * @return Number of unique buyers
     */
    function getAnimalBuyersCount(
        uint256 _animalId
    ) external view returns (uint256) {
        return s_animalBuyers[_animalId].length;
    }

    /**
     * @notice Get the number of transactions for a specific buyer
     * @param _buyer The buyer's address
     * @return Number of transactions
     */
    function getBuyerTransactionsCount(
        address _buyer
    ) external view returns (uint256) {
        return s_buyerTransactionIds[_buyer].length;
    }

    /**
     * @notice Get the number of animals for a specific vendor
     * @param _vendorAddress The vendor's address
     * @return Number of animals
     */
    function getVendorAnimalsCount(
        address _vendorAddress
    ) external view returns (uint256) {
        return s_vendorAnimalIds[_vendorAddress].length;
    }

    /**
     * @notice Get total cost for purchasing specific number of shares
     * @param _animalId The animal ID
     * @param _shareAmount Number of shares to purchase
     * @return totalCost Total cost in USDC
     * @return platformFee Platform fee amount
     * @return vendorShare Vendor share amount
     */
    function calculatePurchaseCost(
        uint256 _animalId,
        uint8 _shareAmount
    )
        external
        view
        returns (uint256 totalCost, uint256 platformFee, uint256 vendorShare)
    {
        totalCost = _shareAmount * s_animals[_animalId].pricePerShare;
        platformFee = (totalCost * s_platformFeeBps) / BPS_BASE;
        vendorShare = totalCost - platformFee;
    }
}
