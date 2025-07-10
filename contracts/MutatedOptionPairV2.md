# MutatedOptionPairV2.sol

This document provides a detailed explanation of the `MutatedOptionPairV2` smart contract, outlining its functionalities, fee calculations, transaction flows, and potential pitfalls to avoid.

## 1. Contract Overview

`MutatedOptionPairV2` is a Solidity smart contract designed to facilitate a bilateral order book for "mutated options." It enables both buyers and sellers to create and fill orders for a fixed pair of assets: an `underlyingToken` and a `strikeToken`. The `strikeToken` is also used for paying premiums and closing fees.

**Key Components:**

*   **`underlyingToken`**: The asset that is subject to the option (e.g., ETH, BTC).
*   **`strikeToken`**: The asset used to pay the strike price, premiums, and closing fees (e.g., USDC, USDT).
*   **`feeCalculator`**: An external contract (`FeeCalculator.sol`) responsible for determining the premium fee.

**Option States (`OptionState` Enum):**

*   `Open`: An order (Bid or Ask) has been created and is awaiting a counterparty.
*   `Active`: An order has been filled, and the option is now active and can be exercised or closed.
*   `Exercised`: The buyer has successfully exercised the option.
*   `Expired`: The option's expiration timestamp has passed without being exercised.
*   `Closed`: The seller has successfully closed the option early.
*   `Canceled`: An `Open` order was canceled by its creator.

**Order Types (`OrderType` Enum):**

*   `Bid`: A buyer's order to buy an option (buyer locks premium).
*   `Ask`: A seller's order to sell an option (seller locks underlying asset).

**Option Structure (`Option` Struct):**

Each option/order is represented by an `Option` struct, containing details such as `optionId`, `creator`, `seller`, `buyer`, `underlyingAmount`, `strikeAmount`, `premiumAmount`, `expirationTimestamp`, `createTimestamp`, `totalPeriodSeconds`, `orderType`, and `state`.

## 2. Workflows and Transaction Flows

### 2.1. Order Creation

Both buyers and sellers can initiate an order.

*   **`createAsk(uint256 _underlyingAmount, uint256 _strikeAmount, uint256 _premiumAmount, uint256 _periodInSeconds)`**
    *   **Initiator**: Seller.
    *   **Purpose**: To offer an option for sale.
    *   **Pre-requisite**: The seller must `approve` the `MutatedOptionPairV2` contract to transfer `_underlyingAmount` of `underlyingToken` from their wallet.
    *   **Flow**: The `_underlyingAmount` of `underlyingToken` is transferred from the seller to the `MutatedOptionPairV2` contract and locked. An `Ask` order is created with `OptionState.Open`.
    *   **Minimum Period**: `_periodInSeconds` must be at least 1 hour (3600 seconds).

*   **`createBid(uint256 _underlyingAmount, uint256 _strikeAmount, uint256 _premiumAmount, uint256 _periodInSeconds)`**
    *   **Initiator**: Buyer.
    *   **Purpose**: To express interest in buying an option.
    *   **Pre-requisite**: The buyer must `approve` the `MutatedOptionPairV2` contract to transfer `_premiumAmount` of `strikeToken` from their wallet.
    *   **Flow**: The `_premiumAmount` of `strikeToken` is transferred from the buyer to the `MutatedOptionPairV2` contract and locked. A `Bid` order is created with `OptionState.Open`.
    *   **Minimum Period**: `_periodInSeconds` must be at least 1 hour (3600 seconds).

### 2.2. Order Filling

Once an order is `Open`, a counterparty can fill it, activating the option.

*   **`fillAsk(uint256 _optionId)`**
    *   **Initiator**: Buyer.
    *   **Purpose**: To accept a seller's `Ask` order.
    *   **Pre-requisite**: The buyer must `approve` the `MutatedOptionPairV2` contract to transfer the `premiumAmount` of `strikeToken` from their wallet.
    *   **Flow**: The `premiumAmount` is transferred from the buyer to the contract. A premium fee (calculated by `FeeCalculator`) is deducted from this amount and sent to the `feeRecipient`. The remaining premium is sent to the seller. The option's state changes from `Open` to `Active`, and `createTimestamp` and `expirationTimestamp` are set based on the `totalPeriodSeconds`.
    *   **Restriction**: The seller cannot fill their own `Ask` order.

*   **`fillBid(uint256 _optionId)`**
    *   **Initiator**: Seller.
    *   **Purpose**: To accept a buyer's `Bid` order.
    *   **Pre-requisite**: The seller must `approve` the `MutatedOptionPairV2` contract to transfer the `underlyingAmount` of `underlyingToken` from their wallet.
    *   **Flow**: The `underlyingAmount` of `underlyingToken` is transferred from the seller to the contract and locked. A premium fee (calculated by `FeeCalculator`) is deducted from the `premiumAmount` (which was locked by the buyer during `createBid`) and sent to the `feeRecipient`. The remaining premium is sent to the seller. The option's state changes from `Open` to `Active`, and `createTimestamp` and `expirationTimestamp` are set based on the `totalPeriodSeconds`.
    *   **Restriction**: The buyer cannot fill their own `Bid` order.

### 2.3. Order Cancellation

*   **`cancelOrder(uint256 _optionId)`**
    *   **Initiator**: The original `creator` of the `Open` order.
    *   **Purpose**: To cancel an `Open` order that has not yet been filled.
    *   **Flow**: The option's state changes to `Canceled`. The locked assets (either `underlyingToken` for an `Ask` or `strikeToken` for a `Bid`) are returned to the `creator`.
    *   **Restriction**: Only the `creator` can cancel an `Open` order.

### 2.4. Active Option Functions

Once an option is `Active`, it can be exercised, allowed to expire, or closed early.

*   **`exerciseOption(uint256 _optionId)`**
    *   **Initiator**: Buyer.
    *   **Purpose**: To exercise an active option before its expiration.
    *   **Pre-requisite**: The buyer must `approve` the `MutatedOptionPairV2` contract to transfer the `strikeAmount` of `strikeToken` from their wallet.
    *   **Flow**: The `strikeAmount` of `strikeToken` is transferred from the buyer to the seller. The `underlyingAmount` of `underlyingToken` (locked in the contract) is transferred from the contract to the buyer. The option's state changes to `Exercised`.
    *   **Restrictions**: Only the `buyer` can exercise. The option must be `Active` and not `Expired`.

*   **`claimUnderlyingOnExpiration(uint256 _optionId)`**
    *   **Initiator**: Seller.
    *   **Purpose**: To reclaim the locked `underlyingToken` if the option expires unexercised.
    *   **Flow**: The `underlyingAmount` of `underlyingToken` is returned to the seller. The option's state changes to `Expired`.
    *   **Restrictions**: Only the `seller` can claim. The option must be `Active` and `block.timestamp` must be greater than or equal to `expirationTimestamp`.

*   **`closeOption(uint256 _optionId)`**
    *   **Initiator**: Seller.
    *   **Purpose**: To close an active option early, typically to reclaim the `underlyingToken` before expiration.
    *   **Pre-requisite**: The seller must `approve` the `MutatedOptionPairV2` contract to transfer the calculated `closingFeeAmount` of `strikeToken` from their wallet.
    *   **Flow**: A `closingFeeAmount` is calculated (see Section 3.2) and transferred from the seller to the buyer. The `underlyingAmount` of `underlyingToken` (locked in the contract) is returned to the seller. The option's state changes to `Closed`.
    *   **Restrictions**: Only the `seller` can close. The option must be `Active` and not `Expired`. The option must have a `buyer` (i.e., it must have been filled).

## 3. Fee Mechanisms

### 3.1. Premium Fee (on Order Filling)

When an order is filled (`fillAsk` or `fillBid`), a fee is charged from the `premiumAmount`.

*   **Calculation**: The fee is determined by the external `FeeCalculator` contract via `feeCal.getFee(strikeToken, option.premiumAmount)`. The `FeeCalculator` contract defines the fee percentage or fixed amount based on the `strikeToken` and `premiumAmount`.
*   **Recipient**: The calculated fee is sent to the `feeRecipient` address configured in the `FeeCalculator` contract.
*   **Deduction**: The fee is deducted from the `premiumAmount` paid by the buyer (in `fillAsk`) or locked by the buyer (in `fillBid`). The seller receives `premiumAmount - fee`.
*   **Requirement**: The `premiumAmount` must be strictly greater than the calculated fee (`premiumAmount > fee`). If not, the transaction will revert.

### 3.2. Closing Fee (on Early Option Closure)

When a seller chooses to close an active option early using `closeOption`, a closing fee is paid to the buyer.

*   **Calculation**: The closing fee is calculated based on the remaining time of the option using the formula: `Y = 1 - (1 - X)^2`, where `X = remaining time / total contract time`.
    *   `remainingTime`: `option.expirationTimestamp - block.timestamp`.
    *   `totalPeriodSeconds`: The initial duration of the option.
    *   `Y`: The calculated closing fee percentage (returned by `getClosingFeePercentage`).
    *   The final `closingFeeAmount` is `Y * premiumAmount` (returned by `calculateClosingFeeAmount`).
*   **Recipient**: The calculated `closingFeeAmount` is paid by the seller directly to the buyer.
*   **Rationale**: This formula implies that the closer the option is to expiration, the lower the closing fee, as `X` approaches 0, `(1-X)^2` approaches 1, and `Y` approaches 0. Conversely, closing very early (large `X`) results in a higher fee.

## 4. Important Considerations and Avoiding Gas Waste

Users should be aware of the following to avoid failed transactions and wasted gas fees:

1.  **Token Approvals**: Always ensure that the `MutatedOptionPairV2` contract has sufficient `ERC20` `allowance` for the tokens it needs to transfer *before* calling functions like `createAsk`, `createBid`, `fillAsk`, `fillBid`, `exerciseOption`, or `closeOption`. Insufficient approval will cause the transaction to revert.

2.  **Correct Option State**: Most functions have strict `require` checks on the `OptionState`:
    *   `fillAsk`, `fillBid`, `cancelOrder`: Require `OptionState.Open`.
    *   `exerciseOption`, `claimUnderlyingOnExpiration`, `closeOption`: Require `OptionState.Active`.
    *   Attempting to call a function when the option is in an incorrect state will revert.

3.  **Correct Caller**: Functions enforce caller restrictions:
    *   `cancelOrder`: Only `creator`.
    *   `fillAsk`: Not `seller`.
    *   `fillBid`: Not `buyer`.
    *   `exerciseOption`: Only `buyer`.
    *   `claimUnderlyingOnExpiration`, `closeOption`: Only `seller`.
    *   Calling with an unauthorized address will revert.

4.  **Expiration Timestamps**: Pay close attention to `expirationTimestamp`:
    *   `exerciseOption` will revert if `block.timestamp >= option.expirationTimestamp`.
    *   `claimUnderlyingOnExpiration` will revert if `block.timestamp < option.expirationTimestamp`.
    *   `closeOption` will revert if `block.timestamp >= option.expirationTimestamp`.

5.  **Premium vs. Fee**: When filling an order (`fillAsk` or `fillBid`), the `premiumAmount` must be strictly greater than the calculated fee (`option.premiumAmount > fee`). If the premium is too low, the transaction will revert.

6.  **Minimum Period**: When creating an order (`createAsk` or `createBid`), the `_periodInSeconds` must be at least 3600 seconds (1 hour). Shorter periods will revert.

7.  **Zero Amounts**: Ensure `_underlyingAmount`, `_strikeAmount`, and `_premiumAmount` are greater than zero when creating orders. Zero amounts will revert.

By understanding these conditions, users can interact with the `MutatedOptionPairV2` contract efficiently and avoid unnecessary gas expenditures on failed transactions.