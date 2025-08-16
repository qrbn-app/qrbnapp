// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Governed} from "../dao/Governed.sol";
import {Errors} from "../lib/Errors.sol";

/**
 * @title IQrbnTreasury
 * @notice Interface for the QRBN Treasury contract
 * @dev Used to hold and manage platform fees/tips, not Zakat funds. Zakat funds are held in this contract until distribution.
 */
interface IQrbnTreasury {
    function depositFees(address token, uint256 amount) external;
    function withdrawFees(address token, address to, uint256 amount) external;
    function getAvailableBalance(address token) external view returns (uint256);
}

/**
 * @title IZakatNFT
 * @notice Interface for the Zakat NFT contract
 * @dev Used to mint Zakat certificates as NFTs for donors
 */
interface IZakatNFT {
    function safeMint(address to, string memory uri) external returns (uint256);
}

/**
 * @title Zakat
 * @author QRBN Team
 * @notice Main contract for the Zakat (Islamic charity) platform
 * @dev This contract manages:
 *      - Zakat organization registration and verification
 *      - Zakat collection from donors
 *      - Distribution proposals through DAO governance
 *      - NFT certificate minting upon distribution
 *      - Transparent tracking of all Zakat activities
 *
 * @custom:security-contact security@qrbn.app
 */
contract Zakat is Governed, ReentrancyGuard {
    // ============ ENUMS ============

    /**
     * @notice Status of Zakat distributions
     * @dev Controls the lifecycle of Zakat distribution proposals
     */
    enum DistributionStatus {
        PENDING,
        APPROVED,
        DISTRIBUTED,
        COMPLETED
    }

    /**
     * @notice Types of Zakat distributions
     * @dev Categorizes different forms of Zakat assistance
     */
    enum DistributionType {
        CASH,
        FOOD,
        GOODS,
        MIXED
    }

    /**
     * @notice Types of Zakat donations
     * @dev Categorizes different types of Zakat obligations
     */
    enum ZakatType {
        ZAKAT_MAAL,     // Wealth Zakat
        ZAKAT_FITRAH    // End of Ramadan Zakat
    }

    // ============ STRUCTS ============

    /**
     * @notice Information about registered Zakat organizations
     * @dev Stores organization profile and verification status
     */
    struct ZakatOrganization {
        uint256 id;
        address walletAddress;
        string name;
        string contactInfo;
        string location;
        string description;
        string registrationNumber;
        bool isVerified;
        uint256 totalDistributed;
        uint256 totalBeneficiaries;
        uint256 registeredAt;
    }

    /**
     * @notice Record of Zakat donations
     * @dev Stores complete donation information for tracking and NFT minting
     */
    struct ZakatDonation {
        uint256 id;
        address donor;
        uint256 amount;
        uint256 platformFee;
        uint256 netAmount;
        uint256 nftCertificateId;
        uint256 timestamp;
        bool isDistributed;
        ZakatType zakatType;
        string donorMessage;
    }

    /**
     * @notice Zakat distribution proposal and execution record
     * @dev Manages the complete lifecycle of Zakat distributions
     */
    struct ZakatDistribution {
        uint256 id;
        uint256 organizationId;
        address organizationAddress;
        uint256 requestedAmount;
        uint256 approvedAmount;
        uint256 distributedAmount;
        uint256 beneficiaryCount;
        DistributionType distributionType;
        DistributionStatus status;
        string title;
        string description;
        string location;
        string reportUri;
        uint256 createdAt;
        uint256 approvedAt;
        uint256 distributedAt;
        uint256 completedAt;
    }

    // ============ STATE VARIABLES ============

    // ID Counters
    uint256 private _nextDonationId;
    uint256 private _nextDistributionId;
    uint256 private _nextOrganizationId;

    // Financial Tracking
    uint256 public s_totalCollectedZakat; // Total net Zakat donations collected (excluding tips)
    uint256 public s_totalDistributedZakat;
    uint256 public s_totalCollectedFees; // Total tips collected for platform operations
    uint256 public s_availableZakatBalance;

    // Platform Configuration
    uint256 public s_platformFeeBps = 250; // Suggested tip percentage in basis points (2.5%)
    uint256 public constant BPS_BASE = 10000;

    // Core Data Storage
    mapping(address => ZakatOrganization) public s_zakatOrganizations;
    mapping(address => bool) public s_registeredOrganizations;
    mapping(uint256 => ZakatDonation) public s_zakatDonations;
    mapping(uint256 => ZakatDistribution) public s_zakatDistributions;

    // Relationship Mappings
    mapping(address => uint256[]) public s_donorDonationIds;
    mapping(address => uint256[]) public s_organizationDistributionIds;
    mapping(uint256 => uint256[]) public s_distributionDonationIds;
    mapping(uint256 => uint256) public s_donationToDistribution; // Maps donationId to distributionId for allocation

    // External Contract References
    IERC20 public immutable i_usdc;
    IQrbnTreasury public immutable i_treasury;
    IZakatNFT public immutable i_zakatNFT;

    // ============ EVENTS ============

    /// @notice Emitted when a new Zakat organization is registered
    event ZakatOrganizationRegistered(
        address indexed organizationAddress,
        uint256 indexed organizationId,
        string organizationName
    );

    /// @notice Emitted when organization information is updated
    event ZakatOrganizationEdited(
        address indexed organizationAddress,
        uint256 indexed organizationId,
        string organizationName
    );

    /// @notice Emitted when organization verification status changes
    event ZakatOrganizationVerifyUpdated(
        address indexed organizationAddress,
        uint256 indexed organizationId,
        bool isVerified
    );

    /// @notice Emitted when Zakat is donated
    event ZakatDonated(
        address indexed donor,
        uint256 indexed donationId,
        uint256 amount,
        uint256 netAmount
    );

    /// @notice Emitted when a distribution proposal is created
    event DistributionProposed(
        uint256 indexed distributionId,
        address indexed organizationAddress,
        uint256 requestedAmount
    );

    /// @notice Emitted when a distribution is approved by governance
    event DistributionApproved(
        uint256 indexed distributionId,
        uint256 approvedAmount
    );

    /// @notice Emitted when Zakat is distributed to organization
    event ZakatDistributed(
        uint256 indexed distributionId,
        address indexed organizationAddress,
        uint256 amount
    );

    /// @notice Emitted when distribution is completed with report
    event DistributionCompleted(
        uint256 indexed distributionId,
        uint256 beneficiaryCount,
        string reportUri
    );

    /// @notice Emitted when NFT certificates are minted for donors
    event ZakatNFTCertificatesMinted(
        uint256 indexed distributionId,
        uint256 totalCertificates
    );

    /// @notice Emitted when suggested tip percentage is updated
    event ZakatPlatformFeeUpdated(uint256 oldTipBps, uint256 newTipBps);

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initialize the Zakat contract
     * @param _usdcTokenAddress Address of the USDC token contract
     * @param _treasuryAddress Address of the treasury contract
     * @param _timelockAddress Address of the timelock contract (governance)
     * @param _zakatNFTAddress Address of the ZakatNFT contract
     * @param _tempAdminAddress Temporary admin address for initial setup
     */
    constructor(
        address _usdcTokenAddress,
        address _treasuryAddress,
        address _timelockAddress,
        address _zakatNFTAddress,
        address _tempAdminAddress
    ) Governed(_timelockAddress, _tempAdminAddress) {
        i_usdc = IERC20(_usdcTokenAddress);
        i_treasury = IQrbnTreasury(_treasuryAddress);
        i_zakatNFT = IZakatNFT(_zakatNFTAddress);
    }

    // ============ MODIFIERS ============

    /**
     * @notice Ensures organization is registered, verified, and valid
     * @param _organizationAddress Address of the organization to check
     */
    modifier checkOrganization(address _organizationAddress) {
        if (_organizationAddress == address(0))
            revert Errors.AddressZero("organizationAddress");
        if (!isOrganizationRegistered(_organizationAddress))
            revert Errors.NotRegistered("organization");
        if (!s_zakatOrganizations[_organizationAddress].isVerified)
            revert Errors.NotVerified("organization");
        _;
    }

    // ============ ORGANIZATION MANAGEMENT FUNCTIONS ============

    /**
     * @notice Register a new Zakat organization
     * @param _organizationAddress Wallet address of the organization
     * @param _name Display name of the organization
     * @param _contactInfo Contact information
     * @param _location Physical location of the organization
     * @param _description Description of the organization's work
     * @param _registrationNumber Official registration number
     * @dev Only governance can register organizations
     */
    function registerZakatOrganization(
        address _organizationAddress,
        string calldata _name,
        string calldata _contactInfo,
        string calldata _location,
        string calldata _description,
        string calldata _registrationNumber
    ) external onlyRole(GOVERNER_ROLE) {
        if (_organizationAddress == address(0))
            revert Errors.AddressZero("organizationAddress");
        if (s_registeredOrganizations[_organizationAddress])
            revert Errors.AlreadyRegistered("organization");
        if (bytes(_name).length == 0) revert Errors.EmptyString("name");
        if (bytes(_registrationNumber).length == 0)
            revert Errors.EmptyString("registrationNumber");

        uint256 organizationId = _nextOrganizationId++;

        s_zakatOrganizations[_organizationAddress] = ZakatOrganization({
            id: organizationId,
            walletAddress: _organizationAddress,
            name: _name,
            contactInfo: _contactInfo,
            location: _location,
            description: _description,
            registrationNumber: _registrationNumber,
            isVerified: true,
            totalDistributed: 0,
            totalBeneficiaries: 0,
            registeredAt: block.timestamp
        });

        s_registeredOrganizations[_organizationAddress] = true;

        emit ZakatOrganizationRegistered(_organizationAddress, organizationId, _name);
    }

    /**
     * @notice Update organization information
     * @param _organizationAddress Address of the organization to update
     * @param _name New display name
     * @param _contactInfo New contact information
     * @param _location New location
     * @param _description New description
     * @param _registrationNumber New registration number
     */
    function editZakatOrganization(
        address _organizationAddress,
        string calldata _name,
        string calldata _contactInfo,
        string calldata _location,
        string calldata _description,
        string calldata _registrationNumber
    ) external onlyRole(GOVERNER_ROLE) {
        if (_organizationAddress == address(0))
            revert Errors.AddressZero("organizationAddress");
        if (!s_registeredOrganizations[_organizationAddress])
            revert Errors.NotRegistered("organization");
        if (bytes(_name).length == 0) revert Errors.EmptyString("name");

        ZakatOrganization storage organization = s_zakatOrganizations[_organizationAddress];

        organization.name = _name;
        organization.contactInfo = _contactInfo;
        organization.location = _location;
        organization.description = _description;
        organization.registrationNumber = _registrationNumber;

        emit ZakatOrganizationEdited(_organizationAddress, organization.id, _name);
    }

    /**
     * @notice Verify a Zakat organization
     * @param _organizationAddress Address of the organization to verify
     */
    function verifyZakatOrganization(
        address _organizationAddress
    ) external onlyRole(GOVERNER_ROLE) {
        if (!s_registeredOrganizations[_organizationAddress])
            revert Errors.NotRegistered("organization");

        ZakatOrganization storage organization = s_zakatOrganizations[_organizationAddress];

        if (organization.isVerified) revert Errors.AlreadyVerified("organization");

        organization.isVerified = true;

        emit ZakatOrganizationVerifyUpdated(
            organization.walletAddress,
            organization.id,
            organization.isVerified
        );
    }

    /**
     * @notice Remove verification from an organization
     * @param _organizationAddress Address of the organization to unverify
     */
    function unverifyZakatOrganization(
        address _organizationAddress
    ) external onlyRole(GOVERNER_ROLE) {
        if (!s_registeredOrganizations[_organizationAddress])
            revert Errors.NotRegistered("organization");

        ZakatOrganization storage organization = s_zakatOrganizations[_organizationAddress];

        if (!organization.isVerified) revert Errors.AlreadyUnverified("organization");

        organization.isVerified = false;

        emit ZakatOrganizationVerifyUpdated(
            organization.walletAddress,
            organization.id,
            organization.isVerified
        );
    }

    // ============ DONATION FUNCTIONS ============

    /**
     * @notice Donate Zakat to the platform
     * @param _amount Amount of USDC to donate (net amount for Zakat)
     * @param _tipAmount Optional tip amount for platform operations
     * @param _zakatType Type of Zakat being donated
     * @param _donorMessage Optional message from the donor
     * @dev Donor must approve USDC spending for total amount (_amount + _tipAmount) before calling this function
     */
    function donateZakat(
        uint256 _amount,
        uint256 _tipAmount,
        ZakatType _zakatType,
        string calldata _donorMessage
    ) external nonReentrant {
        if (_amount == 0) revert Errors.InvalidAmount("amount");

        uint256 totalAmount = _amount + _tipAmount;

        // Transfer total USDC from donor (donation + tip)
        i_usdc.transferFrom(msg.sender, address(this), totalAmount);

        // Approve and deposit tip to treasury if provided
        if (_tipAmount > 0) {
            i_usdc.approve(address(i_treasury), _tipAmount);
            i_treasury.depositFees(address(i_usdc), _tipAmount);
            s_totalCollectedFees += _tipAmount;
        }

        // Track financial state
        s_totalCollectedZakat += _amount; // Only the net Zakat amount is tracked
        s_availableZakatBalance += _amount; // Only the net Zakat amount is available for distribution

        uint256 donationId = _nextDonationId++;
        s_zakatDonations[donationId] = ZakatDonation({
            id: donationId,
            donor: msg.sender,
            amount: totalAmount,
            platformFee: _tipAmount,
            netAmount: _amount,
            nftCertificateId: 0,
            timestamp: block.timestamp,
            isDistributed: false,
            zakatType: _zakatType,
            donorMessage: _donorMessage
        });

        s_donorDonationIds[msg.sender].push(donationId);

        emit ZakatDonated(msg.sender, donationId, totalAmount, _amount);
    }

    // ============ DISTRIBUTION MANAGEMENT FUNCTIONS ============

    /**
     * @notice Propose a Zakat distribution
     * @param _organizationAddress Address of the receiving organization
     * @param _requestedAmount Amount of USDC requested
     * @param _beneficiaryCount Expected number of beneficiaries
     * @param _distributionType Type of distribution (CASH, FOOD, GOODS, MIXED)
     * @param _title Title of the distribution proposal
     * @param _description Detailed description of the distribution plan
     * @param _location Location where distribution will take place
     * @dev Only governance can propose distributions
     */
    function proposeDistribution(
        address _organizationAddress,
        uint256 _requestedAmount,
        uint256 _beneficiaryCount,
        DistributionType _distributionType,
        string calldata _title,
        string calldata _description,
        string calldata _location
    ) external onlyRole(GOVERNER_ROLE) checkOrganization(_organizationAddress) {
        if (_requestedAmount == 0) revert Errors.InvalidAmount("requestedAmount");
        if (_requestedAmount > s_availableZakatBalance)
            revert Errors.InsufficientBalance(
                address(i_usdc),
                s_availableZakatBalance,
                _requestedAmount
            );
        if (_beneficiaryCount == 0) revert Errors.InvalidAmount("beneficiaryCount");
        if (bytes(_title).length == 0) revert Errors.EmptyString("title");
        if (bytes(_description).length == 0) revert Errors.EmptyString("description");

        uint256 distributionId = _nextDistributionId++;
        ZakatOrganization storage organization = s_zakatOrganizations[_organizationAddress];

        s_zakatDistributions[distributionId] = ZakatDistribution({
            id: distributionId,
            organizationId: organization.id,
            organizationAddress: _organizationAddress,
            requestedAmount: _requestedAmount,
            approvedAmount: 0,
            distributedAmount: 0,
            beneficiaryCount: _beneficiaryCount,
            distributionType: _distributionType,
            status: DistributionStatus.PENDING,
            title: _title,
            description: _description,
            location: _location,
            reportUri: "",
            createdAt: block.timestamp,
            approvedAt: 0,
            distributedAt: 0,
            completedAt: 0
        });

        s_organizationDistributionIds[_organizationAddress].push(distributionId);

        emit DistributionProposed(distributionId, _organizationAddress, _requestedAmount);
    }

    /**
     * @notice Approve a distribution proposal
     * @param _distributionId ID of the distribution to approve
     * @param _approvedAmount Amount approved for distribution
     * @dev Only governance can approve distributions
     */
    function approveDistribution(
        uint256 _distributionId,
        uint256 _approvedAmount
    ) external onlyRole(GOVERNER_ROLE) {
        ZakatDistribution storage distribution = s_zakatDistributions[_distributionId];

        if (distribution.status != DistributionStatus.PENDING)
            revert Errors.NotAvailable("distribution for approval");
        if (_approvedAmount == 0) revert Errors.InvalidAmount("approvedAmount");
        if (_approvedAmount > s_availableZakatBalance)
            revert Errors.InsufficientBalance(
                address(i_usdc),
                s_availableZakatBalance,
                _approvedAmount
            );

        distribution.approvedAmount = _approvedAmount;
        distribution.status = DistributionStatus.APPROVED;
        distribution.approvedAt = block.timestamp;

        emit DistributionApproved(_distributionId, _approvedAmount);
    }

    /**
     * @notice Distribute Zakat to approved organization
     * @param _distributionId ID of the approved distribution
     * @dev Only governance can execute distributions
     */
    function distributeZakat(
        uint256 _distributionId
    ) external onlyRole(GOVERNER_ROLE) nonReentrant {
        ZakatDistribution storage distribution = s_zakatDistributions[_distributionId];

        if (distribution.status != DistributionStatus.APPROVED)
            revert Errors.NotAvailable("distribution for execution");
        if (distribution.approvedAmount > s_availableZakatBalance)
            revert Errors.InsufficientBalance(
                address(i_usdc),
                s_availableZakatBalance,
                distribution.approvedAmount
            );

        // Transfer USDC to organization
        i_usdc.transfer(distribution.organizationAddress, distribution.approvedAmount);

        // Update tracking
        distribution.distributedAmount = distribution.approvedAmount;
        distribution.status = DistributionStatus.DISTRIBUTED;
        distribution.distributedAt = block.timestamp;

        s_availableZakatBalance -= distribution.approvedAmount;
        s_totalDistributedZakat += distribution.approvedAmount;

        ZakatOrganization storage organization = s_zakatOrganizations[distribution.organizationAddress];
        organization.totalDistributed += distribution.approvedAmount;

        emit ZakatDistributed(_distributionId, distribution.organizationAddress, distribution.approvedAmount);
    }

    /**
     * @notice Allocate specific donations to a distribution
     * @param _distributionId ID of the distribution
     * @param _donationIds Array of donation IDs to allocate
     * @dev Only governance can allocate donations to distributions
     */
    function allocateDonationsToDistribution(
        uint256 _distributionId,
        uint256[] calldata _donationIds
    ) external onlyRole(GOVERNER_ROLE) {
        ZakatDistribution storage distribution = s_zakatDistributions[_distributionId];
        
        if (distribution.status != DistributionStatus.APPROVED)
            revert Errors.NotAvailable("distribution for allocation");

        for (uint256 i = 0; i < _donationIds.length; i++) {
            uint256 donationId = _donationIds[i];
            ZakatDonation storage donation = s_zakatDonations[donationId];
            
            // Check if donation exists and is not already distributed
            if (donation.donor == address(0)) revert Errors.NotFound("donation");
            if (donation.isDistributed) revert Errors.AlreadyDistributed("donation");
            if (s_donationToDistribution[donationId] != 0) revert Errors.AlreadyAllocated("donation");
            
            // Allocate donation to distribution
            s_donationToDistribution[donationId] = _distributionId;
            s_distributionDonationIds[_distributionId].push(donationId);
        }
    }

    /**
     * @notice Complete distribution with report and mint NFT certificates
     * @param _distributionId ID of the distributed Zakat
     * @param _actualBeneficiaryCount Actual number of beneficiaries served
     * @param _reportUri URI pointing to the distribution report
     * @param _certificateURI Base URI for NFT certificates
     * @dev Only governance can complete distributions
     */
    function completeDistributionAndMintCertificates(
        uint256 _distributionId,
        uint256 _actualBeneficiaryCount,
        string calldata _reportUri,
        string calldata _certificateURI
    ) external onlyRole(GOVERNER_ROLE) nonReentrant {
        ZakatDistribution storage distribution = s_zakatDistributions[_distributionId];

        if (distribution.status != DistributionStatus.DISTRIBUTED)
            revert Errors.NotAvailable("distribution for completion");
        if (bytes(_reportUri).length == 0) revert Errors.EmptyString("reportUri");
        if (bytes(_certificateURI).length == 0) revert Errors.EmptyString("certificateURI");

        distribution.status = DistributionStatus.COMPLETED;
        distribution.reportUri = _reportUri;
        distribution.completedAt = block.timestamp;

        // Update organization beneficiary count
        ZakatOrganization storage organization = s_zakatOrganizations[distribution.organizationAddress];
        organization.totalBeneficiaries += _actualBeneficiaryCount;

        // Mint NFT certificates only for donations allocated to this distribution
        uint256[] memory allocatedDonations = s_distributionDonationIds[_distributionId];
        uint256 totalCertificates = 0;
        
        for (uint256 i = 0; i < allocatedDonations.length; i++) {
            uint256 donationId = allocatedDonations[i];
            ZakatDonation storage donation = s_zakatDonations[donationId];
            
            if (!donation.isDistributed && donation.nftCertificateId == 0) {
                string memory uniqueURI = string(
                    abi.encodePacked(
                        _certificateURI,
                        "/",
                        Strings.toString(_distributionId),
                        "/",
                        Strings.toString(donation.id)
                    )
                );

                uint256 nftCertificateId = i_zakatNFT.safeMint(
                    donation.donor,
                    uniqueURI
                );
                
                donation.nftCertificateId = nftCertificateId;
                donation.isDistributed = true;
                totalCertificates++;
            }
        }

        emit DistributionCompleted(_distributionId, _actualBeneficiaryCount, _reportUri);
        emit ZakatNFTCertificatesMinted(_distributionId, totalCertificates);
    }

    // ============ CONFIGURATION FUNCTIONS ============

    /**
     * @notice Update the suggested tip percentage
     * @param _newTipBps New suggested tip percentage in basis points
     */
    function setSuggestedTipPercentage(
        uint256 _newTipBps
    ) external onlyRole(GOVERNER_ROLE) {
        if (_newTipBps > 1000) {
            revert Errors.InvalidAmount("tipPercentage");
        }

        uint256 oldTipBps = s_platformFeeBps;
        s_platformFeeBps = _newTipBps;
        emit ZakatPlatformFeeUpdated(oldTipBps, _newTipBps);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Get all distributions with a specific status
     * @param _status The status to filter by
     * @return Array of distribution IDs matching the status
     */
    function getDistributionsByStatus(
        DistributionStatus _status
    ) external view returns (uint256[] memory) {
        uint256 statusCount = 0;
        for (uint256 i = 0; i < _nextDistributionId; i++) {
            if (s_zakatDistributions[i].status == _status) {
                statusCount++;
            }
        }

        uint256[] memory distributions = new uint256[](statusCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < _nextDistributionId; i++) {
            if (s_zakatDistributions[i].status == _status) {
                distributions[currentIndex] = i;
                currentIndex++;
            }
        }

        return distributions;
    }

    /**
     * @notice Get all distribution IDs for a specific organization
     * @param _organizationAddress The organization address
     * @return Array of distribution IDs
     */
    function getOrganizationDistributions(
        address _organizationAddress
    ) external view returns (uint256[] memory) {
        return s_organizationDistributionIds[_organizationAddress];
    }

    /**
     * @notice Get all donation IDs for a specific donor
     * @param _donor The donor address
     * @return Array of donation IDs
     */
    function getDonorDonations(
        address _donor
    ) external view returns (uint256[] memory) {
        return s_donorDonationIds[_donor];
    }

    /**
     * @notice Get all donation IDs associated with a distribution
     * @param _distributionId The distribution ID
     * @return Array of donation IDs
     */
    function getDistributionDonations(
        uint256 _distributionId
    ) external view returns (uint256[] memory) {
        return s_distributionDonationIds[_distributionId];
    }

    /**
     * @notice Check if an organization is registered
     * @param _organizationAddress The organization address
     * @return True if registered, false otherwise
     */
    function isOrganizationRegistered(
        address _organizationAddress
    ) public view returns (bool) {
        return s_registeredOrganizations[_organizationAddress];
    }

    /**
     * @notice Get organization information by address
     * @param _organizationAddress The organization address
     * @return ZakatOrganization struct
     */
    function getOrganizationInfo(
        address _organizationAddress
    ) external view returns (ZakatOrganization memory) {
        return s_zakatOrganizations[_organizationAddress];
    }

    /**
     * @notice Get donation information by ID
     * @param _donationId The donation ID
     * @return ZakatDonation struct
     */
    function getDonationInfo(
        uint256 _donationId
    ) external view returns (ZakatDonation memory) {
        return s_zakatDonations[_donationId];
    }

    /**
     * @notice Get distribution information by ID
     * @param _distributionId The distribution ID
     * @return ZakatDistribution struct
     */
    function getDistributionInfo(
        uint256 _distributionId
    ) external view returns (ZakatDistribution memory) {
        return s_zakatDistributions[_distributionId];
    }

    /**
     * @notice Get total counts
     * @return Total donations, distributions, and organizations
     */
    function getTotalCounts() external view returns (uint256, uint256, uint256) {
        return (_nextDonationId, _nextDistributionId, _nextOrganizationId);
    }

    /**
     * @notice Calculate donation amounts including tip
     * @param _donationAmount Net amount for Zakat donation
     * @param _tipAmount Tip amount for platform operations
     * @return totalAmount Total amount to be transferred, netAmount Amount available for Zakat distribution
     */
    function calculateDonationAmounts(
        uint256 _donationAmount,
        uint256 _tipAmount
    ) external pure returns (uint256 totalAmount, uint256 netAmount) {
        totalAmount = _donationAmount + _tipAmount;
        netAmount = _donationAmount;
    }
}