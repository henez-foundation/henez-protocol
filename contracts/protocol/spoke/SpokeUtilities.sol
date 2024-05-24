// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../common/Structs.sol";
import "./SpokeState.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract SpokeUtilities is Structs, SpokeState {
    /**
     * @notice Provides a quote for the cost of cross-chain transfer to the hub.
     * @param targetChain The target chain for the cross-chain transfer.
     * @param receiverValue The value to be sent to the hub.
     * @return cost The estimated cost for the cross-chain transfer.
     * @return secondaryCost The estimated cost for the secondary cross-chain transfer.
     */
    function quoteCrossChainPrice(uint16 targetChain, uint256 receiverValue)
        public
        view
        returns (uint256 cost, uint256 secondaryCost)
    {
        secondaryCost = 0;
        if (targetChain != hubChainId()) {
            (secondaryCost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, wormholeGasLimit());
        }

        (cost,) = wormholeRelayer.quoteEVMDeliveryPrice(hubChainId(), receiverValue + secondaryCost, wormholeGasLimit());
    }

    function checkValidHub(uint16 chainId, address sender) internal view {
        require(chainId == hubChainId(), "Invalid hub chain id");
        require(sender == hubContractAddress(), "Invalid hub address");
    }
}
