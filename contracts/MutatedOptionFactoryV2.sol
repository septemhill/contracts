// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MutatedOptionPairV2.sol";

contract MutatedOptionFactoryV2 {
    address[] public allOptionPairs;
    mapping(bytes32 => address) public getPairBySalt;

    event OptionPairCreated(
        address indexed underlyingToken,
        address indexed strikeToken,
        address pairAddress,
        bytes32 salt,
        uint256 totalPairs
    );

    /**
     * @dev Calculates the deterministic address for a new MutatedOptionPairV2 contract.
     * This function allows predicting the address before deployment without consuming gas for state changes.
     * @param _underlyingToken The address of the underlying token.
     * @param _strikeToken The address of the strike token.
     * @param _salt A user-provided salt to ensure a unique, predictable address.
     * @return The predicted address of the new option pair contract.
     */
    function getPairAddress(
        address _underlyingToken,
        address _strikeToken,
        bytes32 _salt
    ) public view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(MutatedOptionPairV2).creationCode,
            abi.encode(_underlyingToken, _strikeToken)
        );
        
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            _salt,
            keccak256(bytecode)
        )))));
    }

    /**
     * @dev Deploys a new MutatedOptionPairV2 contract using CREATE2 for a deterministic address.
     * @param _underlyingToken The address of the underlying token (e.g., WBTC).
     * @param _strikeToken The address of the strike token (e.g., WETH, USDC).
     * @param _salt A user-provided salt for deterministic deployment. Must not have been used before.
     * @return The address of the newly created option pair contract.
     */
    function createOptionPair(
        address _underlyingToken,
        address _strikeToken,
        bytes32 _salt
    ) external returns (address) {
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
        require(
            getPairBySalt[_salt] == address(0),
            "Factory: Salt has been used"
        );

        MutatedOptionPairV2 newOptionPair = new MutatedOptionPairV2{salt: _salt}(
            _underlyingToken,
            _strikeToken
        );

        address pairAddress = address(newOptionPair);
        allOptionPairs.push(pairAddress);
        getPairBySalt[_salt] = pairAddress;

        emit OptionPairCreated(
            _underlyingToken,
            _strikeToken,
            pairAddress,
            _salt,
            allOptionPairs.length
        );
        
        return pairAddress;
    }

    /**
     * @dev Returns the total number of option pair contracts created.
     */
    function totalOptionPairs() external view returns (uint256) {
        return allOptionPairs.length;
    }
}
