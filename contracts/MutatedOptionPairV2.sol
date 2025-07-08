// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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
        uint256 closingFeeAmount;
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
        uint256 premiumAmount,
        uint256 closingFeeAmount
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

    constructor(address _underlyingToken, address _strikeToken) {
        underlyingToken = _underlyingToken;
        strikeToken = _strikeToken;
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
        require(_periodInSeconds > 0, "Ask: Period must be > 0");

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
            closingFeeAmount: 0,
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
        uint256 _periodInSeconds,
        uint256 _closingFeeAmount
    ) external nonReentrant {
        require(_underlyingAmount > 0, "Bid: Underlying amount must be > 0");
        require(_strikeAmount > 0, "Bid: Strike amount must be > 0");
        require(_premiumAmount > 0, "Bid: Premium amount must be > 0");
        require(_periodInSeconds > 0, "Bid: Period must be > 0");

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
            closingFeeAmount: _closingFeeAmount,
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
    function fillAsk(
        uint256 _optionId,
        uint256 _closingFeeAmount
    ) external nonReentrant {
        Option storage option = options[_optionId];
        require(option.state == OptionState.Open, "Order: Not open");
        require(option.orderType == OrderType.Ask, "Order: Not an Ask");
        require(
            msg.sender != option.seller,
            "Order: Seller cannot fill their own Ask"
        );

        // State update
        option.buyer = payable(msg.sender);
        option.closingFeeAmount = _closingFeeAmount;
        option.state = OptionState.Active;

        // Premium transfer from buyer to seller
        IERC20(strikeToken).safeTransferFrom(
            msg.sender,
            option.seller,
            option.premiumAmount
        );

        emit OrderFilled(
            _optionId,
            msg.sender,
            option.seller,
            option.premiumAmount,
            _closingFeeAmount
        );
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

        // Seller locks the underlying asset
        IERC20(underlyingToken).safeTransferFrom(
            msg.sender,
            address(this),
            option.underlyingAmount
        );

        // Premium (already locked in contract) is transferred to seller
        IERC20(strikeToken).safeTransfer(option.seller, option.premiumAmount);

        emit OrderFilled(
            _optionId,
            option.buyer,
            msg.sender,
            option.premiumAmount,
            option.closingFeeAmount
        );
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
        require(option.closingFeeAmount > 0, "Option: Closing fee must be > 0");

        option.state = OptionState.Closed;

        // Seller pays closing fee to buyer
        IERC20(strikeToken).safeTransferFrom(
            msg.sender,
            option.buyer,
            option.closingFeeAmount
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
            option.closingFeeAmount,
            option.underlyingAmount
        );
    }
}
