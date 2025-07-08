// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/MutatedOptionFactoryV1.sol";
import "contracts/MutatedOptionPairV1.sol";
import "contracts/TestToken.sol";

contract MutatedOptionFactoryTest is Test {
    // --- State Variables ---

    MutatedOptionFactoryV1 public factory;
    TestToken public underlyingToken;
    TestToken public strikeToken;
    MutatedOptionPairV1 public optionPair;

    address public seller = address(0x100);
    address public buyer = address(0x200);
    uint256 initialMintAmount = 1_000_000; // 1,000,000 tokens

    // --- Setup ---

    function setUp() public {
        // Deploy a new factory for each test
        factory = new MutatedOptionFactoryV1();

        // Deploy mock tokens, initial supply is minted to the deployer (seller)
        vm.startPrank(seller);
        underlyingToken = new TestToken(
            "Underlying Token",
            "ULT",
            initialMintAmount
        );
        strikeToken = new TestToken("Strike Token", "STK", initialMintAmount);
        vm.stopPrank();

        // Mint tokens for the buyer as well
        strikeToken.mint(buyer, initialMintAmount * 1e18);
    }

    // --- Factory Tests ---

    function test_Factory_GetPairAddress_And_CreatePair_Success() public {
        bytes32 salt = keccak256(abi.encodePacked("my-unique-salt"));

        // 1. Predict the address
        address predictedAddress = factory.getPairAddress(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        assertTrue(
            predictedAddress != address(0),
            "Predicted address should not be zero"
        );

        // 2. Create the pair using the same salt
        vm.expectEmit(true, true, true, true);
        emit MutatedOptionFactoryV1.OptionPairCreated(
            address(underlyingToken),
            address(strikeToken),
            predictedAddress,
            salt,
            1
        );

        address deployedAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );

        // 3. Verify addresses match and state is updated
        assertEq(
            deployedAddress,
            predictedAddress,
            "Deployed address should match predicted address"
        );
        assertEq(factory.totalOptionPairs(), 1, "Total pairs should be 1");
        assertEq(
            factory.allOptionPairs(0),
            deployedAddress,
            "Pair address mismatch in array"
        );
        assertEq(
            factory.getPairBySalt(salt),
            deployedAddress,
            "Pair address mismatch in salt mapping"
        );
    }

    function test_Factory_CreatePair_Revert_SaltUsed() public {
        bytes32 salt = keccak256(abi.encodePacked("reused-salt"));

        // First deployment should succeed
        factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );

        // Second deployment with the same salt should fail
        vm.expectRevert("Factory: Salt has been used");
        factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
    }

    function test_Factory_CreatePair_Revert_ZeroAddress() public {
        bytes32 salt = keccak256(abi.encodePacked("zero-addr-salt"));
        vm.expectRevert("Factory: Underlying token cannot be zero address");
        factory.createOptionPair(address(0), address(strikeToken), salt);

        vm.expectRevert("Factory: Strike token cannot be zero address");
        factory.createOptionPair(address(underlyingToken), address(0), salt);
    }

    function test_Factory_CreatePair_Revert_SameAddress() public {
        bytes32 salt = keccak256(abi.encodePacked("same-addr-salt"));
        vm.expectRevert("Factory: Tokens cannot be the same");
        factory.createOptionPair(
            address(underlyingToken),
            address(underlyingToken),
            salt
        );
    }

    // --- Option Pair Full Workflow Test ---

    function test_Pair_FullWorkflow() public {
        // 1. Create the pair contract first
        bytes32 salt = keccak256(abi.encodePacked("workflow-salt"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);

        // --- Test Constants ---
        uint256 underlyingAmount = 1e18; // 1 ULT
        uint256 strikeAmount = 100e18; // 100 STK
        uint256 premiumAmount = 5e18; // 5 STK
        uint256 closingFee = 2e18; // 2 STK
        uint256 period = 1 days;
        uint256 optionId = 1;

        // --- 2. Create Option ---
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), underlyingAmount);

        optionPair.createOption(
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            period
        );

        // Verify option state
        (
            ,
            address optSeller,
            ,
            uint256 optUnderlyingAmount,
            ,
            ,
            ,
            ,
            MutatedOptionPairV1.OptionState optState
        ) = optionPair.options(optionId);
        assertEq(optSeller, seller, "Seller mismatch");
        assertEq(
            optUnderlyingAmount,
            underlyingAmount,
            "Underlying amount mismatch"
        );
        assertEq(
            uint(optState),
            uint(MutatedOptionPairV1.OptionState.AvailableForPurchase),
            "State should be Available"
        );
        assertEq(
            underlyingToken.balanceOf(address(optionPair)),
            underlyingAmount,
            "Contract ULT balance incorrect"
        );
        vm.stopPrank();

        // --- 3. Purchase Option ---
        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), premiumAmount);

        optionPair.purchaseOption(optionId, closingFee);

        // Verify state after purchase
        (
            ,
            ,
            address optBuyer,
            ,
            ,
            ,
            ,
            uint256 optClosingFee,
            MutatedOptionPairV1.OptionState optStateAfterPurchase
        ) = optionPair.options(optionId);
        assertEq(optBuyer, buyer, "Buyer mismatch");
        assertEq(optClosingFee, closingFee, "Closing fee mismatch");
        assertEq(
            uint(optStateAfterPurchase),
            uint(MutatedOptionPairV1.OptionState.Active),
            "State should be Active"
        );
        assertEq(
            strikeToken.balanceOf(seller),
            (initialMintAmount * 1e18) + premiumAmount,
            "Seller STK balance incorrect"
        );
        vm.stopPrank();

        // --- 4. Exercise Option ---
        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), strikeAmount);

        optionPair.exerciseOption(optionId);

        // Verify state after exercise
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            MutatedOptionPairV1.OptionState optStateAfterExercise
        ) = optionPair.options(optionId);
        assertEq(
            uint(optStateAfterExercise),
            uint(MutatedOptionPairV1.OptionState.Exercised),
            "State should be Exercised"
        );
        assertEq(
            underlyingToken.balanceOf(buyer),
            underlyingAmount,
            "Buyer ULT balance incorrect"
        );
        assertEq(
            strikeToken.balanceOf(seller),
            (initialMintAmount * 1e18) + premiumAmount + strikeAmount,
            "Seller STK balance incorrect after exercise"
        );
        assertEq(
            underlyingToken.balanceOf(address(optionPair)),
            0,
            "Contract ULT balance should be 0"
        );
        vm.stopPrank();
    }

    // --- Expiration Test ---
    function test_Pair_ClaimOnExpiration() public {
        // Setup: Create and purchase an option
        bytes32 salt = keccak256(abi.encodePacked("expiration-salt"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        uint256 underlyingAmount = 1e18;
        uint256 period = 1 days;
        uint256 optionId = 1;
        uint256 premiumAmount = 5e18;

        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), underlyingAmount);
        optionPair.createOption(
            underlyingAmount,
            100e18,
            premiumAmount,
            period
        );
        vm.stopPrank();

        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), premiumAmount);
        optionPair.purchaseOption(optionId, 2e18);
        vm.stopPrank();

        // Fast forward time past expiration
        vm.warp(block.timestamp + period + 1);

        // Claim
        vm.startPrank(seller);
        optionPair.claimUnderlyingOnExpiration(optionId);

        // Verify
        (, , , , , , , , MutatedOptionPairV1.OptionState optState) = optionPair
            .options(optionId);
        assertEq(
            uint(optState),
            uint(MutatedOptionPairV1.OptionState.Expired),
            "State should be Expired"
        );
        assertEq(
            underlyingToken.balanceOf(seller),
            initialMintAmount * 1e18,
            "Seller should have received underlying back"
        );
        assertEq(
            underlyingToken.balanceOf(address(optionPair)),
            0,
            "Contract should have no underlying"
        );
        vm.stopPrank();
    }

    // --- Close Option Test ---
    function test_Pair_CloseOption() public {
        // Setup: Create and purchase an option
        bytes32 salt = keccak256(abi.encodePacked("close-option-salt"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        uint256 underlyingAmount = 1e18;
        uint256 closingFee = 2e18;
        uint256 optionId = 1;
        uint256 premiumAmount = 5e18;

        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), underlyingAmount);
        optionPair.createOption(
            underlyingAmount,
            100e18,
            premiumAmount,
            1 days
        );
        vm.stopPrank();

        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), premiumAmount);
        optionPair.purchaseOption(optionId, closingFee);
        vm.stopPrank();

        // Close the option
        vm.startPrank(seller);
        strikeToken.approve(address(optionPair), closingFee);

        optionPair.closeOption(optionId);

        // Verify
        (, , , , , , , , MutatedOptionPairV1.OptionState optState) = optionPair
            .options(optionId);
        assertEq(
            uint(optState),
            uint(MutatedOptionPairV1.OptionState.Closed),
            "State should be Closed"
        );
        assertEq(
            underlyingToken.balanceOf(seller),
            initialMintAmount * 1e18,
            "Seller should get underlying back"
        );
        assertEq(
            strikeToken.balanceOf(buyer),
            (initialMintAmount * 1e18) - premiumAmount + closingFee,
            "Buyer should get closing fee"
        );
        assertEq(
            underlyingToken.balanceOf(address(optionPair)),
            0,
            "Contract should have no underlying"
        );
        vm.stopPrank();
    }

    // --- Revert Tests for createOption ---

    function test_Revert_CreateOption_ZeroUnderlying() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-0"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        vm.startPrank(seller);
        vm.expectRevert("Option: Underlying amount must be greater than 0");
        optionPair.createOption(0, 100e18, 5e18, 1 days);
        vm.stopPrank();
    }

    function test_Revert_CreateOption_ZeroStrike() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-1"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        vm.startPrank(seller);
        vm.expectRevert("Option: Strike amount must be greater than 0");
        optionPair.createOption(1e18, 0, 5e18, 1 days);
        vm.stopPrank();
    }

    function test_Revert_CreateOption_ZeroPremium() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-2"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        vm.startPrank(seller);
        vm.expectRevert("Option: Premium amount must be greater than 0");
        optionPair.createOption(1e18, 100e18, 0, 1 days);
        vm.stopPrank();
    }

    function test_Revert_CreateOption_ZeroPeriod() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-3"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        vm.startPrank(seller);
        vm.expectRevert("Option: Period must be greater than 0");
        optionPair.createOption(1e18, 100e18, 5e18, 0);
        vm.stopPrank();
    }

    // --- Revert Tests for purchaseOption ---

    function test_Revert_PurchaseOption_NotAvailable() public {
        // Setup: Create and purchase an option, then try to purchase again
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-4"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);
        vm.stopPrank();

        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), 5e18);
        optionPair.purchaseOption(1, 2e18);

        // Try to purchase again
        strikeToken.approve(address(optionPair), 5e18);
        vm.expectRevert("Option: Not available for purchase");
        optionPair.purchaseOption(1, 2e18);
        vm.stopPrank();
    }

    function test_Revert_PurchaseOption_SellerCannotBuy() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-5"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);

        strikeToken.approve(address(optionPair), 5e18);
        vm.expectRevert("Option: Seller cannot purchase their own option");
        optionPair.purchaseOption(1, 2e18);
        vm.stopPrank();
    }

    // --- Revert Tests for exerciseOption ---

    function test_Revert_ExerciseOption_NotActive() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-6"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);
        vm.stopPrank();

        vm.startPrank(buyer);
        vm.expectRevert("Option: Not active");
        optionPair.exerciseOption(1);
        vm.stopPrank();
    }

    function test_Revert_ExerciseOption_NotBuyer() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-7"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        address otherUser = address(0x300);

        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);
        vm.stopPrank();

        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), 5e18);
        optionPair.purchaseOption(1, 2e18);
        vm.stopPrank();

        vm.startPrank(otherUser);
        vm.expectRevert("Option: Only the buyer can exercise this option");
        optionPair.exerciseOption(1);
        vm.stopPrank();
    }

    function test_Revert_ExerciseOption_Expired() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-8"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        uint256 period = 1 days;

        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, period);
        vm.stopPrank();

        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), 5e18);
        optionPair.purchaseOption(1, 2e18);

        vm.warp(block.timestamp + period + 1); // Fast forward time

        vm.expectRevert("Option: Has expired");
        optionPair.exerciseOption(1);
        vm.stopPrank();
    }

    // --- Revert Tests for claimUnderlyingOnExpiration ---

    function test_Revert_Claim_NotActive() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-9"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);
        vm.expectRevert("Option: Not active or already handled");
        optionPair.claimUnderlyingOnExpiration(1);
        vm.stopPrank();
    }

    function test_Revert_Claim_NotSeller() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-10"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);
        vm.stopPrank();

        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), 5e18);
        optionPair.purchaseOption(1, 2e18);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert("Option: Only the original seller can claim");
        optionPair.claimUnderlyingOnExpiration(1);
        vm.stopPrank();
    }

    function test_Revert_Claim_NotExpired() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-11"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);
        vm.stopPrank();

        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), 5e18);
        optionPair.purchaseOption(1, 2e18);
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectRevert("Option: Has not expired yet");
        optionPair.claimUnderlyingOnExpiration(1);
        vm.stopPrank();
    }

    // --- Revert Tests for closeOption ---

    function test_Revert_Close_NotActive() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-12"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);
        vm.expectRevert("Option: Not active");
        optionPair.closeOption(1);
        vm.stopPrank();
    }

    function test_Revert_Close_NotSeller() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-13"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);
        vm.stopPrank();

        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), 5e18);
        optionPair.purchaseOption(1, 2e18);
        vm.expectRevert(
            "Option: Only the original seller can close this option"
        );
        optionPair.closeOption(1);
        vm.stopPrank();
    }

    function test_Revert_Close_Expired() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-14"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        uint256 period = 1 days;
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, period);
        vm.stopPrank();

        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), 5e18);
        optionPair.purchaseOption(1, 2e18);
        vm.stopPrank();

        vm.warp(block.timestamp + period + 1);

        vm.startPrank(seller);
        vm.expectRevert("Option: Has already expired");
        optionPair.closeOption(1);
        vm.stopPrank();
    }

    function test_Revert_Close_NotPurchased() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-15"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);
        // For an un-purchased option, the state is AvailableForPurchase, not Active.
        // The first check in closeOption is for the Active state.
        vm.expectRevert("Option: Not active");
        optionPair.closeOption(1);
        vm.stopPrank();
    }

    function test_Revert_Close_ZeroClosingFee() public {
        bytes32 salt = keccak256(abi.encodePacked("revert-salt-16"));
        address pairAddress = factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken),
            salt
        );
        optionPair = MutatedOptionPairV1(pairAddress);
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);
        vm.stopPrank();

        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), 5e18);
        optionPair.purchaseOption(1, 0); // Purchase with 0 closing fee
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectRevert(
            "Option: Closing fee must be greater than 0 to close early"
        );
        optionPair.closeOption(1);
        vm.stopPrank();
    }
}
