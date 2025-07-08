// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MutatedOptionPair.sol";

contract MutatedOptionFactory {
    address[] public allOptionPairs;

    event OptionPairCreated(
        address indexed underlyingToken,
        address indexed strikeToken,
        address pairAddress,
        uint256 totalPairs
    );

    /**
     * @dev Deploys a new MutatedOptionPair contract for a specific token pair.
     * Assumes premium and settlement tokens are the same as the strike token.
     * @param _underlyingToken The address of the underlying token (e.g., WBTC).
     * @param _strikeToken The address of the strike token (e.g., WETH, USDC).
     */
    function createOptionPair(
        address _underlyingToken,
        address _strikeToken
    ) external {
        require(
            _underlyingToken != address(0),
            "Factory: Underlying token cannot be zero address"
        );
        require(
            _strikeToken != address(0),
            "Factory: Strike token cannot be zero address"
        );
        require(
            _underlyingToken != _strikeToken,
            "Factory: Tokens cannot be the same"
        );

        MutatedOptionPair newOptionPair = new MutatedOptionPair(
            _underlyingToken,
            _strikeToken
        );

        allOptionPairs.push(address(newOptionPair));

        emit OptionPairCreated(
            _underlyingToken,
            _strikeToken,
            address(newOptionPair),
            allOptionPairs.length
        );
    }

    /**
     * @dev Returns the total number of option pair contracts created.
     */
    function totalOptionPairs() external view returns (uint256) {
        return allOptionPairs.length;
    }
}
