// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import {FeeCalculator} from "./FeeCalculator.sol";

/**
 * @title MutatedOptionPair
 * @dev This contract manages a bilateral order book for mutated options,
 * allowing both buyers and sellers to create orders for a fixed asset pair.
 * The strike token is also used for premiums and closing fees.
 */
contract MutatedOptionPairV2 is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- State Variables ---

    address public immutable underlyingToken;
    address public immutable strikeToken;
    address public immutable feeCalculator;

    // Enum to define the type of an order
    enum OrderType {
        Bid, // A buyer's order to buy an option
        Ask // A seller's order to sell an option
    }

    // Enum to define the state of an option/order
    enum OptionState {
        Open, // Order is available to be filled
        Active, // Option has been formed and is active
        Exercised,
        Expired,
        Closed,
        Canceled // Order was canceled before being filled
    }

    // Struct to hold the details of an option order
    struct Option {
        uint256 optionId;
        address payable creator; // The address that created the order
        address payable seller;
        address payable buyer;
        uint256 underlyingAmount;
        uint256 strikeAmount;
        uint256 premiumAmount;
        uint256 expirationTimestamp;
        uint256 createTimestamp;
        uint256 totalPeriodSeconds;
        OrderType orderType;
        OptionState state;
    }

    mapping(uint256 => Option) private options;
    uint256 private nextOptionId;

    /**
     * @dev Returns the details of an option by its ID.
     * @param _optionId The ID of the option.
     * @return The Option struct containing all details.
     */
    function getOption(uint256 _optionId) public view returns (Option memory) {
        return options[_optionId];
    }

    // --- Events ---

    event OrderCreated(
        uint256 indexed optionId,
        OrderType indexed orderType,
        address indexed creator,
        uint256 underlyingAmount,
        uint256 strikeAmount,
        uint256 premiumAmount,
        uint256 expirationTimestamp
    );

    event OrderFilled(
        uint256 indexed optionId,
        address indexed buyer,
        address indexed seller,
        uint256 premiumAmount
    );

    event OrderCanceled(uint256 indexed optionId, address indexed creator);

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

    // --- Constructor ---

    constructor(
        address _underlyingToken,
        address _strikeToken,
        address _feeCalculator
    ) {
        underlyingToken = _underlyingToken;
        strikeToken = _strikeToken;
        feeCalculator = _feeCalculator;
        nextOptionId = 1;
    }

    // --- Order Creation ---

    /**
     * @dev Creates an "Ask" order to sell an option.
     * The seller (creator) must approve the contract to transfer the underlying tokens.
     */
    function createAsk(
        uint256 _underlyingAmount,
        uint256 _strikeAmount,
        uint256 _premiumAmount,
        uint256 _periodInSeconds
    ) external nonReentrant {
        require(_underlyingAmount > 0, "Ask: Underlying amount must be > 0");
        require(_strikeAmount > 0, "Ask: Strike amount must be > 0");
        require(_premiumAmount > 0, "Ask: Premium amount must be > 0");
        require(
            _periodInSeconds >= 3600,
            "Ask: Period must be at least 1 hour (3600 seconds)"
        );

        // Seller locks the underlying asset
        IERC20(underlyingToken).safeTransferFrom(
            msg.sender,
            address(this),
            _underlyingAmount
        );

        uint256 newOptionId = nextOptionId++;
        uint256 expiration = block.timestamp + _periodInSeconds;

        options[newOptionId] = Option({
            optionId: newOptionId,
            creator: payable(msg.sender),
            seller: payable(msg.sender),
            buyer: payable(address(0)),
            underlyingAmount: _underlyingAmount,
            strikeAmount: _strikeAmount,
            premiumAmount: _premiumAmount,
            expirationTimestamp: expiration,
            createTimestamp: 0,
            totalPeriodSeconds: _periodInSeconds,
            orderType: OrderType.Ask,
            state: OptionState.Open
        });

        emit OrderCreated(
            newOptionId,
            OrderType.Ask,
            msg.sender,
            _underlyingAmount,
            _strikeAmount,
            _premiumAmount,
            expiration
        );
    }

    /**
     * @dev Creates a "Bid" order to buy an option.
     * The buyer (creator) must approve the contract to transfer the premium tokens.
     */
    function createBid(
        uint256 _underlyingAmount,
        uint256 _strikeAmount,
        uint256 _premiumAmount,
        uint256 _periodInSeconds
    ) external nonReentrant {
        require(_underlyingAmount > 0, "Bid: Underlying amount must be > 0");
        require(_strikeAmount > 0, "Bid: Strike amount must be > 0");
        require(_premiumAmount > 0, "Bid: Premium amount must be > 0");
        require(
            _periodInSeconds >= 3600,
            "Bid: Period must be at least 1 hour (3600 seconds)"
        );

        // Buyer locks the premium
        IERC20(strikeToken).safeTransferFrom(
            msg.sender,
            address(this),
            _premiumAmount
        );

        uint256 newOptionId = nextOptionId++;
        uint256 expiration = block.timestamp + _periodInSeconds;

        options[newOptionId] = Option({
            optionId: newOptionId,
            creator: payable(msg.sender),
            seller: payable(address(0)),
            buyer: payable(msg.sender),
            underlyingAmount: _underlyingAmount,
            strikeAmount: _strikeAmount,
            premiumAmount: _premiumAmount,
            expirationTimestamp: expiration,
            createTimestamp: 0,
            totalPeriodSeconds: _periodInSeconds,
            orderType: OrderType.Bid,
            state: OptionState.Open
        });

        emit OrderCreated(
            newOptionId,
            OrderType.Bid,
            msg.sender,
            _underlyingAmount,
            _strikeAmount,
            _premiumAmount,
            expiration
        );
    }

    // --- Order Filling ---

    /**
     * @dev A buyer fills a seller's "Ask" order.
     * The buyer must approve the contract to transfer the premium.
     */
    function fillAsk(uint256 _optionId) external nonReentrant {
        Option storage option = options[_optionId];
        require(option.state == OptionState.Open, "Order: Not open");
        require(option.orderType == OrderType.Ask, "Order: Not an Ask");
        require(
            msg.sender != option.seller,
            "Order: Seller cannot fill their own Ask"
        );

        // State update
        option.buyer = payable(msg.sender);
        option.state = OptionState.Active;
        option.createTimestamp = block.timestamp;
        option.expirationTimestamp =
            block.timestamp +
            option.totalPeriodSeconds;

        // Calculate fee
        FeeCalculator feeCal = FeeCalculator(feeCalculator);
        uint256 fee = feeCal.getFee(strikeToken, option.premiumAmount);
        address feeRecipient = feeCal.feeRecipient();

        // Ensure premium is sufficient to pay the fee
        require(
            option.premiumAmount > fee,
            "Premium must be greater than the fee"
        );

        // Deduct fee from premium amount
        uint256 premiumToSeller = option.premiumAmount - fee;

        // Transfer the full premium from the buyer to this contract first.
        IERC20(strikeToken).safeTransferFrom(
            msg.sender,
            address(this),
            option.premiumAmount
        );

        // From the contract's balance, send the fee to the recipient and the rest to the seller.
        IERC20(strikeToken).safeTransfer(feeRecipient, fee);
        IERC20(strikeToken).safeTransfer(option.seller, premiumToSeller);

        emit OrderFilled(_optionId, msg.sender, option.seller, premiumToSeller);
    }

    /**
     * @dev A seller fills a buyer's "Bid" order.
     * The seller must approve the contract to transfer the underlying asset.
     */
    function fillBid(uint256 _optionId) external nonReentrant {
        Option storage option = options[_optionId];
        require(option.state == OptionState.Open, "Order: Not open");
        require(option.orderType == OrderType.Bid, "Order: Not a Bid");
        require(
            msg.sender != option.buyer,
            "Order: Buyer cannot fill their own Bid"
        );

        // State update
        option.seller = payable(msg.sender);
        option.state = OptionState.Active;
        option.createTimestamp = block.timestamp;
        option.expirationTimestamp =
            block.timestamp +
            option.totalPeriodSeconds;

        // Seller locks the underlying asset
        IERC20(underlyingToken).safeTransferFrom(
            msg.sender,
            address(this),
            option.underlyingAmount
        );

        // Calculate fee
        FeeCalculator feeCal = FeeCalculator(feeCalculator);
        uint256 fee = feeCal.getFee(strikeToken, option.premiumAmount);
        address feeRecipient = feeCal.feeRecipient();

        // Ensure premium is sufficient to pay the fee
        require(
            option.premiumAmount > fee,
            "Premium must be greater than the fee"
        );

        // Deduct fee from premium amount
        uint256 premiumToSeller = option.premiumAmount - fee;

        // Transfer fee to fee recipient
        IERC20(strikeToken).safeTransfer(feeRecipient, fee);

        // Premium (already locked in contract) is transferred to seller
        IERC20(strikeToken).safeTransfer(option.seller, premiumToSeller);

        emit OrderFilled(_optionId, option.buyer, msg.sender, premiumToSeller);
    }

    /**
     * @dev Cancels an open order. Only the creator can cancel.
     */
    function cancelOrder(uint256 _optionId) external nonReentrant {
        Option storage option = options[_optionId];
        require(option.state == OptionState.Open, "Order: Not open");
        require(msg.sender == option.creator, "Order: Only creator can cancel");

        option.state = OptionState.Canceled;

        // Return locked assets to the creator
        if (option.orderType == OrderType.Ask) {
            // Return underlying tokens to the seller
            IERC20(underlyingToken).safeTransfer(
                option.creator,
                option.underlyingAmount
            );
        } else {
            // Return premium tokens to the buyer
            IERC20(strikeToken).safeTransfer(
                option.creator,
                option.premiumAmount
            );
        }

        emit OrderCanceled(_optionId, msg.sender);
    }

    // --- Active Option Functions ---

    /**
     * @dev Allows the buyer to exercise an active option before expiration.
     */
    function exerciseOption(uint256 _optionId) external nonReentrant {
        Option storage option = options[_optionId];
        require(option.state == OptionState.Active, "Option: Not active");
        require(msg.sender == option.buyer, "Option: Only buyer can exercise");
        require(
            block.timestamp < option.expirationTimestamp,
            "Option: Expired"
        );

        option.state = OptionState.Exercised;

        // Buyer pays strike amount to seller
        IERC20(strikeToken).safeTransferFrom(
            msg.sender,
            option.seller,
            option.strikeAmount
        );

        // Buyer receives underlying asset from contract
        IERC20(underlyingToken).safeTransfer(
            option.buyer,
            option.underlyingAmount
        );

        emit OptionExercised(
            _optionId,
            option.buyer,
            option.seller,
            option.strikeAmount,
            option.underlyingAmount
        );
    }

    /**
     * @dev Allows the seller to claim underlying tokens if the option expires unexercised.
     */
    function claimUnderlyingOnExpiration(
        uint256 _optionId
    ) external nonReentrant {
        Option storage option = options[_optionId];
        require(option.state == OptionState.Active, "Option: Not active");
        require(msg.sender == option.seller, "Option: Only seller can claim");
        require(
            block.timestamp >= option.expirationTimestamp,
            "Option: Not expired yet"
        );

        option.state = OptionState.Expired;

        // Return underlying tokens to seller
        IERC20(underlyingToken).safeTransfer(
            option.seller,
            option.underlyingAmount
        );

        emit OptionExpired(_optionId, msg.sender, option.underlyingAmount);
    }

    /**
     * @dev Allows the seller to close an active option early by paying a closing fee.
     */
    function closeOption(uint256 _optionId) external nonReentrant {
        Option storage option = options[_optionId];
        require(option.state == OptionState.Active, "Option: Not active");
        require(msg.sender == option.seller, "Option: Only seller can close");
        require(
            block.timestamp < option.expirationTimestamp,
            "Option: Already expired"
        );
        require(
            option.buyer != address(0),
            "Option: Has not been purchased yet"
        );

        uint256 closingFee = calculateClosingFeeAmount(_optionId);
        require(closingFee > 0, "Option: Calculated closing fee must be > 0");

        option.state = OptionState.Closed;

        // Seller pays closing fee to buyer
        IERC20(strikeToken).safeTransferFrom(
            msg.sender,
            option.buyer,
            closingFee
        );

        // Underlying tokens are returned to seller
        IERC20(underlyingToken).safeTransfer(
            option.seller,
            option.underlyingAmount
        );

        emit OptionClosed(
            _optionId,
            msg.sender,
            option.buyer,
            closingFee,
            option.underlyingAmount
        );
    }

    /// @dev Calculates the closing fee percentage based on the formula Y = 1 - (1 - X)^2,
    ///      where X = remaining time / total contract time.
    /// @param _optionId The ID of the option.
    /// @return calculatedFeePercent The calculated closing fee percentage (in UD60x18 format).
    function getClosingFeePercentage(
        uint256 _optionId
    ) public view returns (UD60x18 calculatedFeePercent) {
        Option storage option = options[_optionId];

        // Ensure the option is active to calculate the closing fee
        require(
            option.state == OptionState.Active,
            "Option not active for fee calculation"
        );

        uint256 remainingTime;
        if (option.expirationTimestamp <= block.timestamp) {
            remainingTime = 0; // Expired or past due
        } else {
            remainingTime = option.expirationTimestamp - block.timestamp;
        }

        // Handle edge cases: if total period is zero or time has run out, the fee percentage is 0
        if (option.totalPeriodSeconds == 0 || remainingTime == 0) {
            return ud(0); // Return 0
        }

        // Calculate X = remainingTime / totalPeriodSeconds
        // Convert uint256 to UD60x18 for the division
        UD60x18 x_ud = ud(remainingTime).div(ud(option.totalPeriodSeconds));

        // Step 1: Calculate (1 - X)
        // Ensure that x_ud does not exceed UD60x18.ONE to prevent underflow in UD60x18.sub
        // If remainingTime > totalPeriodSeconds, this would mean X > 1.
        // Given the logic, remainingTime should always be <= totalPeriodSeconds for an active option.
        UD60x18 oneMinusX = UD60x18.wrap(1e18).sub(x_ud);

        // Step 2: Calculate (1 - X)^2
        UD60x18 oneMinusX_squared = oneMinusX.mul(oneMinusX);

        // Step 3: Calculate 1 - (1 - X)^2
        calculatedFeePercent = UD60x18.wrap(1e18).sub(oneMinusX_squared);

        return calculatedFeePercent;
    }

    /// @dev Calculates the closing fee amount the seller needs to pay for an early close.
    /// @param _optionId The ID of the option.
    /// @return closingFeeAmount The final closing fee amount.
    function calculateClosingFeeAmount(
        uint256 _optionId
    ) public view returns (uint256 closingFeeAmount) {
        Option storage option = options[_optionId];

        // Get the closing fee percentage (in UD60x18 format)
        UD60x18 feePercent = getClosingFeePercentage(_optionId);

        // Convert premiumAmount to UD60x18, then multiply by feePercent
        UD60x18 premiumAmount_ud = ud(option.premiumAmount);
        closingFeeAmount = premiumAmount_ud.mul(feePercent).intoUint256();

        return closingFeeAmount;
    }
}
