// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MutatedOption is ReentrancyGuard {
    using SafeERC20 for IERC20;

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
        address payable buyer; // Buyer can receive ETH if closingFee is ETH
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
    ) external nonReentrant {
        require(
            _underlyingAmount > 0,
            "Option: Underlying amount must be greater than 0"
        );
        require(
            _strikeAmount > 0,
            "Option: Strike amount must be greater than 0"
        );
        require(
            _premiumAmount > 0,
            "Option: Premium amount must be greater than 0"
        );
        require(_periodInSeconds > 0, "Option: Period must be greater than 0");
        require(
            _underlyingTokenAddress != address(0),
            "Option: Underlying token address cannot be zero"
        );
        require(
            _strikeTokenAddress != address(0),
            "Option: Strike token address cannot be zero"
        );

        // Transfer underlying tokens from seller to contract
        // Using SafeERC20 for checked transferFrom
        IERC20(_underlyingTokenAddress).safeTransferFrom(
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
    function purchaseOption(
        uint256 _optionId,
        uint256 _closingFeeAmount
    ) external nonReentrant {
        Option storage option = options[_optionId];
        require(
            option.state == OptionState.AvailableForPurchase,
            "Option: Not available for purchase"
        );
        require(
            msg.sender != option.seller,
            "Option: Seller cannot purchase their own option"
        );

        // Checks-Effects-Interactions pattern: Update state before external calls
        option.buyer = payable(msg.sender);
        option.closingFeeAmount = _closingFeeAmount;
        option.state = OptionState.Active;

        // Transfer premium tokens from buyer to contract
        // Using SafeERC20 for checked transferFrom
        IERC20(option.strikeTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            option.premiumAmount
        );

        // Transfer premium tokens from contract to seller
        // Using SafeERC20 for checked transfer
        IERC20(option.strikeTokenAddress).safeTransfer(
            option.seller,
            option.premiumAmount
        );

        emit OptionPurchased(
            _optionId,
            msg.sender,
            option.seller,
            option.premiumAmount,
            _closingFeeAmount
        );
    }

    /**
     * @dev Allows the buyer to exercise an active option before expiration.
     * The buyer must approve this contract to transfer `option.strikeAmount` of `option.strikeToken`
     * before calling this function.
     * @param _optionId The ID of the option to exercise.
     */
    function exerciseOption(uint256 _optionId) external nonReentrant {
        Option storage option = options[_optionId];
        require(option.state == OptionState.Active, "Option: Not active");
        require(
            msg.sender == option.buyer,
            "Option: Only the buyer can exercise this option"
        );
        require(
            block.timestamp < option.expirationTimestamp,
            "Option: Has expired"
        );

        // Checks-Effects-Interactions pattern: Update state before external calls
        option.state = OptionState.Exercised;

        // Transfer strike tokens from buyer to contract
        // Using SafeERC20 for checked transferFrom
        IERC20(option.strikeTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            option.strikeAmount
        );

        // Transfer strike tokens from contract to seller
        // Using SafeERC20 for checked transfer
        IERC20(option.strikeTokenAddress).safeTransfer(
            option.seller,
            option.strikeAmount
        );

        // Transfer underlying tokens from contract to buyer
        // Using SafeERC20 for checked transfer
        IERC20(option.underlyingTokenAddress).safeTransfer(
            option.buyer,
            option.underlyingAmount
        );

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
    function claimUnderlyingOnExpiration(
        uint256 _optionId
    ) external nonReentrant {
        Option storage option = options[_optionId];
        require(
            option.state == OptionState.Active,
            "Option: Not active or already handled"
        );
        require(
            msg.sender == option.seller,
            "Option: Only the original seller can claim"
        );
        require(
            block.timestamp >= option.expirationTimestamp,
            "Option: Has not expired yet"
        );

        // Checks-Effects-Interactions pattern: Update state before external calls
        option.state = OptionState.Expired;

        // Transfer underlying tokens back to seller
        // Using SafeERC20 for checked transfer
        IERC20(option.underlyingTokenAddress).safeTransfer(
            option.seller,
            option.underlyingAmount
        );

        emit OptionExpired(_optionId, msg.sender, option.underlyingAmount);
    }

    /**
     * @dev Allows the original seller to close an active option early by paying a closing fee to the buyer.
     * The seller must approve this contract to transfer `option.closingFeeAmount` of `option.strikeToken`
     * before calling this function.
     * @param _optionId The ID of the option to close.
     */
    function closeOption(uint256 _optionId) external nonReentrant {
        Option storage option = options[_optionId];
        require(option.state == OptionState.Active, "Option: Not active");
        require(
            msg.sender == option.seller,
            "Option: Only the original seller can close this option"
        );
        require(
            block.timestamp < option.expirationTimestamp,
            "Option: Has already expired"
        );
        require(
            option.buyer != address(0),
            "Option: Has not been purchased yet"
        ); // Ensure there's a buyer to pay the fee to
        require(
            option.closingFeeAmount > 0,
            "Option: Closing fee must be greater than 0 to close early"
        );

        // Checks-Effects-Interactions pattern: Update state before external calls
        option.state = OptionState.Closed;

        // Transfer closing fee from seller to contract
        // Using SafeERC20 for checked transferFrom
        IERC20(option.strikeTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            option.closingFeeAmount
        );

        // Transfer closing fee from contract to buyer
        // Using SafeERC20 for checked transfer
        IERC20(option.strikeTokenAddress).safeTransfer(
            option.buyer,
            option.closingFeeAmount
        );

        // Transfer underlying tokens back to seller
        // Using SafeERC20 for checked transfer
        IERC20(option.underlyingTokenAddress).safeTransfer(
            option.seller,
            option.underlyingAmount
        );

        emit OptionClosed(
            _optionId,
            msg.sender,
            option.buyer,
            option.closingFeeAmount,
            option.underlyingAmount
        );
    }
}
