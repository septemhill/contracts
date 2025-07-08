// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/MutatedOptionFactoryV2.sol";
import "../contracts/MutatedOptionPairV2.sol";
import "../contracts/TestToken.sol";

contract MutatedOptionFactoryV2Test is Test {
    MutatedOptionFactoryV2 public factory;
    TestToken public tokenA;
    TestToken public tokenB;
    TestToken public tokenC;

    address public deployer;

    function setUp() public {
        deployer = makeAddr("deployer");

        vm.startPrank(deployer);
        factory = new MutatedOptionFactoryV2();
        tokenA = new TestToken("TokenA", "TKA", 1_000_000e18);
        tokenB = new TestToken("TokenB", "TKB", 1_000_000e18);
        tokenC = new TestToken("TokenC", "TKC", 1_000_000e18);
        vm.stopPrank();
    }

    function test_GetPairAddress() public view {
        bytes32 salt = keccak256(abi.encodePacked("test_salt_1"));
        address expectedAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(factory),
            salt,
            keccak256(abi.encodePacked(
                type(MutatedOptionPairV2).creationCode,
                abi.encode(address(tokenA), address(tokenB))
            ))
        )))));

        address calculatedAddress = factory.getPairAddress(address(tokenA), address(tokenB), salt);
        assertEq(calculatedAddress, expectedAddress, "Calculated address mismatch");
    }

    function test_CreateOptionPair_Success() public {
        bytes32 salt = keccak256(abi.encodePacked("test_salt_2"));

        vm.expectEmit(true, true, true, true);
        emit MutatedOptionFactoryV2.OptionPairCreated(
            address(tokenA),
            address(tokenB),
            factory.getPairAddress(address(tokenA), address(tokenB), salt),
            salt,
            1
        );

        address pairAddress = factory.createOptionPair(address(tokenA), address(tokenB), salt);

        assertNotEq(pairAddress, address(0), "Pair address should not be zero");
        assertEq(factory.allOptionPairs(0), pairAddress, "Pair not added to allOptionPairs");
        assertEq(factory.getPairBySalt(salt), pairAddress, "Salt mapping incorrect");
        assertEq(factory.totalOptionPairs(), 1, "Total pairs count incorrect");

        // Verify the created pair's tokens
        MutatedOptionPairV2 createdPair = MutatedOptionPairV2(payable(pairAddress));
        assertEq(createdPair.underlyingToken(), address(tokenA), "Created pair underlying token mismatch");
        assertEq(createdPair.strikeToken(), address(tokenB), "Created pair strike token mismatch");
    }

    function test_CreateOptionPair_RevertZeroUnderlyingToken() public {
        bytes32 salt = keccak256(abi.encodePacked("test_salt_3"));
        vm.expectRevert("Factory: Underlying token cannot be zero address");
        factory.createOptionPair(address(0), address(tokenB), salt);
    }

    function test_CreateOptionPair_RevertZeroStrikeToken() public {
        bytes32 salt = keccak256(abi.encodePacked("test_salt_4"));
        vm.expectRevert("Factory: Strike token cannot be zero address");
        factory.createOptionPair(address(tokenA), address(0), salt);
    }

    function test_CreateOptionPair_RevertSameTokens() public {
        bytes32 salt = keccak256(abi.encodePacked("test_salt_5"));
        vm.expectRevert("Factory: Tokens cannot be the same");
        factory.createOptionPair(address(tokenA), address(tokenA), salt);
    }

    function test_CreateOptionPair_RevertSaltUsed() public {
        bytes32 salt = keccak256(abi.encodePacked("test_salt_6"));
        factory.createOptionPair(address(tokenA), address(tokenB), salt);

        vm.expectRevert("Factory: Salt has been used");
        factory.createOptionPair(address(tokenA), address(tokenC), salt);
    }

    function test_TotalOptionPairs() public {
        assertEq(factory.totalOptionPairs(), 0, "Initial total pairs should be 0");

        bytes32 salt1 = keccak256(abi.encodePacked("salt_A"));
        factory.createOptionPair(address(tokenA), address(tokenB), salt1);
        assertEq(factory.totalOptionPairs(), 1, "Total pairs should be 1 after first creation");

        bytes32 salt2 = keccak256(abi.encodePacked("salt_B"));
        factory.createOptionPair(address(tokenA), address(tokenC), salt2);
        assertEq(factory.totalOptionPairs(), 2, "Total pairs should be 2 after second creation");
    }
}
