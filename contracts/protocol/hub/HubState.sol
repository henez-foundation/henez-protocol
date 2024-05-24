// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../common/Structs.sol";

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "../../interfaces/IMockPyth.sol";
import "../../interfaces/IZUSD.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract HubStorage is Structs {
    struct Provider {
        uint16 chainId;
        IPyth pyth;
        MockPyth mockPyth;
    }

    struct State {
        Provider provider;
        // mock Pyth address
        address mockPythAddress;
        // oracle mode: 0 for Pyth, 1 for mock Pyth, 2 for fake oracle
        uint8 oracleMode;
        // list spoke contract
        mapping(uint16 => address) spokeContracts;
        // address => AssetInfo
        mapping(address => AssetInfo) assetInfos;
        // wormhole message hashes
        mapping(bytes32 => bool) consumedMessages;
        // mock gas price for testing
        uint64 mockTokenGasPrice;
        // storage gap
        uint256[50] ______gap;
        // MockOracle
        mapping(bytes32 => Price) oracle;
        address zUSD;
        uint256 badCollateralRatio;
        uint256 vaultKeeperRatio; // ratio for liquidation caller (keeper)
        uint256 totalDepositedAsset;
        ZUSDCCSupply zusdCCSupply;
        uint256 mintVaultMaxSupply;
        uint256 safeCollateralRatio;
        uint256 keeperRatio; // max is 5%
        uint256 wormholeGasLimit;
        uint256 redemptionFee;
        mapping(address => UserPosition) userPosition;
        address USDC;
    }
}

abstract contract HubState is OwnableUpgradeable, Structs {
    HubStorage.State _state;
    IWormholeRelayer public wormholeRelayer;
    IWormhole public wormhole;
    mapping(uint16 => bytes32) registeredSenders;

    modifier onlyWormholeRelayer() {
        require(msg.sender == address(wormholeRelayer), "Msg.sender is not Wormhole Relayer");
        _;
    }

    modifier isRegisteredSender(uint16 sourceChain, bytes32 sourceAddress) {
        require(registeredSenders[sourceChain] == sourceAddress, "Not registered sender");
        _;
    }

    /**
     * Sets the registered address for 'sourceChain' to 'sourceAddress'
     * So that for messages from 'sourceChain', only ones from 'sourceAddress' are valid
     *
     * Assumes only one sender per chain is valid
     * Sender is the address that called 'send' on the Wormhole Relayer contract on the source chain)
     */
    function setRegisteredSender(uint16 sourceChain, bytes32 sourceAddress) public onlyOwner {
        registeredSenders[sourceChain] = sourceAddress;
    }

    function setWormholeAddress(address _wormholeRelayer, address _wormhole) internal onlyOwner {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        wormhole = IWormhole(_wormhole);
    }

    // getters
    function getChainId() public view returns (uint16) {
        return _state.provider.chainId;
    }

    function getSpokeContract(uint16 chainId) internal view returns (address) {
        return _state.spokeContracts[chainId];
    }

    function mockPyth() internal view returns (IMockPyth) {
        return IMockPyth(_state.mockPythAddress);
    }

    function messageHashConsumed(bytes32 vmHash) internal view returns (bool) {
        return _state.consumedMessages[vmHash];
    }

    function getAssetInfo(address assetAddress) public view returns (AssetInfo memory) {
        return _state.assetInfos[assetAddress];
    }

    function getOracleMode() internal view returns (uint8) {
        return _state.oracleMode;
    }

    function getPythPriceStruct(bytes32 pythId) internal view returns (PythStructs.Price memory) {
        return _state.provider.pyth.getPriceUnsafe(pythId);
    }

    function getOraclePrice(bytes32 oracleId) internal view returns (Price memory price) {
        return _state.oracle[oracleId];
    }

    function getMockPythPriceStruct(bytes32 pythId) internal view returns (PythStructs.Price memory) {
        return _state.provider.mockPyth.getPrice(pythId);
    }

    function _getSafeCollateralRatio() internal view returns (uint256) {
        return _state.safeCollateralRatio;
    }

    function wormholeGasLimit() internal view returns (uint256) {
        return _state.wormholeGasLimit;
    }

    function safeCollateralRatio() internal view returns (uint256) {
        return _state.safeCollateralRatio;
    }

    function mintVaultMaxSupply() internal view returns (uint256) {
        return _state.mintVaultMaxSupply;
    }

    function _getUserPosition(address user_) internal view returns (UserPosition storage) {
        return _state.userPosition[user_];
    }

    function getUserPosition(address user_) public view returns (UserPosition memory) {
        return _state.userPosition[user_];
    }

    function zUSD() internal view returns (IZUSD) {
        return IZUSD(_state.zUSD);
    }

    function getTotalDepositedAsset() public view returns (uint256) {
        return _state.totalDepositedAsset;
    }

    function getRedemptionFee() public view returns (uint256) {
        return _state.redemptionFee;
    }

    function getOverallCollateralRatio(uint256 assetPrice) public view returns (uint256) {
        return (_state.totalDepositedAsset * assetPrice * 100) / getTotalCrossChainZUSDSupply();
    }

    function getTotalCrossChainZUSDSupply() public view returns (uint256) {
        return _state.zusdCCSupply.totalCrossChainSupply;
    }

    function getVaultKeeperRatio() internal view returns (uint256) {
        return _state.vaultKeeperRatio;
    }

    function getBadCollateralRatio() public view returns (uint256) {
        return _state.badCollateralRatio;
    }

    function _getUserCollateralRatio(address user_, uint256 assetPrice_) internal view returns (uint256) {
        return ((_getUserPosition(user_).depositedAmount * assetPrice_ * 100) / _getUserPosition(user_).borrowed);
    }

    function mockTokenGasPrice() public view returns (uint64) {
        return _state.mockTokenGasPrice;
    }

    // setters
    function setChainId(uint16 chainId) internal {
        _state.provider.chainId = chainId;
    }

    function setPyth(address pythAddress) public onlyOwner {
        _state.provider.pyth = IPyth(pythAddress);
    }

    function setOracleMode(uint8 oracleMode) public onlyOwner {
        _state.oracleMode = oracleMode;
    }

    function registerSpokeContract(uint16 chainId, address spokeContractAddress) public onlyOwner {
        _state.spokeContracts[chainId] = spokeContractAddress;
    }

    function registerAssetInfo(address assetAddress, AssetInfo memory info) public onlyOwner {
        _state.assetInfos[assetAddress] = info;
    }

    function consumeMessageHash(bytes32 vmHash) internal {
        _state.consumedMessages[vmHash] = true;
    }

    function setMockPyth(uint256 validTimePeriod, uint256 singleUpdateFeeInWei) internal {
        _state.provider.mockPyth = new MockPyth(validTimePeriod, singleUpdateFeeInWei);
    }

    function setOraclePrice(bytes32 oracleId, Price memory price) public onlyOwner {
        _state.oracle[oracleId] = price;
    }

    function setMockPythFeed(
        bytes32 id,
        int64 price,
        uint64 conf,
        int32 expo,
        int64 emaPrice,
        uint64 emaConf,
        uint64 publishTime
    ) public onlyOwner {
        bytes memory priceFeedData =
            _state.provider.mockPyth.createPriceFeedUpdateData(id, price, conf, expo, emaPrice, emaConf, publishTime);

        bytes[] memory updateData = new bytes[](1);
        updateData[0] = priceFeedData;
        _state.provider.mockPyth.updatePriceFeeds(updateData);
    }

    function setWormholeGasLimit(uint256 wormholeGasLimit_) public onlyOwner {
        _state.wormholeGasLimit = wormholeGasLimit_;
    }

    function setZUSD(address _zUSD) public onlyOwner {
        _state.zUSD = _zUSD;
    }

    function setSafeCollateralRatio(uint256 newRatio) public onlyOwner {
        _state.safeCollateralRatio = newRatio;
    }

    function setRedemptionFee(uint256 redemptionFee) public onlyOwner {
        _state.redemptionFee = redemptionFee;
    }

    function USDC() internal view returns (IZUSD) {
        return IZUSD(_state.USDC);
    }

    function setUSDC(address _USDC) public onlyOwner {
        _state.USDC = _USDC;
    }

    function setVaultKeeperRatio(uint256 vaultKeeperRatio) internal {
        _state.vaultKeeperRatio = vaultKeeperRatio;
    }

    function setBadCollateralRatio(uint256 badCollateralRatio) internal {
        _state.badCollateralRatio = badCollateralRatio;
    }

    function setGasTokenPrice(uint64 _mockTokenGasPrice) public onlyOwner {
        _state.mockTokenGasPrice = _mockTokenGasPrice;
    }
}
