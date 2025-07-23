// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Zakat} from "../src/zakat/Zakat.sol";
import {ZakatNFT} from "../src/zakat/ZakatNFT.sol";
import {Errors} from "../src/lib/Errors.sol";
import {QrbnToken} from "../src/dao/QrbnToken.sol";
import {QrbnGov} from "../src/dao/QrbnGov.sol";
import {QrbnTreasury} from "../src/dao/QrbnTreasury.sol";
import {QrbnTimelock} from "../src/dao/QrbnTimelock.sol";
import {DeployQrbn} from "../script/DeployQrbn.s.sol";
import {DeployConfig} from "../script/DeployConfig.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {Constants} from "../src/lib/Constants.sol";

/**
 * @title TestZakat
 * @notice Comprehensive test suite for Zakat (Islamic charity) functionality
 * @dev Tests all Zakat-related features: organizations, donations, distributions, NFTs
 */
contract TestZakat is Test {
    // ============ CONTRACTS ============
    QrbnTreasury i_qrbnTreasury;
    QrbnTimelock i_qrbnTimelock;
    QrbnToken i_qrbnToken;
    QrbnGov i_qrbnGov;
    ZakatNFT i_zakatNFT;
    Zakat i_zakat;
    MockUSDC i_mockUSDC;

    // ============ ADDRESSES ============
    address immutable i_deployer = address(this);
    address immutable i_founder = makeAddr("founder");
    address immutable i_syariahCouncil = makeAddr("syariahCouncil");
    address immutable i_communityRep = makeAddr("communityRep");
    address immutable i_orgRep = makeAddr("orgRep");
    
    // Zakat-specific addresses
    address immutable i_donor = makeAddr("donor");
    address immutable i_donor2 = makeAddr("donor2");
    address immutable i_zakatOrg = makeAddr("zakatOrg");
    address immutable i_anotherZakatOrg = makeAddr("anotherZakatOrg");

    function setUp() public {
        DeployConfig deployConfig = new DeployConfig(i_deployer, i_deployer);
        DeployConfig.NetworkConfig memory networkConfig = deployConfig
            .getNetworkConfig();

        DeployQrbn deployScript = new DeployQrbn();
        (
            i_qrbnTimelock,
            i_qrbnGov,
            i_qrbnToken,
            ,
            ,
            i_zakat,
            i_zakatNFT,
            i_qrbnTreasury
        ) = deployScript.runDeploy(
            networkConfig.usdcTokenAddress,
            i_founder,
            i_syariahCouncil,
            i_orgRep,
            i_communityRep,
            true
        );

        i_mockUSDC = MockUSDC(networkConfig.usdcTokenAddress);

        // Mint USDC for testing
        if (
            block.chainid != Constants.LISK_CHAINID &&
            block.chainid != Constants.LISK_SEPOLIA_CHAINID
        ) {
            i_mockUSDC.mint(i_donor, 100000e6);   // 100k USDC for primary donor
            i_mockUSDC.mint(i_donor2, 50000e6);   // 50k USDC for secondary donor
        }
    }

    // ============ ROLE & DEPLOYMENT TESTS ============

    function test_ZakatGovRoleIsTimelockContract() public view {
        assertEq(
            i_zakat.hasRole(i_zakat.GOVERNER_ROLE(), address(i_qrbnTimelock)),
            true,
            "Zakat should be governed by timelock"
        );
    }

    function test_ZakatGovRoleIsDeployerInTestnet() public view {
        if (block.chainid != Constants.LISK_CHAINID) {
            assertEq(
                i_zakat.hasRole(i_zakat.GOVERNER_ROLE(), i_deployer),
                true,
                "Deployer should have governor role in testnet"
            );
        }
    }

    function test_ZakatNFTGovIsTimelockContract() public view {
        assertEq(
            i_zakatNFT.hasRole(
                i_zakatNFT.GOVERNER_ROLE(),
                address(i_qrbnTimelock)
            ),
            true,
            "ZakatNFT should be governed by timelock"
        );
    }

    function test_ZakatNFTGovIsZakatContract() public view {
        assertEq(
            i_zakatNFT.hasRole(i_zakatNFT.GOVERNER_ROLE(), address(i_zakat)),
            true,
            "Zakat contract should be able to mint NFTs"
        );
    }

    function test_ZakatNFTAdminIsRevoked() public view {
        if (block.chainid == Constants.LISK_CHAINID) {
            assertEq(
                i_zakatNFT.hasRole(
                    i_zakatNFT.DEFAULT_ADMIN_ROLE(),
                    i_deployer
                ),
                false,
                "Admin role should be revoked in production"
            );
        }
    }

    function test_ZakatIsAuthorizedTreasuryDepositor() public view {
        assertEq(
            i_qrbnTreasury.authorizedDepositors(address(i_zakat)),
            true,
            "Zakat should be authorized to deposit fees to treasury"
        );
    }

    // ============ ORGANIZATION REGISTRATION TESTS ============

    function test_RegisterZakatOrganizationByTimelock() public {
        vm.expectEmit(true, true, true, true);
        emit Zakat.ZakatOrganizationRegistered(i_zakatOrg, 0, "Jakarta Food Bank");
        vm.prank(address(i_qrbnTimelock));
        i_zakat.registerZakatOrganization(
            i_zakatOrg,
            "Jakarta Food Bank",
            "contact@jakartafoodbank.org",
            "Jakarta, Indonesia",
            "Distributes food to poor families in Jakarta",
            "REG-JFB-2024"
        );

        // Verify organization data
        assertEq(i_zakat.s_registeredOrganizations(i_zakatOrg), true);

        (
            uint256 id,
            address walletAddress,
            string memory name,
            string memory contactInfo,
            string memory location,
            string memory description,
            string memory registrationNumber,
            bool isVerified,
            uint256 totalDistributed,
            uint256 totalBeneficiaries,
            uint256 registeredAt
        ) = i_zakat.s_zakatOrganizations(i_zakatOrg);

        assertEq(id, 0);
        assertEq(walletAddress, i_zakatOrg);
        assertEq(name, "Jakarta Food Bank");
        assertEq(contactInfo, "contact@jakartafoodbank.org");
        assertEq(location, "Jakarta, Indonesia");
        assertEq(description, "Distributes food to poor families in Jakarta");
        assertEq(registrationNumber, "REG-JFB-2024");
        assertEq(isVerified, true);
        assertEq(totalDistributed, 0);
        assertEq(totalBeneficiaries, 0);
        assertGt(registeredAt, 0);
    }

    function test_RegisterZakatOrganizationByDeployerInTestnet() public {
        if (block.chainid != Constants.LISK_CHAINID) {
            vm.expectEmit(true, true, true, true);
            emit Zakat.ZakatOrganizationRegistered(i_zakatOrg, 0, "Test Org");
            i_zakat.registerZakatOrganization(
                i_zakatOrg,
                "Test Org",
                "contact@test.org",
                "Jakarta",
                "Test organization",
                "REG123456"
            );

            assertEq(i_zakat.s_registeredOrganizations(i_zakatOrg), true);
        }
    }

    function test_RegisterZakatOrganizationByNonGov() public {
        vm.expectRevert();
        vm.prank(i_founder);
        i_zakat.registerZakatOrganization(
            i_zakatOrg,
            "Test Org",
            "contact@test.org",
            "Jakarta",
            "Description",
            "REG123456"
        );
    }

    function test_RegisterZakatOrganizationWithZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.AddressZero.selector, "organizationAddress")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.registerZakatOrganization(
            address(0),
            "Test Org",
            "contact@test.org",
            "Jakarta",
            "Description",
            "REG123456"
        );
    }

    function test_RegisterZakatOrganizationTwice() public {
        vm.prank(address(i_qrbnTimelock));
        i_zakat.registerZakatOrganization(
            i_zakatOrg,
            "Test Org",
            "contact@test.org",
            "Jakarta",
            "Description",
            "REG123456"
        );

        vm.expectRevert(
            abi.encodeWithSelector(Errors.AlreadyRegistered.selector, "organization")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.registerZakatOrganization(
            i_zakatOrg,
            "Test Org 2",
            "contact2@test.org",
            "Bandung",
            "Description 2",
            "REG789012"
        );
    }

    function test_RegisterZakatOrganizationWithEmptyName() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EmptyString.selector, "name")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.registerZakatOrganization(
            i_zakatOrg,
            "",
            "contact@test.org",
            "Jakarta",
            "Description",
            "REG123456"
        );
    }

    function test_RegisterZakatOrganizationWithEmptyRegistrationNumber() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EmptyString.selector, "registrationNumber")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.registerZakatOrganization(
            i_zakatOrg,
            "Test Org",
            "contact@test.org",
            "Jakarta",
            "Description",
            ""
        );
    }

    // ============ ORGANIZATION EDITING TESTS ============

    function test_EditZakatOrganization() public {
        // First register organization
        vm.prank(address(i_qrbnTimelock));
        i_zakat.registerZakatOrganization(
            i_zakatOrg,
            "Test Org",
            "contact@test.org",
            "Jakarta",
            "Original description",
            "REG123456"
        );

        // Edit organization
        vm.expectEmit(true, true, true, true);
        emit Zakat.ZakatOrganizationEdited(i_zakatOrg, 0, "Updated Test Org");
        vm.prank(address(i_qrbnTimelock));
        i_zakat.editZakatOrganization(
            i_zakatOrg,
            "Updated Test Org",
            "newemail@test.org",
            "Surabaya",
            "Updated description",
            "REG789012"
        );

        // Verify changes
        (
            ,
            ,
            string memory name,
            string memory contactInfo,
            string memory location,
            string memory description,
            string memory registrationNumber,
            ,
            ,
            ,
        ) = i_zakat.s_zakatOrganizations(i_zakatOrg);
        
        assertEq(name, "Updated Test Org");
        assertEq(contactInfo, "newemail@test.org");
        assertEq(location, "Surabaya");
        assertEq(description, "Updated description");
        assertEq(registrationNumber, "REG789012");
    }

    function test_EditZakatOrganizationByNonGov() public {
        _setupStandardZakatOrganization();

        vm.expectRevert();
        vm.prank(i_founder);
        i_zakat.editZakatOrganization(
            i_zakatOrg,
            "Updated Name",
            "new@email.com",
            "New Location",
            "New description",
            "NEW123"
        );
    }

    function test_EditZakatOrganizationNotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NotRegistered.selector, "organization")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.editZakatOrganization(
            i_zakatOrg,
            "Name",
            "email@test.com",
            "Location",
            "Description",
            "REG123"
        );
    }

    // ============ ORGANIZATION VERIFICATION TESTS ============

    function test_VerifyZakatOrganization() public {
        // Register and unverify first
        vm.prank(address(i_qrbnTimelock));
        i_zakat.registerZakatOrganization(
            i_zakatOrg,
            "Test Org",
            "contact@test.org",
            "Jakarta",
            "Description",
            "REG123456"
        );

        vm.prank(address(i_qrbnTimelock));
        i_zakat.unverifyZakatOrganization(i_zakatOrg);

        // Now verify
        vm.expectEmit(true, true, true, true);
        emit Zakat.ZakatOrganizationVerifyUpdated(i_zakatOrg, 0, true);
        vm.prank(address(i_qrbnTimelock));
        i_zakat.verifyZakatOrganization(i_zakatOrg);

        // Check verification status
        (, , , , , , , bool isVerified, , , ) = i_zakat.s_zakatOrganizations(i_zakatOrg);
        assertEq(isVerified, true);
    }

    function test_VerifyZakatOrganizationAlreadyVerified() public {
        _setupStandardZakatOrganization();

        vm.expectRevert(
            abi.encodeWithSelector(Errors.AlreadyVerified.selector, "organization")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.verifyZakatOrganization(i_zakatOrg);
    }

    function test_UnverifyZakatOrganization() public {
        _setupStandardZakatOrganization();

        vm.expectEmit(true, true, true, true);
        emit Zakat.ZakatOrganizationVerifyUpdated(i_zakatOrg, 0, false);
        vm.prank(address(i_qrbnTimelock));
        i_zakat.unverifyZakatOrganization(i_zakatOrg);

        // Check verification status
        (, , , , , , , bool isVerified, , , ) = i_zakat.s_zakatOrganizations(i_zakatOrg);
        assertEq(isVerified, false);
    }

    function test_UnverifyZakatOrganizationAlreadyUnverified() public {
        _setupStandardZakatOrganization();

        vm.prank(address(i_qrbnTimelock));
        i_zakat.unverifyZakatOrganization(i_zakatOrg);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.AlreadyUnverified.selector, "organization")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.unverifyZakatOrganization(i_zakatOrg);
    }

    // ============ DONATION TESTS ============

    function test_DonateZakat() public {
        uint256 donationAmount = 1000e6; // 1000 USDC
        uint256 expectedFee = (donationAmount * 250) / 10000; // 2.5%
        uint256 expectedNetAmount = donationAmount - expectedFee;

        vm.prank(i_donor);
        i_mockUSDC.approve(address(i_zakat), donationAmount);

        vm.expectEmit(true, true, true, true);
        emit Zakat.ZakatDonated(i_donor, 0, donationAmount, expectedNetAmount);
        vm.prank(i_donor);
        i_zakat.donateZakat(donationAmount, "May Allah accept this zakat");

        // Verify donation record
        (
            uint256 id,
            address donor,
            uint256 amount,
            uint256 platformFee,
            uint256 netAmount,
            uint256 nftCertificateId,
            uint256 timestamp,
            bool isDistributed,
            string memory donorMessage
        ) = i_zakat.s_zakatDonations(0);

        assertEq(id, 0);
        assertEq(donor, i_donor);
        assertEq(amount, donationAmount);
        assertEq(platformFee, expectedFee);
        assertEq(netAmount, expectedNetAmount);
        assertEq(nftCertificateId, 0);
        assertGt(timestamp, 0);
        assertEq(isDistributed, false);
        assertEq(donorMessage, "May Allah accept this zakat");

        // Verify contract state
        assertEq(i_zakat.s_totalCollectedZakat(), donationAmount);
        assertEq(i_zakat.s_totalCollectedFees(), expectedFee);
        assertEq(i_zakat.s_availableZakatBalance(), expectedNetAmount);

        // Verify donor tracking
        uint256[] memory donorDonations = i_zakat.getDonorDonations(i_donor);
        assertEq(donorDonations.length, 1);
        assertEq(donorDonations[0], 0);

        // Verify fees were deposited to treasury
        assertEq(i_qrbnTreasury.getAvailableBalance(address(i_mockUSDC)), expectedFee);
    }

    function test_DonateZakatWithZeroAmount() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidAmount.selector, "amount")
        );
        vm.prank(i_donor);
        i_zakat.donateZakat(0, "");
    }

    function test_MultipleDonationsFromSameDonor() public {
        uint256 donation1 = 1000e6;
        uint256 donation2 = 500e6;
        uint256 totalDonations = donation1 + donation2;
        uint256 totalFees = ((donation1 + donation2) * 250) / 10000;
        uint256 totalNetAmount = totalDonations - totalFees;

        // First donation
        vm.prank(i_donor);
        i_mockUSDC.approve(address(i_zakat), donation1);
        vm.prank(i_donor);
        i_zakat.donateZakat(donation1, "First donation");

        // Second donation
        vm.prank(i_donor);
        i_mockUSDC.approve(address(i_zakat), donation2);
        vm.prank(i_donor);
        i_zakat.donateZakat(donation2, "Second donation");

        // Verify totals
        assertEq(i_zakat.s_totalCollectedZakat(), totalDonations);
        assertEq(i_zakat.s_totalCollectedFees(), totalFees);
        assertEq(i_zakat.s_availableZakatBalance(), totalNetAmount);

        // Verify donor has 2 donations
        uint256[] memory donorDonations = i_zakat.getDonorDonations(i_donor);
        assertEq(donorDonations.length, 2);
        assertEq(donorDonations[0], 0);
        assertEq(donorDonations[1], 1);
    }

    function test_MultipleDonorsCanDonate() public {
        uint256 donation1 = 1000e6;
        uint256 donation2 = 2000e6;

        // First donor
        vm.prank(i_donor);
        i_mockUSDC.approve(address(i_zakat), donation1);
        vm.prank(i_donor);
        i_zakat.donateZakat(donation1, "From donor 1");

        // Second donor
        vm.prank(i_donor2);
        i_mockUSDC.approve(address(i_zakat), donation2);
        vm.prank(i_donor2);
        i_zakat.donateZakat(donation2, "From donor 2");

        // Verify separate tracking
        uint256[] memory donor1Donations = i_zakat.getDonorDonations(i_donor);
        uint256[] memory donor2Donations = i_zakat.getDonorDonations(i_donor2);
        
        assertEq(donor1Donations.length, 1);
        assertEq(donor2Donations.length, 1);
        assertEq(donor1Donations[0], 0);
        assertEq(donor2Donations[0], 1);

        // Verify total state
        assertEq(i_zakat.s_totalCollectedZakat(), donation1 + donation2);
    }

    // ============ DISTRIBUTION PROPOSAL TESTS ============

    function test_ProposeDistribution() public {
        _setupStandardZakatOrganizationWithFunds();

        uint256 requestedAmount = 500e6;
        uint256 beneficiaryCount = 100;

        vm.expectEmit(true, true, true, true);
        emit Zakat.DistributionProposed(0, i_zakatOrg, requestedAmount);
        vm.prank(address(i_qrbnTimelock));
        i_zakat.proposeDistribution(
            i_zakatOrg,
            requestedAmount,
            beneficiaryCount,
            Zakat.DistributionType.MIXED,
            "Food Distribution for Poor Families",
            "Providing rice, oil, and basic necessities to 100 poor families in Jakarta",
            "Jakarta Selatan"
        );

        // Verify distribution proposal
        Zakat.ZakatDistribution memory dist = i_zakat.getDistributionInfo(0);

        assertEq(dist.id, 0);
        assertEq(dist.organizationId, 0);
        assertEq(dist.organizationAddress, i_zakatOrg);
        assertEq(dist.requestedAmount, requestedAmount);
        assertEq(dist.approvedAmount, 0);
        assertEq(dist.distributedAmount, 0);
        assertEq(dist.beneficiaryCount, beneficiaryCount);
        assertEq(uint8(dist.distributionType), uint8(Zakat.DistributionType.MIXED));
        assertEq(uint8(dist.status), uint8(Zakat.DistributionStatus.PENDING));
        assertEq(dist.title, "Food Distribution for Poor Families");
        assertEq(dist.description, "Providing rice, oil, and basic necessities to 100 poor families in Jakarta");
        assertEq(dist.location, "Jakarta Selatan");
        assertEq(dist.reportUri, "");
        assertGt(dist.createdAt, 0);
        assertEq(dist.approvedAt, 0);
        assertEq(dist.distributedAt, 0);
        assertEq(dist.completedAt, 0);


        // Verify organization tracking
        uint256[] memory orgDistributions = i_zakat.getOrganizationDistributions(i_zakatOrg);
        assertEq(orgDistributions.length, 1);
        assertEq(orgDistributions[0], 0);
    }

    function test_ProposeDistributionWithUnregisteredOrganization() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NotRegistered.selector, "organization")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.proposeDistribution(
            i_zakatOrg,
            500e6,
            100,
            Zakat.DistributionType.CASH,
            "Title",
            "Description",
            "Location"
        );
    }

    function test_ProposeDistributionWithInsufficientFunds() public {
        _setupStandardZakatOrganization();
        
        // Try to propose more than available (no donations made)
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InsufficientBalance.selector,
                address(i_mockUSDC),
                0,
                500e6
            )
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.proposeDistribution(
            i_zakatOrg,
            500e6,
            100,
            Zakat.DistributionType.CASH,
            "Title",
            "Description",
            "Location"
        );
    }

    function test_ProposeDistributionWithInvalidData() public {
        _setupStandardZakatOrganizationWithFunds();

        // Test zero amount
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidAmount.selector, "requestedAmount")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.proposeDistribution(
            i_zakatOrg,
            0,
            100,
            Zakat.DistributionType.CASH,
            "Title",
            "Description",
            "Location"
        );

        // Test zero beneficiaries
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidAmount.selector, "beneficiaryCount")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.proposeDistribution(
            i_zakatOrg,
            500e6,
            0,
            Zakat.DistributionType.CASH,
            "Title",
            "Description",
            "Location"
        );

        // Test empty title
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EmptyString.selector, "title")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.proposeDistribution(
            i_zakatOrg,
            500e6,
            100,
            Zakat.DistributionType.CASH,
            "",
            "Description",
            "Location"
        );
    }

    // ============ DISTRIBUTION APPROVAL TESTS ============

    function test_ApproveDistribution() public {
        _setupStandardZakatOrganizationWithFunds();
        _proposeStandardDistribution();

        uint256 approvedAmount = 400e6; // Approve less than requested

        vm.expectEmit(true, true, true, true);
        emit Zakat.DistributionApproved(0, approvedAmount);
        vm.prank(address(i_qrbnTimelock));
        i_zakat.approveDistribution(0, approvedAmount);

        // Verify approval
        (
            ,
            ,
            ,
            ,
            uint256 approvedAmountStored,
            ,
            ,
            ,
            Zakat.DistributionStatus status,
            ,
            ,
            ,
            ,
            ,
            uint256 approvedAt,
            ,
        ) = i_zakat.s_zakatDistributions(0);

        assertEq(approvedAmountStored, approvedAmount);
        assertEq(uint8(status), uint8(Zakat.DistributionStatus.APPROVED));
        assertGt(approvedAt, 0);
    }

    function test_ApproveDistributionWithInsufficientBalance() public {
        _setupStandardZakatOrganizationWithFunds();
        _proposeStandardDistribution();

        // Try to approve more than available
        uint256 excessiveAmount = i_zakat.s_availableZakatBalance() + 1e6;
        
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InsufficientBalance.selector,
                address(i_mockUSDC),
                i_zakat.s_availableZakatBalance(),
                excessiveAmount
            )
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.approveDistribution(0, excessiveAmount);
    }

    function test_ApproveDistributionAlreadyApproved() public {
        _setupStandardZakatOrganizationWithFunds();
        _proposeStandardDistribution();
        
        // First approval
        vm.prank(address(i_qrbnTimelock));
        i_zakat.approveDistribution(0, 400e6);

        // Try to approve again
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NotAvailable.selector, "distribution for approval")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.approveDistribution(0, 300e6);
    }

    // ============ DISTRIBUTION EXECUTION TESTS ============

    function test_DistributeZakat() public {
        _setupStandardZakatOrganizationWithFunds();
        _proposeStandardDistribution();
        uint256 approvedAmount = 400e6;
        _approveDistribution(0, approvedAmount);

        uint256 initialOrgBalance = i_mockUSDC.balanceOf(i_zakatOrg);
        uint256 initialAvailableBalance = i_zakat.s_availableZakatBalance();

        vm.expectEmit(true, true, true, true);
        emit Zakat.ZakatDistributed(0, i_zakatOrg, approvedAmount);
        vm.prank(address(i_qrbnTimelock));
        i_zakat.distributeZakat(0);

        // Verify distribution
        (
            ,
            ,
            ,
            ,
            ,
            uint256 distributedAmount,
            ,
            ,
            Zakat.DistributionStatus status,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 distributedAt,
        ) = i_zakat.s_zakatDistributions(0);

        assertEq(distributedAmount, approvedAmount);
        assertEq(uint8(status), uint8(Zakat.DistributionStatus.DISTRIBUTED));
        assertGt(distributedAt, 0);

        // Verify balances
        assertEq(i_mockUSDC.balanceOf(i_zakatOrg), initialOrgBalance + approvedAmount);
        assertEq(i_zakat.s_availableZakatBalance(), initialAvailableBalance - approvedAmount);
        assertEq(i_zakat.s_totalDistributedZakat(), approvedAmount);

        // Verify organization stats
        (, , , , , , , , uint256 totalDistributed, , ) = i_zakat.s_zakatOrganizations(i_zakatOrg);
        assertEq(totalDistributed, approvedAmount);
    }

    function test_DistributeZakatNotApproved() public {
        _setupStandardZakatOrganizationWithFunds();
        _proposeStandardDistribution();

        vm.expectRevert(
            abi.encodeWithSelector(Errors.NotAvailable.selector, "distribution for execution")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.distributeZakat(0);
    }

    function test_DistributeZakatByNonGov() public {
        _setupStandardZakatOrganizationWithFunds();
        _proposeStandardDistribution();
        _approveDistribution(0, 400e6);

        vm.expectRevert();
        vm.prank(i_founder);
        i_zakat.distributeZakat(0);
    }

    // ============ COMPLETION AND NFT MINTING TESTS ============

    function test_CompleteDistributionAndMintCertificates() public {
        _setupStandardZakatOrganizationWithFunds();
        _proposeStandardDistribution();
        uint256 approvedAmount = 400e6;
        _approveDistribution(0, approvedAmount);
        _distributeZakat(0);

        uint256 actualBeneficiaries = 95;
        string memory reportUri = "https://ipfs.io/ipfs/QmReport123";
        string memory certificateUri = "https://api.qrbn.com/zakat-certificates";

        vm.expectEmit(true, true, true, true);
        emit Zakat.DistributionCompleted(0, actualBeneficiaries, reportUri);
        vm.expectEmit(true, true, true, true);
        emit Zakat.ZakatNFTCertificatesMinted(0, 1); // 1 donor

        vm.prank(address(i_qrbnTimelock));
        i_zakat.completeDistributionAndMintCertificates(
            0,
            actualBeneficiaries,
            reportUri,
            certificateUri
        );

        // Verify completion
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            Zakat.DistributionStatus status,
            ,
            ,
            ,
            string memory storedReportUri,
            ,
            ,
            ,
            uint256 completedAt
        ) = i_zakat.s_zakatDistributions(0);

        assertEq(uint8(status), uint8(Zakat.DistributionStatus.COMPLETED));
        assertEq(storedReportUri, reportUri);
        assertGt(completedAt, 0);

        // Verify organization beneficiaries updated
        (, , , , , , , , , uint256 totalBeneficiaries, ) = i_zakat.s_zakatOrganizations(i_zakatOrg);
        assertEq(totalBeneficiaries, actualBeneficiaries);

        // Verify NFT was minted to donor
        (, , , , , uint256 nftCertificateId, , bool isDistributed, ) = i_zakat.s_zakatDonations(0);
        assertGt(nftCertificateId, 0);
        assertEq(isDistributed, true);
        assertEq(i_zakatNFT.ownerOf(nftCertificateId), i_donor);

        // Verify distribution tracking
        uint256[] memory distributionDonations = i_zakat.getDistributionDonations(0);
        assertEq(distributionDonations.length, 1);
        assertEq(distributionDonations[0], 0);
    }

    function test_CompleteDistributionNotDistributed() public {
        _setupStandardZakatOrganizationWithFunds();
        _proposeStandardDistribution();
        _approveDistribution(0, 400e6);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.NotAvailable.selector, "distribution for completion")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.completeDistributionAndMintCertificates(
            0,
            95,
            "https://ipfs.io/ipfs/QmReport123",
            "https://api.qrbn.com/certificates"
        );
    }

    function test_CompleteDistributionWithEmptyReportUri() public {
        _setupStandardZakatOrganizationWithFunds();
        _proposeStandardDistribution();
        _approveDistribution(0, 400e6);
        _distributeZakat(0);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.EmptyString.selector, "reportUri")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.completeDistributionAndMintCertificates(
            0,
            95,
            "",
            "https://api.qrbn.com/certificates"
        );
    }

    function test_CompleteDistributionWithEmptyCertificateUri() public {
        _setupStandardZakatOrganizationWithFunds();
        _proposeStandardDistribution();
        _approveDistribution(0, 400e6);
        _distributeZakat(0);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.EmptyString.selector, "certificateURI")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.completeDistributionAndMintCertificates(
            0,
            95,
            "https://ipfs.io/ipfs/QmReport123",
            ""
        );
    }

    function test_CompleteDistributionWithMultipleDonors() public {
        _setupStandardZakatOrganization();
        
        // Multiple donors donate
        _donateZakat(i_donor, 1000e6, "First donor");
        _donateZakat(i_donor2, 800e6, "Second donor");

        _proposeStandardDistribution();
        _approveDistribution(0, 600e6);
        _distributeZakat(0);

        vm.expectEmit(true, true, true, true);
        emit Zakat.ZakatNFTCertificatesMinted(0, 2); // 2 donors

        vm.prank(address(i_qrbnTimelock));
        i_zakat.completeDistributionAndMintCertificates(
            0,
            120,
            "https://ipfs.io/ipfs/QmReport123",
            "https://api.qrbn.com/certificates"
        );

        // Verify both donors received NFTs
        (, , , , , uint256 nftId1, , bool isDistributed1, ) = i_zakat.s_zakatDonations(0);
        (, , , , , uint256 nftId2, , bool isDistributed2, ) = i_zakat.s_zakatDonations(1);

        assertGt(nftId1, 0);
        assertGt(nftId2, 0);
        assertEq(isDistributed1, true);
        assertEq(isDistributed2, true);
        assertEq(i_zakatNFT.ownerOf(nftId1), i_donor);
        assertEq(i_zakatNFT.ownerOf(nftId2), i_donor2);
    }

    // ============ CONFIGURATION TESTS ============

    function test_SetZakatPlatformFee() public {
        uint256 newFeeBps = 500; // 5%
        uint256 oldFeeBps = i_zakat.s_platformFeeBps();

        vm.expectEmit(true, true, true, true);
        emit Zakat.ZakatPlatformFeeUpdated(oldFeeBps, newFeeBps);
        vm.prank(address(i_qrbnTimelock));
        i_zakat.setZakatPlatformFee(newFeeBps);

        assertEq(i_zakat.s_platformFeeBps(), newFeeBps);
    }

    function test_SetZakatPlatformFeeExceedsMaximum() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidAmount.selector, "platformFee")
        );
        vm.prank(address(i_qrbnTimelock));
        i_zakat.setZakatPlatformFee(1001); // Over 10%
    }

    function test_SetZakatPlatformFeeByNonGov() public {
        vm.expectRevert();
        vm.prank(i_founder);
        i_zakat.setZakatPlatformFee(300);
    }

    // ============ VIEW FUNCTION TESTS ============

    function test_GetDistributionsByStatus() public {
        _setupStandardZakatOrganizationWithFunds();
        
        // Create multiple distributions with different statuses
        _proposeStandardDistribution(); // Distribution 0 - PENDING
        _proposeDistribution("Food for Orphans", 300e6, 50); // Distribution 1 - PENDING
        
        _approveDistribution(0, 400e6); // Distribution 0 - APPROVED
        _distributeZakat(0); // Distribution 0 - DISTRIBUTED

        // Test pending distributions
        uint256[] memory pendingDistributions = i_zakat.getDistributionsByStatus(
            Zakat.DistributionStatus.PENDING
        );
        assertEq(pendingDistributions.length, 1);
        assertEq(pendingDistributions[0], 1);

        // Test approved distributions (none, since we distributed it)
        uint256[] memory approvedDistributions = i_zakat.getDistributionsByStatus(
            Zakat.DistributionStatus.APPROVED
        );
        assertEq(approvedDistributions.length, 0);

        // Test distributed distributions
        uint256[] memory distributedDistributions = i_zakat.getDistributionsByStatus(
            Zakat.DistributionStatus.DISTRIBUTED
        );
        assertEq(distributedDistributions.length, 1);
        assertEq(distributedDistributions[0], 0);
    }

    function test_GetOrganizationDistributions() public {
        _setupStandardZakatOrganizationWithFunds();
        _setupAnotherZakatOrganization();

        // Create distributions for different organizations
        _proposeStandardDistribution(); // Org 1
        vm.prank(address(i_qrbnTimelock));
        i_zakat.proposeDistribution(
            i_anotherZakatOrg,
            200e6,
            40,
            Zakat.DistributionType.CASH,
            "Cash Assistance",
            "Direct cash help",
            "Bandung"
        ); // Org 2

        uint256[] memory org1Distributions = i_zakat.getOrganizationDistributions(i_zakatOrg);
        uint256[] memory org2Distributions = i_zakat.getOrganizationDistributions(i_anotherZakatOrg);

        assertEq(org1Distributions.length, 1);
        assertEq(org2Distributions.length, 1);
        assertEq(org1Distributions[0], 0);
        assertEq(org2Distributions[0], 1);
    }

    function test_GetDonorDonations() public {
        _donateZakat(i_donor, 1000e6, "First");
        _donateZakat(i_donor, 500e6, "Second");
        _donateZakat(i_donor2, 800e6, "From donor2");

        uint256[] memory donor1Donations = i_zakat.getDonorDonations(i_donor);
        uint256[] memory donor2Donations = i_zakat.getDonorDonations(i_donor2);

        assertEq(donor1Donations.length, 2);
        assertEq(donor2Donations.length, 1);
        assertEq(donor1Donations[0], 0);
        assertEq(donor1Donations[1], 1);
        assertEq(donor2Donations[0], 2);
    }

    function test_GetTotalCounts() public {
        _setupStandardZakatOrganizationWithFunds();
        _proposeStandardDistribution();

        (uint256 totalDonations, uint256 totalDistributions, uint256 totalOrganizations) = i_zakat.getTotalCounts();
        assertEq(totalDonations, 1); // From setup
        assertEq(totalDistributions, 1);
        assertEq(totalOrganizations, 1);
    }

    function test_CalculateDonationAmounts() public view {
        uint256 amount = 1000e6;
        (uint256 netAmount, uint256 platformFee) = i_zakat.calculateDonationAmounts(amount);
        
        uint256 expectedFee = (amount * 250) / 10000; // 2.5%
        uint256 expectedNet = amount - expectedFee;
        
        assertEq(platformFee, expectedFee);
        assertEq(netAmount, expectedNet);
    }

    function test_IsOrganizationRegistered() public {
        assertEq(i_zakat.isOrganizationRegistered(i_zakatOrg), false);
        
        _setupStandardZakatOrganization();
        
        assertEq(i_zakat.isOrganizationRegistered(i_zakatOrg), true);
    }

    function test_GetOrganizationInfo() public {
        _setupStandardZakatOrganization();

        Zakat.ZakatOrganization memory orgInfo = i_zakat.getOrganizationInfo(i_zakatOrg);
        
        assertEq(orgInfo.id, 0);
        assertEq(orgInfo.walletAddress, i_zakatOrg);
        assertEq(orgInfo.name, "Jakarta Food Bank");
        assertEq(orgInfo.isVerified, true);
        assertEq(orgInfo.totalDistributed, 0);
        assertEq(orgInfo.totalBeneficiaries, 0);
    }

    function test_GetDonationInfo() public {
        _donateZakat(i_donor, 1000e6, "Test donation");

        Zakat.ZakatDonation memory donationInfo = i_zakat.getDonationInfo(0);
        
        assertEq(donationInfo.id, 0);
        assertEq(donationInfo.donor, i_donor);
        assertEq(donationInfo.amount, 1000e6);
        assertEq(donationInfo.donorMessage, "Test donation");
        assertEq(donationInfo.isDistributed, false);
    }

    function test_GetDistributionInfo() public {
        _setupStandardZakatOrganizationWithFunds();
        _proposeStandardDistribution();

        Zakat.ZakatDistribution memory distributionInfo = i_zakat.getDistributionInfo(0);
        
        assertEq(distributionInfo.id, 0);
        assertEq(distributionInfo.organizationAddress, i_zakatOrg);
        assertEq(distributionInfo.requestedAmount, 500e6);
        assertEq(distributionInfo.title, "Food Distribution for Poor Families");
        assertEq(uint8(distributionInfo.status), uint8(Zakat.DistributionStatus.PENDING));
    }

    // ============ ZAKAT NFT TESTS ============

    function test_ZakatNFTMinting() public {
        string memory tokenUri = "https://api.qrbn.com/zakat-nft/1";
        
        vm.expectEmit(true, true, true, true);
        emit ZakatNFT.ZakatCertificateMinted(i_donor, 1, tokenUri);
        vm.prank(address(i_zakat));
        uint256 tokenId = i_zakatNFT.safeMint(i_donor, tokenUri);
        
        assertEq(tokenId, 1);
        assertEq(i_zakatNFT.ownerOf(tokenId), i_donor);
        assertEq(i_zakatNFT.tokenURI(tokenId), tokenUri);
        assertEq(i_zakatNFT.balanceOf(i_donor), 1);
    }

    function test_ZakatNFTGetTokensByOwner() public {
        // Mint multiple NFTs to donor
        vm.prank(address(i_zakat));
        i_zakatNFT.safeMint(i_donor, "uri1");
        vm.prank(address(i_zakat));
        i_zakatNFT.safeMint(i_donor, "uri2");
        vm.prank(address(i_zakat));
        i_zakatNFT.safeMint(i_zakatOrg, "uri3");

        uint256[] memory donorTokens = i_zakatNFT.getTokensByOwner(i_donor);
        assertEq(donorTokens.length, 2);
        assertEq(donorTokens[0], 1);
        assertEq(donorTokens[1], 2);

        uint256[] memory orgTokens = i_zakatNFT.getTokensByOwner(i_zakatOrg);
        assertEq(orgTokens.length, 1);
        assertEq(orgTokens[0], 3);
    }

    function test_ZakatNFTNonGovCannotMint() public {
        vm.expectRevert();
        vm.prank(i_donor);
        i_zakatNFT.safeMint(i_donor, "uri");
    }

    function test_ZakatNFTGetNextTokenId() public view {
        assertEq(i_zakatNFT.getNextTokenId(), 1);
    }

    // ============ INTEGRATION TESTS ============

    function test_FullZakatWorkflow() public {
        // 1. Register organization
        _setupStandardZakatOrganization();

        // 2. Multiple donors donate
        _donateZakat(i_donor, 1000e6, "First donation");
        _donateZakat(i_donor2, 500e6, "Second donation");

        // 3. Propose distribution
        _proposeStandardDistribution();

        // 4. Approve distribution
        uint256 approvedAmount = 800e6;
        _approveDistribution(0, approvedAmount);

        // 5. Distribute zakat
        _distributeZakat(0);

        // 6. Complete and mint certificates
        vm.prank(address(i_qrbnTimelock));
        i_zakat.completeDistributionAndMintCertificates(
            0,
            120,
            "https://ipfs.io/ipfs/QmReport123",
            "https://api.qrbn.com/certificates"
        );

        // Verify final state
        assertEq(i_zakat.s_totalDistributedZakat(), approvedAmount);
        assertEq(i_zakatNFT.balanceOf(i_donor), 1);
        assertEq(i_zakatNFT.balanceOf(i_donor2), 1);
        
        // Verify organization received funds
        assertEq(i_mockUSDC.balanceOf(i_zakatOrg), approvedAmount);

        // Verify organization stats
        (, , , , , , , , uint256 totalDistributed, uint256 totalBeneficiaries, ) = i_zakat.s_zakatOrganizations(i_zakatOrg);
        assertEq(totalDistributed, approvedAmount);
        assertEq(totalBeneficiaries, 120);
    }

    // ============ HELPER FUNCTIONS ============

    function _setupStandardZakatOrganization() internal {
        vm.prank(address(i_qrbnTimelock));
        i_zakat.registerZakatOrganization(
            i_zakatOrg,
            "Jakarta Food Bank",
            "contact@jakartafoodbank.org",
            "Jakarta, Indonesia",
            "Distributes food to poor families in Jakarta",
            "REG-JFB-2024"
        );
    }

    function _setupAnotherZakatOrganization() internal {
        vm.prank(address(i_qrbnTimelock));
        i_zakat.registerZakatOrganization(
            i_anotherZakatOrg,
            "Bandung Orphanage",
            "contact@bandungorphanage.org",
            "Bandung, Indonesia",
            "Supports orphaned children in Bandung",
            "REG-BO-2024"
        );
    }

    function _setupStandardZakatOrganizationWithFunds() internal {
        _setupStandardZakatOrganization();
        _donateZakat(i_donor, 1000e6, "Test donation for distribution");
    }

    function _donateZakat(address donor, uint256 amount, string memory message) internal {
        vm.prank(donor);
        i_mockUSDC.approve(address(i_zakat), amount);
        vm.prank(donor);
        i_zakat.donateZakat(amount, message);
    }

    function _proposeStandardDistribution() internal {
        vm.prank(address(i_qrbnTimelock));
        i_zakat.proposeDistribution(
            i_zakatOrg,
            500e6,
            100,
            Zakat.DistributionType.MIXED,
            "Food Distribution for Poor Families",
            "Providing rice, oil, and basic necessities to 100 poor families",
            "Jakarta Selatan"
        );
    }

    function _proposeDistribution(string memory title, uint256 amount, uint256 beneficiaries) internal {
        vm.prank(address(i_qrbnTimelock));
        i_zakat.proposeDistribution(
            i_zakatOrg,
            amount,
            beneficiaries,
            Zakat.DistributionType.FOOD,
            title,
            "Distribution description",
            "Jakarta"
        );
    }

    function _approveDistribution(uint256 distributionId, uint256 amount) internal {
        vm.prank(address(i_qrbnTimelock));
        i_zakat.approveDistribution(distributionId, amount);
    }

    function _distributeZakat(uint256 distributionId) internal {
        vm.prank(address(i_qrbnTimelock));
        i_zakat.distributeZakat(distributionId);
    }
}