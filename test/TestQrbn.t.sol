// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Qurban} from "../src/qurban/Qurban.sol";
import {QurbanErrors} from "../src/qurban/QurbanErrors.sol";
import {QurbanNFT} from "../src/qurban/QurbanNFT.sol";
import {QrbnToken} from "../src/dao/QrbnToken.sol";
import {QrbnGov} from "../src/dao/QrbnGov.sol";
import {QrbnTimelock} from "../src/dao/QrbnTimelock.sol";
import {DeployQrbn} from "../script/DeployQrbn.s.sol";
import {DeployConfig} from "../script/DeployConfig.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Constants} from "../src/lib/Constants.sol";

contract TestQrbn is Test {
    QurbanNFT i_qurbanNFT;
    QrbnToken i_qrbnToken;
    QrbnGov i_qrbnGov;
    QrbnTimelock i_qrbnTimelock;
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
        DeployConfig deployConfig = new DeployConfig();
        DeployConfig.NetworkConfig memory networkConfig = deployConfig
            .getNetworkConfig();

        DeployQrbn deployScript = new DeployQrbn();
        (
            i_qrbnTimelock,
            i_qrbnGov,
            i_qrbnToken,
            i_qurban,
            i_qurbanNFT
        ) = deployScript.runDeploy(
            networkConfig.usdcTokenAddress,
            i_founder,
            i_syariahCouncil,
            i_orgRep,
            i_communityRep,
            true
        );

        i_mockUSDC = MockUSDC(address(i_qurban.i_usdc()));

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
            abi.encodeWithSelector(
                QurbanErrors.AddressZero.selector,
                "vendorAddress"
            )
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(address(0), "NAME", "CONTACT", "LOCATION");
    }

    function test_RegisterVendorTwice() public {
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_vendor, "NAME", "CONTACT", "LOCATION");

        vm.expectRevert(
            abi.encodeWithSelector(
                QurbanErrors.AlreadyRegistered.selector,
                "vendor"
            )
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_vendor, "NAME2", "CONTACT2", "LOCATION2");
    }

    function test_RegisterVendorWithEmptyName() public {
        vm.expectRevert(
            abi.encodeWithSelector(QurbanErrors.EmptyString.selector, "name")
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
            abi.encodeWithSelector(
                QurbanErrors.NotRegistered.selector,
                "vendor"
            )
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.editVendor(i_vendor, "NAME", "CONTACT", "LOCATION");
    }

    function test_EditVendorWithEmptyName() public {
        vm.prank(address(i_qrbnTimelock));
        i_qurban.registerVendor(i_vendor, "NAME", "CONTACT", "LOCATION");

        vm.expectRevert(
            abi.encodeWithSelector(QurbanErrors.EmptyString.selector, "name")
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
            abi.encodeWithSelector(
                QurbanErrors.AlreadyVerified.selector,
                "vendor"
            )
        );
        vm.prank(address(i_qrbnTimelock));
        i_qurban.verifyVendor(i_vendor);
    }

    function test_VerifyVendorNotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                QurbanErrors.NotRegistered.selector,
                "vendor"
            )
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
            abi.encodeWithSelector(
                QurbanErrors.AlreadyUnverified.selector,
                "vendor"
            )
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
            abi.encodeWithSelector(
                QurbanErrors.NotRegistered.selector,
                "vendor"
            )
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
            abi.encodeWithSelector(QurbanErrors.EmptyString.selector, "name")
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
            abi.encodeWithSelector(
                QurbanErrors.InvalidAmount.selector,
                "totalShares"
            )
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
            abi.encodeWithSelector(
                QurbanErrors.InvalidDate.selector,
                "sacrificeDate"
            )
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
            abi.encodeWithSelector(
                QurbanErrors.Forbidden.selector,
                "vendorAddress"
            )
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
            abi.encodeWithSelector(
                QurbanErrors.AlreadyAvailable.selector,
                "animal"
            )
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
            uint256 timestamp,
            uint8 shareAmount,
            address buyer
        ) = i_qurban.s_buyerTransactions(0);

        assertEq(txId, 0);
        assertEq(animalId, 0);
        assertEq(nftCertificateId, 0);
        assertEq(pricePerShare, 100e6);
        assertEq(totalPaid, 500e6);
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
        uint256 expectedVendorShare = 500e6 - ((500e6 * 250) / 10000); // Total - platform fee
        assertEq(totalSales, expectedVendorShare);
    }

    function test_PurchaseAnimalSharesFullySold() public {
        // Setup
        _setupStandardVendorWithAnimal();

        address usdcAddress = address(i_qurban.i_usdc());
        MockUSDC usdc = MockUSDC(usdcAddress);

        vm.prank(i_buyer);
        usdc.approve(address(i_qurban), 1000e6);

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
            abi.encodeWithSelector(QurbanErrors.NotAvailable.selector, "animal")
        );
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 5);
    }

    function test_PurchaseAnimalSharesInvalidAmount() public {
        _setupStandardVendorWithAnimal();

        // Test zero shares
        vm.expectRevert(
            abi.encodeWithSelector(
                QurbanErrors.InvalidAmount.selector,
                "shareAmount"
            )
        );
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 0);

        // Test more shares than available
        vm.expectRevert(
            abi.encodeWithSelector(
                QurbanErrors.InvalidAmount.selector,
                "shareAmount"
            )
        );
        vm.prank(i_buyer);
        i_qurban.purchaseAnimalShares(0, 8); // Trying to buy 8 shares when only 7 are available
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
        return 0; // Return the ID of the just-created animal (assuming first animal = 0)
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
}
