// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Structs.sol";
import "wormhole-solidity-sdk/testing/helpers/BytesLib.sol";

contract Messages is Structs {
    using BytesLib for bytes;

    function encodeActionPayload(Action action, bytes memory payload) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(action), payload);
    }

    function decodeDepositAssetToMintActionPayload(bytes memory actionPayload)
        internal
        pure
        returns (Action action, uint16 targetChain, uint256 depositAmount, address mintToAddress, uint256 mintAmount)
    {
        uint256 index = 0;

        action = Action(actionPayload.toUint8(index));
        index += 1;

        targetChain = actionPayload.toUint16(index);
        index += 2;

        depositAmount = actionPayload.toUint256(index);
        index += 32;

        mintToAddress = actionPayload.toAddress(index);
        index += 20;

        mintAmount = actionPayload.toUint256(index);
    }

    function decodeMintActionPayload(bytes memory actionPayload)
        internal
        pure
        returns (Action action, uint16 targetChain, address mintToAddress, uint256 mintAmount)
    {
        uint256 index = 0;

        action = Action(actionPayload.toUint8(index));
        index += 1;

        targetChain = actionPayload.toUint16(index);
        index += 2;

        mintToAddress = actionPayload.toAddress(index);
        index += 20;

        mintAmount = actionPayload.toUint256(index);
    }

    function getDecodedActionInPayload(bytes memory actionPayload) internal pure returns (Action action) {
        action = Action(actionPayload.toUint8(0));
    }

    function decodeWithdrawActionPayload(bytes memory actionPayload)
        internal
        pure
        returns (Action action, uint16 targetChain, address beneficiary, uint256 amount)
    {
        uint256 index = 0;

        action = Action(actionPayload.toUint8(index));
        index += 1;

        targetChain = actionPayload.toUint16(index);
        index += 2;

        beneficiary = actionPayload.toAddress(index);
        index += 20;

        amount = actionPayload.toUint256(index);
    }

    function decodeRedeemActionPayload(bytes memory actionPayload)
        internal
        pure
        returns (
            Action action,
            uint16 targetChain,
            address beneficiary,
            address provider,
            uint256 zusdAmount,
            uint256 minReceiveCollateralAmount
        )
    {
        uint256 index = 0;

        action = Action(actionPayload.toUint8(index));
        index += 1;

        targetChain = actionPayload.toUint16(index);
        index += 2;

        beneficiary = actionPayload.toAddress(index);
        index += 20;

        provider = actionPayload.toAddress(index);
        index += 20;

        zusdAmount = actionPayload.toUint256(index);
        index += 32;

        minReceiveCollateralAmount = actionPayload.toUint256(index);
    }

    function decodeRepayActionPayload(bytes memory actionPayload)
        internal
        pure
        returns (Action action, address user, uint256 amount)
    {
        uint256 index = 0;

        action = Action(actionPayload.toUint8(index));
        index += 1;

        user = actionPayload.toAddress(index);
        index += 20;

        amount = actionPayload.toUint256(index);
    }

    function decodeSwapActionPayload(bytes memory actionPayload)
        internal
        pure
        returns (Action action, uint16 targetChain, uint8 swapMode, address toAddress, uint256 amount)
    {
        uint256 index = 0;

        action = Action(actionPayload.toUint8(index));
        index += 1;

        targetChain = actionPayload.toUint16(index);
        index += 2;

        swapMode = actionPayload.toUint8(index);
        index += 1;

        toAddress = actionPayload.toAddress(index);
        index += 20;

        amount = actionPayload.toUint256(index);
    }
}
