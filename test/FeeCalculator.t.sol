// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {FeeCalculator} from "../contracts/FeeCalculator.sol";
import {TestToken} from "../contracts/TestToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";

contract FeeCalculatorTest is Test {
    FeeCalculator public feeCalculator;
    TestToken public tokenA;
    TestToken public tokenB;
    TestToken public tokenC; // Add a third token for more robust testing
    address public owner;
    address public user;
    address public zeroAddress = address(0);

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");

        vm.startPrank(owner);
        feeCalculator = new FeeCalculator(owner);
        // Using common decimals for easier testing, e.g., 18 for most ERC20s
        tokenA = new TestToken("Token A", "TKA", 1_000_000e18, 18);
        tokenB = new TestToken("Token B", "TKB", 1_000_000e18, 18);
        tokenC = new TestToken("Token C", "TKC", 1_000_000e18, 18); // Initialize the new token
        vm.stopPrank();
    }

    // --- Existing Tests (Modified for new contract logic) ---

    function test_SetFeeRate() public {
        vm.startPrank(owner);
        // Set fee rate to 0.5%
        UD60x18 feeRate = ud(0.005e18); // 0.5%
        feeCalculator.setFeeRate(address(tokenA), feeRate);
        vm.stopPrank();

        // Assert fee rate is set
        assertEq(
            feeCalculator.feeRates(address(tokenA)).intoUint256(), // Use intoUint252 for UD60x18 comparison
            feeRate.intoUint256(),
            "Fee rate should be correctly set"
        );
        // Assert token is now supported
        assertTrue(
            feeCalculator.supportedTokens(address(tokenA)),
            "Token A should be marked as supported after setting fee rate"
        );
    }

    function test_CalculateFee() public {
        vm.startPrank(owner);
        // Set fee rate to 0.5%
        UD60x18 feeRate = ud(0.005e18); // 0.5%
        feeCalculator.setFeeRate(address(tokenA), feeRate);
        vm.stopPrank();

        uint256 amount = 1000e18; // Use 18 decimals for consistency
        uint256 expectedFee = ud(amount).mul(feeRate).intoUint256();
        uint256 actualFee = feeCalculator.getFee(address(tokenA), amount);

        assertEq(
            actualFee,
            expectedFee,
            "Fee calculation is incorrect for supported token"
        );
    }

    function test_CalculateFee_NoRateSetAndNotSupported() public {
        // This token has no rate set, and thus is not in supportedTokens mapping
        // It should revert as per the new logic
        uint256 amount = 1000e18;
        vm.expectRevert(
            "FeeCalculator: Token not supported for fee calculation"
        );
        feeCalculator.getFee(address(tokenB), amount);
    }

    function test_RevertIf_SetFeeRate_NotOwner() public {
        vm.startPrank(user);
        UD60x18 feeRate = ud(0.01e18); // 1%
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        feeCalculator.setFeeRate(address(tokenA), feeRate);
        vm.stopPrank();
    }

    function test_RevertIf_SetFeeRate_ExceedsMax() public {
        vm.startPrank(owner);
        // Set fee rate to 100.000...1% which is > 100%
        UD60x18 invalidRate = ud(1e18).add(ud(1));
        vm.expectRevert("Fee rate cannot exceed 100%");
        feeCalculator.setFeeRate(address(tokenA), invalidRate);
        vm.stopPrank();
    }

    // --- New Tests for Supported Tokens and Remove Support ---

    function test_SetFeeRate_ZeroAddressReverts() public {
        vm.startPrank(owner);
        UD60x18 feeRate = ud(0.001e18);
        vm.expectRevert("FeeCalculator: Token cannot be zero address");
        feeCalculator.setFeeRate(zeroAddress, feeRate);
        vm.stopPrank();
    }

    function test_CalculateFee_ZeroAddressReverts() public {
        uint256 amount = 100e18;
        vm.expectRevert("FeeCalculator: Token cannot be zero address");
        feeCalculator.getFee(zeroAddress, amount);
    }

    function test_CalculateFee_ZeroAmount() public {
        vm.startPrank(owner);
        UD60x18 feeRate = ud(0.005e18);
        feeCalculator.setFeeRate(address(tokenA), feeRate);
        vm.stopPrank();

        uint256 actualFee = feeCalculator.getFee(address(tokenA), 0);
        assertEq(actualFee, 0, "Fee should be 0 for zero amount");
    }

    function test_CalculateFee_SupportedButZeroRate() public {
        vm.startPrank(owner);
        // Set tokenC to be supported but with a 0% fee rate
        UD60x18 zeroFeeRate = ud(0);
        feeCalculator.setFeeRate(address(tokenC), zeroFeeRate);
        vm.stopPrank();

        assertTrue(
            feeCalculator.supportedTokens(address(tokenC)),
            "Token C should be supported"
        );
        assertEq(
            feeCalculator.feeRates(address(tokenC)).intoUint256(),
            zeroFeeRate.intoUint256(),
            "Token C fee rate should be 0"
        );

        uint256 amount = 500e18;
        uint256 actualFee = feeCalculator.getFee(address(tokenC), amount);
        assertEq(
            actualFee,
            0,
            "Fee should be 0 for supported token with zero rate"
        );
    }

    function test_RemoveTokenSupport_Success() public {
        vm.startPrank(owner);
        UD60x18 feeRate = ud(0.01e18); // 1%
        feeCalculator.setFeeRate(address(tokenB), feeRate); // First, set rate to support it
        vm.stopPrank();

        assertTrue(
            feeCalculator.supportedTokens(address(tokenB)),
            "Token B should be supported initially"
        );
        assertEq(
            feeCalculator.feeRates(address(tokenB)).intoUint256(),
            feeRate.intoUint256(),
            "Token B fee rate should be non-zero initially"
        );

        vm.startPrank(owner);
        // Expect events before the function call that triggers them
        vm.expectEmit(true, true, false, true); // indexed token, indexed newRate
        // Note: For FeeRateSet, the third boolean (indexed) refers to `msg.sender` if it were an indexed param in the event.
        // For TokenSupportToggled, the third boolean refers to `isSupported`.
        // You need to match the indexed parameters of your events precisely.
        // For FeeRateSet(address indexed token, UD60x18 newRate), token is indexed.
        // For TokenSupportToggled(address indexed token, bool isSupported), token is indexed.
        emit FeeCalculator.FeeRateSet(address(tokenB), ud(0)); // Explicitly qualify the event
        emit FeeCalculator.TokenSupportToggled(address(tokenB), false); // Explicitly qualify the event
        feeCalculator.removeTokenSupport(address(tokenB)); // This call triggers the events
        vm.stopPrank();

        assertFalse(
            feeCalculator.supportedTokens(address(tokenB)),
            "Token B should no longer be supported"
        );
        assertEq(
            feeCalculator.feeRates(address(tokenB)).intoUint256(),
            ud(0).intoUint256(),
            "Token B fee rate should be reset to 0"
        );

        // Verify that trying to get fee for tokenB now reverts
        uint256 amount = 100e18;
        vm.expectRevert(
            "FeeCalculator: Token not supported for fee calculation"
        );
        feeCalculator.getFee(address(tokenB), amount);
    }

    function test_RemoveTokenSupport_RevertsIfNotOwner() public {
        vm.startPrank(owner);
        feeCalculator.setFeeRate(address(tokenA), ud(0.005e18));
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        feeCalculator.removeTokenSupport(address(tokenA));
        vm.stopPrank();
    }

    function test_RemoveTokenSupport_RevertsIfNotCurrentlySupported() public {
        // tokenC is not supported initially
        assertFalse(
            feeCalculator.supportedTokens(address(tokenC)),
            "Token C should not be supported initially"
        );

        vm.startPrank(owner);
        vm.expectRevert("FeeCalculator: Token not currently supported");
        feeCalculator.removeTokenSupport(address(tokenC));
        vm.stopPrank();
    }

    function test_EventsEmitted() public {
        vm.startPrank(owner);
        // Test FeeRateSet event for setFeeRate
        UD60x18 rate1 = ud(0.005e18);
        vm.expectEmit(true, true, false, true); // _indexed [token], _indexed [newRate], non-indexed, non-indexed
        emit FeeCalculator.FeeRateSet(address(tokenA), rate1); // Specify the contract to qualify the event
        emit FeeCalculator.TokenSupportToggled(address(tokenA), true);
        feeCalculator.setFeeRate(address(tokenA), rate1); // This call triggers the events

        // Test events for removeTokenSupport
        // Need to set a rate for tokenB first so it's supported
        feeCalculator.setFeeRate(address(tokenB), ud(0.01e18)); // Set a rate for tokenB

        vm.expectEmit(true, true, false, true); // _indexed [token], _indexed [newRate]
        emit FeeCalculator.FeeRateSet(address(tokenB), ud(0)); // Expect rate to be set to 0
        emit FeeCalculator.TokenSupportToggled(address(tokenB), false); // Expect support to be toggled to false
        feeCalculator.removeTokenSupport(address(tokenB)); // This call triggers the events
        vm.stopPrank();
    }
}
