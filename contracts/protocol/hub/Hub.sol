// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../common/Structs.sol";
import "../common/Messages.sol";
import "./HubUtilities.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract Hub is Structs, Messages, HubUtilities, IWormholeReceiver, PausableUpgradeable, ReentrancyGuardUpgradeable {
    event Deposit(address user, uint256 amount, uint16 sourceChainID);
    event Mint(address user, uint256 amount);
    event Withdraw(address user, uint256 amount);
    event Repay(address user, uint256 amount);
    event Redeem(address user, uint256 amount);

    /**
     * @notice Emitted when a liquidate transaction occurs.
     * @param keeper Address of the entity who calls the liquidate function.
     * @param provider Address of the entity who provides ZUSD.
     * @param borrower Address of the entity who borrows ZUSD.
     * @param zusdAmount Amount of ZUSD to repay (burn).
     * @param amountCollateralToLiquidate Amount of collateral provided.
     * @param reward2keeper Reward given to the keeper.
     * @param timestamp The time when the liquidation occurred.
     */
    event SuperLiquidation(
        address indexed keeper,
        address indexed provider,
        address indexed borrower,
        uint256 zusdAmount,
        uint256 amountCollateralToLiquidate,
        uint256 reward2keeper,
        uint256 timestamp
    );

    function initialize(
        address zusd_,
        address usdc_,
        address wormholeRelayer_,
        address wormhole_,
        uint16 hubChainId_,
        /* Pyth Information */
        address pythAddress,
        uint8 oracleMode,
        bytes32 pythId
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __Pausable_init();
        setWormholeAddress(wormholeRelayer_, wormhole_);
        setZUSD(zusd_);
        setUSDC(usdc_);
        setPyth(pythAddress);
        setOracleMode(oracleMode);
        registerAssetInfo(
            address(0),
            AssetInfo(
                pythId, // pyth id
                18, // decimals
                true // exists
            )
        ); // address 0 is for ETH

        setWormholeGasLimit(300_000);
        setChainId(hubChainId_);
        setSafeCollateralRatio(125 * 1e18); // can't mint more ZUSD if bellow 125%
        setBadCollateralRatio(200 * 1e18); // overallCollateralRatio < 200% is able to liquidate users position
        setRedemptionFee(100); // 100 is 1%
        setVaultKeeperRatio(1 ether); // 1e18 is 1%
    }

    /**
     * @notice This function is triggered by the Wormhole relayer when spoke contracts send cross-chain messages to the hub.
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
        require(!_state.consumedMessages[deliveryHash], "Already consumed");
        Action action = getDecodedActionInPayload(payload);
        if (action == Action.DepositAssetToMint) {
            (, uint16 targetChain_, uint256 depositAmount_, address mintToAddress_, uint256 mintAmount_) =
                decodeDepositAssetToMintActionPayload(payload);
            _handleDepositToMint(msg.value, sourceChain, targetChain_, depositAmount_, mintAmount_, mintToAddress_);
        } else if (action == Action.Mint) {
            (, uint16 targetChain_, address mintToAddress_, uint256 mintAmount_) = decodeMintActionPayload(payload);
            _handleMint(msg.value, targetChain_, mintAmount_, mintToAddress_);
        } else if (action == Action.Withdraw) {
            (, uint16 targetChain_, address beneficiary_, uint256 amount_) = decodeWithdrawActionPayload(payload);
            _handleWithdraw(targetChain_, beneficiary_, amount_);
        } else if (action == Action.Redeem) {
            (
                ,
                uint16 targetChain_,
                address beneficiary_,
                address provider,
                uint256 zusdAmount,
                uint256 minReceiveCollateralAmount
            ) = decodeRedeemActionPayload(payload);
            _handleRedeem(targetChain_, beneficiary_, provider, zusdAmount, minReceiveCollateralAmount);
        } else if (action == Action.Repay) {
            (, address user_, uint256 amount_) = decodeRepayActionPayload(payload);
            _handleRepay(user_, amount_);
        }

        consumeMessageHash(deliveryHash);
    }

    /**
     * @notice Registers a spoke contract for the `isRegisteredSender` modifier.
     * @param chainId The Wormhole chain ID of the spoke contract.
     * @param spokeContractAddress The address of the spoke contract to be registered.
     */
    function registerSpoke(uint16 chainId, address spokeContractAddress) public onlyOwner {
        registerSpokeContract(chainId, spokeContractAddress);
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
    ) public payable {
        _handleDepositToMint(msg.value, getChainId(), targetChain_, depositAmount_, mintAmount_, mintToAddress_);
    }

    /**
     * @notice Withdraws collateral.
     * @param targetChain_ The Wormhole chain ID where the collateral will be received.
     * @param amount_ The amount of collateral to withdraw.
     */
    function withdraw(uint16 targetChain_, uint256 amount_) public payable {
        _handleWithdraw(targetChain_, msg.sender, amount_);
    }

    /**
     * @notice Repays ZUSD to reduce the user's position.
     * @param amount_ The amount of ZUSD to repay.
     */
    function repay(uint256 amount_) public payable {
        require(zUSD().balanceOf(msg.sender) >= amount_, "Token balance must be greater");
        zUSD().burn(msg.sender, amount_);
        _handleRepay(msg.sender, amount_);
        emit Repay(msg.sender, amount_);
    }

    /**
     * @notice Mints ZUSD on a target chain.
     * @param targetChain_ The Wormhole chain ID where the ZUSD will be received.
     * @param mintAmount_ The amount of ZUSD to mint.
     */
    function mint(uint256 mintAmount_, uint16 targetChain_) public payable {
        _handleMint(msg.value, targetChain_, mintAmount_, msg.sender);
    }

    /**
     * @notice Redeems ZUSD to get a 1:1 value of collateral.
     * @param targetChain_ The chain on which the user wants to receive the collateral.
     * @param beneficiary_ The user (caller) who redeems and owns the ZUSD.
     * @param provider The user with the ZUSD borrowed position who provides the collateral.
     * @param zusdAmount The amount of ZUSD the caller wishes to redeem.
     * @param minReceiveCollateralAmount The minimum amount of collateral to receive.
     */
    function redeem(
        uint16 targetChain_,
        address beneficiary_,
        address provider,
        uint256 zusdAmount,
        uint256 minReceiveCollateralAmount
    ) public payable {
        require(zUSD().balanceOf(msg.sender) >= zusdAmount, "Token balance must be greater");
        zUSD().burn(msg.sender, zusdAmount);

        _handleRedeem(targetChain_, beneficiary_, provider, zusdAmount, minReceiveCollateralAmount);

        emit Redeem(msg.sender, zusdAmount);
    }

    /**
     * @notice When overallCollateralRatio is below badCollateralRatio, borrowers with collateralRatio below 125% could be fully liquidated.
     * Emits a `LiquidationRecord` event.
     *
     * Requirements:
     * - Current overallCollateralRatio should be below badCollateralRatio.
     * - `onBehalfOf` collateralRatio should be below 125%.
     * @dev After Liquidation, borrower's debt is reduced by collateralAmount * etherPrice, deposit is reduced by collateralAmount * borrower's collateralRatio.
     * Keeper gets a liquidation reward of `keeperRatio / borrower's collateralRatio`.
     * @param provider The address of the provider who provided collateral.
     * @param borrower The address of the borrower who borrowed ZUSD.
     * @param amountCollateralToLiquidate The amount of collateral to be liquidated.
     * @param targetChain The target chain where the liquidation occurs.
     */
    function superLiquidation(
        address provider,
        address borrower,
        uint256 amountCollateralToLiquidate,
        uint16 targetChain
    ) public payable {
        uint256 assetPrice = getGasTokenPrice();

        require(
            getOverallCollateralRatio(assetPrice) < getBadCollateralRatio(),
            "overallCollateralRatio should below badCollateralRatio(200%)"
        );

        UserPosition storage borrowerPosition = _getUserPosition(borrower);

        uint256 borrowerCollateralRatio = getUserCollateralRatio(borrower);
        require(
            borrowerCollateralRatio < 125 * 1e18, // require borrowerCollateralRatio < 125%
            "borrowers collateralRatio should below 125%"
        );

        require(
            amountCollateralToLiquidate <= borrowerPosition.depositedAmount,
            "total of collateral can be liquidated at most"
        );

        uint256 zusdAmount = (amountCollateralToLiquidate * assetPrice) / 1e18;
        if (borrowerCollateralRatio >= 1e20) {
            // if borrowerCollateralRatio > 100%
            zusdAmount = (zusdAmount * 1e20) / borrowerCollateralRatio;
        }
        require(
            zUSD().allowance(provider, address(this)) != 0 || msg.sender == provider,
            "Provider should authorize to provide liquidation zUSD"
        );

        // repay ZUSD and update user borrow state
        require(zUSD().balanceOf(provider) >= zusdAmount, "Token balance must be greater");
        zUSD().burn(provider, zusdAmount);
        _handleRepay(borrower, zusdAmount);

        // update collateral state
        _state.totalDepositedAsset -= amountCollateralToLiquidate;
        borrowerPosition.depositedAmount -= amountCollateralToLiquidate;

        // reward for caller a.k.a keeper
        uint256 reward2keeper;
        if (
            msg.sender != provider && borrowerCollateralRatio >= 1e20 + getVaultKeeperRatio() // if borrowerCollateralRatio > 100% then reward2keeper will occur
        ) {
            reward2keeper = (amountCollateralToLiquidate * getVaultKeeperRatio()) / borrowerCollateralRatio;
            payable(msg.sender).transfer(reward2keeper);
        }

        // send amountCollateralToLiquidate to ZUSD provider
        // if targetChain = hubChainId, no need to send cross-chain message, provider receives directly on hub
        if (targetChain == getChainId()) {
            _withdrawOnHub(provider, amountCollateralToLiquidate);
        } else {
            _crosschainWithdraw(targetChain, provider, amountCollateralToLiquidate);
        }

        emit SuperLiquidation(
            msg.sender, provider, borrower, zusdAmount, amountCollateralToLiquidate, reward2keeper, block.timestamp
        );
    }

    /**
     * @notice Allows the owner to withdraw `amount_` of `token_` in case of emergency.
     * @param amount_ The amount of tokens to withdraw.
     * @param user_ The address of the user to receive the withdrawn tokens.
     * @param token_ The address of the token to withdraw.
     */
    function emergencyWithdraw(uint256 amount_, address user_, address token_) public onlyOwner {
        if (token_ == address(0)) {
            payable(user_).transfer(amount_);
        } else {
            IERC20(token_).transfer(user_, amount_);
        }
    }

    function getCollateralAmountToReceiveWhenRedeem(uint256 zusdAmount, address provider)
    public
    view
    returns (uint256 collateralAmountToReceive, uint256 collateralAmount)
    {
        // take redemption fee, if getRedemptionFee() = 100 is 1%
        collateralAmount = (zusdAmount * 1e18 * (10_000 - getRedemptionFee())) / getGasTokenPrice() / 10_000;

        // check deposit time
        collateralAmountToReceive = _checkWithdraw(_getUserPosition(provider).depositedTime, collateralAmount);
    }

    function getGasTokenPrice() public view returns (uint256) {
        (uint64 priceValue, uint64 priceStandardDeviationsValue) = getOraclePrices(address(0));
        return uint256(priceValue) * 1e10; // to convert to 1e18
    }

    function getUserCollateralRatio(address user_) public view returns (uint256) {
        return _getUserCollateralRatio(user_, getGasTokenPrice());
    }

    function getUserMaxMintableZUSD(address user_) public view returns (uint256) {
        // (deposited * price * 100 / safeCollateralRatio) - borrowed
        return ((_getUserPosition(user_).depositedAmount * getGasTokenPrice() * 100) / safeCollateralRatio())
            - _getUserPosition(user_).borrowed;
    }

    function getSuperLiquidationPrice(address user_) public view returns (uint256) {
        // price = liquidateRatio /(deposited * 100 / borrowed)
        return (125 * 1e18 * _getUserPosition(user_).borrowed) / (_getUserPosition(user_).depositedAmount * 100);
    }

    function getMaxWithdrawableAmount(address user_) public view returns (uint256) {
        // deposited - (borrowed * safeCollateralRatio)/(price * 100) - 1
        // minus 1 to make sure collateralRatioOfUser is bigger than safeCollateralRatio after withdraw
        return _getUserPosition(user_).depositedAmount
        - (_getUserPosition(user_).borrowed * safeCollateralRatio()) / (getGasTokenPrice() * 100) - 1;
    }

    function getCRIfDepositAndMint(address user_, uint256 newDepositAmount_, uint256 newMintAmount_)
    public
    view
    returns (uint256)
    {
        return (
            ((_getUserPosition(user_).depositedAmount + newDepositAmount_) * getGasTokenPrice() * 100)
            / (_getUserPosition(user_).borrowed + newMintAmount_)
        );
    }

    function getCRIfWithdraw(address user_, uint256 newWithdrawAmount_) public view returns (uint256) {
        return (
            ((_getUserPosition(user_).depositedAmount - newWithdrawAmount_) * getGasTokenPrice() * 100)
            / (_getUserPosition(user_).borrowed)
        );
    }

    function getCRIfRepay(address user_, uint256 newRepayAmount_) public view returns (uint256) {
        return (
            ((_getUserPosition(user_).depositedAmount) * getGasTokenPrice() * 100)
            / (_getUserPosition(user_).borrowed - newRepayAmount_)
        );
    }

    function _handleRepay(address user_, uint256 amount_) internal {
        // update user state
        UserPosition storage userPosition_ = _state.userPosition[user_];
        userPosition_.borrowed -= amount_;
    }

    function _handleDepositToMint(
        uint256 value_,
        uint16 sourceChain_,
        uint16 targetChain_,
        uint256 depositAmount_,
        uint256 mintAmount_,
        address mintToAddress_
    ) internal {
        // store the message state
        _depositAsset(value_, mintToAddress_, depositAmount_, sourceChain_);
        if (mintAmount_ != 0) {
            _handleMint(value_, targetChain_, mintAmount_, mintToAddress_);
        }
    }

    function _handleMint(uint256 value_, uint16 targetChain_, uint256 mintAmount_, address mintToAddress_) internal {
        // update zusd supply state
        _state.zusdCCSupply.totalCrossChainSupply += mintAmount_;
        _state.zusdCCSupply.supplyByChainId[targetChain_] += mintAmount_;

        // if targetChain = hubChainId, no need to send cross-chain message
        if (targetChain_ == getChainId()) {
            // if mint on spoke, send to target chain, else mint on hub
            // if mintAmount_ == 0, just a normal deposit
            _mintZUSD(mintToAddress_, mintAmount_);
        } else {
            _crosschainMint(value_, mintToAddress_, mintAmount_, targetChain_);
        }
    }

    function _handleWithdraw(uint16 targetChain_, address beneficiary_, uint256 amount_) internal {
        require(amount_ != 0, "ZERO_WITHDRAW");
        UserPosition storage userPosition = _getUserPosition(beneficiary_);
        require(userPosition.depositedAmount >= amount_, "Withdraw amount exceeds deposited amount.");
        _state.totalDepositedAsset -= amount_;
        userPosition.depositedAmount -= amount_;

        uint256 withdrawal = _checkWithdraw(userPosition.depositedTime, amount_);
        if (userPosition.borrowed > 0) {
            _checkHealth(beneficiary_, getGasTokenPrice());
        }

        // if targetChain = hubChainId, no need to send cross-chain message, user withdraws directly on hub
        if (targetChain_ == getChainId()) {
            _withdrawOnHub(beneficiary_, withdrawal);
        } else {
            _crosschainWithdraw(targetChain_, beneficiary_, withdrawal);
        }
    }

    function _checkWithdraw(uint256 depositedTime_, uint256 amount_) public view returns (uint256 withdrawal) {
        withdrawal = block.timestamp - 3 days >= depositedTime_ ? amount_ : (amount_ * 999) / 1000; // if user withdraws sooner than 3 days, 0.1% of _amount will be deducted
    }

    function _withdrawOnHub(address user_, uint256 withdrawal_) internal {
        payable(user_).transfer(withdrawal_);
        emit Withdraw(user_, withdrawal_);
    }

    function _crosschainWithdraw(uint16 targetChain_, address beneficiary_, uint256 amount_)
        internal
        returns (uint256 sequence)
    {
        // cost = amount_ + gas for crosschain
        uint256 cost = quoteCrossChainPrice(targetChain_, amount_); // only calculate gas price
        require(
            msg.value + amount_ >= cost,
            "Msg value and withdraw amount must be greater than or equal gas used for cross-chain messaging"
        );

        // send withdraw payload to target chain
        bytes memory message = abi.encodePacked(targetChain_, beneficiary_, amount_);

        bytes memory serializedMessage = encodeActionPayload(Action.Withdraw, message);

        sequence = wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain_,
            getSpokeContract(targetChain_),
            serializedMessage,
            amount_,
            wormholeGasLimit(),
            getChainId(),
            beneficiary_
        );
    }

    function _crosschainMint(uint256 value_, address mintToAddress_, uint256 mintAmount_, uint16 targetChain_)
        internal
        returns (uint256 sequence)
    {
        // save state + check user position
        UserPosition storage userPosition_ = _state.userPosition[mintToAddress_];
        userPosition_.borrowed += mintAmount_;
        _checkHealth(mintToAddress_, getGasTokenPrice());

        // targetChain is spoke chain
        uint256 cost = quoteCrossChainPrice(targetChain_, 0); // only calculate gas price
        require(value_ >= cost, "Msg.value must greater than or equal gas used for cross-chain messaging");
        // send mint payload to target chain
        bytes memory message = abi.encodePacked(targetChain_, mintToAddress_, mintAmount_);
        bytes memory serializedMessage = encodeActionPayload(Action.Mint, message);
        sequence = wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain_, getSpokeContract(targetChain_), serializedMessage, 0, wormholeGasLimit()
        );
    }

    function _depositAsset(uint256 value_, address user_, uint256 depositAmount_, uint16 sourceChain_) internal {
        require(depositAmount_ != 0, "ZERO_DEPOSIT");
        require(value_ >= depositAmount_, "msg.value must be bigger or equal depositAmount");

        UserPosition storage userPosition_ = _getUserPosition(user_);
        _state.totalDepositedAsset += depositAmount_;
        userPosition_.depositedAmount += depositAmount_;
        userPosition_.depositedTime = block.timestamp;
        emit Deposit(user_, depositAmount_, sourceChain_);
    }

    function _mintZUSD(address user_, uint256 mintAmount_) internal {
        UserPosition storage userPosition_ = _state.userPosition[user_];
        userPosition_.borrowed += mintAmount_;
        _checkHealth(user_, getGasTokenPrice());
        zUSD().mint(user_, mintAmount_);
        emit Mint(user_, mintAmount_);
    }

    function _handleRedeem(
        uint16 targetChain_,
        address beneficiary_,
        address provider,
        uint256 zusdAmount,
        uint256 minReceiveCollateralAmount
    ) internal {
        require(provider != msg.sender, "Caller is provider");
        UserPosition storage providerPosition_ = _getUserPosition(provider);
        require(providerPosition_.borrowed >= zusdAmount, "zusdAmount cannot surpass providers debt");
        uint256 assetPrice = getGasTokenPrice();
        uint256 providerCollateralRatio =
            (providerPosition_.depositedAmount * assetPrice * 100) / providerPosition_.borrowed;
        require(providerCollateralRatio >= 100 * 1e18, "The provider's collateral ratio should be not less than 100%.");

        // caller repays zusd to decrement borrow amount of provider
        _handleRepay(provider, zusdAmount);

        (uint256 collateralAmountToReceive, uint256 collateralAmount) =
            getCollateralAmountToReceiveWhenRedeem(zusdAmount, provider);

        require(collateralAmountToReceive >= minReceiveCollateralAmount, "Amount to receive is too little");
        providerPosition_.depositedAmount -= collateralAmount;
        _state.totalDepositedAsset -= collateralAmount;

        if (providerPosition_.borrowed > 0) {
            _checkHealth(provider, getGasTokenPrice());
        }

        // if targetChain = hubChainId, no need to send cross-chain message, user withdraws directly on hub
        if (targetChain_ == getChainId()) {
            _withdrawOnHub(beneficiary_, collateralAmountToReceive);
        } else {
            _crosschainWithdraw(targetChain_, beneficiary_, collateralAmountToReceive);
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/5.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
