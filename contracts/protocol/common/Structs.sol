// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

//TODO: Update struct
contract Structs {
    struct VaultAmount {
        uint256 deposited;
        uint256 borrowed;
    }

    struct AccrualIndices {
        uint256 deposited;
        uint256 borrowed;
    }

    struct AssetInfo {
        bytes32 pythId;
        // pyth id info
        uint8 decimals;
        bool exists;
    }

    enum Action {
        DepositAssetToMint,
        Mint,
        Withdraw,
        Repay,
        Redeem,
        Swap
    }

    enum Round {
        UP,
        DOWN
    }

    // struct for mock oracle price
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    struct UserPosition {
        address asset;
        uint256 depositedAmount;
        uint256 depositedTime;
        uint256 borrowed;
    }

    struct ZUSDCCSupply {
        uint256 totalCrossChainSupply;
        // wormhole chainId => zusd supply
        mapping(uint16 => uint256) supplyByChainId;
    }
}
