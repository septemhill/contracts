// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";

interface ITokenWithDecimals is IERC20 {
    function decimals() external view returns (uint8);
}

/**
 * @title OptionContract
 * @author Gemini
 * @notice A smart contract for creating and trading European-style options for ERC20 token pairs.
 */
contract OptionContract {
    // --- Enums and Structs ---

    enum OptionType { Call, Put }

    struct Option {
        uint256 id;
        address creator;
        address buyer;
        OptionType optionType;
        address baseToken;      // e.g., WBTC
        address quoteToken;     // e.g., WETH
        uint256 baseAmount;     // Amount of baseToken to be exchanged
        uint256 strikePrice;    // Price of 1 baseToken unit in terms of quoteToken, with 18 decimals
        uint256 premium;        // Cost to buy the option, in quoteToken
        uint256 expiration;     // Unix timestamp of expiration
        bool isExercised;
        bool isCancelled;
    }

    // --- State Variables ---

    mapping(uint256 => Option) public options;
    uint256 private _nextOptionId;

    // --- Events ---

    event OptionCreated(
        uint256 indexed optionId,
        address indexed creator,
        OptionType optionType,
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        uint256 strikePrice,
        uint256 premium,
        uint256 expiration
    );

    event OptionBought(uint256 indexed optionId, address indexed buyer);
    event OptionExercised(uint256 indexed optionId, address indexed buyer);
    event CollateralReclaimed(uint256 indexed optionId, address indexed creator);
    event OptionCancelled(uint256 indexed optionId);

    // --- Errors ---

    error InvalidOptionId();
    error AlreadyPurchased();
    error NotPurchased();
    error NotTheBuyer();
    error NotTheCreator();
    error OptionExpired();
    error OptionNotExpired();
    error AlreadyExercised();
    error AlreadyCancelled();
    error ZeroAddress();
    error ZeroAmount();
    error TransferFailed();
    error SameToken();

    // --- Functions ---

    /**
     * @notice Creates a new option.
     * @dev The creator must approve the contract to spend the required collateral.
     *      The strike price is assumed to have 18 decimals.
     * @param _optionType The type of option (Call or Put).
     * @param _baseToken The address of the base token (the asset to be bought/sold).
     * @param _quoteToken The address of the quote token (the asset used for pricing).
     * @param _baseAmount The amount of base tokens in the option (in wei).
     * @param _strikePrice The price of one base token unit, denominated in quote tokens (with 18 decimals).
     * @param _premium The price to purchase the option, denominated in quote tokens (in wei).
     * @param _expiration The Unix timestamp when the option expires.
     * @return optionId The ID of the newly created option.
     */
    function createOption(
        OptionType _optionType,
        address _baseToken,
        address _quoteToken,
        uint256 _baseAmount,
        uint256 _strikePrice,
        uint256 _premium,
        uint256 _expiration
    ) external returns (uint256) {
        if (_baseToken == address(0) || _quoteToken == address(0)) revert ZeroAddress();
        if (_baseToken == _quoteToken) revert SameToken();
        if (_baseAmount == 0 || _strikePrice == 0) revert ZeroAmount();
        if (_expiration <= block.timestamp) revert OptionExpired();

        uint256 optionId = _nextOptionId;
        options[optionId] = Option({
            id: optionId,
            creator: msg.sender,
            buyer: address(0),
            optionType: _optionType,
            baseToken: _baseToken,
            quoteToken: _quoteToken,
            baseAmount: _baseAmount,
            strikePrice: _strikePrice,
            premium: _premium,
            expiration: _expiration,
            isExercised: false,
            isCancelled: false
        });

        _nextOptionId++;

        // Lock collateral
        if (_optionType == OptionType.Call) {
            // Seller needs to provide the base token as collateral
            _transferFrom(msg.sender, address(this), _baseToken, _baseAmount);
        } else {
            // Seller needs to provide the quote token as collateral (total value at strike price)
            uint256 quoteAmount = _getQuoteAmountForStrike(_baseToken, _quoteToken, _baseAmount, _strikePrice);
            _transferFrom(msg.sender, address(this), _quoteToken, quoteAmount);
        }

        emit OptionCreated(
            optionId, msg.sender, _optionType, _baseToken, _quoteToken,
            _baseAmount, _strikePrice, _premium, _expiration
        );

        return optionId;
    }

    /**
     * @notice Buys an existing option.
     * @dev The buyer must approve the contract to spend the premium amount.
     * @param _optionId The ID of the option to buy.
     */
    function buyOption(uint256 _optionId) external {
        Option storage opt = options[_optionId];
        if (opt.creator == address(0)) revert InvalidOptionId();
        if (opt.buyer != address(0)) revert AlreadyPurchased();
        if (opt.isCancelled) revert AlreadyCancelled();
        if (block.timestamp >= opt.expiration) revert OptionExpired();

        opt.buyer = msg.sender;

        // Pay premium to the creator
        if (opt.premium > 0) {
            _transferFrom(msg.sender, opt.creator, opt.quoteToken, opt.premium);
        }

        emit OptionBought(_optionId, msg.sender);
    }

    /**
     * @notice Exercises a purchased option.
     * @dev Can only be called by the buyer after the option has expired.
     * @param _optionId The ID of the option to exercise.
     */
    function exercise(uint256 _optionId) external {
        Option storage opt = options[_optionId];
        if (opt.creator == address(0)) revert InvalidOptionId();
        if (opt.buyer == address(0)) revert NotPurchased();
        if (opt.buyer != msg.sender) revert NotTheBuyer();
        if (block.timestamp < opt.expiration) revert OptionNotExpired();
        if (opt.isExercised) revert AlreadyExercised();

        opt.isExercised = true;

        if (opt.optionType == OptionType.Call) {
            // Buyer pays quote tokens to get base tokens
            uint256 quoteAmount = _getQuoteAmountForStrike(opt.baseToken, opt.quoteToken, opt.baseAmount, opt.strikePrice);
            _transferFrom(msg.sender, opt.creator, opt.quoteToken, quoteAmount);
            // Contract sends locked base tokens to the buyer
            _transfer(msg.sender, opt.baseToken, opt.baseAmount);
        } else { // Put
            // Buyer provides base tokens to get quote tokens
            _transferFrom(msg.sender, opt.creator, opt.baseToken, opt.baseAmount);
            // Contract sends locked quote tokens to the buyer
            uint256 quoteAmount = _getQuoteAmountForStrike(opt.baseToken, opt.quoteToken, opt.baseAmount, opt.strikePrice);
            _transfer(msg.sender, opt.quoteToken, quoteAmount);
        }

        emit OptionExercised(_optionId, msg.sender);
    }

    /**
     * @notice Reclaims collateral from an expired, un-exercised option.
     * @dev Can only be called by the creator. The contract's token balance is the guard against re-entrancy.
     * @param _optionId The ID of the option.
     */
    function reclaimCollateral(uint256 _optionId) external {
        Option storage opt = options[_optionId];
        if (opt.creator == address(0)) revert InvalidOptionId();
        if (opt.creator != msg.sender) revert NotTheCreator();
        if (block.timestamp < opt.expiration) revert OptionNotExpired();
        if (opt.isExercised) revert AlreadyExercised();

        // Transfer the remaining collateral back to the creator.
        // This will fail if called a second time as the contract balance will be zero.
        if (opt.optionType == OptionType.Call) {
            _transfer(opt.creator, opt.baseToken, opt.baseAmount);
        } else { // Put
            uint256 quoteAmount = _getQuoteAmountForStrike(opt.baseToken, opt.quoteToken, opt.baseAmount, opt.strikePrice);
            _transfer(opt.creator, opt.quoteToken, quoteAmount);
        }

        emit CollateralReclaimed(_optionId, msg.sender);
    }

    /**
     * @notice Cancels an option that has not been purchased yet.
     * @dev Can only be called by the creator.
     * @param _optionId The ID of the option to cancel.
     */
    function cancelOption(uint256 _optionId) external {
        Option storage opt = options[_optionId];
        if (opt.creator == address(0)) revert InvalidOptionId();
        if (opt.creator != msg.sender) revert NotTheCreator();
        if (opt.buyer != address(0)) revert AlreadyPurchased();
        if (opt.isCancelled) revert AlreadyCancelled();

        opt.isCancelled = true;

        // Return collateral to creator
        if (opt.optionType == OptionType.Call) {
            _transfer(opt.creator, opt.baseToken, opt.baseAmount);
        } else { // Put
            uint256 quoteAmount = _getQuoteAmountForStrike(opt.baseToken, opt.quoteToken, opt.baseAmount, opt.strikePrice);
            _transfer(opt.creator, opt.quoteToken, quoteAmount);
        }

        emit OptionCancelled(_optionId);
    }

    // --- Internal Helper Functions ---

    /**
     * @dev Calculates the amount of quote tokens corresponding to a given amount of base tokens at the strike price.
     *      Handles tokens with different decimal places. The strike price is assumed to have 18 decimals.
     */
    function _getQuoteAmountForStrike(
        address _baseToken,
        address _quoteToken,
        uint256 _baseAmount,
        uint256 _strikePrice
    ) private view returns (uint256) {
        uint8 baseDecimals = ITokenWithDecimals(_baseToken).decimals();
        uint8 quoteDecimals = ITokenWithDecimals(_quoteToken).decimals();
        uint256 priceDecimals = 18;

        // Formula: quoteAmount = (baseAmount * strikePrice) / 10**(priceDecimals + baseDecimals - quoteDecimals)
        uint256 exponent = priceDecimals + baseDecimals;
        if (exponent < quoteDecimals) {
            // This case is unlikely but handled for completeness.
            // It implies we need to multiply by a factor of 10.
            return _baseAmount * _strikePrice * (10**(uint256(quoteDecimals) - exponent));
        } else {
            exponent = exponent - quoteDecimals;
            return (_baseAmount * _strikePrice) / (10**exponent);
        }
    }

    function _transferFrom(address from, address to, address token, uint256 amount) private {
        bool success = IERC20(token).transferFrom(from, to, amount);
        if (!success) revert TransferFailed();
    }

    function _transfer(address to, address token, uint256 amount) private {
        bool success = IERC20(token).transfer(to, amount);
        if (!success) revert TransferFailed();
    }
}
