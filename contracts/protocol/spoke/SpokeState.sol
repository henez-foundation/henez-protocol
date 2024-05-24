// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../common/Structs.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "../../interfaces/IZUSD.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SpokeStorage is Structs {
    struct Provider {
        uint16 chainId;
        address wormholeRelayer;
    }

    struct State {
        Provider provider;
        // number of confirmations for wormhole messages
        uint8 consistencyLevel;
        // Wormhole chain id
        uint16 hubChainId;
        address hubContractAddress;
        address zUSD;
        uint256 badCollateralRatio;
        uint256 totalDepositedAsset;
        uint256 poolTotalCirculation;
        uint256 mintVaultMaxSupply;
        uint256 safeCollateralRatio;
        uint256 keeperRatio; // max is 5%
        uint256 wormholeGasLimit;
        // wormhole message hashes
        mapping(bytes32 => bool) consumedMessages;
        // @dev storage gap
        uint256[50] ______gap;
        address USDC;
    }
}

abstract contract SpokeState is OwnableUpgradeable, Structs {
    SpokeStorage.State _state;
    IWormholeRelayer public wormholeRelayer;
    IWormhole public wormhole;
    mapping(uint16 => bytes32) registeredSenders;

    modifier onlyWormholeRelayer() {
        require(
            msg.sender == address(wormholeRelayer),
            "Msg.sender is not Wormhole Relayer"
        );
        _;
    }

    modifier isRegisteredSender(uint16 sourceChain, bytes32 sourceAddress) {
        require(
            registeredSenders[sourceChain] == sourceAddress,
            "Not registered sender"
        );
        _;
    }

    /**
     * Sets the registered address for 'sourceChain' to 'sourceAddress'
     * So that for messages from 'sourceChain', only ones from 'sourceAddress' are valid
     *
     * Assumes only one sender per chain is valid
     * Sender is the address that called 'send' on the Wormhole Relayer contract on the source chain)
     */
    function setRegisteredSender(
        uint16 sourceChain,
        bytes32 sourceAddress
    ) public onlyOwner {
        registeredSenders[sourceChain] = sourceAddress;
    }

    function setWormholeAddress(address _wormholeRelayer, address _wormhole) internal onlyOwner{
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        wormhole = IWormhole(_wormhole);
    }

    // getters
    function getChainId() public view returns (uint16) {
        return _state.provider.chainId;
    }

    function chainId() public view returns (uint16) {
        return _state.provider.chainId;
    }

    function wormholeRelayerAddress() public view returns (address) {
        return _state.provider.wormholeRelayer;
    }

    function consistencyLevel() internal view returns (uint8) {
        return _state.consistencyLevel;
    }

    function hubChainId() internal view returns (uint16) {
        return _state.hubChainId;
    }

    function hubContractAddress() internal view returns (address) {
        return _state.hubContractAddress;
    }

    function wormholeGasLimit() internal view returns (uint256) {
        return _state.wormholeGasLimit;
    }

    function safeCollateralRatio() internal view returns (uint256) {
        return _state.safeCollateralRatio;
    }

    function poolTotalCirculation() internal view returns (uint256) {
        return _state.poolTotalCirculation;
    }

    function mintVaultMaxSupply() internal view returns (uint256) {
        return _state.mintVaultMaxSupply;
    }

    function zUSD() internal view returns (IZUSD) {
        return IZUSD(_state.zUSD);
    }

    // setters

    function setChainId(uint16 chainId_) internal {
        _state.provider.chainId = chainId_;
    }

    function setWormholeRelayer(address wormholeRelayerAddress_) internal {
        _state.provider.wormholeRelayer = wormholeRelayerAddress_;
    }

    function setHubChainId(uint16 hubChainId_) internal {
        _state.hubChainId = hubChainId_;
    }

    function setHubContractAddress(address hubContractAddress_) internal {
        _state.hubContractAddress = hubContractAddress_;
    }

    function messageHashConsumed(bytes32 vmHash) internal view returns (bool) {
        return _state.consumedMessages[vmHash];
    }

    function consumeMessageHash(bytes32 vmHash) internal {
        _state.consumedMessages[vmHash] = true;
    }

    function setWormholeGasLimit(uint256 wormholeGasLimit_) public onlyOwner {
        _state.wormholeGasLimit = wormholeGasLimit_;
    }

    function setZUSD(address _zUSD) internal {
        _state.zUSD = _zUSD;
    }

    function USDC() internal view returns (IZUSD) {
        return IZUSD(_state.USDC);
    }

    function setUSDC(address _USDC) public onlyOwner {
        _state.USDC = _USDC;
    }
}
