// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title P2PExchange
 * @dev A simple peer-to-peer exchange contract where users can create offers
 * to trade one ERC20 token for another.
 */
contract P2PExchange {
    enum OfferStatus {
        Open,
        Filled,
        Cancelled
    }

    struct Offer {
        uint256 id;
        address payable maker; // The person who created the offer
        IERC20 tokenSell;      // The token the maker wants to sell
        uint256 amountSell;    // The amount of tokens to sell
        IERC20 tokenBuy;       // The token the maker wants to buy
        uint256 amountBuy;     // The amount of tokens to buy
        OfferStatus status;    // The current status of the offer
    }

    // --- State Variables ---

    Offer[] public offers;
    mapping(uint256 => address) public offerIdToMaker;

    // --- Events ---

    event OfferCreated(
        uint256 indexed id,
        address indexed maker,
        address tokenSell,
        uint256 amountSell,
        address tokenBuy,
        uint256 amountBuy
    );

    event OfferFilled(uint256 indexed id, address indexed taker);

    event OfferCancelled(uint256 indexed id);

    // --- Errors ---

    error InvalidOfferId(uint256 id);
    error NotOfferMaker(uint256 id, address caller);
    error OfferNotOpen(uint256 id);
    error TransferFailed();
    error InvalidAmount();

    // --- Functions ---

    /**
     * @dev Creates a new offer to trade tokens.
     * The caller must have approved the contract to spend `_amountSell` of `_tokenSell`.
     * @param _tokenSell The address of the ERC20 token to sell.
     * @param _amountSell The amount of the token to sell.
     * @param _tokenBuy The address of the ERC20 token to buy.
     * @param _amountBuy The amount of the token to buy.
     */
    function createOffer(
        IERC20 _tokenSell,
        uint256 _amountSell,
        IERC20 _tokenBuy,
        uint256 _amountBuy
    ) external {
        if (_amountSell == 0 || _amountBuy == 0) {
            revert InvalidAmount();
        }

        // Transfer the tokens to be sold from the maker to this contract
        bool success = _tokenSell.transferFrom(
            msg.sender,
            address(this),
            _amountSell
        );
        if (!success) {
            revert TransferFailed();
        }

        uint256 offerId = offers.length;

        offers.push(
            Offer({
                id: offerId,
                maker: payable(msg.sender),
                tokenSell: _tokenSell,
                amountSell: _amountSell,
                tokenBuy: _tokenBuy,
                amountBuy: _amountBuy,
                status: OfferStatus.Open
            })
        );

        offerIdToMaker[offerId] = msg.sender;

        emit OfferCreated(
            offerId,
            msg.sender,
            address(_tokenSell),
            _amountSell,
            address(_tokenBuy),
            _amountBuy
        );
    }

    /**
     * @dev Fills an existing open offer.
     * The caller (taker) must have approved the contract to spend `amountBuy` of `tokenBuy`.
     * @param _offerId The ID of the offer to fill.
     */
    function fillOffer(uint256 _offerId) external {
        if (_offerId >= offers.length) {
            revert InvalidOfferId(_offerId);
        }

        Offer storage offer = offers[_offerId];

        if (offer.status != OfferStatus.Open) {
            revert OfferNotOpen(_offerId);
        }

        // Transfer the tokens to buy from the taker to the maker
        bool success = offer.tokenBuy.transferFrom(
            msg.sender,
            offer.maker,
            offer.amountBuy
        );
        if (!success) {
            revert TransferFailed();
        }

        // Transfer the escrowed tokens from the contract to the taker
        success = offer.tokenSell.transfer(msg.sender, offer.amountSell);
        if (!success) {
            revert TransferFailed();
        }

        offer.status = OfferStatus.Filled;

        emit OfferFilled(_offerId, msg.sender);
    }

    /**
     * @dev Cancels an open offer. Only the offer maker can cancel.
     * @param _offerId The ID of the offer to cancel.
     */
    function cancelOffer(uint256 _offerId) external {
        if (_offerId >= offers.length) {
            revert InvalidOfferId(_offerId);
        }

        Offer storage offer = offers[_offerId];

        if (offer.maker != msg.sender) {
            revert NotOfferMaker(_offerId, msg.sender);
        }

        if (offer.status != OfferStatus.Open) {
            revert OfferNotOpen(_offerId);
        }

        // Return the escrowed tokens to the maker
        bool success = offer.tokenSell.transfer(offer.maker, offer.amountSell);
        if (!success) {
            revert TransferFailed();
        }

        offer.status = OfferStatus.Cancelled;

        emit OfferCancelled(_offerId);
    }

    /**
     * @dev Returns a list of all open offer IDs.
     * @return A dynamic array of uint256 containing the IDs of open offers.
     */
    function getOpenOffers() external view returns (uint256[] memory) {
        uint256 openOffersCount = 0;
        for (uint256 i = 0; i < offers.length; i++) {
            if (offers[i].status == OfferStatus.Open) {
                openOffersCount++;
            }
        }

        uint256[] memory openOfferIds = new uint256[](openOffersCount);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < offers.length; i++) {
            if (offers[i].status == OfferStatus.Open) {
                openOfferIds[currentIndex] = i;
                currentIndex++;
            }
        }

        return openOfferIds;
    }
}
