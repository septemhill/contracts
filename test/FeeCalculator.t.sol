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
    address public owner;
    address public user;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");

        vm.startPrank(owner);
        feeCalculator = new FeeCalculator(owner);
        tokenA = new TestToken("Token A", "TKA", 1_000_000, 6);
        tokenB = new TestToken("Token B", "TKB", 1_000_000, 8);
        vm.stopPrank();
    }

    function test_SetFeeRate() public {
        vm.startPrank(owner);
        // Set fee rate to 0.5%
        UD60x18 feeRate = ud(0.005e18);
        feeCalculator.setFeeRate(address(tokenA), feeRate);
        vm.stopPrank();

        assertEq(
            feeCalculator.feeRates(address(tokenA)).intoUint256(),
            feeRate.intoUint256()
        );
    }

    function test_CalculateFee() public {
        vm.startPrank(owner);
        // Set fee rate to 0.5%
        UD60x18 feeRate = ud(0.005e18);
        feeCalculator.setFeeRate(address(tokenA), feeRate);
        vm.stopPrank();

        uint256 amount = 1000 * (10**tokenA.decimals());
        uint256 expectedFee = ud(amount).mul(feeRate).intoUint256();
        uint256 actualFee = feeCalculator.getFee(address(tokenA), amount);

        assertEq(actualFee, expectedFee, "Fee calculation is incorrect");
    }

    function test_CalculateFee_NoRateSet() public view {
        uint256 amount = 1000 * (10**tokenB.decimals());
        uint256 fee = feeCalculator.getFee(address(tokenB), amount);
        assertEq(fee, 0, "Fee should be 0 for token with no rate set");
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
}
