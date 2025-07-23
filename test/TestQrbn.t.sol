// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Qurban} from "../src/qurban/Qurban.sol";
import {Errors} from "../src/lib/Errors.sol";
import {QurbanNFT} from "../src/qurban/QurbanNFT.sol";
import {QrbnToken} from "../src/dao/QrbnToken.sol";
import {QrbnGov} from "../src/dao/QrbnGov.sol";
import {QrbnTreasury} from "../src/dao/QrbnTreasury.sol";
import {QrbnTimelock} from "../src/dao/QrbnTimelock.sol";
import {DeployQrbn} from "../script/DeployQrbn.s.sol";
import {DeployConfig} from "../script/DeployConfig.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {Constants} from "../src/lib/Constants.sol";

contract TestQrbn is Test {
    QrbnTreasury i_qrbnTreasury;
    QrbnTimelock i_qrbnTimelock;
    QrbnToken i_qrbnToken;
    QrbnGov i_qrbnGov;
    QurbanNFT i_qurbanNFT;
    Qurban i_qurban;
    MockUSDC i_mockUSDC;

    address immutable i_deployer = address(this);
    address immutable i_founder = makeAddr("founder");
    address immutable i_syariahCouncil = makeAddr("syariahCouncil");
    address immutable i_communityRep = makeAddr("communityRep");
    address immutable i_orgRep = makeAddr("orgRep");
    address immutable i_buyer = makeAddr("buyer");
    address immutable i_vendor = makeAddr("vendor");
    address immutable i_anotherVendor = makeAddr("anotherVendor");

    function setUp() public {
        DeployConfig deployConfig = new DeployConfig(i_deployer, i_deployer);
        DeployConfig.NetworkConfig memory networkConfig = deployConfig
            .getNetworkConfig();

        DeployQrbn deployScript = new DeployQrbn();
        (
            i_qrbnTimelock,
            i_qrbnGov,
            i_qrbnToken,
            i_qurban,
            i_qurbanNFT,
            ,
            ,
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

        if (
            block.chainid != Constants.LISK_CHAINID &&
            block.chainid != Constants.LISK_SEPOLIA_CHAINID
        ) {
            i_mockUSDC.mint(i_buyer, 10000e6);
        }
    }

    // ============ ROLE TESTS ============

    function test_GovRoleIsTimelockContract() public view {
        assertEq(
            i_qurban.hasRole(i_qurban.GOVERNER_ROLE(), address(i_qrbnTimelock)),
            true
        );
    }

    function test_GovRoleIsDeployerInTestnet() public view {
        if (block.chainid != Constants.LISK_CHAINID) {
            assertEq(
                i_qurban.hasRole(i_qurban.GOVERNER_ROLE(), i_deployer),
                true
            );
        }
    }

    function test_QrbnNFTGovIsTimelockContract() public view {
        assertEq(
            i_qurbanNFT.hasRole(
                i_qurbanNFT.GOVERNER_ROLE(),
                address(i_qrbnTimelock)
            ),
            true
        );
    }

    function test_QrbnNFTGovIsQurbanContract() public view {
        assertEq(
            i_qurbanNFT.hasRole(i_qurbanNFT.GOVERNER_ROLE(), address(i_qurban)),
            true
        );
    }

    function test_QrbnNFTAdminIsRevoked() public view {
        if (block.chainid == Constants.LISK_CHAINID) {
            assertEq(
                i_qurbanNFT.hasRole(
                    i_qurbanNFT.DEFAULT_ADMIN_ROLE(),
                    i_deployer
                ),
                false
            );
        }
    }

    function test_QrbnTokenGovIsTimelockContract() public view {
        assertEq(
            i_qrbnToken.hasRole(
                i_qrbnToken.GOVERNER_ROLE(),
                address(i_qrbnTimelock)
            ),
            true
        );
    }

    function test_QrbnTokenAdminIsRevoked() public view {
        assertEq(
            i_qrbnToken.hasRole(i_qrbnToken.DEFAULT_ADMIN_ROLE(), i_deployer),
            false
        );
    }

    function test_InitialTokenBalances() public view {
        uint256 expectedBalance = 1 * 10 ** i_qrbnToken.decimals();
        assertEq(i_qrbnToken.balanceOf(i_founder), expectedBalance);
        assertEq(i_qrbnToken.balanceOf(i_syariahCouncil), expectedBalance);
        assertEq(i_qrbnToken.balanceOf(i_orgRep), expectedBalance);
        assertEq(i_qrbnToken.balanceOf(i_communityRep), expectedBalance);
    }

    // ============ VENDOR REGISTRATION TESTS ============

    function test_RegisterVendorByNonGov() public {
        vm.expectRevert();
        vm.prank(i_founder);
        i_qurban.registerVendor(i_vendor, "NAME", "CONTACT", "LOCATION");
    }

    function test_RegisterVendorByTimelock() public {
        vm.expectEmit(true, true, true, true);
        emit Qurban.VendorRegistered(i_vendor, 0, "NAME");
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_vendor, "NAME", "CONTACT", "LOCATION");

        // Verify vendor data
        assertEq(i_qurban.s_registeredVendors(i_vendor), true);

        (
            uint256 id,
            address walletAddress,
            string memory name,
            string memory contactInfo,
            string memory location,
            bool isVerified,
            uint256 totalSales,
            uint256 registeredAt
        ) = i_qurban.s_vendors(i_vendor);

        assertEq(id, 0);
        assertEq(walletAddress, i_vendor);
        assertEq(name, "NAME");
        assertEq(contactInfo, "CONTACT");
        assertEq(location, "LOCATION");
        assertEq(isVerified, true);
        assertEq(totalSales, 0);
        assertGt(registeredAt, 0);
        // Vendors no longer get tokens when they register
        assertEq(i_qrbnToken.balanceOf(i_vendor), 0);
    }

    function test_RegisterVendorByDeployerInTestnet() public {
        if (block.chainid != Constants.LISK_CHAINID) {
            vm.expectEmit(true, true, true, true);
            emit Qurban.VendorRegistered(i_vendor, 0, "NAME");
            i_qurban.registerVendor(i_vendor, "NAME", "CONTACT", "LOCATION");

            assertEq(i_qurban.s_registeredVendors(i_vendor), true);
            // Vendors no longer get tokens when they register
            assertEq(i_qrbnToken.balanceOf(i_vendor), 0);
        }
    }

    function test_RegisterVendorWithZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.AddressZero.selector, "vendorAddress")
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(address(0), "NAME", "CONTACT", "LOCATION");
    }

    function test_RegisterVendorTwice() public {
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_vendor, "NAME", "CONTACT", "LOCATION");

        vm.expectRevert(
            abi.encodeWithSelector(Errors.AlreadyRegistered.selector, "vendor")
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_vendor, "NAME2", "CONTACT2", "LOCATION2");
    }

    function test_RegisterVendorWithEmptyName() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EmptyString.selector, "name")
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_vendor, "", "CONTACT", "LOCATION");
    }

    // ============ VENDOR EDITING TESTS ============

    function test_EditVendorByTimelock() public {
        // First register vendor
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_vendor, "NAME", "CONTACT", "LOCATION");

        // Edit vendor
        vm.expectEmit(true, true, true, true);
        emit Qurban.VendorEdited(i_vendor, 0, "NEW NAME");
        vm.prank(address(i_qrbnTimelock));
        i_qurban.editVendor(
            i_vendor,
            "NEW NAME",
            "NEW CONTACT",
            "NEW LOCATION"
        );

        // Verify changes
        (
            ,
            ,
            string memory name,
            string memory contactInfo,
            string memory location,
            ,
            ,

        ) = i_qurban.s_vendors(i_vendor);
        assertEq(name, "NEW NAME");
        assertEq(contactInfo, "NEW CONTACT");
        assertEq(location, "NEW LOCATION");
    }

    function test_EditVendorByNonGov() public {
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_vendor, "NAME", "CONTACT", "LOCATION");

        vm.expectRevert();
        vm.prank(i_founder);
        i_qurban.editVendor(
            i_vendor,
            "NEW NAME",
            "NEW CONTACT",
            "NEW LOCATION"
        );
    }

    function test_EditVendorNotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NotRegistered.selector, "vendor")
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.editVendor(i_vendor, "NAME", "CONTACT", "LOCATION");
    }

    function test_EditVendorWithEmptyName() public {
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_vendor, "NAME", "CONTACT", "LOCATION");

        vm.expectRevert(
            abi.encodeWithSelector(Errors.EmptyString.selector, "name")
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.editVendor(i_vendor, "", "CONTACT", "LOCATION");
    }

    // ============ VENDOR VERIFICATION TESTS ============

    function test_VerifyVendor() public {
        // Register vendor and unverify first
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_vendor, "NAME", "CONTACT", "LOCATION");

        vm.prank(address(i_qrbnTimelock));
        i_qurban.unverifyVendor(i_vendor);

        // Now verify
        vm.expectEmit(true, true, true, true);
        emit Qurban.VendorVerifyUpdated(i_vendor, 0, true);
        vm.prank(address(i_qrbnTimelock));
        i_qurban.verifyVendor(i_vendor);

        // Check verification status and token balance
        (, , , , , bool isVerified, , ) = i_qurban.s_vendors(i_vendor);
        assertEq(isVerified, true);
        // Vendors don't get tokens when verified anymore
        assertEq(i_qrbnToken.balanceOf(i_vendor), 0);
    }

    function test_VerifyVendorAlreadyVerified() public {
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_vendor, "NAME", "CONTACT", "LOCATION");

        vm.expectRevert(
            abi.encodeWithSelector(Errors.AlreadyVerified.selector, "vendor")
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.verifyVendor(i_vendor);
    }

    function test_VerifyVendorNotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NotRegistered.selector, "vendor")
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.verifyVendor(i_vendor);
    }

    function test_UnverifyVendor() public {
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_vendor, "NAME", "CONTACT", "LOCATION");

        vm.expectEmit(true, true, true, true);
        emit Qurban.VendorVerifyUpdated(i_vendor, 0, false);
        vm.prank(address(i_qrbnTimelock));
        i_qurban.unverifyVendor(i_vendor);

        // Check verification status and token balance
        (, , , , , bool isVerified, , ) = i_qurban.s_vendors(i_vendor);
        assertEq(isVerified, false);
        // Vendors don't have tokens to be burned anymore
        assertEq(i_qrbnToken.balanceOf(i_vendor), 0);
    }

    function test_UnverifyVendorAlreadyUnverified() public {
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_vendor, "NAME", "CONTACT", "LOCATION");

        vm.prank(address(i_qrbnTimelock));
        i_qurban.unverifyVendor(i_vendor);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.AlreadyUnverified.selector, "vendor")
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.unverifyVendor(i_vendor);
    }

    // ============ ANIMAL MANAGEMENT TESTS ============

    function test_AddAnimal() public {
        // Register vendor first
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_orgRep, "NAME", "CONTACT", "LOCATION");

        uint256 futureDate = block.timestamp + 30 days;

        vm.expectEmit(true, true, true, true);
        emit Qurban.AnimalAdded(0, i_orgRep, "Sheep Name");
        vm.prank(address(i_qrbnTimelock));
        i_qurban.addAnimal(
            i_orgRep,
            "Sheep Name",
            Qurban.AnimalType.SHEEP,
            7,
            100e6,
            "Farm Location",
            "image.jpg",
            "Description",
            "Breed",
            50,
            2,
            "Farm Name",
            futureDate
        );

        // Verify animal data
        (
            uint256 id,
            string memory name,
            Qurban.AnimalType animalType,
            uint8 totalShares,
            uint8 availableShares,
            uint256 pricePerShare,
            string memory location,
            string memory image,
            string memory description,
            string memory breed,
            uint16 weight,
            uint16 age,
            string memory farmName,
            uint256 sacrificeDate,
            Qurban.AnimalStatus status,
            address vendorAddress,
            uint256 createdAt
        ) = i_qurban.s_animals(0);

        assertEq(id, 0);
        assertEq(name, "Sheep Name");
        assertEq(uint8(animalType), uint8(Qurban.AnimalType.SHEEP));
        assertEq(totalShares, 7);
        assertEq(availableShares, 7);
        assertEq(pricePerShare, 100e6);
        assertEq(location, "Farm Location");
        assertEq(image, "image.jpg");
        assertEq(description, "Description");
        assertEq(breed, "Breed");
        assertEq(weight, 50);
        assertEq(age, 2);
        assertEq(farmName, "Farm Name");
        assertEq(sacrificeDate, futureDate);
        assertEq(uint8(status), uint8(Qurban.AnimalStatus.AVAILABLE));
        assertEq(vendorAddress, i_orgRep);
        assertGt(createdAt, 0);

        // Check vendor's animal list
        assertEq(i_qurban.s_vendorAnimalIds(i_orgRep, 0), 0);
    }

    function test_AddAnimalByNonGov() public {
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_orgRep, "NAME", "CONTACT", "LOCATION");

        vm.expectRevert();
        vm.prank(i_founder);
        i_qurban.addAnimal(
            i_orgRep,
            "Sheep Name",
            Qurban.AnimalType.SHEEP,
            10,
            100e6,
            "Farm Location",
            "image.jpg",
            "Description",
            "Breed",
            50,
            2,
            "Farm Name",
            block.timestamp + 30 days
        );
    }

    function test_AddAnimalWithUnregisteredVendor() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NotRegistered.selector, "vendor")
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.addAnimal(
            i_orgRep,
            "Sheep Name",
            Qurban.AnimalType.SHEEP,
            10,
            100e6,
            "Farm Location",
            "image.jpg",
            "Description",
            "Breed",
            50,
            2,
            "Farm Name",
            block.timestamp + 30 days
        );
    }

    function test_AddAnimalWithInvalidData() public {
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_orgRep, "NAME", "CONTACT", "LOCATION");

        // Test empty name
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EmptyString.selector, "name")
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.addAnimal(
            i_orgRep,
            "",
            Qurban.AnimalType.SHEEP,
            7,
            100e6,
            "Farm Location",
            "image.jpg",
            "Description",
            "Breed",
            50,
            2,
            "Farm Name",
            block.timestamp + 30 days
        );

        // Test zero shares
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidAmount.selector, "totalShares")
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.addAnimal(
            i_orgRep,
            "Sheep Name",
            Qurban.AnimalType.SHEEP,
            0,
            100e6,
            "Farm Location",
            "image.jpg",
            "Description",
            "Breed",
            50,
            2,
            "Farm Name",
            block.timestamp + 30 days
        );

        // Test past date
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidDate.selector, "sacrificeDate")
        );
        vm.warp(block.timestamp + 30 days);
        vm.prank(address(i_qrbnTimelock));
        i_qurban.addAnimal(
            i_orgRep,
            "Sheep Name",
            Qurban.AnimalType.SHEEP,
            7,
            100e6,
            "Farm Location",
            "image.jpg",
            "Description",
            "Breed",
            50,
            2,
            "Farm Name",
            block.timestamp - 1 days
        );
    }

    function test_EditAnimal() public {
        // Register vendor and add animal
        _setupStandardVendorWithAnimal();

        // Edit animal
        uint256 newFutureDate = block.timestamp + 60 days;
        vm.expectEmit(true, true, true, true);
        emit Qurban.AnimalUpdated(0, address(i_qrbnTimelock), "New Sheep Name");
        vm.prank(address(i_qrbnTimelock));
        i_qurban.editAnimal(
            i_vendor,
            0,
            "New Sheep Name",
            Qurban.AnimalType.COW,
            5,
            200e6,
            "New Farm Location",
            "newimage.jpg",
            "New Description",
            "New Breed",
            60,
            3,
            "New Farm Name",
            newFutureDate
        );

        // Verify changes
        (
            ,
            string memory name,
            Qurban.AnimalType animalType,
            uint8 totalShares,
            uint8 availableShares,
            uint256 pricePerShare,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 sacrificeDate,
            ,
            ,

        ) = i_qurban.s_animals(0);
        assertEq(name, "New Sheep Name");
        assertEq(uint8(animalType), uint8(Qurban.AnimalType.COW));
        assertEq(totalShares, 5);
        assertEq(availableShares, 5);
        assertEq(pricePerShare, 200e6);
        assertEq(sacrificeDate, newFutureDate);
    }

    function test_EditAnimalWrongVendor() public {
        _setupStandardVendorWithAnimal();
        _registerVendor(i_anotherVendor);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Forbidden.selector, "vendorAddress")
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.editAnimal(
            i_anotherVendor,
            0,
            "New Sheep Name",
            Qurban.AnimalType.COW,
            15,
            200e6,
            "New Farm Location",
            "newimage.jpg",
            "New Description",
            "New Breed",
            60,
            3,
            "New Farm Name",
            block.timestamp + 60 days
        );
    }

    function test_ApproveAnimal() public {
        // Register vendor and add animal
        _setupStandardVendorWithAnimal();

        // Unapprove first
        vm.prank(address(i_qrbnTimelock));
        i_qurban.unapproveAnimal(0);

        // Now approve
        vm.expectEmit(true, true, true, true);
        emit Qurban.AnimalStatusUpdated(0, Qurban.AnimalStatus.AVAILABLE);
        vm.prank(address(i_qrbnTimelock));
        i_qurban.approveAnimal(0);

        // Verify status
        (, , , , , , , , , , , , , , Qurban.AnimalStatus status, , ) = i_qurban
            .s_animals(0);
        assertEq(uint8(status), uint8(Qurban.AnimalStatus.AVAILABLE));
    }

    function test_ApproveAnimalAlreadyApproved() public {
        _setupStandardVendorWithAnimal();

        vm.expectRevert(
            abi.encodeWithSelector(Errors.AlreadyAvailable.selector, "animal")
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.approveAnimal(0);
    }

    function test_UnapproveAnimal() public {
        _setupStandardVendorWithAnimal();

        vm.expectEmit(true, true, true, true);
        emit Qurban.AnimalStatusUpdated(0, Qurban.AnimalStatus.PENDING);
        vm.prank(address(i_qrbnTimelock));
        i_qurban.unapproveAnimal(0);

        // Verify status
        (, , , , , , , , , , , , , , Qurban.AnimalStatus status, , ) = i_qurban
            .s_animals(0);
        assertEq(uint8(status), uint8(Qurban.AnimalStatus.PENDING));
    }

    // ============ PURCHASE TESTS ============

    function test_PurchaseAnimalShares() public {
        // Setup
        _setupStandardVendorWithAnimal();

        vm.prank(i_buyer);
        i_mockUSDC.approve(address(i_qurban), 500e6);

        // Purchase shares
        vm.expectEmit(true, true, true, true);
        emit Qurban.AnimalPurchased(i_buyer, 0, 0);
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 5);

        // Verify purchase
        (
            uint256 txId,
            uint256 animalId,
            uint256 nftCertificateId,
            uint256 pricePerShare,
            uint256 totalPaid,
            uint256 fee,
            uint256 vendorShare,
            uint256 timestamp,
            uint8 shareAmount,
            address buyer
        ) = i_qurban.s_buyerTransactions(0);

        assertEq(txId, 0);
        assertEq(animalId, 0);
        assertEq(nftCertificateId, 0);
        assertEq(pricePerShare, 100e6);
        assertEq(totalPaid, 500e6);
        assertEq(fee, (500e6 * 250) / 10000);
        assertEq(vendorShare, 500e6 - fee);
        assertEq(shareAmount, 5);
        assertEq(buyer, i_buyer);
        assertGt(timestamp, 0);

        // Check animal available shares
        (, , , , uint8 availableShares, , , , , , , , , , , , ) = i_qurban
            .s_animals(0);
        assertEq(availableShares, 2); // 7 total shares - 5 purchased = 2 remaining

        // Check buyer transaction IDs
        assertEq(i_qurban.s_buyerTransactionIds(i_buyer, 0), 0);

        // Check vendor sales
        (, , , , , , uint256 totalSales, ) = i_qurban.s_vendors(i_vendor);
        uint256 expectedVendorShare = 500e6 - fee;
        assertEq(totalSales, expectedVendorShare);

        // Check buyer tracking
        address[] memory buyers = i_qurban.getAnimalBuyers(0);
        assertEq(buyers.length, 1);
        assertEq(buyers[0], i_buyer);

        uint256[] memory buyerTransactions = i_qurban
            .getAnimalBuyerTransactionsIds(0, i_buyer);
        assertEq(buyerTransactions.length, 1);
        assertEq(buyerTransactions[0], 0);
    }

    function test_PurchaseAnimalSharesFullySold() public {
        // Setup
        _setupStandardVendorWithAnimal();

        vm.prank(i_buyer);
        i_mockUSDC.approve(address(i_qurban), 1000e6);

        // Purchase all shares
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 7);

        // Verify animal status changed to SOLD
        (
            ,
            ,
            ,
            ,
            uint8 availableShares,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            Qurban.AnimalStatus status,
            ,

        ) = i_qurban.s_animals(0);
        assertEq(availableShares, 0);
        assertEq(uint8(status), uint8(Qurban.AnimalStatus.SOLD));
    }

    function test_PurchaseAnimalSharesNotAvailable() public {
        _setupStandardVendorWithAnimal();

        // Unapprove animal
        vm.prank(address(i_qrbnTimelock));
        i_qurban.unapproveAnimal(0);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.NotAvailable.selector, "animal")
        );
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 5);
    }

    function test_PurchaseAnimalSharesInvalidAmount() public {
        _setupStandardVendorWithAnimal();

        // Test zero shares
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidAmount.selector, "shareAmount")
        );
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 0);

        // Test more shares than available
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidAmount.selector, "shareAmount")
        );
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 8); // Trying to buy 8 shares when only 7 are available
    }

    // ============ NFT CERTIFICATE MINTING TESTS ============

    function test_MarkAnimalSacrificedAndMintCertificates() public {
        // Setup animal and purchase shares
        _setupStandardVendorWithAnimal();

        // Multiple buyers purchase shares
        address buyer2 = makeAddr("buyer2");
        i_mockUSDC.mint(buyer2, 1000e6);

        vm.startPrank(i_buyer);
        i_mockUSDC.approve(address(i_qurban), 500e6);
        i_qurban.purchaseAnimalShares(0, 5);
        vm.stopPrank();

        vm.startPrank(buyer2);
        i_mockUSDC.approve(address(i_qurban), 200e6);
        i_qurban.purchaseAnimalShares(0, 2);
        vm.stopPrank();

        // Verify animal is sold
        (, , , , , , , , , , , , , , Qurban.AnimalStatus status, , ) = i_qurban
            .s_animals(0);
        assertEq(uint8(status), uint8(Qurban.AnimalStatus.SOLD));

        // Mark as sacrificed and mint certificates
        string memory certificateURI = "https://api.qrbn.com/certificates";

        vm.expectEmit(true, true, true, true);
        emit Qurban.VendorShareDistributed(i_vendor, 0, 682500000);
        vm.expectEmit(true, true, true, true);
        emit Qurban.AnimalSacrificed(0, block.timestamp);
        vm.expectEmit(true, true, true, true);
        emit Qurban.NFTCertificatesMinted(0, 2);

        vm.prank(address(i_qrbnTimelock));
        i_qurban.markAnimalSacrificedAndMintCertificates(0, certificateURI);

        // Verify animal status
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            Qurban.AnimalStatus newStatus,
            ,

        ) = i_qurban.s_animals(0);
        assertEq(uint8(newStatus), uint8(Qurban.AnimalStatus.SACRIFICED));

        // Verify NFT certificates were minted
        (, , uint256 nftCertId1, , , , , , , ) = i_qurban.s_buyerTransactions(
            0
        );
        (, , uint256 nftCertId2, , , , , , , ) = i_qurban.s_buyerTransactions(
            1
        );

        assertGt(nftCertId1, 0);
        assertGt(nftCertId2, 0);
        assertNotEq(nftCertId1, nftCertId2);

        // Verify NFT ownership
        assertEq(i_qurbanNFT.ownerOf(nftCertId1), i_buyer);
        assertEq(i_qurbanNFT.ownerOf(nftCertId2), buyer2);
    }

    function test_MarkAnimalSacrificedAndMintCertificates_NotSold() public {
        _setupStandardVendorWithAnimal();

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.NotAvailable.selector,
                "animal for sacrifice"
            )
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.markAnimalSacrificedAndMintCertificates(
            0,
            "https://api.qrbn.com/certificates"
        );
    }

    function test_MarkAnimalSacrificedAndMintCertificates_EmptyURI() public {
        _setupStandardVendorWithAnimal();
        _purchaseAllShares();

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.EmptyString.selector,
                "certificateURI"
            )
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.markAnimalSacrificedAndMintCertificates(0, "");
    }

    function test_MarkAnimalSacrificedAndMintCertificates_NonGov() public {
        _setupStandardVendorWithAnimal();
        _purchaseAllShares();

        vm.expectRevert();
        vm.prank(i_buyer);
        i_qurban.markAnimalSacrificedAndMintCertificates(
            0,
            "https://api.qrbn.com/certificates"
        );
    }

    // ============ REFUND TESTS ============

    function test_RefundAnimalPurchases() public {
        // Setup and purchase
        _setupStandardVendorWithAnimal();

        address buyer2 = makeAddr("buyer2");
        i_mockUSDC.mint(buyer2, 1000e6);

        uint256 buyer1InitialBalance = i_mockUSDC.balanceOf(i_buyer);
        uint256 buyer2InitialBalance = i_mockUSDC.balanceOf(buyer2);

        vm.prank(i_buyer);
        i_mockUSDC.approve(address(i_qurban), 500e6);
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 5);

        vm.prank(buyer2);
        i_mockUSDC.approve(address(i_qurban), 200e6);
        vm.prank(buyer2);
        i_qurban.purchaseAnimalShares(0, 2);

        // Refund purchases
        string memory reason = "Animal is sick";

        vm.expectEmit(true, true, false, false);
        emit Qurban.BuyerRefunded(i_buyer, 0, 500e6, reason);
        vm.expectEmit(true, true, false, false);
        emit Qurban.BuyerRefunded(buyer2, 0, 200e6, reason);
        vm.expectEmit(true, true, false, false);
        emit Qurban.AnimalRefunded(0, 700e6, reason);

        vm.prank(address(i_qrbnTimelock));
        i_qurban.refundAnimalPurchases(0, reason);

        // Verify refunds
        assertEq(i_mockUSDC.balanceOf(i_buyer), buyer1InitialBalance);
        assertEq(i_mockUSDC.balanceOf(buyer2), buyer2InitialBalance);

        // Verify animal status reset
        (
            ,
            ,
            ,
            ,
            uint8 availableShares,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            Qurban.AnimalStatus status,
            ,

        ) = i_qurban.s_animals(0);
        assertEq(availableShares, 7);
        assertEq(uint8(status), uint8(Qurban.AnimalStatus.PENDING));

        // Verify transactions marked as refunded
        (, , uint256 nftCertId1, , , , , , , ) = i_qurban.s_buyerTransactions(
            0
        );
        (, , uint256 nftCertId2, , , , , , , ) = i_qurban.s_buyerTransactions(
            1
        );

        assertEq(nftCertId1, type(uint256).max);
        assertEq(nftCertId2, type(uint256).max);
    }

    function test_RefundAnimalPurchases_NotSold() public {
        _setupStandardVendorWithAnimal();

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.NotAvailable.selector,
                "animal for refund"
            )
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.refundAnimalPurchases(0, "Animal is sick");
    }

    function test_RefundAnimalPurchases_EmptyReason() public {
        _setupStandardVendorWithAnimal();
        _purchaseAllShares();

        vm.expectRevert(
            abi.encodeWithSelector(Errors.EmptyString.selector, "reason")
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.refundAnimalPurchases(0, "");
    }

    function test_RefundAnimalPurchases_NonGov() public {
        _setupStandardVendorWithAnimal();
        _purchaseAllShares();

        vm.expectRevert();
        vm.prank(i_buyer);
        i_qurban.refundAnimalPurchases(0, "Animal is sick");
    }

    // ============ GETTER FUNCTION TESTS ============

    function test_GetAvailableAnimals() public {
        // Setup multiple animals
        _setupStandardVendorWithAnimal(); // Animal 0
        _addSheepAnimal(i_vendor, "Animal 2", 5, 150e6); // Animal 1
        _addSheepAnimal(i_vendor, "Animal 3", 3, 200e6); // Animal 2

        // Unapprove one animal
        vm.prank(address(i_qrbnTimelock));
        i_qurban.unapproveAnimal(1);

        uint256[] memory availableAnimals = i_qurban.getAnimalsByStatus(
            Qurban.AnimalStatus.AVAILABLE
        );
        assertEq(availableAnimals.length, 2);
        assertEq(availableAnimals[0], 0);
        assertEq(availableAnimals[1], 2);
    }

    function test_GetAnimalsByStatus() public {
        // Setup multiple animals with different statuses
        _setupStandardVendorWithAnimal(); // Animal 0 - AVAILABLE
        _addSheepAnimal(i_vendor, "Animal 2", 5, 150e6); // Animal 1 - AVAILABLE
        _addSheepAnimal(i_vendor, "Animal 3", 3, 200e6); // Animal 2 - AVAILABLE

        // Change statuses
        vm.prank(address(i_qrbnTimelock));
        i_qurban.unapproveAnimal(1); // PENDING

        _purchaseAllSharesForAnimal(2); // SOLD

        // Test different status queries
        uint256[] memory availableAnimals = i_qurban.getAnimalsByStatus(
            Qurban.AnimalStatus.AVAILABLE
        );
        assertEq(availableAnimals.length, 1);
        assertEq(availableAnimals[0], 0);

        uint256[] memory pendingAnimals = i_qurban.getAnimalsByStatus(
            Qurban.AnimalStatus.PENDING
        );
        assertEq(pendingAnimals.length, 1);
        assertEq(pendingAnimals[0], 1);

        uint256[] memory soldAnimals = i_qurban.getAnimalsByStatus(
            Qurban.AnimalStatus.SOLD
        );
        assertEq(soldAnimals.length, 1);
        assertEq(soldAnimals[0], 2);
    }

    function test_GetVendorAnimals() public {
        _setupStandardVendorWithAnimal();
        _addSheepAnimal(i_vendor, "Animal 2", 5, 150e6);

        // Setup another vendor
        address vendor2 = makeAddr("vendor2");
        _setupVendorWithAnimal(vendor2, "Animal 3", 4, 120e6);

        uint256[] memory vendor1Animals = i_qurban.getVendorAnimals(i_vendor);
        assertEq(vendor1Animals.length, 2);
        assertEq(vendor1Animals[0], 0);
        assertEq(vendor1Animals[1], 1);

        uint256[] memory vendor2Animals = i_qurban.getVendorAnimals(vendor2);
        assertEq(vendor2Animals.length, 1);
        assertEq(vendor2Animals[0], 2);
    }

    function test_GetVendorAnimalsByStatus() public {
        _setupStandardVendorWithAnimal(); // Animal 0
        _addSheepAnimal(i_vendor, "Animal 2", 5, 150e6); // Animal 1
        _addSheepAnimal(i_vendor, "Animal 3", 3, 200e6); // Animal 2

        // Change one to pending
        vm.prank(address(i_qrbnTimelock));
        i_qurban.unapproveAnimal(1);

        uint256[] memory availableAnimals = i_qurban.getVendorAnimalsByStatus(
            i_vendor,
            Qurban.AnimalStatus.AVAILABLE
        );
        assertEq(availableAnimals.length, 2);
        assertEq(availableAnimals[0], 0);
        assertEq(availableAnimals[1], 2);

        uint256[] memory pendingAnimals = i_qurban.getVendorAnimalsByStatus(
            i_vendor,
            Qurban.AnimalStatus.PENDING
        );
        assertEq(pendingAnimals.length, 1);
        assertEq(pendingAnimals[0], 1);
    }

    function test_GetBuyerTransactionIds() public {
        _setupStandardVendorWithAnimal();

        // Buyer makes multiple purchases
        vm.prank(i_buyer);
        i_mockUSDC.approve(address(i_qurban), 500e6);
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 3);

        vm.prank(i_buyer);
        i_mockUSDC.approve(address(i_qurban), 200e6);
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 2);

        uint256[] memory buyerTransactions = i_qurban.getBuyerTransactionIds(
            i_buyer
        );
        assertEq(buyerTransactions.length, 2);
        assertEq(buyerTransactions[0], 0);
        assertEq(buyerTransactions[1], 1);
    }

    function test_IsVendorRegistered() public {
        assertEq(i_qurban.isVendorRegistered(i_vendor), false);

        _registerVendor(i_vendor);

        assertEq(i_qurban.isVendorRegistered(i_vendor), true);
    }

    function test_GetTotalAnimalsCount() public {
        assertEq(i_qurban.getTotalAnimalsCount(), 0);

        _setupStandardVendorWithAnimal();
        assertEq(i_qurban.getTotalAnimalsCount(), 1);

        _addSheepAnimal(i_vendor, "Animal 2", 5, 150e6);
        assertEq(i_qurban.getTotalAnimalsCount(), 2);
    }

    // ============ TOKEN TRANSFER TESTS ============

    function test_TokenTransferFails() public {
        TokenBalances memory balances = _getTokenBalances();

        // Try to transfer from founder to syariah council - should fail
        _expectTransferToFail(i_founder, i_syariahCouncil, 10);

        // Verify balances unchanged
        _assertBalancesUnchanged(balances);
    }

    function test_TokenTransferFromFails() public {
        TokenBalances memory balances = _getTokenBalances();

        // Founder approves syariah council to spend tokens
        _approveTokens(i_founder, i_syariahCouncil, 10);

        // Try transferFrom - should fail even with approval
        _expectTransferFromToFail(
            i_syariahCouncil,
            i_founder,
            i_communityRep,
            5
        );

        // Verify balances unchanged
        _assertBalancesUnchanged(balances);
    }

    function test_TokenMintingStillWorks() public {
        uint256 initialBalance = i_qrbnToken.balanceOf(i_buyer);
        assertEq(initialBalance, 0);

        // Mint tokens to buyer - should work (from = address(0))
        _mintTokens(i_buyer, 1);

        // Verify tokens were minted
        assertEq(i_qrbnToken.balanceOf(i_buyer), 1);

        // Verify total supply increased
        uint256 expectedSupply = _getInitialSupply() + 1;
        assertEq(i_qrbnToken.totalSupply(), expectedSupply);
    }

    function test_TokenBurningStillWorks() public {
        uint256 initialBalance = i_qrbnToken.balanceOf(i_founder);
        assertGt(initialBalance, 0);

        // Burn tokens from founder - should work (to = address(0))
        _burnTokens(i_founder, 10);

        // Verify tokens were burned
        assertEq(i_qrbnToken.balanceOf(i_founder), initialBalance - 10);
    }

    function test_TokenTransferToZeroAddressFails() public {
        // This should fail because it's handled by the burn function, not transfer
        vm.expectRevert();
        vm.prank(i_founder);
        i_qrbnToken.transfer(address(0), 10);
    }

    function test_TokenTransferFromZeroAddressFails() public {
        // This should fail because only minting function can do this
        vm.expectRevert();
        vm.prank(i_founder);
        i_qrbnToken.transferFrom(address(0), i_buyer, 10);
    }

    function test_VendorTokensCannotBeTransferred() public {
        // Register vendor (they don't get tokens anymore)
        _registerStandardVendor();

        uint256 vendorBalance = i_qrbnToken.balanceOf(i_vendor);
        assertEq(vendorBalance, 0); // Vendors no longer get tokens

        // Try to transfer from orgRep (who has tokens) - should fail
        _expectTransferToFail(i_orgRep, i_buyer, 100);

        // Verify balance unchanged
        assertEq(
            i_qrbnToken.balanceOf(i_orgRep),
            1 * 10 ** i_qrbnToken.decimals()
        );
    }

    // ============ TREASURY TESTS ============

    function test_Treasury_InitialState() public view {
        assertEq(
            i_qrbnTreasury.isSupportedToken(address(i_mockUSDC)),
            true,
            "USDC should be a supported token"
        );
        assertEq(
            i_qrbnTreasury.getSupportedTokensCount(),
            1,
            "Should be 1 supported token"
        );
        assertEq(
            i_qrbnTreasury.authorizedDepositors(address(i_qurban)),
            true,
            "Qurban contract should be authorized initially"
        );
        assertEq(
            i_qrbnTreasury.hasRole(
                i_qrbnTreasury.GOVERNER_ROLE(),
                address(i_qrbnTimelock)
            ),
            true,
            "Timelock should be governor"
        );
    }

    function test_Treasury_Fails_AuthorizeDepositorByNonGov() public {
        vm.expectRevert();
        vm.prank(i_founder);
        i_qrbnTreasury.authorizeDepositor(address(i_qurban));
    }

    function test_Treasury_DeauthorizeDepositor() public {
        vm.expectEmit(true, true, true, true);
        emit QrbnTreasury.DepositorDeauthorized(address(i_qurban));
        vm.prank(address(i_qrbnTimelock));
        i_qrbnTreasury.deauthorizeDepositor(address(i_qurban));
        assertEq(i_qrbnTreasury.authorizedDepositors(address(i_qurban)), false);
    }

    function test_Treasury_WithdrawFees() public {
        // 1. Purchase to calculate fees (but not deposit them yet)
        _setupStandardVendorWithAnimal();
        vm.prank(i_buyer);
        i_mockUSDC.approve(address(i_qurban), 500e6);
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 5);

        // At this point, treasury should still be empty
        assertEq(i_qrbnTreasury.getAvailableBalance(address(i_mockUSDC)), 0);

        // 2. Complete the animal sacrifice to deposit fees
        vm.prank(i_buyer);
        i_mockUSDC.approve(address(i_qurban), 200e6);
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 2); // Buy remaining shares to make it SOLD

        // Mark as sacrificed - this deposits the fees
        vm.prank(address(i_qrbnTimelock));
        i_qurban.markAnimalSacrificedAndMintCertificates(
            0,
            "https://api.qrbn.com/certificates"
        );

        uint256 feeAmount = (700e6 * 250) / 10000; // Total fees from both purchases

        // Now verify fees were deposited to treasury
        assertEq(
            i_qrbnTreasury.getAvailableBalance(address(i_mockUSDC)),
            feeAmount
        );

        // 3. Test withdrawal
        uint256 recipientInitialBalance = i_mockUSDC.balanceOf(i_founder);
        vm.prank(address(i_qrbnTimelock));
        i_qrbnTreasury.withdrawFees(address(i_mockUSDC), i_founder, feeAmount);

        // 4. Verify
        assertEq(
            i_mockUSDC.balanceOf(i_founder),
            recipientInitialBalance + feeAmount
        );
        assertEq(i_qrbnTreasury.getAvailableBalance(address(i_mockUSDC)), 0);
    }

    function test_Treasury_Fails_WithdrawFeesByNonGov() public {
        // 1. Purchase to deposit fees into treasury
        _setupStandardVendorWithAnimal();
        vm.prank(i_buyer);
        i_mockUSDC.approve(address(i_qurban), 500e6);
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 5);
        uint256 feeAmount = (500e6 * 250) / 10000;

        // 2. Attempt to withdraw
        vm.expectRevert();
        vm.prank(i_founder);
        i_qrbnTreasury.withdrawFees(address(i_mockUSDC), i_founder, feeAmount);
    }

    function test_Treasury_Fails_WithdrawInsufficientBalance() public {
        // 1. Setup and complete a full purchase cycle to get fees in treasury
        _setupStandardVendorWithAnimal();

        // Purchase 5 shares
        vm.prank(i_buyer);
        i_mockUSDC.approve(address(i_qurban), 500e6);
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 5);

        // Purchase remaining 2 shares to make animal SOLD
        vm.prank(i_buyer);
        i_mockUSDC.approve(address(i_qurban), 200e6);
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 2);

        // Mark as sacrificed to deposit fees to treasury
        vm.prank(address(i_qrbnTimelock));
        i_qurban.markAnimalSacrificedAndMintCertificates(
            0,
            "https://api.qrbn.com/certificates"
        );

        uint256 totalFeeAmount = (700e6 * 250) / 10000; // Total fees from both purchases

        // Verify fees were deposited to treasury after sacrifice
        assertEq(
            i_qrbnTreasury.getAvailableBalance(address(i_mockUSDC)),
            totalFeeAmount
        );

        // 2. Try to withdraw more than available - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InsufficientBalance.selector,
                address(i_mockUSDC),
                totalFeeAmount,
                totalFeeAmount + 1
            )
        );
        vm.prank(address(i_qrbnTimelock));
        i_qrbnTreasury.withdrawFees(
            address(i_mockUSDC),
            i_founder,
            totalFeeAmount + 1
        );
    }

    function test_Treasury_DirectDepositFees() public {
        // 1. Authorize self as depositor
        vm.prank(address(i_qrbnTimelock));
        i_qrbnTreasury.authorizeDepositor(address(this));
        assertEq(i_qrbnTreasury.authorizedDepositors(address(this)), true);

        // 2. Mint USDC to self and approve treasury
        uint256 depositAmount = 100e6;
        i_mockUSDC.mint(address(this), depositAmount);
        i_mockUSDC.approve(address(i_qrbnTreasury), depositAmount);

        // 3. Deposit fees
        vm.expectEmit(true, true, true, true);
        emit QrbnTreasury.FeeDeposited(
            address(i_mockUSDC),
            address(this),
            depositAmount,
            depositAmount
        );
        i_qrbnTreasury.depositFees(address(i_mockUSDC), depositAmount);

        // 4. Verify balance
        assertEq(
            i_qrbnTreasury.getAvailableBalance(address(i_mockUSDC)),
            depositAmount
        );
        QrbnTreasury.TokenBalance memory balance = i_qrbnTreasury
            .getTokenBalance(address(i_mockUSDC));
        assertEq(balance.totalCollected, depositAmount);
        assertEq(balance.availableBalance, depositAmount);
    }

    function test_Treasury_Fails_DirectDepositFromUnauthorized() public {
        // Attempt to deposit without being an authorized depositor
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NotAuthorized.selector, "depositor")
        );
        i_qrbnTreasury.depositFees(address(i_mockUSDC), 100e6);
    }

    function test_Treasury_Fails_DirectDepositUnsupportedToken() public {
        // 1. Authorize self as depositor
        vm.prank(address(i_qrbnTimelock));
        i_qrbnTreasury.authorizeDepositor(address(this));

        // 2. Create a new mock token
        MockUSDC newUnsupportedToken = new MockUSDC(
            address(this),
            address(this)
        );

        // 3. Attempt to deposit
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.TokenNotSupported.selector,
                address(newUnsupportedToken)
            )
        );
        i_qrbnTreasury.depositFees(address(newUnsupportedToken), 100e6);
    }

    function test_Treasury_AddAndRemoveToken() public {
        // 1. Create a new mock token
        MockUSDC newToken = new MockUSDC(address(this), address(this));
        address tokenAddress = address(newToken);

        // 2. Add the token
        vm.expectEmit(true, true, false, false);
        emit QrbnTreasury.TokenAdded(tokenAddress);
        vm.prank(address(i_qrbnTimelock));
        i_qrbnTreasury.addToken(tokenAddress);
        assertEq(i_qrbnTreasury.isSupportedToken(tokenAddress), true);
        assertEq(i_qrbnTreasury.getSupportedTokensCount(), 2);

        // 3. Remove the token
        vm.expectEmit(true, true, false, false);
        emit QrbnTreasury.TokenRemoved(tokenAddress);
        vm.prank(address(i_qrbnTimelock));
        i_qrbnTreasury.removeToken(tokenAddress);
        assertEq(i_qrbnTreasury.isSupportedToken(tokenAddress), false);
        assertEq(i_qrbnTreasury.getSupportedTokensCount(), 1);
    }

    function test_Treasury_Fails_RemoveTokenWithBalance() public {
        // 1. Add a new token
        MockUSDC newToken = new MockUSDC(address(this), address(this));
        address tokenAddress = address(newToken);
        vm.prank(address(i_qrbnTimelock));
        i_qrbnTreasury.addToken(tokenAddress);

        // 2. Deposit some of the new token
        vm.prank(address(i_qrbnTimelock));
        i_qrbnTreasury.authorizeDepositor(address(this));
        uint256 depositAmount = 50e6;
        newToken.mint(address(this), depositAmount);
        newToken.approve(address(i_qrbnTreasury), depositAmount);
        i_qrbnTreasury.depositFees(tokenAddress, depositAmount);

        // 3. Attempt to remove the token
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.TokenBalanceNotZero.selector,
                tokenAddress
            )
        );
        vm.prank(address(i_qrbnTimelock));
        i_qrbnTreasury.removeToken(tokenAddress);
    }

    function test_Treasury_Fails_DeauthorizeNonAuthorizedDepositor() public {
        address nonDepositor = makeAddr("nonDepositor");
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.DepositorNotAuthorized.selector,
                nonDepositor
            )
        );
        vm.prank(address(i_qrbnTimelock));
        i_qrbnTreasury.deauthorizeDepositor(nonDepositor);
    }

    // ============ HELPER FUNCTIONS ============

    struct TokenBalances {
        uint256 founder;
        uint256 syariahCouncil;
        uint256 communityRep;
        uint256 orgRep;
        uint256 buyer;
    }

    function _getTokenBalances() internal view returns (TokenBalances memory) {
        return
            TokenBalances({
                founder: i_qrbnToken.balanceOf(i_founder),
                syariahCouncil: i_qrbnToken.balanceOf(i_syariahCouncil),
                communityRep: i_qrbnToken.balanceOf(i_communityRep),
                orgRep: i_qrbnToken.balanceOf(i_orgRep),
                buyer: i_qrbnToken.balanceOf(i_buyer)
            });
    }

    function _assertBalancesUnchanged(
        TokenBalances memory balances
    ) internal view {
        assertEq(i_qrbnToken.balanceOf(i_founder), balances.founder);
        assertEq(
            i_qrbnToken.balanceOf(i_syariahCouncil),
            balances.syariahCouncil
        );
        assertEq(i_qrbnToken.balanceOf(i_communityRep), balances.communityRep);
        assertEq(i_qrbnToken.balanceOf(i_orgRep), balances.orgRep);
        assertEq(i_qrbnToken.balanceOf(i_buyer), balances.buyer);
    }

    function _expectTransferToFail(
        address from,
        address to,
        uint256 amount
    ) internal {
        vm.expectRevert(QrbnToken.TokenNotTransferrable.selector);
        vm.prank(from);
        i_qrbnToken.transfer(to, amount);
    }

    function _expectTransferFromToFail(
        address spender,
        address from,
        address to,
        uint256 amount
    ) internal {
        vm.expectRevert(QrbnToken.TokenNotTransferrable.selector);
        vm.prank(spender);
        i_qrbnToken.transferFrom(from, to, amount);
    }

    function _approveTokens(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        vm.prank(owner);
        i_qrbnToken.approve(spender, amount);
        // Verify allowance is set
        assertEq(i_qrbnToken.allowance(owner, spender), amount);
    }

    function _mintTokens(address to, uint256 amount) internal {
        vm.prank(address(i_qrbnTimelock));
        i_qrbnToken.mint(to, amount);
    }

    function _burnTokens(address from, uint256 amount) internal {
        vm.prank(from);
        i_qrbnToken.burn(amount);
    }

    function _getInitialSupply() internal view returns (uint256) {
        return (1 + 1 + 1 + 1) * 10 ** i_qrbnToken.decimals();
    }

    function _setupVendorWithAnimal(
        address vendor,
        string memory animalName,
        uint8 shares,
        uint256 price
    ) internal returns (uint256 animalId) {
        _registerVendor(vendor);
        return _addSheepAnimal(vendor, animalName, shares, price);
    }

    function _setupVendorWithStandardAnimal(
        address vendor
    ) internal returns (uint256 animalId) {
        return _setupVendorWithAnimal(vendor, "Sheep Name", 7, 100e6);
    }

    function _setupStandardVendorWithAnimal()
        internal
        returns (uint256 animalId)
    {
        return _setupVendorWithStandardAnimal(i_vendor);
    }

    function _registerVendor(address vendor) internal {
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(vendor, "NAME", "CONTACT", "LOCATION");
    }

    function _registerStandardVendor() internal {
        _registerVendor(i_vendor);
    }

    function _addAnimal(
        address vendor,
        uint8 shares,
        uint256 price
    ) internal returns (uint256) {
        return
            _addAnimalWithDetails(
                vendor,
                "Animal Name",
                Qurban.AnimalType.SHEEP,
                shares,
                price,
                "Farm Location",
                "image.jpg",
                "Description",
                "Breed",
                50,
                2,
                "Farm Name",
                block.timestamp + 30 days
            );
    }

    function _addAnimalWithDetails(
        address vendor,
        string memory name,
        Qurban.AnimalType animalType,
        uint8 shares,
        uint256 price,
        string memory location,
        string memory image,
        string memory description,
        string memory breed,
        uint16 weight,
        uint16 age,
        string memory farmName,
        uint256 sacrificeDate
    ) internal returns (uint256) {
        uint256 currentCount = i_qurban.getTotalAnimalsCount();
        vm.prank(address(i_qrbnTimelock));
        i_qurban.addAnimal(
            vendor,
            name,
            animalType,
            shares,
            price,
            location,
            image,
            description,
            breed,
            weight,
            age,
            farmName,
            sacrificeDate
        );
        return currentCount; // Return the ID of the just-created animal
    }

    function _addSheepAnimal(
        address vendor,
        string memory name,
        uint8 shares,
        uint256 price
    ) internal returns (uint256) {
        return
            _addAnimalWithDetails(
                vendor,
                name,
                Qurban.AnimalType.SHEEP,
                shares,
                price,
                "Farm Location",
                "image.jpg",
                "Description",
                "Breed",
                50,
                2,
                "Farm Name",
                block.timestamp + 30 days
            );
    }

    function _purchaseAllShares() internal {
        vm.prank(i_buyer);
        i_mockUSDC.approve(address(i_qurban), 1000e6);

        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 7);
    }

    function _purchaseAllSharesForAnimal(uint256 animalId) internal {
        Qurban.Animal memory animal = i_qurban.getAnimalById(animalId);

        vm.startPrank(i_buyer);
        i_mockUSDC.approve(
            address(i_qurban),
            animal.totalShares * animal.pricePerShare
        );
        i_qurban.purchaseAnimalShares(animalId, animal.totalShares);
        vm.stopPrank();
    }
}
