// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "contracts/P2PExchange.sol";
import "contracts/TestToken.sol";

contract P2PExchangeTest is Test {
    P2PExchange public exchange;
    TestToken public tokenA;
    TestToken public tokenB;

    address public constant MAKER = address(0x1);
    address public constant TAKER = address(0x2);

    uint256 public constant INITIAL_TOKEN_AMOUNT = 1_000_000; // Base amount, decimals applied during minting
    uint256 public constant TEST_SEND_AMOUNT = 10_000; // Base amount, decimals applied during transfer

    function setUp() public {
        _deployTokensWithDecimals(18, 18); // Default setup with 18 decimals
    }

    function _deployTokensWithDecimals(uint8 decimalsA, uint8 decimalsB) internal {
        exchange = new P2PExchange();
        tokenA = new TestToken("Token A", "TKA", INITIAL_TOKEN_AMOUNT, decimalsA);
        tokenB = new TestToken("Token B", "TKB", INITIAL_TOKEN_AMOUNT, decimalsB);

        // Distribute tokens to maker and taker, adjusting for decimals
        tokenA.transfer(MAKER, TEST_SEND_AMOUNT * (10 ** decimalsA));
        tokenB.transfer(MAKER, TEST_SEND_AMOUNT * (10 ** decimalsB));
        tokenA.transfer(TAKER, TEST_SEND_AMOUNT * (10 ** decimalsA));
        tokenB.transfer(TAKER, TEST_SEND_AMOUNT * (10 ** decimalsB));
    }

    function test_CreateOffer_DifferentDecimals() public {
        // Test with tokenA having 6 decimals and tokenB having 18 decimals
        _deployTokensWithDecimals(6, 18);

        uint256 amountSell = 100 * (10 ** tokenA.decimals()); // 100 units of Token A
        uint256 amountBuy = 200 * (10 ** tokenB.decimals()); // 200 units of Token B

        vm.startPrank(MAKER);
        tokenA.approve(address(exchange), amountSell);

        vm.expectEmit(true, true, true, true);
        emit P2PExchange.OfferCreated(0, MAKER, address(tokenA), amountSell, address(tokenB), amountBuy);
        exchange.createOffer(tokenA, amountSell, tokenB, amountBuy);

        (uint256 id, address maker, IERC20 tokenSell, , IERC20 tokenBuy, , P2PExchange.OfferStatus status) = exchange.offers(0);
        assertEq(maker, MAKER);
        assertEq(address(tokenSell), address(tokenA));
        assertEq(uint(status), 0); // Open

        assertEq(tokenA.balanceOf(address(exchange)), amountSell);
        vm.stopPrank();

        // Test with tokenA having 18 decimals and tokenB having 6 decimals
        _deployTokensWithDecimals(18, 6);

        amountSell = 50 * (10 ** tokenA.decimals()); // 50 units of Token A
        amountBuy = 100 * (10 ** tokenB.decimals()); // 100 units of Token B

        vm.startPrank(MAKER);
        tokenA.approve(address(exchange), amountSell);

        vm.expectEmit(true, true, true, true);
        emit P2PExchange.OfferCreated(0, MAKER, address(tokenA), amountSell, address(tokenB), amountBuy); // Offer ID will be 0 as exchange is re-deployed
        exchange.createOffer(tokenA, amountSell, tokenB, amountBuy);

        (id, maker, tokenSell, , tokenBuy, , status) = exchange.offers(0);
        assertEq(maker, MAKER);
        assertEq(address(tokenSell), address(tokenA));
        assertEq(uint(status), 0); // Open

        assertEq(tokenA.balanceOf(address(exchange)), amountSell);
        vm.stopPrank();
    }

    function test_CreateOffer() public {
        uint256 amountSell = 100e18;
        uint256 amountBuy = 200e18;

        vm.startPrank(MAKER);
        tokenA.approve(address(exchange), amountSell);

        vm.expectEmit(true, true, true, true);
        emit P2PExchange.OfferCreated(0, MAKER, address(tokenA), amountSell, address(tokenB), amountBuy);
        exchange.createOffer(tokenA, amountSell, tokenB, amountBuy);

        (uint256 id, address maker, IERC20 tokenSell, , IERC20 tokenBuy, , P2PExchange.OfferStatus status) = exchange.offers(0);
        assertEq(maker, MAKER);
        assertEq(address(tokenSell), address(tokenA));
        assertEq(uint(status), 0); // Open

        assertEq(tokenA.balanceOf(address(exchange)), amountSell);
        vm.stopPrank();
    }

    function test_FillOffer() public {
        uint256 amountSell = 100e18;
        uint256 amountBuy = 200e18;

        // Maker creates offer
        vm.startPrank(MAKER);
        tokenA.approve(address(exchange), amountSell);
        exchange.createOffer(tokenA, amountSell, tokenB, amountBuy);
        vm.stopPrank();

        uint256 makerInitialTokenBBalance = tokenB.balanceOf(MAKER);
        uint256 takerInitialTokenABalance = tokenA.balanceOf(TAKER);

        // Taker fills offer
        vm.startPrank(TAKER);
        tokenB.approve(address(exchange), amountBuy);

        vm.expectEmit(true, true, true, true);
        emit P2PExchange.OfferFilled(0, TAKER);
        exchange.fillOffer(0);
        vm.stopPrank();

        (, , , , , , P2PExchange.OfferStatus status) = exchange.offers(0);
        assertEq(uint(status), 1); // Filled

        assertEq(tokenA.balanceOf(address(exchange)), 0);
        assertEq(tokenB.balanceOf(MAKER), makerInitialTokenBBalance + amountBuy);
        assertEq(tokenA.balanceOf(TAKER), takerInitialTokenABalance + amountSell);
    }

    function test_CancelOffer() public {
        uint256 amountSell = 100e18;
        uint256 amountBuy = 200e18;

        vm.startPrank(MAKER);
        tokenA.approve(address(exchange), amountSell);
        exchange.createOffer(tokenA, amountSell, tokenB, amountBuy);

        uint256 initialMakerBalance = tokenA.balanceOf(MAKER);

        vm.expectEmit(true, true, false, true);
        emit P2PExchange.OfferCancelled(0);
        exchange.cancelOffer(0);

        (, , , , , , P2PExchange.OfferStatus status) = exchange.offers(0);
        assertEq(uint(status), 2); // Cancelled

        assertEq(tokenA.balanceOf(address(exchange)), 0);
        assertEq(tokenA.balanceOf(MAKER), initialMakerBalance + amountSell);
        vm.stopPrank();
    }

    function test_ListOpenOffers() public {
        // Create first offer
        vm.startPrank(MAKER);
        tokenA.approve(address(exchange), 100e18);
        exchange.createOffer(tokenA, 100e18, tokenB, 200e18);
        vm.stopPrank();

        // Create second offer
        vm.startPrank(TAKER);
        tokenB.approve(address(exchange), 50e18);
        exchange.createOffer(tokenB, 50e18, tokenA, 25e18);
        vm.stopPrank();

        uint256[] memory openOfferIds = exchange.getOpenOffers();
        assertEq(openOfferIds.length, 2);
        assertEq(openOfferIds[0], 0);
        assertEq(openOfferIds[1], 1);

        // Fill the first offer
        vm.startPrank(TAKER);
        tokenB.approve(address(exchange), 200e18);
        exchange.fillOffer(0);
        vm.stopPrank();

        openOfferIds = exchange.getOpenOffers();
        assertEq(openOfferIds.length, 1);
        assertEq(openOfferIds[0], 1);
    }

    function test_Fail_FillNonExistentOffer() public {
        vm.expectRevert(abi.encodeWithSelector(P2PExchange.InvalidOfferId.selector, 999));
        exchange.fillOffer(999);
    }

    function test_Fail_CancelByNonMaker() public {
        uint256 amountSell = 100e18;
        uint256 amountBuy = 200e18;

        vm.startPrank(MAKER);
        tokenA.approve(address(exchange), amountSell);
        exchange.createOffer(tokenA, amountSell, tokenB, amountBuy);
        vm.stopPrank();

        vm.startPrank(TAKER);
        vm.expectRevert(abi.encodeWithSelector(P2PExchange.NotOfferMaker.selector, 0, TAKER));
        exchange.cancelOffer(0);
        vm.stopPrank();
    }

    function test_Fail_FillNonOpenOffer() public {
        uint256 amountSell = 100e18;
        uint256 amountBuy = 200e18;

        vm.startPrank(MAKER);
        tokenA.approve(address(exchange), amountSell);
        exchange.createOffer(tokenA, amountSell, tokenB, amountBuy);
        exchange.cancelOffer(0); // Cancel the offer
        vm.stopPrank();

        vm.startPrank(TAKER);
        vm.expectRevert(abi.encodeWithSelector(P2PExchange.OfferNotOpen.selector, 0));
        exchange.fillOffer(0);
        vm.stopPrank();
    }
}
