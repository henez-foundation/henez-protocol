// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../common/Structs.sol";
import "../common/Messages.sol";
import "./SpokeUtilities.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract Spoke is Messages, SpokeUtilities, IWormholeReceiver, PausableUpgradeable, ReentrancyGuardUpgradeable {
    event Mint(address user, uint256 amount);
    event Withdraw(address user, uint256 amount);
    event Repay(address user, uint256 amount);
    event Redeem(address user, uint256 amount);

    function initialize(
        address wormholeRelayer_,
        address wormhole_,
        uint16 hubChainId,
        address hubContractAddress,
        address zUSD_,
        address USDC_,
        uint16 spokeChainId_
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __Pausable_init();
        wormholeRelayer = IWormholeRelayer(wormholeRelayer_);
        wormhole = IWormhole(wormhole_);
        setHubChainId(hubChainId);
        setHubContractAddress(hubContractAddress);
        setWormholeGasLimit(300_000);
        setChainId(spokeChainId_);
        setZUSD(zUSD_);
        setUSDC(USDC_);
    }

    /**
     * @notice This function is triggered by the Wormhole relayer.
     * @param payload The payload of the message being received.
     * @param sourceAddress The address of the message sender on the source chain.
     * @param sourceChain The Wormhole chain ID of the source chain.
     * @param deliveryHash The hash of the delivery.
     */
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory, // additionalVaas
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) public payable override onlyWormholeRelayer isRegisteredSender(sourceChain, sourceAddress) {
        require(msg.sender == address(wormholeRelayer), "Only relayer allowed");
        require(!_state.consumedMessages[deliveryHash], "Already consumed");
        Action action = getDecodedActionInPayload(payload);

        if (action == Action.Mint) {
            (Action action_, uint16 targetChain_, address mintToAddress_, uint256 mintAmount_) =
                decodeMintActionPayload(payload);
            require(targetChain_ == chainId(), "invalid target chain");
            _mintZUSD(mintToAddress_, mintAmount_);
        } else if (action == Action.Withdraw) {
            (, uint16 targetChain_, address beneficiary_, uint256 amount_) = decodeWithdrawActionPayload(payload);
            _withdrawOnSpoke(beneficiary_, amount_);
        } else if (action == Action.Redeem) {
            (, uint16 targetChain_, address beneficiary_, uint256 amount_) = decodeWithdrawActionPayload(payload);
            _handleWithdraw(targetChain_, beneficiary_, amount_);
        }

        consumeMessageHash(deliveryHash);
    }

    /**
     * @notice Deposits collateral to mint ZUSD.
     * @param targetChain_ The Wormhole chain ID where the ZUSD will be minted.
     * @param depositAmount_ The amount of ETH the user wants to deposit to the hub.
     * @param mintAmount_ The amount of ZUSD to be minted.
     * @param mintToAddress_ The address where the minted ZUSD will be sent.
     */
    function depositAssetToMint(
        uint16 targetChain_,
        uint256 depositAmount_,
        uint256 mintAmount_,
        address mintToAddress_
    ) public payable returns (uint64 sequence) {
        // cost = depositAmount + gas price for crosschain messaging
        (uint256 cost, uint256 secondaryCost) = quoteCrossChainPrice(targetChain_, depositAmount_); // only calculate gas price
        require(msg.value >= cost, "Value must greater than or equal gas used for cross-chain messaging");

        // send mint payload to target chain
        bytes memory message = abi.encodePacked(targetChain_, depositAmount_, mintToAddress_, mintAmount_);
        bytes memory serializedMessage = encodeActionPayload(Action.DepositAssetToMint, message);

        sequence = wormholeRelayer.sendPayloadToEvm{value: cost}(
            hubChainId(),
            hubContractAddress(),
            serializedMessage,
            depositAmount_ + secondaryCost,
            wormholeGasLimit(),
            chainId(),
            msg.sender
        );
    }

    /**
     * @notice Withdraws `amount_` of collateral to receive on `targetChain_`.
     * @param targetChain_ The Wormhole chain ID where the collateral will be received.
     * @param amount_ The amount of collateral to withdraw.
     * @param receiverValueContinueCrossChainForHub The value to be sent to the hub when continuing the cross-chain transfer.
     */
    function withdraw(uint16 targetChain_, uint256 amount_, uint256 receiverValueContinueCrossChainForHub)
        public
        payable
    {
        require(amount_ != 0, "ZERO_WITHDRAW");
        _crosschainWithdraw(targetChain_, msg.sender, amount_, receiverValueContinueCrossChainForHub);
    }

    /**
     * @notice Redeems `zusdAmount` of ZUSD to get a 1:1 value of collateral.
     * @param targetChain_ The chain on which the user wants to receive the collateral.
     * @param beneficiary_ The user (caller) who redeems and owns the ZUSD.
     * @param provider The user with the ZUSD borrowed position who provides the collateral.
     * @param zusdAmount The amount of ZUSD the caller wishes to redeem.
     * @param minReceiveCollateralAmount The minimum amount of collateral to receive.
     * @param receiverValueContinueCrossChainForHub The amount for the hub to continue sending cross-chain messages.
     */
    function redeem(
        uint16 targetChain_,
        address beneficiary_,
        address provider,
        uint256 zusdAmount,
        uint256 minReceiveCollateralAmount,
        uint256 receiverValueContinueCrossChainForHub // gas for hub to send another crosschain message
    ) public payable {
        // caller repays zusd
        require(zUSD().balanceOf(msg.sender) >= zusdAmount, "Token balance must be greater");
        zUSD().burn(msg.sender, zusdAmount);

        // send crosschain message to decrement borrow amount of provider and receive collateral
        _crosschainRedeem(
            targetChain_,
            beneficiary_,
            provider,
            zusdAmount,
            minReceiveCollateralAmount,
            receiverValueContinueCrossChainForHub
        );
        emit Redeem(msg.sender, zusdAmount);
    }

    /**
     * @notice Mints `mintAmount_` of ZUSD on `targetChain_`.
     * @param targetChain_ The Wormhole chain ID where the ZUSD will be received.
     * @param mintAmount_ The amount of ZUSD to mint.
     */
    function mint(address mintToAddress_, uint256 mintAmount_, uint16 targetChain_)
        public
        payable
        returns (uint256 sequence)
    {
        // cost = double gas price for crosschain messaging
        (uint256 cost, uint256 secondaryCost) = quoteCrossChainPrice(targetChain_, 0); // only calculate gas price
        require(msg.value >= cost, "Value must greater than or equal gas used for cross-chain messaging");

        // send mint payload to target chain
        bytes memory message = abi.encodePacked(targetChain_, mintToAddress_, mintAmount_);
        bytes memory serializedMessage = encodeActionPayload(Action.Mint, message);

        sequence = wormholeRelayer.sendPayloadToEvm{value: cost}(
            hubChainId(),
            hubContractAddress(),
            serializedMessage,
            secondaryCost,
            wormholeGasLimit(),
            chainId(),
            msg.sender
        );
    }

    /**
     * @notice Repays `amount_` of ZUSD to reduce the user's position.
     * @param amount_ The amount of ZUSD to repay.
     * @return sequence The sequence number of the repayment transaction.
     */
    function repay(uint256 amount_) public payable returns (uint256 sequence) {
        zUSD().burn(msg.sender, amount_);
        // cost = depositAmount + gas price for crosschain messaging
        (uint256 cost,) = quoteCrossChainPrice(hubChainId(), 0); // only calculate gas price
        require(msg.value >= cost, "Msg value must be greater than or equal gas used for cross-chain messaging");

        // send withdraw payload to target chain
        bytes memory message = abi.encodePacked(msg.sender, amount_);

        bytes memory serializedMessage = encodeActionPayload(Action.Repay, message);

        sequence = wormholeRelayer.sendPayloadToEvm{value: cost}(
            hubChainId(), hubContractAddress(), serializedMessage, 0, wormholeGasLimit(), chainId(), msg.sender
        );
        emit Repay(msg.sender, amount_);
    }

    function _handleWithdraw(uint16 targetChain_, address beneficiary_, uint256 amount_) internal {
        if (targetChain_ == getChainId()) {
            _withdrawOnSpoke(beneficiary_, amount_);
        }
    }

    function _crosschainWithdraw(
        uint16 targetChain_,
        address beneficiary_,
        uint256 amount_,
        uint256 receiverValueContinueCrossChainForHub
    ) internal returns (uint256 sequence) {
        // cost = depositAmount + gas price for crosschain messaging
        (uint256 cost, uint256 secondaryCost) =
            quoteCrossChainPrice(hubChainId(), receiverValueContinueCrossChainForHub); // only calculate gas price
        require(
            msg.value >= cost + secondaryCost,
            "Msg value must be greater than or equal gas used for cross-chain messaging"
        );

        // send withdraw payload to target chain
        bytes memory message = abi.encodePacked(targetChain_, msg.sender, amount_);

        bytes memory serializedMessage = encodeActionPayload(Action.Withdraw, message);

        sequence = wormholeRelayer.sendPayloadToEvm{value: cost}(
            hubChainId(),
            hubContractAddress(),
            serializedMessage,
            receiverValueContinueCrossChainForHub,
            wormholeGasLimit(),
            chainId(),
            msg.sender
        );
    }

    function _crosschainRedeem(
        uint16 targetChain_,
        address beneficiary_,
        address provider,
        uint256 zusdAmount,
        uint256 minReceiveCollateralAmount,
        uint256 receiverValueContinueCrossChainForHub
    ) internal returns (uint256 sequence) {
        // cost = depositAmount + gas price for crosschain messaging
        (uint256 cost,) = quoteCrossChainPrice(hubChainId(), receiverValueContinueCrossChainForHub); // only calculate gas price

        require(msg.value >= cost, "Msg value must be greater than or equal gas used for cross-chain messaging");

        sequence = wormholeRelayer.sendPayloadToEvm{value: cost}(
            hubChainId(),
            hubContractAddress(),
            encodeActionPayload(
                Action.Redeem,
                abi.encodePacked(targetChain_, beneficiary_, provider, zusdAmount, minReceiveCollateralAmount)
            ),
            receiverValueContinueCrossChainForHub,
            wormholeGasLimit(),
            chainId(),
            beneficiary_
        );
    }

    function _withdrawOnSpoke(address user_, uint256 withdrawal_) internal {
        payable(user_).transfer(withdrawal_);
        emit Withdraw(user_, withdrawal_);
    }

    function _mintZUSD(address user_, uint256 mintAmount_) internal {
        zUSD().mint(user_, mintAmount_);
        emit Mint(user_, mintAmount_);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/5.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
