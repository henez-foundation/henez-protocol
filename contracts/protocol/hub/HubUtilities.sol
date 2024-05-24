// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "wormhole-solidity-sdk/testing/helpers/BytesLib.sol";

import "./HubState.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";

abstract contract HubUtilities is HubState {
    using BytesLib for bytes;

    /**
     * @notice Provides a quote for the cost of cross-chain transfer to the hub.
     * @param targetChain The target chain for the cross-chain transfer.
     * @param receiverValue The value to be sent to the hub.
     * @return cost The estimated cost for the cross-chain transfer.
     */
    function quoteCrossChainPrice(uint16 targetChain, uint256 receiverValue) public view returns (uint256 cost) {
        (cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, receiverValue, wormholeGasLimit());
    }

    function getOraclePrices(address assetAddress) internal view returns (uint64, uint64) {
        AssetInfo memory assetInfo = getAssetInfo(assetAddress);

        uint8 oracleMode = getOracleMode();

        int64 priceValue;
        uint64 priceStandardDeviationsValue;

        if (oracleMode == 0) {
            // using Pyth price
            PythStructs.Price memory oraclePrice = getPythPriceStruct(assetInfo.pythId);

            priceValue = oraclePrice.price;
            priceStandardDeviationsValue = oraclePrice.conf;
        } else if (oracleMode == 1) {
            // using mock Pyth price
            priceValue = int64(mockTokenGasPrice());
            priceStandardDeviationsValue = uint64(449500504);
        } else {
            // using fake oracle price
            Price memory oraclePrice = getOraclePrice(assetInfo.pythId);

            priceValue = oraclePrice.price;
            priceStandardDeviationsValue = oraclePrice.conf;
        }

        require(priceValue >= 0, "no negative price assets allowed in XC borrow-lend");

        return (uint64(priceValue), priceStandardDeviationsValue);
    }

    //--------------------------- CHECKER ------------------------------//

    function checkValidSpoke(uint16 chainId, address sender) internal view {
        require(getSpokeContract(chainId) == sender, "Invalid spoke");
    }

    /**
     * @notice Check if an address has been registered on the Hub yet (through the registerAsset function)
     * Errors out if assetAddress has not been registered yet
     * @param assetAddress - The address to be checked
     */
    function checkValidAddress(address assetAddress) internal view {
        // check if asset address is allowed
        AssetInfo memory registeredInfo = getAssetInfo(assetAddress);
        require(registeredInfo.exists, "Unregistered asset");
    }

    /**
     * @notice Checks if the array of addresses has duplicate addresses
     * @param assetAddresses - The address array to be checked
     */
    function checkDuplicates(address[] memory assetAddresses) internal pure {
        // check if asset address array contains duplicates
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            for (uint256 j = 0; j < i; j++) {
                require(assetAddresses[i] != assetAddresses[j], "Address array has duplicate addresses");
            }
        }
    }

    /**
     * @dev Retrieves the USD value of the current collateral asset and minted peUSD through the price oracle.
     * Collateral asset USD value must be higher than the safe Collateral Ratio.
     * @param user_ The address of the user for whom health is being checked.
     * @param assetPrice_ The current price of the collateral asset.
     */
    function _checkHealth(address user_, uint256 assetPrice_) internal view {
        uint256 userCollateralRatio = _getUserCollateralRatio(user_, assetPrice_);

        require(userCollateralRatio > safeCollateralRatio(), "collateralRatio is below safeCollateralRatio");
    }
}
