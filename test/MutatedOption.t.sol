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
        underlyingToken = new TestToken(
            "Underlying Token",
            "UND",
            INITIAL_TOKEN_BALANCE
        );
        strikeToken = new TestToken(
            "Strike Token",
            "STK",
            INITIAL_TOKEN_BALANCE
        );

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
        return 1; // Assuming first option created will have ID 1, needs to be dynamic for multiple creations
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
        uint256 _optionId,
        uint256 _closingFeeAmount // Added closingFeeAmount to helper for approval
    ) internal {
        vm.startPrank(_seller);
        // Approve is needed for the seller to transfer closingFeeAmount to the contract
        strikeToken.approve(address(mutatedOption), _closingFeeAmount); // Approve the closing fee
        mutatedOption.closeOption(_optionId);
        vm.stopPrank();
    }

    // Test cases for createOption
    function testCreateOptionSuccess() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        // closingFeeAmount is not relevant for createOption, removed from local variable

        uint256 sellerInitialUnderlyingBalance = underlyingToken.balanceOf(
            seller
        );

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

        assertEq(
            underlyingToken.balanceOf(seller),
            sellerInitialUnderlyingBalance - underlyingAmount
        );
        assertEq(
            underlyingToken.balanceOf(address(mutatedOption)),
            underlyingAmount
        );

        (
            ,
            address retrievedSeller,
            ,
            ,
            uint256 retrievedUnderlyingAmount,
            ,
            ,
            ,
            uint256 retrievedExpirationTimestamp,
            uint256 retrievedClosingFeeAmount,
            MutatedOption.OptionState retrievedState
        ) = mutatedOption.options(1);
        assertEq(retrievedSeller, seller);
        assertEq(retrievedUnderlyingAmount, underlyingAmount);
        assertEq(
            uint8(retrievedState),
            uint8(MutatedOption.OptionState.AvailableForPurchase)
        );
        assertEq(retrievedExpirationTimestamp, expectedExpirationTimestamp);
        assertEq(retrievedClosingFeeAmount, 0); // closingFeeAmount should be 0 initially
    }

    function testCreateOptionRevertZeroUnderlyingAmount() public {
        uint256 underlyingAmount = 0;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;

        vm.startPrank(seller);
        vm.expectRevert("Option: Underlying amount must be greater than 0");
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
        vm.expectRevert("Option: Strike amount must be greater than 0");
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
        vm.expectRevert("Option: Premium amount must be greater than 0");
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
        vm.expectRevert("Option: Period must be greater than 0");
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
        emit MutatedOption.OptionPurchased(
            optionId,
            buyer1,
            seller,
            premiumAmount,
            closingFeeAmount
        );

        mutatedOption.purchaseOption(optionId, closingFeeAmount);
        vm.stopPrank();

        assertEq(
            strikeToken.balanceOf(seller),
            sellerInitialStrikeBalance + premiumAmount
        );
        assertEq(
            strikeToken.balanceOf(buyer1),
            buyer1InitialStrikeBalance - premiumAmount
        );

        (
            ,
            ,
            address retrievedBuyer,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            MutatedOption.OptionState retrievedState
        ) = mutatedOption.options(optionId);
        assertEq(retrievedBuyer, buyer1);
        assertEq(
            uint8(retrievedState),
            uint8(MutatedOption.OptionState.Active)
        );
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
        vm.expectRevert("Option: Not available for purchase");
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
        vm.expectRevert("Option: Seller cannot purchase their own option");
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
        uint256 buyer1InitialUnderlyingBalance = underlyingToken.balanceOf(
            buyer1
        );

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

        assertEq(
            strikeToken.balanceOf(seller),
            sellerInitialStrikeBalance + strikeAmount
        );
        assertEq(
            underlyingToken.balanceOf(buyer1),
            buyer1InitialUnderlyingBalance + underlyingAmount
        );
        assertEq(underlyingToken.balanceOf(address(mutatedOption)), 0);

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
            MutatedOption.OptionState retrievedState
        ) = mutatedOption.options(optionId);
        assertEq(
            uint8(retrievedState),
            uint8(MutatedOption.OptionState.Exercised)
        );
    }

    function testExerciseOptionRevertNotActive() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        // uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );

        vm.startPrank(buyer1);
        vm.expectRevert("Option: Not active");
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
        vm.expectRevert("Option: Only the buyer can exercise this option");
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
        vm.expectRevert("Option: Has expired");
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

        uint256 sellerInitialUnderlyingBalance = underlyingToken.balanceOf(
            seller
        );

        vm.warp(block.timestamp + periodInSeconds + 1); // Advance time past expiration

        vm.expectEmit(true, true, true, true);
        emit MutatedOption.OptionExpired(optionId, seller, underlyingAmount);

        vm.prank(seller);
        mutatedOption.claimUnderlyingOnExpiration(optionId);

        assertEq(
            underlyingToken.balanceOf(seller),
            sellerInitialUnderlyingBalance + underlyingAmount
        );
        assertEq(underlyingToken.balanceOf(address(mutatedOption)), 0);

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
            MutatedOption.OptionState retrievedState
        ) = mutatedOption.options(optionId);
        assertEq(
            uint8(retrievedState),
            uint8(MutatedOption.OptionState.Expired)
        );
    }

    function testClaimUnderlyingOnExpirationRevertNotActive() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 1;
        // uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );

        vm.warp(block.timestamp + periodInSeconds + 1); // Advance time past expiration

        vm.expectRevert("Option: Not active or already handled");
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

        vm.expectRevert("Option: Only the original seller can claim");
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

        vm.expectRevert("Option: Has not expired yet");
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

        uint256 sellerInitialUnderlyingBalance = underlyingToken.balanceOf(
            seller
        );
        uint256 sellerInitialStrikeBalance = strikeToken.balanceOf(seller);
        uint256 buyer1InitialStrikeBalance = strikeToken.balanceOf(buyer1);

        vm.startPrank(seller);
        strikeToken.approve(address(mutatedOption), closingFeeAmount);

        vm.expectEmit(true, true, true, true);
        emit MutatedOption.OptionClosed(
            optionId,
            seller,
            buyer1,
            closingFeeAmount,
            underlyingAmount
        );

        mutatedOption.closeOption(optionId);
        vm.stopPrank();

        assertEq(
            underlyingToken.balanceOf(seller),
            sellerInitialUnderlyingBalance + underlyingAmount
        );
        assertEq(underlyingToken.balanceOf(address(mutatedOption)), 0);
        assertEq(
            strikeToken.balanceOf(seller),
            sellerInitialStrikeBalance - closingFeeAmount
        );
        assertEq(
            strikeToken.balanceOf(buyer1),
            buyer1InitialStrikeBalance + closingFeeAmount
        );

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
            MutatedOption.OptionState retrievedState
        ) = mutatedOption.options(optionId);
        assertEq(
            uint8(retrievedState),
            uint8(MutatedOption.OptionState.Closed)
        );
    }

    function testCloseOptionRevertNotActive() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        // uint256 closingFeeAmount = 5 ether;

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );

        vm.startPrank(seller);
        vm.expectRevert("Option: Not active");
        mutatedOption.closeOption(optionId); // Not purchased yet
        vm.stopPrank();
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

        vm.startPrank(buyer1);
        vm.expectRevert(
            "Option: Only the original seller can close this option"
        );
        mutatedOption.closeOption(optionId);
        vm.stopPrank();
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

        vm.startPrank(seller);
        vm.expectRevert("Option: Has already expired");
        mutatedOption.closeOption(optionId);
        vm.stopPrank();
    }

    function testCloseOptionRevertNoBuyer() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        // uint256 closingFeeAmount = 5 ether; // Even if a fee is specified, if no buyer, it should revert

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );

        // The option is created but not purchased, so buyer is address(0)
        vm.startPrank(seller);
        vm.expectRevert("Option: Not active");
        mutatedOption.closeOption(optionId);
        vm.stopPrank();
    }

    function testCloseOptionRevertZeroClosingFee() public {
        uint256 underlyingAmount = 1 ether;
        uint256 strikeAmount = 45 ether;
        uint256 premiumAmount = 10 ether;
        uint256 periodInSeconds = 3 days;
        uint256 closingFeeAmount = 0; // Set closing fee to 0

        uint256 optionId = _createOption(
            seller,
            underlyingAmount,
            strikeAmount,
            premiumAmount,
            periodInSeconds
        );
        _purchaseOption(buyer1, optionId, premiumAmount, closingFeeAmount); // Purchase with 0 closing fee

        vm.startPrank(seller);
        vm.expectRevert(
            "Option: Closing fee must be greater than 0 to close early"
        );
        mutatedOption.closeOption(optionId);
        vm.stopPrank();
    }
}
