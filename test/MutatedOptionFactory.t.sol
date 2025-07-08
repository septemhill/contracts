// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/MutatedOptionFactory.sol";
import "contracts/MutatedOptionPair.sol";
import "contracts/TestToken.sol";

contract MutatedOptionFactoryTest is Test {
    // --- State Variables ---

    MutatedOptionFactory public factory;
    TestToken public underlyingToken;
    TestToken public strikeToken;
    MutatedOptionPair public optionPair;

    address public seller = address(0x100);
    address public buyer = address(0x200);
    uint256 initialMintAmount = 1_000_000; // 1,000,000 tokens

    // --- Setup ---

    function setUp() public {
        // Deploy a new factory for each test
        factory = new MutatedOptionFactory();

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

    function test_Factory_CreatePair_Success() public {
        // Create a new option pair
        factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken)
        );

        // Verify state changes
        assertEq(factory.totalOptionPairs(), 1, "Total pairs should be 1");
        address pairAddress = factory.allOptionPairs(0);
        assertTrue(
            pairAddress != address(0),
            "Pair address should not be zero"
        );

        // Verify the new pair's tokens
        MutatedOptionPair createdPair = MutatedOptionPair(pairAddress);
        assertEq(
            createdPair.underlyingToken(),
            address(underlyingToken),
            "Underlying token mismatch"
        );
        assertEq(
            createdPair.strikeToken(),
            address(strikeToken),
            "Strike token mismatch"
        );
    }

    function test_Factory_CreatePair_Revert_ZeroAddress() public {
        vm.expectRevert("Factory: Underlying token cannot be zero address");
        factory.createOptionPair(address(0), address(strikeToken));

        vm.expectRevert("Factory: Strike token cannot be zero address");
        factory.createOptionPair(address(underlyingToken), address(0));
    }

    function test_Factory_CreatePair_Revert_SameAddress() public {
        vm.expectRevert("Factory: Tokens cannot be the same");
        factory.createOptionPair(
            address(underlyingToken),
            address(underlyingToken)
        );
    }

    // --- Option Pair Full Workflow Test ---

    function test_Pair_FullWorkflow() public {
        // 1. Create the pair contract first
        factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken)
        );
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));

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
            MutatedOptionPair.OptionState optState
        ) = optionPair.options(optionId);
        assertEq(optSeller, seller, "Seller mismatch");
        assertEq(
            optUnderlyingAmount,
            underlyingAmount,
            "Underlying amount mismatch"
        );
        assertEq(
            uint(optState),
            uint(MutatedOptionPair.OptionState.AvailableForPurchase),
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
            MutatedOptionPair.OptionState optStateAfterPurchase
        ) = optionPair.options(optionId);
        assertEq(optBuyer, buyer, "Buyer mismatch");
        assertEq(optClosingFee, closingFee, "Closing fee mismatch");
        assertEq(
            uint(optStateAfterPurchase),
            uint(MutatedOptionPair.OptionState.Active),
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
            MutatedOptionPair.OptionState optStateAfterExercise
        ) = optionPair.options(optionId);
        assertEq(
            uint(optStateAfterExercise),
            uint(MutatedOptionPair.OptionState.Exercised),
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
        factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken)
        );
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
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
        (, , , , , , , , MutatedOptionPair.OptionState optState) = optionPair
            .options(optionId);
        assertEq(
            uint(optState),
            uint(MutatedOptionPair.OptionState.Expired),
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
        factory.createOptionPair(
            address(underlyingToken),
            address(strikeToken)
        );
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
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
        (, , , , , , , , MutatedOptionPair.OptionState optState) = optionPair
            .options(optionId);
        assertEq(
            uint(optState),
            uint(MutatedOptionPair.OptionState.Closed),
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
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
        vm.startPrank(seller);
        vm.expectRevert("Option: Underlying amount must be greater than 0");
        optionPair.createOption(0, 100e18, 5e18, 1 days);
        vm.stopPrank();
    }

    function test_Revert_CreateOption_ZeroStrike() public {
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
        vm.startPrank(seller);
        vm.expectRevert("Option: Strike amount must be greater than 0");
        optionPair.createOption(1e18, 0, 5e18, 1 days);
        vm.stopPrank();
    }

    function test_Revert_CreateOption_ZeroPremium() public {
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
        vm.startPrank(seller);
        vm.expectRevert("Option: Premium amount must be greater than 0");
        optionPair.createOption(1e18, 100e18, 0, 1 days);
        vm.stopPrank();
    }

    function test_Revert_CreateOption_ZeroPeriod() public {
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
        vm.startPrank(seller);
        vm.expectRevert("Option: Period must be greater than 0");
        optionPair.createOption(1e18, 100e18, 5e18, 0);
        vm.stopPrank();
    }

    // --- Revert Tests for purchaseOption ---

    function test_Revert_PurchaseOption_NotAvailable() public {
        // Setup: Create and purchase an option, then try to purchase again
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
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
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
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
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
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
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
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
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
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
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);
        vm.expectRevert("Option: Not active or already handled");
        optionPair.claimUnderlyingOnExpiration(1);
        vm.stopPrank();
    }

    function test_Revert_Claim_NotSeller() public {
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
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
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
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
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);
        vm.expectRevert("Option: Not active");
        optionPair.closeOption(1);
        vm.stopPrank();
    }

    function test_Revert_Close_NotSeller() public {
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);
        vm.stopPrank();

        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), 5e18);
        optionPair.purchaseOption(1, 2e18);
        vm.expectRevert("Option: Only the original seller can close this option");
        optionPair.closeOption(1);
        vm.stopPrank();
    }

    function test_Revert_Close_Expired() public {
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
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
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
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
        factory.createOptionPair(address(underlyingToken), address(strikeToken));
        optionPair = MutatedOptionPair(factory.allOptionPairs(0));
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), 1e18);
        optionPair.createOption(1e18, 100e18, 5e18, 1 days);
        vm.stopPrank();

        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), 5e18);
        optionPair.purchaseOption(1, 0); // Purchase with 0 closing fee
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectRevert("Option: Closing fee must be greater than 0 to close early");
        optionPair.closeOption(1);
        vm.stopPrank();
    }
}
