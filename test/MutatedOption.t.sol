// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {MutatedOption} from "../contracts/MutatedOption.sol";
import {TestToken} from "../contracts/TestToken.sol";

contract MutatedOptionTest is Test {
    MutatedOption public mutatedOption;
    TestToken public underlyingToken;
    TestToken public strikeToken;

    address public seller;
    address public buyer1;
    address public buyer2;

    uint256 public constant INITIAL_TOKEN_BALANCE = 1000 ether;

    function setUp() public {
        mutatedOption = new MutatedOption();
        underlyingToken = new TestToken("Underlying Token", "UND", INITIAL_TOKEN_BALANCE);
        strikeToken = new TestToken("Strike Token", "STK", INITIAL_TOKEN_BALANCE);

        seller = makeAddr("seller");
        buyer1 = makeAddr("buyer1");
        buyer2 = makeAddr("buyer2");

        // Mint initial tokens for seller and buyers
        underlyingToken.mint(seller, INITIAL_TOKEN_BALANCE);
        strikeToken.mint(seller, INITIAL_TOKEN_BALANCE);
        strikeToken.mint(buyer1, INITIAL_TOKEN_BALANCE);
        strikeToken.mint(buyer2, INITIAL_TOKEN_BALANCE);
    }

    // Helper function to create an option
    function _createOption(
        address _seller,
        uint256 _underlyingAmount,
        uint256 _strikeAmount,
        uint256 _premiumAmount,
        uint256 _periodInSeconds
    ) internal returns (uint256 optionId) {
        vm.startPrank(_seller);
        underlyingToken.approve(address(mutatedOption), _underlyingAmount);
        mutatedOption.createOption(
            address(underlyingToken),
            _underlyingAmount,
            address(strikeToken),
            _strikeAmount,
            _premiumAmount,
            _periodInSeconds
        );
        vm.stopPrank();
        return 1; // Assuming first option created will have ID 1
    }

    // Helper function to purchase an option
    function _purchaseOption(
        address _buyer,
        uint256 _optionId,
        uint256 _premiumAmount,
        uint256 _closingFeeAmount
    ) internal {
        vm.startPrank(_buyer);
        strikeToken.approve(address(mutatedOption), _premiumAmount);
        mutatedOption.purchaseOption(_optionId, _closingFeeAmount);
        vm.stopPrank();
    }

    // Helper function to exercise an option
    function _exerciseOption(
        address _buyer,
        uint256 _optionId,
        uint256 _strikeAmount
    ) internal {
        vm.startPrank(_buyer);
        strikeToken.approve(address(mutatedOption), _strikeAmount);
        mutatedOption.exerciseOption(_optionId);
        vm.stopPrank();
    }

    // Helper function to close an option
    function _closeOption(
        address _seller,
        uint256 _optionId
    ) internal {
        vm.startPrank(_seller);
        // Approve is needed for the seller to transfer closingFeeAmount to the contract
        // The actual closingFeeAmount is retrieved from the option struct
        mutatedOption.closeOption(_optionId);
        vm.stopPrank();
    }

    // Test cases for createOption
    function testCreateOptionSuccess() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        uint256 closingFeeAmount = 5 ether; // This is for purchaseOption, not createOption

        uint256 sellerInitialUnderlyingBalance = underlyingToken.balanceOf(seller);

        uint256 expectedExpirationTimestamp = block.timestamp + periodInSeconds;

        vm.startPrank(seller);
        underlyingToken.approve(address(mutatedOption), underlyingAmount);

        vm.expectEmit(true, true, false, true);
        emit MutatedOption.OptionCreated(
            1,
            seller,
            address(underlyingToken),
            underlyingAmount,
            address(strikeToken),
            strikeAmount,
            premiumAmount,
            expectedExpirationTimestamp
        );

        mutatedOption.createOption(
            address(underlyingToken),
            underlyingAmount,
            address(strikeToken),
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(seller), sellerInitialUnderlyingBalance - underlyingAmount);
        assertEq(underlyingToken.balanceOf(address(mutatedOption)), underlyingAmount);

        (uint256 retrievedOptionId, address retrievedSeller, address retrievedBuyer, address retrievedUnderlyingTokenAddress, uint256 retrievedUnderlyingAmount, address retrievedStrikeTokenAddress, uint256 retrievedStrikeAmount, uint256 retrievedPremiumAmount, uint256 retrievedExpirationTimestamp, uint256 retrievedClosingFeeAmount, MutatedOption.OptionState retrievedState) = mutatedOption.options(1);
        assertEq(retrievedSeller, seller);
        assertEq(retrievedUnderlyingAmount, underlyingAmount);
        assertEq(uint8(retrievedState), uint8(MutatedOption.OptionState.AvailableForPurchase));
        assertEq(retrievedExpirationTimestamp, expectedExpirationTimestamp);
        assertEq(retrievedClosingFeeAmount, 0); // closingFeeAmount should be 0 initially
    }

    function testCreateOptionRevertZeroUnderlyingAmount() public {
        uint256 underlyingAmount = 0;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;

        vm.startPrank(seller);
        vm.expectRevert("Underlying amount must be greater than 0");
        mutatedOption.createOption(
            address(underlyingToken),
            underlyingAmount,
            address(strikeToken),
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        vm.stopPrank();
    }

    function testCreateOptionRevertZeroStrikeAmount() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 0;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;

        vm.startPrank(seller);
        vm.expectRevert("Strike amount must be greater than 0");
        mutatedOption.createOption(
            address(underlyingToken),
            underlyingAmount,
            address(strikeToken),
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        vm.stopPrank();
    }

    function testCreateOptionRevertZeroPremiumAmount() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 0;
        uint256 periodInSeconds = 3 days;

        vm.startPrank(seller);
        vm.expectRevert("Premium amount must be greater than 0");
        mutatedOption.createOption(
            address(underlyingToken),
            underlyingAmount,
            address(strikeToken),
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        vm.stopPrank();
    }

    function testCreateOptionRevertZeroPeriod() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 0;

        vm.startPrank(seller);
        vm.expectRevert("Period must be greater than 0");
        mutatedOption.createOption(
            address(underlyingToken),
            underlyingAmount,
            address(strikeToken),
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        vm.stopPrank();
    }

    // Test cases for purchaseOption
    function testPurchaseOptionSuccess() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );

        uint256 sellerInitialStrikeBalance = strikeToken.balanceOf(seller);
        uint256 buyer1InitialStrikeBalance = strikeToken.balanceOf(buyer1);

        vm.startPrank(buyer1);
        strikeToken.approve(address(mutatedOption), premiumAmount);

        vm.expectEmit(true, true, true, true);
        emit MutatedOption.OptionPurchased(optionId, buyer1, seller, premiumAmount, closingFeeAmount);

        mutatedOption.purchaseOption(optionId, closingFeeAmount);
        vm.stopPrank();

        assertEq(strikeToken.balanceOf(seller), sellerInitialStrikeBalance + premiumAmount);
        assertEq(strikeToken.balanceOf(buyer1), buyer1InitialStrikeBalance - premiumAmount);

        (uint256 optionId_, address seller_, address retrievedBuyer, address underlyingToken_, uint256 underlyingAmount_, address strikeToken_, uint256 strikeAmount_, uint256 premiumAmount_, uint256 expirationTimestamp_, uint256 closingFeeAmount_, MutatedOption.OptionState retrievedState) = mutatedOption.options(optionId);
        assertEq(retrievedBuyer, buyer1);
        assertEq(uint8(retrievedState), uint8(MutatedOption.OptionState.Active));
    }

    function testPurchaseOptionRevertNotAvailable() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );

        _purchaseOption(buyer1, optionId, premiumAmount, closingFeeAmount);

        vm.startPrank(buyer2);
        vm.expectRevert("Option not available for purchase");
        mutatedOption.purchaseOption(optionId, closingFeeAmount);
        vm.stopPrank();
    }

    function testPurchaseOptionRevertSellerCannotPurchase() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );

        vm.startPrank(seller);
        vm.expectRevert("Seller cannot purchase their own option");
        mutatedOption.purchaseOption(optionId, closingFeeAmount); // Seller tries to purchase their own option
        vm.stopPrank();
    }

    // Test cases for exerciseOption
    function testExerciseOptionSuccess() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        _purchaseOption(buyer1, optionId, premiumAmount, closingFeeAmount);

        uint256 sellerInitialStrikeBalance = strikeToken.balanceOf(seller);
        uint256 buyer1InitialUnderlyingBalance = underlyingToken.balanceOf(buyer1);

        vm.startPrank(buyer1);
        strikeToken.approve(address(mutatedOption), strikeAmount);

        vm.expectEmit(true, true, true, true);
        emit MutatedOption.OptionExercised(
            optionId,
            buyer1,
            seller,
            strikeAmount,
            underlyingAmount
        );

        mutatedOption.exerciseOption(optionId);
        vm.stopPrank();

        assertEq(strikeToken.balanceOf(seller), sellerInitialStrikeBalance + strikeAmount);
        assertEq(underlyingToken.balanceOf(buyer1), buyer1InitialUnderlyingBalance + underlyingAmount);
        assertEq(underlyingToken.balanceOf(address(mutatedOption)), 0);

        (uint256 optionId_, address seller_, address buyer_, address underlyingTokenAddress_, uint256 underlyingAmount_, address strikeTokenAddress_, uint256 strikeAmount_, uint256 premiumAmount_, uint256 expirationTimestamp_, uint256 closingFeeAmount_, MutatedOption.OptionState retrievedState) = mutatedOption.options(optionId);
        assertEq(uint8(retrievedState), uint8(MutatedOption.OptionState.Exercised));
    }

    function testExerciseOptionRevertNotActive() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );

        vm.startPrank(buyer1);
        vm.expectRevert("Option is not active");
        mutatedOption.exerciseOption(optionId); // Not purchased yet
        vm.stopPrank();
    }

    function testExerciseOptionRevertNotBuyer() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        _purchaseOption(buyer1, optionId, premiumAmount, closingFeeAmount);

        vm.startPrank(buyer2);
        vm.expectRevert("Only the buyer can exercise this option");
        mutatedOption.exerciseOption(optionId);
        vm.stopPrank();
    }

    function testExerciseOptionRevertExpired() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 1;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        _purchaseOption(buyer1, optionId, premiumAmount, closingFeeAmount);

        vm.warp(block.timestamp + periodInSeconds + 1); // Advance time past expiration

        vm.startPrank(buyer1);
        vm.expectRevert("Option has expired");
        mutatedOption.exerciseOption(optionId);
        vm.stopPrank();
    }

    // Test cases for claimUnderlyingOnExpiration
    function testClaimUnderlyingOnExpirationSuccess() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 1;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        _purchaseOption(buyer1, optionId, premiumAmount, closingFeeAmount);

        uint256 sellerInitialUnderlyingBalance = underlyingToken.balanceOf(seller);

        vm.warp(block.timestamp + periodInSeconds + 1); // Advance time past expiration

        vm.expectEmit(true, true, true, true);
        emit MutatedOption.OptionExpired(optionId, seller, underlyingAmount);

        vm.prank(seller);
        mutatedOption.claimUnderlyingOnExpiration(optionId);

        assertEq(underlyingToken.balanceOf(seller), sellerInitialUnderlyingBalance + underlyingAmount);
        assertEq(underlyingToken.balanceOf(address(mutatedOption)), 0);

        (uint256 optionId_, address seller_, address buyer_, address underlyingTokenAddress_, uint256 underlyingAmount_, address strikeTokenAddress_, uint256 strikeAmount_, uint256 premiumAmount_, uint256 expirationTimestamp_, uint256 closingFeeAmount_, MutatedOption.OptionState retrievedState) = mutatedOption.options(optionId);
        assertEq(uint8(retrievedState), uint8(MutatedOption.OptionState.Expired));
    }

    function testClaimUnderlyingOnExpirationRevertNotActive() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 1;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );

        vm.warp(block.timestamp + periodInSeconds + 1); // Advance time past expiration

        vm.expectRevert("Option is not active");
        vm.prank(seller);
        mutatedOption.claimUnderlyingOnExpiration(optionId); // Not purchased yet
    }

    function testClaimUnderlyingOnExpirationRevertNotSeller() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 1;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        _purchaseOption(buyer1, optionId, premiumAmount, closingFeeAmount);

        vm.warp(block.timestamp + periodInSeconds + 1); // Advance time past expiration

        vm.expectRevert("Only the original seller can claim");
        vm.prank(buyer1);
        mutatedOption.claimUnderlyingOnExpiration(optionId); // Buyer tries to claim
    }

    function testClaimUnderlyingOnExpirationRevertNotExpired() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        _purchaseOption(buyer1, optionId, premiumAmount, closingFeeAmount);

        vm.expectRevert("Option has not expired yet");
        vm.prank(seller);
        mutatedOption.claimUnderlyingOnExpiration(optionId);
    }

    // Test cases for closeOption
    function testCloseOptionSuccess() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        _purchaseOption(buyer1, optionId, premiumAmount, closingFeeAmount);

        uint256 sellerInitialUnderlyingBalance = underlyingToken.balanceOf(seller);
        uint256 buyer1InitialStrikeBalance = strikeToken.balanceOf(buyer1);

        // Seller needs to approve the closing fee before calling closeOption
        vm.startPrank(seller);
        strikeToken.approve(address(mutatedOption), closingFeeAmount);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit MutatedOption.OptionClosed(
            optionId,
            seller,
            buyer1,
            closingFeeAmount,
            underlyingAmount
        );

        _closeOption(seller, optionId);

        assertEq(underlyingToken.balanceOf(seller), sellerInitialUnderlyingBalance + underlyingAmount);
        assertEq(strikeToken.balanceOf(buyer1), buyer1InitialStrikeBalance + closingFeeAmount);
        assertEq(underlyingToken.balanceOf(address(mutatedOption)), 0);

        (uint256 optionId_, address seller_, address buyer_, address underlyingTokenAddress_, uint256 underlyingAmount_, address strikeTokenAddress_, uint256 strikeAmount_, uint256 premiumAmount_, uint256 expirationTimestamp_, uint256 closingFeeAmount_, MutatedOption.OptionState retrievedState) = mutatedOption.options(optionId);
        assertEq(uint8(retrievedState), uint8(MutatedOption.OptionState.Closed));
    }

    function testCloseOptionRevertNotActive() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );

        vm.expectRevert("Option is not active");
        _closeOption(seller, optionId); // Not purchased yet
    }

    function testCloseOptionRevertNotSeller() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        _purchaseOption(buyer1, optionId, premiumAmount, closingFeeAmount);

        vm.expectRevert("Only the original seller can close this option");
        _closeOption(buyer1, optionId); // Buyer tries to close
    }

    function testCloseOptionRevertExpired() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 1;
        uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        _purchaseOption(buyer1, optionId, premiumAmount, closingFeeAmount);

        vm.warp(block.timestamp + periodInSeconds + 1); // Advance time past expiration

        vm.expectRevert("Option has already expired");
        _closeOption(seller, optionId);
    }
}