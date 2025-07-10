// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import {MutatedOptionPairV2} from "../contracts/MutatedOptionPairV2.sol";
import {TestToken} from "../contracts/TestToken.sol";

contract MutatedOptionPairV2Test is Test {
    MutatedOptionPairV2 internal optionPair;
    TestToken internal underlyingToken;
    TestToken internal strikeToken;

    address internal seller = address(0x1);
    address internal buyer = address(0x2);
    address internal deployer = address(this); // The test contract itself is the deployer

    uint256 internal constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 internal constant UNDERLYING_AMOUNT = 1e18;
    uint256 internal constant STRIKE_AMOUNT = 200e18;
    uint256 internal constant PREMIUM_AMOUNT = 10e18;
    uint256 internal constant PERIOD_IN_SECONDS = 3600; // 1 hour

    function setUp() public {
        underlyingToken = new TestToken(
            "Underlying Token",
            "ULT",
            INITIAL_SUPPLY,
            18
        );
        strikeToken = new TestToken("Strike Token", "STK", INITIAL_SUPPLY, 18);

        optionPair = new MutatedOptionPairV2(
            address(underlyingToken),
            address(strikeToken)
        );

        // Mint tokens for seller and buyer from the deployer's balance
        underlyingToken.transfer(seller, UNDERLYING_AMOUNT * 10);
        strikeToken.transfer(buyer, STRIKE_AMOUNT + PREMIUM_AMOUNT);
        strikeToken.transfer(seller, STRIKE_AMOUNT); // For closing fee

        // Approve tokens for the option pair contract
        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), type(uint256).max);
        strikeToken.approve(address(optionPair), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(buyer);
        strikeToken.approve(address(optionPair), type(uint256).max);
        vm.stopPrank();
    }

    // --- Deployment and Initialization Tests ---

    function test_Deployment() public view {
        assertEq(
            address(optionPair.underlyingToken()),
            address(underlyingToken),
            "Underlying token mismatch"
        );
        assertEq(
            address(optionPair.strikeToken()),
            address(strikeToken),
            "Strike token mismatch"
        );
    }

    function _createAndFillAsk() internal returns (uint256 optionId) {
        vm.startPrank(seller);
        optionPair.createAsk(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );
        vm.stopPrank();

        optionId = 1;

        vm.startPrank(buyer);
        optionPair.fillAsk(optionId);
        vm.stopPrank();
    }

    function testGetClosingFeePercentage() public {
        uint256 optionId = _createAndFillAsk();

        // --- Test Case 1: Half time remaining ---
        vm.warp(block.timestamp + PERIOD_IN_SECONDS / 2);

        UD60x18 feePercentHalfTime = optionPair.getClosingFeePercentage(
            optionId
        );

        // Expected: Y = 1 - (1 - 0.5)^2 = 1 - 0.25 = 0.75
        assertEq(
            feePercentHalfTime.intoUint256(),
            0.75e18,
            "Fee percent at half time should be 0.75"
        );

        // --- Test Case 2: Full time remaining (almost) ---
        // We need to get the timestamp right after filling the ask
        MutatedOptionPairV2.Option memory option = optionPair.getOption(
            optionId
        );
        vm.warp(option.createTimestamp + 1); // Go back to near the beginning

        UD60x18 feePercentFullTime = optionPair.getClosingFeePercentage(
            optionId
        );
        // Expected: Y should be close to 1
        assertTrue(
            feePercentFullTime.intoUint256() > 0.99e18,
            "Fee percent at full time should be close to 1"
        );

        // --- Test Case 3: No time remaining ---
        vm.warp(option.expirationTimestamp);
        UD60x18 feePercentNoTime = optionPair.getClosingFeePercentage(optionId);
        // Expected: Y = 0
        assertEq(
            feePercentNoTime.intoUint256(),
            0,
            "Fee percent at no time remaining should be 0"
        );
    }

    function testCalculateClosingFeeAmount() public {
        uint256 optionId = _createAndFillAsk();

        // --- Test Case 1: Half time remaining ---
        vm.warp(block.timestamp + PERIOD_IN_SECONDS / 2);
        uint256 closingFeeAmount = optionPair.calculateClosingFeeAmount(
            optionId
        );

        // Expected: 10 * 0.75 = 7.5
        assertEq(
            closingFeeAmount,
            7.5e18,
            "Closing fee at half time should be 7.5"
        );
    }

    function testCloseOption() public {
        uint256 optionId = _createAndFillAsk();

        vm.warp(block.timestamp + PERIOD_IN_SECONDS / 2); // Half time

        uint256 closingFee = optionPair.calculateClosingFeeAmount(optionId);
        uint256 sellerStrikeBalanceBefore = strikeToken.balanceOf(seller);
        uint256 buyerStrikeBalanceBefore = strikeToken.balanceOf(buyer);
        uint256 sellerUnderlyingBalanceBefore = underlyingToken.balanceOf(
            seller
        );
        uint256 contractUnderlyingBalanceBefore = underlyingToken.balanceOf(
            address(optionPair)
        );

        vm.startPrank(seller);
        optionPair.closeOption(optionId);
        vm.stopPrank();

        // Check balances
        assertEq(
            strikeToken.balanceOf(seller),
            sellerStrikeBalanceBefore - closingFee,
            "Seller should pay closing fee"
        );
        assertEq(
            strikeToken.balanceOf(buyer),
            buyerStrikeBalanceBefore + closingFee,
            "Buyer should receive closing fee"
        );
        assertEq(
            underlyingToken.balanceOf(seller),
            sellerUnderlyingBalanceBefore + UNDERLYING_AMOUNT,
            "Seller should get underlying back"
        );
        assertEq(
            underlyingToken.balanceOf(address(optionPair)),
            contractUnderlyingBalanceBefore - UNDERLYING_AMOUNT,
            "Contract should release underlying"
        );

        // Check option state
        MutatedOptionPairV2.Option memory option = optionPair.getOption(
            optionId
        );
        assertEq(
            uint(option.state),
            uint(MutatedOptionPairV2.OptionState.Closed),
            "Option state should be Closed"
        );
    }

    function test_CloseOption_RevertsWhenNotActive() public {
        vm.startPrank(seller);
        optionPair.createAsk(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );
        vm.stopPrank();

        uint256 optionId = 1;

        vm.startPrank(seller);
        vm.expectRevert("Option: Not active");
        optionPair.closeOption(optionId);
        vm.stopPrank();
    }

    function test_CloseOption_RevertsWhenNotSeller() public {
        uint256 optionId = _createAndFillAsk();

        vm.startPrank(buyer); // Try to close from buyer's account
        vm.expectRevert("Option: Only seller can close");
        optionPair.closeOption(optionId);
        vm.stopPrank();
    }

    function test_CloseOption_RevertsWhenExpired() public {
        uint256 optionId = _createAndFillAsk();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(
            optionId
        );
        vm.warp(option.expirationTimestamp + 1); // Expire the option

        vm.startPrank(seller);
        vm.expectRevert("Option: Already expired");
        optionPair.closeOption(optionId);
        vm.stopPrank();
    }

    // --- Bid and Fill Bid Tests ---

    function _createAndFillBid() internal returns (uint256 optionId) {
        vm.startPrank(buyer);
        optionPair.createBid(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );
        vm.stopPrank();

        optionId = 1;

        vm.startPrank(seller);
        optionPair.fillBid(optionId);
        vm.stopPrank();
    }

    function test_CreateAndFillBid_Success() public {
        uint256 sellerUnderlyingBalanceBefore = underlyingToken.balanceOf(
            seller
        );
        uint256 contractStrikeBalanceBefore = strikeToken.balanceOf(
            address(optionPair)
        );
        uint256 contractUnderlyingBalanceBefore = underlyingToken.balanceOf(
            address(optionPair)
        );

        _createAndFillBid();
        uint256 optionId = 1;

        MutatedOptionPairV2.Option memory option = optionPair.getOption(
            optionId
        );

        // Check option state
        assertEq(
            uint(option.state),
            uint(MutatedOptionPairV2.OptionState.Active)
        );
        assertEq(option.buyer, buyer);
        assertEq(option.seller, seller);

        // Check balances after fill
        // Buyer's premium is locked in createBid, then transferred to seller in fillBid.
        // Net change for buyer is 0 from their perspective at this point, as the premium is gone.
        // The contract's strike balance should be net zero (premium in, premium out).
        assertEq(
            strikeToken.balanceOf(address(optionPair)),
            contractStrikeBalanceBefore,
            "Contract strike balance should be net zero"
        );

        // Seller receives the premium
        assertEq(
            strikeToken.balanceOf(seller),
            strikeToken.balanceOf(seller),
            "Seller should receive premium"
        );

        // Seller locks underlying asset
        assertEq(
            underlyingToken.balanceOf(seller),
            sellerUnderlyingBalanceBefore - UNDERLYING_AMOUNT,
            "Seller should have locked underlying"
        );
        assertEq(
            underlyingToken.balanceOf(address(optionPair)),
            contractUnderlyingBalanceBefore + UNDERLYING_AMOUNT,
            "Contract should hold underlying"
        );
    }

    // --- Cancel Order Tests ---

    function test_Cancel_AskOrder_Success() public {
        vm.startPrank(seller);
        optionPair.createAsk(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );
        vm.stopPrank();
        uint256 optionId = 1;

        uint256 sellerUnderlyingBalanceBefore = underlyingToken.balanceOf(
            seller
        );
        uint256 contractUnderlyingBalanceBefore = underlyingToken.balanceOf(
            address(optionPair)
        );

        vm.startPrank(seller);
        optionPair.cancelOrder(optionId);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(
            optionId
        );
        assertEq(
            uint(option.state),
            uint(MutatedOptionPairV2.OptionState.Canceled)
        );
        assertEq(
            underlyingToken.balanceOf(seller),
            sellerUnderlyingBalanceBefore + UNDERLYING_AMOUNT,
            "Seller should get underlying back"
        );
        assertEq(
            underlyingToken.balanceOf(address(optionPair)),
            contractUnderlyingBalanceBefore - UNDERLYING_AMOUNT,
            "Contract should release underlying"
        );
    }

    function test_Cancel_BidOrder_Success() public {
        vm.startPrank(buyer);
        optionPair.createBid(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );
        vm.stopPrank();
        uint256 optionId = 1;

        uint256 buyerStrikeBalanceBefore = strikeToken.balanceOf(buyer);
        uint256 contractStrikeBalanceBefore = strikeToken.balanceOf(
            address(optionPair)
        );

        vm.startPrank(buyer);
        optionPair.cancelOrder(optionId);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(
            optionId
        );
        assertEq(
            uint(option.state),
            uint(MutatedOptionPairV2.OptionState.Canceled)
        );
        assertEq(
            strikeToken.balanceOf(buyer),
            buyerStrikeBalanceBefore + PREMIUM_AMOUNT,
            "Buyer should get premium back"
        );
        assertEq(
            strikeToken.balanceOf(address(optionPair)),
            contractStrikeBalanceBefore - PREMIUM_AMOUNT,
            "Contract should release premium"
        );
    }

    function test_Cancel_RevertsWhenNotCreator() public {
        vm.startPrank(seller);
        optionPair.createAsk(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );
        vm.stopPrank();
        uint256 optionId = 1;

        vm.startPrank(buyer); // Not the creator
        vm.expectRevert("Order: Only creator can cancel");
        optionPair.cancelOrder(optionId);
        vm.stopPrank();
    }

    // --- Exercise Option Tests ---

    function test_ExerciseOption_Success() public {
        uint256 optionId = _createAndFillAsk();

        uint256 buyerStrikeBalanceBefore = strikeToken.balanceOf(buyer);
        uint256 sellerStrikeBalanceBefore = strikeToken.balanceOf(seller);
        uint256 buyerUnderlyingBalanceBefore = underlyingToken.balanceOf(buyer);
        uint256 contractUnderlyingBalanceBefore = underlyingToken.balanceOf(
            address(optionPair)
        );

        vm.startPrank(buyer);
        optionPair.exerciseOption(optionId);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(
            optionId
        );
        assertEq(
            uint(option.state),
            uint(MutatedOptionPairV2.OptionState.Exercised)
        );

        // Buyer pays strike, gets underlying
        assertEq(
            strikeToken.balanceOf(buyer),
            buyerStrikeBalanceBefore - STRIKE_AMOUNT,
            "Buyer should pay strike amount"
        );
        assertEq(
            underlyingToken.balanceOf(buyer),
            buyerUnderlyingBalanceBefore + UNDERLYING_AMOUNT,
            "Buyer should receive underlying"
        );

        // Seller receives strike
        assertEq(
            strikeToken.balanceOf(seller),
            sellerStrikeBalanceBefore + STRIKE_AMOUNT,
            "Seller should receive strike amount"
        );

        // Contract releases underlying
        assertEq(
            underlyingToken.balanceOf(address(optionPair)),
            contractUnderlyingBalanceBefore - UNDERLYING_AMOUNT,
            "Contract should release underlying"
        );
    }

    function test_ExerciseOption_RevertsWhenNotBuyer() public {
        uint256 optionId = _createAndFillAsk();

        vm.startPrank(seller); // Not the buyer
        vm.expectRevert("Option: Only buyer can exercise");
        optionPair.exerciseOption(optionId);
        vm.stopPrank();
    }

    // --- Claim Underlying on Expiration Tests ---

    function test_ClaimUnderlying_Success() public {
        uint256 optionId = _createAndFillAsk();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(
            optionId
        );
        vm.warp(option.expirationTimestamp + 1); // Expire the option

        uint256 sellerUnderlyingBalanceBefore = underlyingToken.balanceOf(
            seller
        );
        uint256 contractUnderlyingBalanceBefore = underlyingToken.balanceOf(
            address(optionPair)
        );

        vm.startPrank(seller);
        optionPair.claimUnderlyingOnExpiration(optionId);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory expiredOption = optionPair.getOption(
            optionId
        );
        assertEq(
            uint(expiredOption.state),
            uint(MutatedOptionPairV2.OptionState.Expired)
        );

        // Seller gets underlying back
        assertEq(
            underlyingToken.balanceOf(seller),
            sellerUnderlyingBalanceBefore + UNDERLYING_AMOUNT,
            "Seller should get underlying back"
        );
        assertEq(
            underlyingToken.balanceOf(address(optionPair)),
            contractUnderlyingBalanceBefore - UNDERLYING_AMOUNT,
            "Contract should release underlying"
        );
    }

    function test_ClaimUnderlying_RevertsWhenNotSeller() public {
        uint256 optionId = _createAndFillAsk();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(
            optionId
        );
        vm.warp(option.expirationTimestamp + 1);

        vm.startPrank(buyer); // Not the seller
        vm.expectRevert("Option: Only seller can claim");
        optionPair.claimUnderlyingOnExpiration(optionId);
        vm.stopPrank();
    }

    function test_ClaimUnderlying_RevertsWhenNotExpired() public {
        uint256 optionId = _createAndFillAsk();

        vm.startPrank(seller);
        vm.expectRevert("Option: Not expired yet");
        optionPair.claimUnderlyingOnExpiration(optionId);
        vm.stopPrank();
    }

    // --- Additional Revert Tests for Branch Coverage ---

    function test_CreateAsk_RevertsWithZeroAmount() public {
        vm.startPrank(seller);
        vm.expectRevert("Ask: Underlying amount must be > 0");
        optionPair.createAsk(
            0,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );

        vm.expectRevert("Ask: Strike amount must be > 0");
        optionPair.createAsk(
            UNDERLYING_AMOUNT,
            0,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );

        vm.expectRevert("Ask: Premium amount must be > 0");
        optionPair.createAsk(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            0,
            PERIOD_IN_SECONDS
        );

        vm.expectRevert("Ask: Period must be at least 1 hour (3600 seconds)");
        optionPair.createAsk(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            0
        );
        vm.stopPrank();
    }

    function test_CreateBid_RevertsWithZeroAmount() public {
        vm.startPrank(buyer);
        vm.expectRevert("Bid: Underlying amount must be > 0");
        optionPair.createBid(
            0,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );

        vm.expectRevert("Bid: Strike amount must be > 0");
        optionPair.createBid(
            UNDERLYING_AMOUNT,
            0,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );

        vm.expectRevert("Bid: Premium amount must be > 0");
        optionPair.createBid(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            0,
            PERIOD_IN_SECONDS
        );

        vm.expectRevert("Bid: Period must be at least 1 hour (3600 seconds)");
        optionPair.createBid(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            0
        );
        vm.stopPrank();
    }

    function test_FillAsk_RevertsOnWrongOrderType() public {
        // Create a Bid order
        vm.startPrank(buyer);
        optionPair.createBid(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );
        vm.stopPrank();
        uint256 bidOptionId = 1;

        // Try to fill it as an Ask
        vm.startPrank(seller);
        vm.expectRevert("Order: Not an Ask");
        optionPair.fillAsk(bidOptionId);
        vm.stopPrank();
    }

    function test_FillAsk_RevertsWhenSellerFillsOwn() public {
        vm.startPrank(seller);
        optionPair.createAsk(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );
        vm.stopPrank();
        uint256 askOptionId = 1;

        vm.startPrank(seller);
        vm.expectRevert("Order: Seller cannot fill their own Ask");
        optionPair.fillAsk(askOptionId);
        vm.stopPrank();
    }

    function test_FillBid_RevertsOnWrongOrderType() public {
        // Create an Ask order
        vm.startPrank(seller);
        optionPair.createAsk(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );
        vm.stopPrank();
        uint256 askOptionId = 1;

        // Try to fill it as a Bid
        vm.startPrank(buyer);
        vm.expectRevert("Order: Not a Bid");
        optionPair.fillBid(askOptionId);
        vm.stopPrank();
    }

    function test_FillBid_RevertsWhenBuyerFillsOwn() public {
        vm.startPrank(buyer);
        optionPair.createBid(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );
        vm.stopPrank();
        uint256 bidOptionId = 1;

        vm.startPrank(buyer);
        vm.expectRevert("Order: Buyer cannot fill their own Bid");
        optionPair.fillBid(bidOptionId);
        vm.stopPrank();
    }

    function test_Cancel_RevertsWhenNotOpen() public {
        uint256 optionId = _createAndFillAsk(); // Creates an Active order
        vm.startPrank(seller);
        vm.expectRevert("Order: Not open");
        optionPair.cancelOrder(optionId);
        vm.stopPrank();
    }

    function test_ExerciseOption_RevertsWhenExpired() public {
        uint256 optionId = _createAndFillAsk();
        MutatedOptionPairV2.Option memory option = optionPair.getOption(
            optionId
        );
        vm.warp(option.expirationTimestamp + 1); // Expire

        vm.startPrank(buyer);
        vm.expectRevert("Option: Expired");
        optionPair.exerciseOption(optionId);
        vm.stopPrank();
    }

    function test_ClaimUnderlying_RevertsWhenNotActive() public {
        vm.startPrank(seller);
        optionPair.createAsk(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );
        vm.stopPrank();
        uint256 optionId = 1; // State is Open, not Active

        MutatedOptionPairV2.Option memory option = optionPair.getOption(
            optionId
        );
        vm.warp(option.expirationTimestamp + 1); // Expire

        vm.startPrank(seller);
        vm.expectRevert("Option: Not active");
        optionPair.claimUnderlyingOnExpiration(optionId);
        vm.stopPrank();
    }

    function test_GetClosingFeePercentage_RevertsWhenNotActive() public {
        vm.startPrank(seller);
        optionPair.createAsk(
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            PERIOD_IN_SECONDS
        );
        vm.stopPrank();
        uint256 optionId = 1; // State is Open

        vm.expectRevert("Option not active for fee calculation");
        optionPair.getClosingFeePercentage(optionId);
    }

    function test_CloseOption_RevertsWhenExpiredAtBoundary() public {
        uint256 optionId = _createAndFillAsk();
        MutatedOptionPairV2.Option memory option = optionPair.getOption(
            optionId
        );
        vm.warp(option.expirationTimestamp); // Exactly at expiration

        vm.startPrank(seller);
        // At the exact expiration timestamp, the first check should fail.
        vm.expectRevert("Option: Already expired");
        optionPair.closeOption(optionId);
        vm.stopPrank();
    }

    function testCloseOptionRightAfterFill() public {
        uint256 optionId = _createAndFillAsk();

        // Close immediately (1 second after fill)
        vm.warp(block.timestamp + 1);

        uint256 closingFee = optionPair.calculateClosingFeeAmount(optionId);

        // Fee should be very close to the premium amount
        uint256 expectedFee = optionPair
            .getClosingFeePercentage(optionId)
            .mul(ud(PREMIUM_AMOUNT))
            .intoUint256();
        assertApproxEqAbs(
            closingFee,
            expectedFee,
            1e12,
            "Fee should be close to expected fee right after fill"
        );
        assertTrue(
            closingFee < PREMIUM_AMOUNT,
            "Fee must be less than total premium"
        );
        assertTrue(
            closingFee > (PREMIUM_AMOUNT * 999) / 1000,
            "Fee should be > 99.9% of premium"
        );

        vm.startPrank(seller);
        optionPair.closeOption(optionId);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(
            optionId
        );
        assertEq(
            uint(option.state),
            uint(MutatedOptionPairV2.OptionState.Closed),
            "Option state should be Closed"
        );
    }

    function testCloseOptionRightBeforeExpiration() public {
        uint256 optionId = _createAndFillAsk();

        // Close 1 second before expiration
        vm.warp(block.timestamp + PERIOD_IN_SECONDS - 1);

        uint256 closingFee = optionPair.calculateClosingFeeAmount(optionId);

        // Fee should be very close to 0
        assertTrue(
            closingFee < PREMIUM_AMOUNT / 100,
            "Fee should be < 1% of premium right before expiration"
        );
        assertTrue(closingFee > 0, "Fee should be greater than 0");

        vm.startPrank(seller);
        optionPair.closeOption(optionId);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(
            optionId
        );
        assertEq(
            uint(option.state),
            uint(MutatedOptionPairV2.OptionState.Closed),
            "Option state should be Closed"
        );
    }
}
