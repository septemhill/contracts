// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";

/**
 * @title FeeCalculator
 * @author Gemini
 * @notice This contract is responsible for calculating the fees for token transactions.
 * It allows the owner to set fee rates for specific, explicitly supported tokens.
 * Fee rates are stored as UD60x18 fixed-point numbers.
 * Only supported tokens can have their fees calculated.
 */
contract FeeCalculator is Ownable {
    /**
     * @notice Mapping from token address to its fee rate in UD60x18 format.
     * 1.0e18 represents 100%.
     */
    mapping(address => UD60x18) public feeRates;

    /**
     * @notice Mapping to keep track of explicitly supported tokens.
     * Only tokens marked as true here can have their fees calculated.
     */
    mapping(address => bool) public supportedTokens;

    /**
     * @notice The address that will receive the fees.
     */
    address payable public feeRecipient;

    event FeeRateSet(address indexed token, UD60x18 newRate);
    event TokenSupportToggled(address indexed token, bool isSupported);
    event FeeRecipientUpdated(
        address indexed oldRecipient,
        address indexed newAddress
    );

    /**
     * @notice Initializes the contract, setting the deployer as the initial owner and the fee receiving address.
     * @param initialOwner The address of the initial owner.
     * @param initialFeeRecipient The address that will receive the fees.
     */
    constructor(
        address initialOwner,
        address initialFeeRecipient
    ) Ownable(initialOwner) {
        require(
            initialFeeRecipient != address(0),
            "FeeCalculator: Fee receiving address cannot be zero address"
        );
        feeRecipient = payable(initialFeeRecipient);
    }

    /**
     * @notice Sets the fee rate for a specific token and adds it to the supported list.
     * @dev The fee rate is specified as a UD60x18 number (e.g., 0.005e18 for 0.5%).
     * Can only be called by the owner.
     * A rate of 0 means the token is supported but currently has no fee.
     * @param token The address of the token for which to set the fee rate.
     * @param rate The new fee rate as a UD60x18 value.
     */
    function setFeeRate(address token, UD60x18 rate) external onlyOwner {
        // Prevent setting fee for zero address
        require(
            token != address(0),
            "FeeCalculator: Token cannot be zero address"
        );
        require(rate.lte(ud(1e18)), "Fee rate cannot exceed 100%");

        feeRates[token] = rate;
        supportedTokens[token] = true; // Automatically mark as supported when setting a rate

        emit FeeRateSet(token, rate);
        emit TokenSupportToggled(token, true);
    }

    /**
     * @notice Removes support for a token and sets its fee rate to zero.
     * No fees will be calculated for this token thereafter.
     * @param token The address of the token to remove support for.
     */
    function removeTokenSupport(address token) external onlyOwner {
        require(
            token != address(0),
            "FeeCalculator: Token cannot be zero address"
        );
        require(
            supportedTokens[token],
            "FeeCalculator: Token not currently supported"
        ); // Only remove if it was supported

        feeRates[token] = ud(0); // Explicitly set rate to zero
        supportedTokens[token] = false; // Mark as not supported

        emit FeeRateSet(token, ud(0));
        emit TokenSupportToggled(token, false);
    }

    /**
     * @notice Calculates the fee for a given amount of a specific token.
     * @dev Will revert if the token is not explicitly marked as supported.
     * @param token The address of the token.
     * @param amount The amount of the token for which to calculate the fee.
     * @return The calculated fee amount.
     */
    function getFee(
        address token,
        uint256 amount
    ) external view returns (uint256) {
        require(
            token != address(0),
            "FeeCalculator: Token cannot be zero address"
        ); // Prevent getting fee for zero address
        require(
            supportedTokens[token],
            "FeeCalculator: Token not supported for fee calculation"
        ); // Only calculate fee for supported tokens

        UD60x18 rate = feeRates[token];

        // If the token is supported but has a fee rate of 0, return 0.
        // This allows us to differentiate between supported and unsupported tokens.
        if (rate.isZero()) {
            return 0;
        }
        // Convert amount to UD60x18, multiply by the rate, and convert back to uint256.
        return ud(amount).mul(rate).intoUint256();
    }

    /**
     * @notice Updates the fee receiving address.
     * @param _newAddress The new address that will receive the fees.
     */
    function updateFeeRecipient(address _newAddress) external onlyOwner {
        require(
            _newAddress != address(0),
            "FeeCalculator: Fee receiving address cannot be zero address"
        );
        emit FeeRecipientUpdated(feeRecipient, _newAddress);
        feeRecipient = payable(_newAddress);
    }
}
