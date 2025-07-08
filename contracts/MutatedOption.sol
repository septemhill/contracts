// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MutatedOption {
    // Enum to define the state of an option
    enum OptionState {
        AvailableForPurchase,
        Active,
        Exercised,
        Expired,
        Closed
    }

    // Struct to hold the details of an option
    struct Option {
        uint256 optionId;
        address payable seller; // Seller can receive ETH if premium/strike is ETH
        address payable buyer;  // Buyer can receive ETH if closingFee is ETH
        address underlyingTokenAddress;
        uint256 underlyingAmount;
        address strikeTokenAddress; // Also used as premiumToken
        uint256 strikeAmount;
        uint256 premiumAmount;
        uint256 expirationTimestamp;
        uint256 closingFeeAmount;
        OptionState state;
    }

    // Mapping to store options by their unique ID
    mapping(uint256 => Option) public options;
    // Counter for generating unique option IDs
    uint256 private nextOptionId;

    // Events to log key actions
    event OptionCreated(
        uint256 indexed optionId,
        address indexed seller,
        address underlyingToken,
        uint256 underlyingAmount,
        address strikeToken,
        uint256 strikeAmount,
        uint256 premiumAmount,
        uint256 expirationTimestamp
    );
    event OptionPurchased(
        uint256 indexed optionId,
        address indexed buyer,
        address indexed seller,
        uint256 premiumAmount,
        uint256 closingFeeAmount
    );
    event OptionExercised(
        uint256 indexed optionId,
        address indexed buyer,
        address indexed seller,
        uint256 strikeAmount,
        uint256 underlyingAmount
    );
    event OptionExpired(
        uint256 indexed optionId,
        address indexed seller,
        uint256 underlyingAmount
    );
    event OptionClosed(
        uint256 indexed optionId,
        address indexed seller,
        address indexed buyer,
        uint256 closingFeeAmount,
        uint256 underlyingAmount
    );

    constructor() {
        nextOptionId = 1; // Start option IDs from 1
    }

    /**
     * @dev Creates a new mutated option.
     * The seller must approve this contract to transfer `_underlyingAmount` of `_underlyingTokenAddress`
     * before calling this function.
     * @param _underlyingTokenAddress The address of the underlying ERC20 token.
     * @param _underlyingAmount The amount of underlying token the buyer can receive.
     * @param _strikeTokenAddress The address of the strike/premium ERC20 token.
     * @param _strikeAmount The amount of strike token the buyer must pay to exercise.
     * @param _premiumAmount The amount of premium token the buyer must pay to purchase.
     * @param _periodInSeconds The duration of the option in seconds from creation.
     */
    function createOption(
        address _underlyingTokenAddress,
        uint256 _underlyingAmount,
        address _strikeTokenAddress,
        uint256 _strikeAmount,
        uint256 _premiumAmount,
        uint256 _periodInSeconds
    ) external {
        require(_underlyingAmount > 0, "Underlying amount must be greater than 0");
        require(_strikeAmount > 0, "Strike amount must be greater than 0");
        require(_premiumAmount > 0, "Premium amount must be greater than 0");
        require(_periodInSeconds > 0, "Period must be greater than 0");

        // Transfer underlying tokens from seller to contract
        IERC20(_underlyingTokenAddress).transferFrom(
            msg.sender,
            address(this),
            _underlyingAmount
        );

        uint256 newOptionId = nextOptionId++;
        uint256 _expirationTimestamp = block.timestamp + _periodInSeconds;

        options[newOptionId] = Option({
            optionId: newOptionId,
            seller: payable(msg.sender),
            buyer: payable(address(0)), // Buyer is set to 0x0 initially
            underlyingTokenAddress: _underlyingTokenAddress,
            underlyingAmount: _underlyingAmount,
            strikeTokenAddress: _strikeTokenAddress,
            strikeAmount: _strikeAmount,
            premiumAmount: _premiumAmount,
            expirationTimestamp: _expirationTimestamp,
            closingFeeAmount: 0,
            state: OptionState.AvailableForPurchase
        });

        emit OptionCreated(
            newOptionId,
            msg.sender,
            _underlyingTokenAddress,
            _underlyingAmount,
            _strikeTokenAddress,
            _strikeAmount,
            _premiumAmount,
            _expirationTimestamp
        );
    }

    /**
     * @dev Allows a buyer to purchase an available option.
     * The buyer must approve this contract to transfer `option.premiumAmount` of `option.strikeToken`
     * before calling this function.
     * @param _optionId The ID of the option to purchase.
     * @param _closingFeeAmount The compensation amount the seller pays to the buyer for early closing.
     */
    function purchaseOption(uint256 _optionId, uint256 _closingFeeAmount) external {
        Option storage option = options[_optionId];
        require(option.state == OptionState.AvailableForPurchase, "Option not available for purchase");
        require(msg.sender != option.seller, "Seller cannot purchase their own option");

        // Transfer premium tokens from buyer to contract
        IERC20(option.strikeTokenAddress).transferFrom(
            msg.sender,
            address(this),
            option.premiumAmount
        );

        // Transfer premium tokens from contract to seller
        IERC20(option.strikeTokenAddress).transfer(option.seller, option.premiumAmount);

        option.buyer = payable(msg.sender);
        option.closingFeeAmount = _closingFeeAmount;
        option.state = OptionState.Active;

        emit OptionPurchased(_optionId, msg.sender, option.seller, option.premiumAmount, _closingFeeAmount);
    }

    /**
     * @dev Allows the buyer to exercise an active option before expiration.
     * The buyer must approve this contract to transfer `option.strikeAmount` of `option.strikeToken`
     * before calling this function.
     * @param _optionId The ID of the option to exercise.
     */
    function exerciseOption(uint256 _optionId) external {
        Option storage option = options[_optionId];
        require(option.state == OptionState.Active, "Option is not active");
        require(msg.sender == option.buyer, "Only the buyer can exercise this option");
        require(block.timestamp < option.expirationTimestamp, "Option has expired");

        // Transfer strike tokens from buyer to contract
        IERC20(option.strikeTokenAddress).transferFrom(
            msg.sender,
            address(this),
            option.strikeAmount
        );

        // Transfer strike tokens from contract to seller
        IERC20(option.strikeTokenAddress).transfer(option.seller, option.strikeAmount);

        // Transfer underlying tokens from contract to buyer
        IERC20(option.underlyingTokenAddress).transfer(option.buyer, option.underlyingAmount);

        option.state = OptionState.Exercised;

        emit OptionExercised(
            _optionId,
            msg.sender,
            option.seller,
            option.strikeAmount,
            option.underlyingAmount
        );
    }

    /**
     * @dev Allows the original seller to claim underlying tokens if the option expires unexercised.
     * @param _optionId The ID of the option.
     */
    function claimUnderlyingOnExpiration(uint256 _optionId) external {
        Option storage option = options[_optionId];
        require(option.state == OptionState.Active, "Option is not active");
        require(msg.sender == option.seller, "Only the original seller can claim");
        require(block.timestamp >= option.expirationTimestamp, "Option has not expired yet");

        // Transfer underlying tokens back to seller
        IERC20(option.underlyingTokenAddress).transfer(option.seller, option.underlyingAmount);

        option.state = OptionState.Expired;

        emit OptionExpired(_optionId, msg.sender, option.underlyingAmount);
    }

    /**
     * @dev Allows the original seller to close an active option early by paying a closing fee to the buyer.
     * The seller must approve this contract to transfer `option.closingFeeAmount` of `option.strikeToken`
     * before calling this function.
     * @param _optionId The ID of the option to close.
     */
    function closeOption(uint256 _optionId) external {
        Option storage option = options[_optionId];
        require(option.state == OptionState.Active, "Option is not active");
        require(msg.sender == option.seller, "Only the original seller can close this option");
        require(block.timestamp < option.expirationTimestamp, "Option has already expired");
        require(option.buyer != address(0), "Option has not been purchased yet"); // Ensure there's a buyer to pay the fee to

        // Transfer closing fee from seller to contract
        IERC20(option.strikeTokenAddress).transferFrom(
            msg.sender,
            address(this),
            option.closingFeeAmount
        );

        // Transfer closing fee from contract to buyer
        IERC20(option.strikeTokenAddress).transfer(option.buyer, option.closingFeeAmount);

        // Transfer underlying tokens back to seller
        IERC20(option.underlyingTokenAddress).transfer(option.seller, option.underlyingAmount);

        option.state = OptionState.Closed;

        emit OptionClosed(
            _optionId,
            msg.sender,
            option.buyer,
            option.closingFeeAmount,
            option.underlyingAmount
        );
    }
}