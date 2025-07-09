// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";

/**
 * @title FeeCalculator
 * @author Gemini
 * @notice This contract is responsible for calculating the fees for token transactions.
 *         It allows the owner to set fee rates for different tokens and provides a
 *         function to calculate the fee for a given amount of a specific token.
 *         Fee rates are stored as UD60x18 fixed-point numbers.
 */
contract FeeCalculator is Ownable {
    /**
     * @notice The fee rate is stored as a UD60x18 fixed-point number. 1.0 represents 100%.
     * @dev mapping from token address to fee rate in UD60x18 format.
     */
    mapping(address => UD60x18) public feeRates;

    event FeeRateSet(address indexed token, UD60x18 newRate);

    /**
     * @notice Initializes the contract, setting the deployer as the initial owner.
     * @param initialOwner The address of the initial owner.
     */
    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @notice Sets the fee rate for a specific token.
     * @dev The fee rate is specified as a UD60x18 number. For example, 0.005e18 for 0.5%.
     *      Can only be called by the owner.
     * @param token The address of the token for which to set the fee rate.
     * @param rate The new fee rate as a UD60x18 value.
     */
    function setFeeRate(address token, UD60x18 rate) external onlyOwner {
        require(rate.lte(ud(1e18)), "Fee rate cannot exceed 100%");
        feeRates[token] = rate;
        emit FeeRateSet(token, rate);
    }

    /**
     * @notice Calculates the fee for a given amount of a specific token.
     * @param token The address of the token.
     * @param amount The amount of the token for which to calculate the fee.
     * @return The calculated fee amount.
     */
    function getFee(address token, uint256 amount) external view returns (uint256) {
        UD60x18 rate = feeRates[token];
        if (rate.isZero()) {
            return 0;
        }
        // Convert amount to UD60x18, multiply by the rate, and convert back to uint256.
        return ud(amount).mul(rate).intoUint256();
    }
}
