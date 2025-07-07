// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {OptionContract, ITokenWithDecimals} from "../contracts/OptionContract.sol";
import {TestToken} from "../contracts/TestToken.sol";

contract OptionContractTest is Test {
    OptionContract internal optionContract;
    TestToken internal baseToken;  // Mock WBTC
    TestToken internal quoteToken; // Mock WETH

    address internal seller = address(0x1);
    address internal buyer = address(0x2);
    address internal randomUser = address(0x3);

    uint256 internal constant ONE_ETHER = 1 ether; // 1e18

    function setUp() public {
        optionContract = new OptionContract();
        baseToken = new TestToken("Wrapped BTC", "WBTC", 8);
        quoteToken = new TestToken("Wrapped ETH", "WETH", 18);

        // Fund users
        baseToken.mint(seller, 10 * 10**8);   // 10 WBTC
        quoteToken.mint(seller, 50000 * ONE_ETHER); // 50000 WETH
        baseToken.mint(buyer, 10 * 10**8);    // 10 WBTC
        quoteToken.mint(buyer, 50000 * ONE_ETHER);  // 50000 WETH
    }

    // --- Helper Functions ---

    function _getQuoteAmount(uint256 baseAmount, uint256 strikePrice) internal view returns (uint256) {
        uint8 baseDecimals = baseToken.decimals();
        uint8 quoteDecimals = quoteToken.decimals();
        uint256 priceDecimals = 18;

        uint256 exponent = priceDecimals + baseDecimals;
        if (exponent < quoteDecimals) {
            return baseAmount * strikePrice * (10**(uint256(quoteDecimals) - exponent));
        } else {
            exponent = exponent - quoteDecimals;
            return (baseAmount * strikePrice) / (10**exponent);
        }
    }

    // --- Test Create Option ---

    function test_createCallOption_success() public {
        uint256 baseAmount = 1 * 10**8; // 1 WBTC
        uint256 strikePrice = 45000 * ONE_ETHER; // $45,000
        uint256 premium = 100 * ONE_ETHER; // $100
        uint256 expiration = block.timestamp + 1 days;

        vm.startPrank(seller);
        baseToken.approve(address(optionContract), baseAmount);

        uint256 optionId = optionContract.createOption(
            OptionContract.OptionType.Call, address(baseToken), address(quoteToken),
            baseAmount, strikePrice, premium, expiration
        );

        vm.stopPrank();

        (,address creator,,,,,,,,,,) = optionContract.options(optionId);
        assertEq(creator, seller);
        assertEq(baseToken.balanceOf(address(optionContract)), baseAmount);
    }

    function test_createPutOption_success() public {
        uint256 baseAmount = 1 * 10**8; // 1 WBTC
        uint256 strikePrice = 45000 * ONE_ETHER;
        uint256 premium = 100 * ONE_ETHER;
        uint256 expiration = block.timestamp + 1 days;
        uint256 quoteCollateral = _getQuoteAmount(baseAmount, strikePrice);

        vm.startPrank(seller);
        quoteToken.approve(address(optionContract), quoteCollateral);

        uint256 optionId = optionContract.createOption(
            OptionContract.OptionType.Put, address(baseToken), address(quoteToken),
            baseAmount, strikePrice, premium, expiration
        );

        vm.stopPrank();

        (,address creator,,,,,,,,,,) = optionContract.options(optionId);
        assertEq(creator, seller);
        assertEq(quoteToken.balanceOf(address(optionContract)), quoteCollateral);
    }

    function test_fail_createOption_expired() public {
        vm.expectRevert(OptionContract.OptionExpired.selector);
        optionContract.createOption(
            OptionContract.OptionType.Call, address(baseToken), address(quoteToken),
            1, 1, 1, block.timestamp - 1
        );
    }

    function test_fail_createOption_zeroAddress() public {
        vm.expectRevert(OptionContract.ZeroAddress.selector);
        optionContract.createOption(
            OptionContract.OptionType.Call, address(0), address(quoteToken),
            1, 1, 1, block.timestamp + 1 days
        );
    }

    function test_fail_createOption_sameToken() public {
        vm.expectRevert(OptionContract.SameToken.selector);
        optionContract.createOption(
            OptionContract.OptionType.Call, address(baseToken), address(baseToken),
            1, 1, 1, block.timestamp + 1 days
        );
    }

    // --- Test Buy Option ---

    function test_buyOption_success() public {
        // 1. Create option
        uint256 baseAmount = 1 * 10**8;
        uint256 strikePrice = 45000 * ONE_ETHER;
        uint256 premium = 200 * ONE_ETHER;
        uint256 expiration = block.timestamp + 1 days;
        vm.startPrank(seller);
        baseToken.approve(address(optionContract), baseAmount);
        uint256 optionId = optionContract.createOption(
            OptionContract.OptionType.Call, address(baseToken), address(quoteToken),
            baseAmount, strikePrice, premium, expiration
        );
        vm.stopPrank();

        // 2. Buy option
        vm.startPrank(buyer);
        quoteToken.approve(address(optionContract), premium);
        uint256 sellerBalanceBefore = quoteToken.balanceOf(seller);

        optionContract.buyOption(optionId);

        uint256 sellerBalanceAfter = quoteToken.balanceOf(seller);
        vm.stopPrank();

        (,,address optBuyer,,,,,,,,,) = optionContract.options(optionId);
        assertEq(optBuyer, buyer);
        assertEq(sellerBalanceAfter, sellerBalanceBefore + premium);
    }

    function test_fail_buyOption_expired() public {
        // 1. Create option
        uint256 baseAmount = 1 * 10**8;
        uint256 strikePrice = 45000 * ONE_ETHER;
        uint256 premium = 200 * ONE_ETHER;
        uint256 expiration = block.timestamp + 1 days;
        vm.startPrank(seller);
        baseToken.approve(address(optionContract), baseAmount);
        uint256 optionId = optionContract.createOption(
            OptionContract.OptionType.Call, address(baseToken), address(quoteToken),
            baseAmount, strikePrice, premium, expiration
        );
        vm.stopPrank();

        // 2. Fast forward time
        vm.warp(expiration + 1);

        // 3. Attempt to buy
        vm.startPrank(buyer);
        quoteToken.approve(address(optionContract), premium);
        vm.expectRevert(OptionContract.OptionExpired.selector);
        optionContract.buyOption(optionId);
        vm.stopPrank();
    }

    // --- Test Exercise ---

    function test_exerciseCall_success() public {
        // 1. Create and buy option
        uint256 baseAmount = 1 * 10**8; // 1 WBTC
        uint256 strikePrice = 45000 * ONE_ETHER;
        uint256 premium = 200 * ONE_ETHER;
        uint256 expiration = block.timestamp + 1 days;
        vm.startPrank(seller);
        baseToken.approve(address(optionContract), baseAmount);
        uint256 optionId = optionContract.createOption(
            OptionContract.OptionType.Call, address(baseToken), address(quoteToken),
            baseAmount, strikePrice, premium, expiration
        );
        vm.stopPrank();
        vm.startPrank(buyer);
        quoteToken.approve(address(optionContract), premium);
        optionContract.buyOption(optionId);
        vm.stopPrank();

        // 2. Fast forward time
        vm.warp(expiration + 1);

        // 3. Exercise
        vm.startPrank(buyer);
        uint256 quoteAmountToPay = _getQuoteAmount(baseAmount, strikePrice);
        quoteToken.approve(address(optionContract), quoteAmountToPay);

        uint256 buyerBaseBalanceBefore = baseToken.balanceOf(buyer);
        uint256 sellerQuoteBalanceBefore = quoteToken.balanceOf(seller);

        optionContract.exercise(optionId);

        uint256 buyerBaseBalanceAfter = baseToken.balanceOf(buyer);
        uint256 sellerQuoteBalanceAfter = quoteToken.balanceOf(seller);
        vm.stopPrank();

        assertEq(buyerBaseBalanceAfter, buyerBaseBalanceBefore + baseAmount);
        assertEq(sellerQuoteBalanceAfter, sellerQuoteBalanceBefore + quoteAmountToPay);
        (,,,,,,,,,, bool isExercised, ) = optionContract.options(optionId);
        assertTrue(isExercised);
    }

    function test_exercisePut_success() public {
        // 1. Create and buy option
        uint256 baseAmount = 1 * 10**8; // 1 WBTC
        uint256 strikePrice = 45000 * ONE_ETHER;
        uint256 premium = 200 * ONE_ETHER;
        uint256 expiration = block.timestamp + 1 days;
        uint256 quoteCollateral = _getQuoteAmount(baseAmount, strikePrice);

        vm.startPrank(seller);
        quoteToken.approve(address(optionContract), quoteCollateral);
        uint256 optionId = optionContract.createOption(
            OptionContract.OptionType.Put, address(baseToken), address(quoteToken),
            baseAmount, strikePrice, premium, expiration
        );
        vm.stopPrank();
        vm.startPrank(buyer);
        quoteToken.approve(address(optionContract), premium);
        optionContract.buyOption(optionId);
        vm.stopPrank();

        // 2. Fast forward time
        vm.warp(expiration + 1);

        // 3. Exercise
        vm.startPrank(buyer);
        baseToken.approve(address(optionContract), baseAmount);

        uint256 buyerQuoteBalanceBefore = quoteToken.balanceOf(buyer);
        uint256 sellerBaseBalanceBefore = baseToken.balanceOf(seller);

        optionContract.exercise(optionId);

        uint256 buyerQuoteBalanceAfter = quoteToken.balanceOf(buyer);
        uint256 sellerBaseBalanceAfter = baseToken.balanceOf(seller);
        vm.stopPrank();

        assertEq(buyerQuoteBalanceAfter, buyerQuoteBalanceBefore + quoteCollateral);
        assertEq(sellerBaseBalanceAfter, sellerBaseBalanceBefore + baseAmount);
        (,,,,,,,,,, bool isExercised, ) = optionContract.options(optionId);
        assertTrue(isExercised);
    }

    function test_fail_exercise_notExpired() public {
        // 1. Create and buy an option
        uint256 baseAmount = 1 * 10**8;
        uint256 strikePrice = 45000 * ONE_ETHER;
        uint256 premium = 200 * ONE_ETHER;
        uint256 expiration = block.timestamp + 1 days;
        vm.startPrank(seller);
        baseToken.approve(address(optionContract), baseAmount);
        uint256 optionId = optionContract.createOption(
            OptionContract.OptionType.Call, address(baseToken), address(quoteToken),
            baseAmount, strikePrice, premium, expiration
        );
        vm.stopPrank();

        vm.startPrank(buyer);
        quoteToken.approve(address(optionContract), premium);
        optionContract.buyOption(optionId);

        // 2. Attempt to exercise before expiration
        vm.expectRevert(OptionContract.OptionNotExpired.selector);
        optionContract.exercise(optionId);
        vm.stopPrank();
    }

    function test_fail_exercise_notTheBuyer() public {
        // 1. Create and buy option
        uint256 optionId = 0;
        vm.startPrank(seller);
        baseToken.approve(address(optionContract), 1);
        optionContract.createOption(OptionContract.OptionType.Call, address(baseToken), address(quoteToken), 1, 1, 1, block.timestamp + 1 days);
        vm.stopPrank();
        vm.startPrank(buyer);
        quoteToken.approve(address(optionContract), 1);
        optionContract.buyOption(optionId);
        vm.stopPrank();

        // 2. Fast forward time
        vm.warp(block.timestamp + 2 days);

        // 3. Attempt to exercise from a random user
        vm.startPrank(randomUser);
        vm.expectRevert(OptionContract.NotTheBuyer.selector);
        optionContract.exercise(optionId);
        vm.stopPrank();
    }

    // --- Test Reclaim Collateral ---

    function test_reclaimCollateral_success() public {
        // 1. Create and buy option
        uint256 baseAmount = 1 * 10**8;
        uint256 strikePrice = 45000 * ONE_ETHER;
        uint256 premium = 200 * ONE_ETHER;
        uint256 expiration = block.timestamp + 1 days;
        vm.startPrank(seller);
        baseToken.approve(address(optionContract), baseAmount);
        uint256 optionId = optionContract.createOption(
            OptionContract.OptionType.Call, address(baseToken), address(quoteToken),
            baseAmount, strikePrice, premium, expiration
        );
        vm.stopPrank();
        vm.startPrank(buyer);
        quoteToken.approve(address(optionContract), premium);
        optionContract.buyOption(optionId);
        vm.stopPrank();

        // 2. Fast forward time
        vm.warp(expiration + 1);

        // 3. Reclaim
        vm.startPrank(seller);
        uint256 sellerBaseBalanceBefore = baseToken.balanceOf(seller);
        optionContract.reclaimCollateral(optionId);
        uint256 sellerBaseBalanceAfter = baseToken.balanceOf(seller);
        vm.stopPrank();

        assertEq(sellerBaseBalanceAfter, sellerBaseBalanceBefore + baseAmount);
    }

    function test_fail_reclaim_notExpired() public {
        // 1. Create option
        uint256 baseAmount = 1 * 10**8;
        uint256 strikePrice = 45000 * ONE_ETHER;
        uint256 premium = 200 * ONE_ETHER;
        uint256 expiration = block.timestamp + 1 days;
        vm.startPrank(seller);
        baseToken.approve(address(optionContract), baseAmount);
        uint256 optionId = optionContract.createOption(
            OptionContract.OptionType.Call, address(baseToken), address(quoteToken),
            baseAmount, strikePrice, premium, expiration
        );
        vm.stopPrank();

        // 2. Attempt to reclaim before expiration
        vm.startPrank(seller);
        vm.expectRevert(OptionContract.OptionNotExpired.selector);
        optionContract.reclaimCollateral(optionId);
        vm.stopPrank();
    }

    // --- Test Cancel Option ---

    function test_cancelOption_success() public {
        // 1. Create option
        uint256 baseAmount = 1 * 10**8;
        uint256 strikePrice = 45000 * ONE_ETHER;
        uint256 premium = 200 * ONE_ETHER;
        uint256 expiration = block.timestamp + 1 days;
        vm.startPrank(seller);
        baseToken.approve(address(optionContract), baseAmount);
        uint256 optionId = optionContract.createOption(
            OptionContract.OptionType.Call, address(baseToken), address(quoteToken),
            baseAmount, strikePrice, premium, expiration
        );

        // 2. Cancel
        uint256 sellerBaseBalanceBefore = baseToken.balanceOf(seller);
        optionContract.cancelOption(optionId);
        uint256 sellerBaseBalanceAfter = baseToken.balanceOf(seller);

        vm.stopPrank();

        assertEq(sellerBaseBalanceAfter, sellerBaseBalanceBefore + baseAmount);
        (,,,,,,,,,,, bool isCancelled) = optionContract.options(optionId);
        assertTrue(isCancelled);
    }

    function test_fail_cancelOption_alreadyBought() public {
        // 1. Create and buy option
        uint256 baseAmount = 1 * 10**8;
        uint256 strikePrice = 45000 * ONE_ETHER;
        uint256 premium = 200 * ONE_ETHER;
        uint256 expiration = block.timestamp + 1 days;
        vm.startPrank(seller);
        baseToken.approve(address(optionContract), baseAmount);
        uint256 optionId = optionContract.createOption(
            OptionContract.OptionType.Call, address(baseToken), address(quoteToken),
            baseAmount, strikePrice, premium, expiration
        );
        vm.stopPrank();
        vm.startPrank(buyer);
        quoteToken.approve(address(optionContract), premium);
        optionContract.buyOption(optionId);
        vm.stopPrank();

        // 2. Attempt to cancel
        vm.startPrank(seller);
        vm.expectRevert(OptionContract.AlreadyPurchased.selector);
        optionContract.cancelOption(optionId);
        vm.stopPrank();
    }

    function test_fail_cancel_notTheCreator() public {
        // 1. Create option
        uint256 optionId = 0;
        vm.startPrank(seller);
        baseToken.approve(address(optionContract), 1);
        optionContract.createOption(OptionContract.OptionType.Call, address(baseToken), address(quoteToken), 1, 1, 1, block.timestamp + 1 days);
        vm.stopPrank();

        // 2. Attempt to cancel from another user
        vm.startPrank(randomUser);
        vm.expectRevert(OptionContract.NotTheCreator.selector);
        optionContract.cancelOption(optionId);
        vm.stopPrank();
    }
}
