// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/MutatedOptionPairV2.sol";
import "../contracts/MutatedOptionFactoryV2.sol";
import "../contracts/TestToken.sol";

contract MutatedOptionPairV2Test is Test {
    MutatedOptionPairV2 public optionPair;
    MutatedOptionFactoryV2 public optionFactory;
    TestToken public underlyingToken;
    TestToken public strikeToken;

    address public deployer;
    address public seller;
    address public buyer;
    address public other;

    uint256 public constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 public constant UNDERLYING_AMOUNT = 100e18;
    uint256 public constant STRIKE_AMOUNT = 500e18;
    uint256 public constant PREMIUM_AMOUNT = 10e18;
    uint256 public constant CLOSING_FEE_AMOUNT = 5e18;
    uint256 public constant PERIOD_IN_SECONDS = 3600; // 1 hour

    function setUp() public {
        deployer = makeAddr("deployer");
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        other = makeAddr("other");

        vm.startPrank(deployer);
        underlyingToken = new TestToken("Underlying", "UND", INITIAL_SUPPLY);
        strikeToken = new TestToken("Strike", "STK", INITIAL_SUPPLY);
        optionFactory = new MutatedOptionFactoryV2();
        bytes32 salt = keccak256("test_salt");
        address pairAddress = optionFactory.createOptionPair(address(underlyingToken), address(strikeToken), salt);
        optionPair = MutatedOptionPairV2(payable(pairAddress));
        vm.stopPrank();

        // Distribute tokens and approve the optionPair contract
        vm.startPrank(deployer);
        underlyingToken.transfer(seller, INITIAL_SUPPLY / 2);
        strikeToken.transfer(buyer, INITIAL_SUPPLY / 2);
        strikeToken.transfer(seller, INITIAL_SUPPLY / 2); // For seller to pay strike/closing fee if they fill bid
        vm.stopPrank();

        vm.startPrank(seller);
        underlyingToken.approve(address(optionPair), type(uint256).max);
        strikeToken.approve(address(optionPair), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(buyer);
        underlyingToken.approve(address(optionPair), type(uint256).max);
        strikeToken.approve(address(optionPair), type(uint256).max);
        vm.stopPrank();
    }

    // --- Deployment and Initialization Tests ---

    function test_Deployment() public view {
        assertEq(address(optionPair.underlyingToken()), address(underlyingToken), "Underlying token mismatch");
        assertEq(address(optionPair.strikeToken()), address(strikeToken), "Strike token mismatch");
    }

    // --- Create Ask Tests ---

    function test_CreateAsk_Success() public {
        uint256 sellerUnderlyingBalBefore = underlyingToken.balanceOf(seller);

        vm.startPrank(seller);
        vm.expectEmit(true, true, true, true);
        emit MutatedOptionPairV2.OrderCreated(
            1,
            MutatedOptionPairV2.OrderType.Ask,
            seller,
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            block.timestamp + PERIOD_IN_SECONDS
        );
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(1);
        assertEq(option.optionId, 1, "Option ID mismatch");
        assertEq(option.creator, seller, "Creator mismatch");
        assertEq(option.seller, seller, "Seller mismatch");
        assertEq(option.buyer, address(0), "Buyer should be zero address");
        assertEq(option.underlyingAmount, UNDERLYING_AMOUNT, "Underlying amount mismatch");
        assertEq(option.strikeAmount, STRIKE_AMOUNT, "Strike amount mismatch");
        assertEq(option.premiumAmount, PREMIUM_AMOUNT, "Premium amount mismatch");
        assertEq(option.expirationTimestamp, block.timestamp + PERIOD_IN_SECONDS, "Expiration timestamp mismatch");
        assertEq(option.closingFeeAmount, 0, "Closing fee should be 0 for Ask");
        assertEq(uint8(option.orderType), uint8(MutatedOptionPairV2.OrderType.Ask), "Order type mismatch");
        assertEq(uint8(option.state), uint8(MutatedOptionPairV2.OptionState.Open), "Option state mismatch");

        assertEq(underlyingToken.balanceOf(address(optionPair)), UNDERLYING_AMOUNT, "Contract underlying balance incorrect");
        assertEq(underlyingToken.balanceOf(seller), sellerUnderlyingBalBefore - UNDERLYING_AMOUNT, "Seller underlying balance incorrect");
    }

    function test_CreateAsk_RevertZeroUnderlying() public {
        vm.startPrank(seller);
        vm.expectRevert("Ask: Underlying amount must be > 0");
        optionPair.createAsk(0, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();
    }

    function test_CreateAsk_RevertZeroStrike() public {
        vm.startPrank(seller);
        vm.expectRevert("Ask: Strike amount must be > 0");
        optionPair.createAsk(UNDERLYING_AMOUNT, 0, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();
    }

    function test_CreateAsk_RevertZeroPremium() public {
        vm.startPrank(seller);
        vm.expectRevert("Ask: Premium amount must be > 0");
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, 0, PERIOD_IN_SECONDS);
        vm.stopPrank();
    }

    function test_CreateAsk_RevertZeroPeriod() public {
        vm.startPrank(seller);
        vm.expectRevert("Ask: Period must be > 0");
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, 0);
        vm.stopPrank();
    }

    // --- Create Bid Tests ---

    function test_CreateBid_Success() public {
        uint256 buyerStrikeBalBefore = strikeToken.balanceOf(buyer);

        vm.startPrank(buyer);
        vm.expectEmit(true, true, true, true);
        emit MutatedOptionPairV2.OrderCreated(
            1,
            MutatedOptionPairV2.OrderType.Bid,
            buyer,
            UNDERLYING_AMOUNT,
            STRIKE_AMOUNT,
            PREMIUM_AMOUNT,
            block.timestamp + PERIOD_IN_SECONDS
        );
        optionPair.createBid(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(1);
        assertEq(option.optionId, 1, "Option ID mismatch");
        assertEq(option.creator, buyer, "Creator mismatch");
        assertEq(option.seller, address(0), "Seller should be zero address");
        assertEq(option.buyer, buyer, "Buyer mismatch");
        assertEq(option.underlyingAmount, UNDERLYING_AMOUNT, "Underlying amount mismatch");
        assertEq(option.strikeAmount, STRIKE_AMOUNT, "Strike amount mismatch");
        assertEq(option.premiumAmount, PREMIUM_AMOUNT, "Premium amount mismatch");
        assertEq(option.expirationTimestamp, block.timestamp + PERIOD_IN_SECONDS, "Expiration timestamp mismatch");
        assertEq(option.closingFeeAmount, CLOSING_FEE_AMOUNT, "Closing fee mismatch");
        assertEq(uint8(option.orderType), uint8(MutatedOptionPairV2.OrderType.Bid), "Order type mismatch");
        assertEq(uint8(option.state), uint8(MutatedOptionPairV2.OptionState.Open), "Option state mismatch");

        assertEq(strikeToken.balanceOf(address(optionPair)), PREMIUM_AMOUNT, "Contract strike balance incorrect");
        assertEq(strikeToken.balanceOf(buyer), buyerStrikeBalBefore - PREMIUM_AMOUNT, "Buyer strike balance incorrect");
    }

    function test_CreateBid_RevertZeroUnderlying() public {
        vm.startPrank(buyer);
        vm.expectRevert("Bid: Underlying amount must be > 0");
        optionPair.createBid(0, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS, CLOSING_FEE_AMOUNT);
        vm.stopPrank();
    }

    function test_CreateBid_RevertZeroStrike() public {
        vm.startPrank(buyer);
        vm.expectRevert("Bid: Strike amount must be > 0");
        optionPair.createBid(UNDERLYING_AMOUNT, 0, PREMIUM_AMOUNT, PERIOD_IN_SECONDS, CLOSING_FEE_AMOUNT);
        vm.stopPrank();
    }

    function test_CreateBid_RevertZeroPremium() public {
        vm.startPrank(buyer);
        vm.expectRevert("Bid: Premium amount must be > 0");
        optionPair.createBid(UNDERLYING_AMOUNT, STRIKE_AMOUNT, 0, PERIOD_IN_SECONDS, CLOSING_FEE_AMOUNT);
        vm.stopPrank();
    }

    function test_CreateBid_RevertZeroPeriod() public {
        vm.startPrank(buyer);
        vm.expectRevert("Bid: Period must be > 0");
        optionPair.createBid(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, 0, CLOSING_FEE_AMOUNT);
        vm.stopPrank();
    }

    // --- Fill Ask Tests ---

    function test_FillAsk_Success() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        uint256 sellerStrikeBalBefore = strikeToken.balanceOf(seller);
        uint256 buyerStrikeBalBefore = strikeToken.balanceOf(buyer);

        vm.startPrank(buyer);
        vm.expectEmit(true, true, true, true);
        emit MutatedOptionPairV2.OrderFilled(
            1,
            buyer,
            seller,
            PREMIUM_AMOUNT,
            CLOSING_FEE_AMOUNT
        );
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(1);
        assertEq(option.buyer, buyer, "Buyer not set correctly");
        assertEq(option.closingFeeAmount, CLOSING_FEE_AMOUNT, "Closing fee not set correctly");
        assertEq(uint8(option.state), uint8(MutatedOptionPairV2.OptionState.Active), "Option state not Active");

        assertEq(strikeToken.balanceOf(seller), sellerStrikeBalBefore + PREMIUM_AMOUNT, "Seller did not receive premium");
        assertEq(strikeToken.balanceOf(buyer), buyerStrikeBalBefore - PREMIUM_AMOUNT, "Buyer did not pay premium");
    }

    function test_FillAsk_RevertNotOpen() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(buyer);
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT); // Fill it once
        vm.expectRevert("Order: Not open");
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT); // Try to fill again
        vm.stopPrank();
    }

    function test_FillAsk_RevertNotAnAsk() public {
        vm.startPrank(buyer);
        optionPair.createBid(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectRevert("Order: Not an Ask");
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT);
        vm.stopPrank();
    }

    function test_FillAsk_RevertSellerFillsOwnAsk() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.expectRevert("Order: Seller cannot fill their own Ask");
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT);
        vm.stopPrank();
    }

    // --- Fill Bid Tests ---

    function test_FillBid_Success() public {
        vm.startPrank(buyer);
        optionPair.createBid(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        uint256 sellerUnderlyingBalBefore = underlyingToken.balanceOf(seller);
        uint256 sellerStrikeBalBefore = strikeToken.balanceOf(seller);

        vm.startPrank(seller);
        vm.expectEmit(true, true, true, true);
        emit MutatedOptionPairV2.OrderFilled(
            1,
            buyer,
            seller,
            PREMIUM_AMOUNT,
            CLOSING_FEE_AMOUNT
        );
        optionPair.fillBid(1);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(1);
        assertEq(option.seller, seller, "Seller not set correctly");
        assertEq(uint8(option.state), uint8(MutatedOptionPairV2.OptionState.Active), "Option state not Active");

        assertEq(underlyingToken.balanceOf(address(optionPair)), UNDERLYING_AMOUNT, "Contract underlying balance incorrect");
        assertEq(sellerUnderlyingBalBefore - UNDERLYING_AMOUNT, underlyingToken.balanceOf(seller), "Seller underlying balance incorrect");
        assertEq(strikeToken.balanceOf(address(optionPair)), 0, "Contract strike balance incorrect after premium transfer");
        assertEq(strikeToken.balanceOf(seller), sellerStrikeBalBefore + PREMIUM_AMOUNT, "Seller did not receive premium");
    }

    function test_FillBid_RevertNotOpen() public {
        vm.startPrank(buyer);
        optionPair.createBid(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(seller);
        optionPair.fillBid(1); // Fill it once
        vm.expectRevert("Order: Not open");
        optionPair.fillBid(1); // Try to fill again
        vm.stopPrank();
    }

    function test_FillBid_RevertNotABid() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(buyer);
        vm.expectRevert("Order: Not a Bid");
        optionPair.fillBid(1);
        vm.stopPrank();
    }

    function test_FillBid_RevertBuyerFillsOwnBid() public {
        vm.startPrank(buyer);
        optionPair.createBid(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS, CLOSING_FEE_AMOUNT);
        vm.expectRevert("Order: Buyer cannot fill their own Bid");
        optionPair.fillBid(1);
        vm.stopPrank();
    }

    // --- Cancel Order Tests ---

    function test_CancelAskOrder_Success() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        uint256 sellerUnderlyingBalBefore = underlyingToken.balanceOf(seller);

        vm.startPrank(seller);
        vm.expectEmit(true, true, false, true);
        emit MutatedOptionPairV2.OrderCanceled(1, seller);
        optionPair.cancelOrder(1);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(1);
        assertEq(uint8(option.state), uint8(MutatedOptionPairV2.OptionState.Canceled), "Option state not Canceled");
        assertEq(underlyingToken.balanceOf(seller), sellerUnderlyingBalBefore + UNDERLYING_AMOUNT, "Seller did not receive underlying refund");
        assertEq(underlyingToken.balanceOf(address(optionPair)), 0, "Contract underlying balance not zero");
    }

    function test_CancelBidOrder_Success() public {
        vm.startPrank(buyer);
        optionPair.createBid(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        uint256 buyerStrikeBalBefore = strikeToken.balanceOf(buyer);

        vm.startPrank(buyer);
        vm.expectEmit(true, true, false, true);
        emit MutatedOptionPairV2.OrderCanceled(1, buyer);
        optionPair.cancelOrder(1);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(1);
        assertEq(uint8(option.state), uint8(MutatedOptionPairV2.OptionState.Canceled), "Option state not Canceled");
        assertEq(strikeToken.balanceOf(buyer), buyerStrikeBalBefore + PREMIUM_AMOUNT, "Buyer did not receive premium refund");
        assertEq(strikeToken.balanceOf(address(optionPair)), 0, "Contract strike balance not zero");
    }

    function test_CancelOrder_RevertNotOpen() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(buyer);
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT); // Fill it
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectRevert("Order: Not open");
        optionPair.cancelOrder(1); // Try to cancel active order
        vm.stopPrank();
    }

    function test_CancelOrder_RevertNotCreator() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(other);
        vm.expectRevert("Order: Only creator can cancel");
        optionPair.cancelOrder(1);
        vm.stopPrank();
    }

    // --- Exercise Option Tests ---

    function test_ExerciseOption_Success() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(buyer);
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        uint256 buyerUnderlyingBalBefore = underlyingToken.balanceOf(buyer);
        uint256 sellerStrikeBalBefore = strikeToken.balanceOf(seller);

        vm.startPrank(buyer);
        vm.expectEmit(true, true, true, true);
        emit MutatedOptionPairV2.OptionExercised(
            1,
            buyer,
            seller,
            STRIKE_AMOUNT,
            UNDERLYING_AMOUNT
        );
        optionPair.exerciseOption(1);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(1);
        assertEq(uint8(option.state), uint8(MutatedOptionPairV2.OptionState.Exercised), "Option state not Exercised");

        assertEq(underlyingToken.balanceOf(buyer), buyerUnderlyingBalBefore + UNDERLYING_AMOUNT, "Buyer did not receive underlying");
        assertEq(strikeToken.balanceOf(seller), sellerStrikeBalBefore + STRIKE_AMOUNT, "Seller did not receive strike");
        assertEq(underlyingToken.balanceOf(address(optionPair)), 0, "Contract underlying balance not zero");
    }

    function test_ExerciseOption_RevertNotActive() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(buyer);
        vm.expectRevert("Option: Not active");
        optionPair.exerciseOption(1); // Try to exercise open order
        vm.stopPrank();
    }

    function test_ExerciseOption_RevertNotBuyer() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(buyer);
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectRevert("Option: Only buyer can exercise");
        optionPair.exerciseOption(1);
        vm.stopPrank();
    }

    function test_ExerciseOption_RevertExpired() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(buyer);
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + PERIOD_IN_SECONDS + 1); // Advance time past expiration

        vm.startPrank(buyer);
        vm.expectRevert("Option: Expired");
        optionPair.exerciseOption(1);
        vm.stopPrank();
    }

    // --- Claim Underlying on Expiration Tests ---

    function test_ClaimUnderlyingOnExpiration_Success() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(buyer);
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + PERIOD_IN_SECONDS + 1); // Advance time past expiration

        uint256 sellerUnderlyingBalBefore = underlyingToken.balanceOf(seller);

        vm.startPrank(seller);
        vm.expectEmit(true, true, false, true);
        emit MutatedOptionPairV2.OptionExpired(1, seller, UNDERLYING_AMOUNT);
        optionPair.claimUnderlyingOnExpiration(1);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(1);
        assertEq(uint8(option.state), uint8(MutatedOptionPairV2.OptionState.Expired), "Option state not Expired");
        assertEq(underlyingToken.balanceOf(seller), sellerUnderlyingBalBefore + UNDERLYING_AMOUNT, "Seller did not receive underlying");
        assertEq(underlyingToken.balanceOf(address(optionPair)), 0, "Contract underlying balance not zero");
    }

    function test_ClaimUnderlyingOnExpiration_RevertNotActive() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.warp(block.timestamp + PERIOD_IN_SECONDS + 1); // Advance time past expiration

        vm.startPrank(seller);
        vm.expectRevert("Option: Not active");
        optionPair.claimUnderlyingOnExpiration(1); // Try to claim on open order
        vm.stopPrank();
    }

    function test_ClaimUnderlyingOnExpiration_RevertNotSeller() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(buyer);
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + PERIOD_IN_SECONDS + 1); // Advance time past expiration

        vm.startPrank(buyer);
        vm.expectRevert("Option: Only seller can claim");
        optionPair.claimUnderlyingOnExpiration(1);
        vm.stopPrank();
    }

    function test_ClaimUnderlyingOnExpiration_RevertNotExpiredYet() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(buyer);
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectRevert("Option: Not expired yet");
        optionPair.claimUnderlyingOnExpiration(1);
        vm.stopPrank();
    }

    // --- Close Option Tests ---

    function test_CloseOption_Success() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(buyer);
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        uint256 sellerUnderlyingBalBefore = underlyingToken.balanceOf(seller);
        uint256 buyerStrikeBalBefore = strikeToken.balanceOf(buyer);

        vm.startPrank(seller);
        vm.expectEmit(true, true, true, true);
        emit MutatedOptionPairV2.OptionClosed(
            1,
            seller,
            buyer,
            CLOSING_FEE_AMOUNT,
            UNDERLYING_AMOUNT
        );
        optionPair.closeOption(1);
        vm.stopPrank();

        MutatedOptionPairV2.Option memory option = optionPair.getOption(1);
        assertEq(uint8(option.state), uint8(MutatedOptionPairV2.OptionState.Closed), "Option state not Closed");

        assertEq(underlyingToken.balanceOf(seller), sellerUnderlyingBalBefore + UNDERLYING_AMOUNT, "Seller did not receive underlying");
        assertEq(strikeToken.balanceOf(buyer), buyerStrikeBalBefore + CLOSING_FEE_AMOUNT, "Buyer did not receive closing fee");
        assertEq(underlyingToken.balanceOf(address(optionPair)), 0, "Contract underlying balance not zero");
    }

    function test_CloseOption_RevertNotActive() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectRevert("Option: Not active");
        optionPair.closeOption(1); // Try to close open order
        vm.stopPrank();
    }

    function test_CloseOption_RevertNotSeller() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(buyer);
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(buyer);
        vm.expectRevert("Option: Only seller can close");
        optionPair.closeOption(1);
        vm.stopPrank();
    }

    function test_CloseOption_RevertAlreadyExpired() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(buyer);
        optionPair.fillAsk(1, CLOSING_FEE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + PERIOD_IN_SECONDS + 1); // Advance time past expiration

        vm.startPrank(seller);
        vm.expectRevert("Option: Already expired");
        optionPair.closeOption(1);
        vm.stopPrank();
    }

    function test_CloseOption_RevertZeroClosingFee() public {
        vm.startPrank(seller);
        optionPair.createAsk(UNDERLYING_AMOUNT, STRIKE_AMOUNT, PREMIUM_AMOUNT, PERIOD_IN_SECONDS);
        vm.stopPrank();

        vm.startPrank(buyer);
        optionPair.fillAsk(1, 0); // Fill with zero closing fee
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectRevert("Option: Closing fee must be > 0");
        optionPair.closeOption(1);
        vm.stopPrank();
    }
}