// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Hub} from "../contracts/protocol/hub/Hub.sol";
import "../contracts/protocol/spoke/Spoke.sol";
import "wormhole-solidity-sdk/testing/WormholeRelayerTest.sol";
import "forge-std/console2.sol";
import {ZUSD} from "../contracts/protocol/stablecoin/ZUSD.sol";
import {ProxyAdmin} from "../contracts/proxy/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "../contracts/proxy/TransparentUpgradeableProxy.sol";

contract HenezProtocolTest is WormholeRelayerBasicTest {
    event GreetingReceived(string greeting, uint16 senderChain, address sender);

    Hub hub;
    Spoke spoke;
    uint8 oracleMode = 1; // for using real oracle
    address celoTestnetPythContractAddress = address(0x74f09cb3c7e2A01865f424FD14F6dc9A14E3e94E);
    bytes32 ethUSDPythId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    address assetAddress = address(1);
    ZUSD hubZUSD;
    ZUSD hubUSDC;
    ZUSD spokeZUSD;
    ZUSD spokeUSDC;
    uint256 spokeFork;
    uint256 hubFork;
    uint16 spokeChainId;
    uint16 hubChainId;

    address alice = 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f;
    address bob = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955;
    address charlie = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;

    // spoke is source
    // hub is target
    function setUpSource() public override {}
    function setUpTarget() public override {}

    function deployProxyAdmin() public returns (ProxyAdmin) {
        return new ProxyAdmin();
    }

    function deployTransparentUpgradeableProxy(address _logic, address _proxyAdmin, bytes memory _data)
        public
        returns (TransparentUpgradeableProxy)
    {
        return new TransparentUpgradeableProxy(_logic, _proxyAdmin, _data);
    }

    function setUpHenez() public {
        spokeFork = sourceFork;
        hubFork = targetFork;
        hubChainId = targetChainInfo.chainId;
        spokeChainId = sourceChainInfo.chainId;

        // set up hub on target chain
        vm.selectFork(hubFork);
        hubZUSD = new ZUSD();
        hubUSDC = new ZUSD();
        vm.startPrank(alice);
        // deploy hub proxy
        ProxyAdmin hubProxyAdmin = deployProxyAdmin();
        TransparentUpgradeableProxy hubTransparentProxy =
            deployTransparentUpgradeableProxy(address(new Hub()), address(hubProxyAdmin), "");
        hub = Hub(address(hubTransparentProxy));
        hub.initialize(
            address(hubZUSD),
            address(hubUSDC),
            address(relayerTarget),
            address(wormholeTarget),
            hubChainId,
            celoTestnetPythContractAddress,
            oracleMode,
            ethUSDPythId
        );
        vm.stopPrank();
        // set pyth price id
        hubZUSD.setMintvault(address(hub));
        hubUSDC.setMintvault(address(hub));

        // set up spoke on source chain
        vm.selectFork(spokeFork);
        spokeZUSD = new ZUSD();
        spokeUSDC = new ZUSD();
        vm.startPrank(alice);
        // deploy spoke proxy
        ProxyAdmin spokeProxyAdmin = deployProxyAdmin();
        TransparentUpgradeableProxy spokeTransparentProxy =
            deployTransparentUpgradeableProxy(address(new Spoke()), address(spokeProxyAdmin), "");
        spoke = Spoke(address(spokeTransparentProxy));
        spoke.initialize(
            address(relayerSource),
            address(wormholeSource),
            hubChainId,
            address(hub),
            address(spokeZUSD),
            address(spokeUSDC),
            spokeChainId
        );
        vm.stopPrank();
        spokeZUSD.setMintvault(address(spoke));
        spokeUSDC.setMintvault(address(spoke));

        // setRegisteredSender
        vm.selectFork(spokeFork);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        vm.prank(alice);
        spoke.setRegisteredSender(targetChain, toWormholeFormat(address(hub)));
        vm.selectFork(hubFork);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.startPrank(alice);
        hub.setGasTokenPrice(uint64(300000000000)); // 3000 usd
        hub.registerSpokeContract(spokeChainId, address(spoke));
        hub.setRegisteredSender(sourceChain, toWormholeFormat(address(spoke)));
        vm.stopPrank();
    }

    function test_DepositAssetToMint_OnHubToReceiveOnHub() public {
        setUpHenez();
        // / @dev test depositAssetToMint only on hub
        {
            vm.selectFork(hubFork);
            uint256 depositAmount = 10 ether;
            uint256 mintAmount = 10000 ether;
            vm.startPrank(alice);
            hub.depositAssetToMint{value: depositAmount}(hubChainId, depositAmount, mintAmount, address(alice));

            vm.stopPrank();
            assertEq(hubZUSD.balanceOf(address(alice)), mintAmount);
            assertEq(hub.getTotalDepositedAsset(), depositAmount);
            assertEq(hub.getUserPosition(address(alice)).depositedAmount, depositAmount);
        }
    }

    function test_DepositAssetToMint_OnHubToReceiveOnSpoke() public {
        setUpHenez();

        {
            vm.selectFork(hubFork);
            vm.recordLogs();
            uint16 targetChain = spokeChainId;
            uint256 depositAmount = 10 ether;
            uint256 mintAmount = 1000 * 1e18;
            uint256 cost = hub.quoteCrossChainPrice(targetChain, 0); // get cost on Front-end before calling depositAssetToMint
            hub.depositAssetToMint{value: cost + depositAmount}(targetChain, depositAmount, mintAmount, address(alice));
            performDelivery();
            assertEq(hub.getTotalDepositedAsset(), depositAmount);
            assertEq(hub.getUserPosition(address(alice)).depositedAmount, depositAmount);

            vm.selectFork(spokeFork);
            assertEq(spokeZUSD.balanceOf(address(alice)), mintAmount);
        }
    }

    function test_DepositAssetToMint_OnSpokeToReceiveOnHub() public {
        setUpHenez();

        /// @dev test depositAssetToMint from spoke -> hub
        {
            vm.selectFork(spokeFork);
            vm.recordLogs();
            uint256 depositAmount = 10 ether;
            uint256 mintAmount = 1000 * 1e18;
            (uint256 cost,) = spoke.quoteCrossChainPrice(hubChainId, depositAmount); // get cost on Front-end before calling depositAssetToMint
            spoke.depositAssetToMint{value: cost}(hubChainId, depositAmount, mintAmount, address(alice));
            performDelivery();
            vm.selectFork(hubFork);
            assertEq(hubZUSD.balanceOf(address(alice)), mintAmount);
            assertEq(hub.getTotalDepositedAsset(), depositAmount);
            assertEq(hub.getUserPosition(address(alice)).depositedAmount, depositAmount);
        }
    }

    function test_DepositAssetToMint_OnSpokeToReceiveOnSpoke() public {
        setUpHenez();

        /// @dev test depositAssetToMint from spoke -> spoke
        {
            vm.selectFork(spokeFork);
            vm.recordLogs();
            uint256 depositAmount = 10 ether;
            uint256 mintAmount = 1000 * 1e18;
            (uint256 cost, uint256 secondaryCost) = spoke.quoteCrossChainPrice(spokeChainId, depositAmount); // get cost on Front-end before calling depositAssetToMint
            spoke.depositAssetToMint{value: cost + secondaryCost}(
                spokeChainId, depositAmount, mintAmount, address(alice)
            );
            // from spoke to hub
            performDelivery();
            vm.selectFork(hubFork);
            assertEq(hub.getTotalDepositedAsset(), depositAmount);
            assertEq(hub.getUserPosition(address(alice)).depositedAmount, depositAmount);
            // from hub to spoke
            performDelivery();

            vm.selectFork(spokeFork);
            assertEq(spokeZUSD.balanceOf(address(alice)), mintAmount);
        }
    }

    function test_Withdraw_OnHubToReceiveOnHub() public {
        setUpHenez();
        _setup_DepositAssetToMint_OnHubToReceiveOnHub();
        /// @dev test Alice withdraw only on hub
        {
            vm.selectFork(hubFork);
            uint256 balanceBeforeWithdraw = alice.balance;
            uint256 withdrawAmount = hub.getMaxWithdrawableAmount(alice);
            vm.startPrank(alice);
            hub.withdraw(hubChainId, withdrawAmount);
            vm.stopPrank();
            uint256 balanceAfterWithdraw = alice.balance;
            assertEq(balanceAfterWithdraw - balanceBeforeWithdraw, ((withdrawAmount * 999) / 1000)); // due to user withdraws sooner than 3 days
        }
    }

    function test_Withdraw_OnHubToReceiveOnSpoke() public {
        setUpHenez();
        _setup_DepositAssetToMint_OnHubToReceiveOnHub();
        /// @dev test Alice withdraw on hub to receive on spoke
        {
            vm.selectFork(spokeFork);
            uint256 aliceBalanceBeforeWithdraw = alice.balance;

            vm.selectFork(hubFork);
            uint256 withdrawAmount = 1 ether;
            vm.recordLogs();
            uint256 cost = hub.quoteCrossChainPrice(spokeChainId, withdrawAmount); // get cost on Front-end before calling withdraw
            uint256 crossChainGas = cost - withdrawAmount;
            vm.startPrank(alice);
            hub.withdraw{value: crossChainGas}(spokeChainId, withdrawAmount);
            vm.stopPrank();
            performDelivery();

            vm.selectFork(spokeFork);
            uint256 aliceBalanceAfterWithdraw = alice.balance;

            assertEq(aliceBalanceAfterWithdraw - aliceBalanceBeforeWithdraw, ((withdrawAmount * 999) / 1000)); // due to user withdraws sooner than 3 days
        }
    }

    function test_Withdraw_OnSpokeToReceiveOnHub() public {
        setUpHenez();
        _setup_DepositAssetToMint_OnHubToReceiveOnHub();
        /// @dev test Alice withdraw on hub to receive on spoke
        {
            vm.selectFork(hubFork);
            uint256 aliceBalanceBeforeWithdraw = alice.balance;

            vm.selectFork(spokeFork);
            uint256 withdrawAmount = 1 ether;
            vm.recordLogs();
            (uint256 cost, uint256 secondaryCost) = spoke.quoteCrossChainPrice(hubChainId, 0); // get cost on Front-end before calling withdraw
            vm.startPrank(alice);
            spoke.withdraw{value: cost + secondaryCost}(hubChainId, withdrawAmount, 0);
            vm.stopPrank();
            performDelivery();

            vm.selectFork(hubFork);
            uint256 aliceBalanceAfterWithdraw = alice.balance;

            assertEq(aliceBalanceAfterWithdraw - aliceBalanceBeforeWithdraw, ((withdrawAmount * 999) / 1000)); // due to user withdraws sooner than 3 days
        }
    }

    function test_Withdraw_OnSpokeToReceiveOnSpoke() public {
        setUpHenez();
        _setup_DepositAssetToMint_OnHubToReceiveOnHub();
        /// @dev test Alice withdraw on spoke to receive on spoke
        {
            // user on spoke will receive withdrawAmount of ETH
            uint256 withdrawAmount = 1 ether;

            vm.selectFork(hubFork);
            uint256 receiverValueToCrossChainForHub = hub.quoteCrossChainPrice(spokeChainId, withdrawAmount);
            receiverValueToCrossChainForHub -= withdrawAmount; // since withdrawAmount derives from hub contract
            vm.selectFork(spokeFork);

            vm.recordLogs();
            (uint256 cost, uint256 secondaryCost) =
                spoke.quoteCrossChainPrice(hubChainId, receiverValueToCrossChainForHub); // get cost on Front-end before calling withdraw
            uint256 aliceBalanceBeforeWithdraw = alice.balance - cost - secondaryCost;
            vm.startPrank(alice);
            spoke.withdraw{value: cost + secondaryCost}(spokeChainId, withdrawAmount, receiverValueToCrossChainForHub);
            vm.stopPrank();
            performDelivery();

            vm.selectFork(hubFork);
            performDelivery();

            vm.selectFork(spokeFork);
            uint256 aliceBalanceAfterWithdraw = alice.balance;

            assertEq(aliceBalanceAfterWithdraw - aliceBalanceBeforeWithdraw, ((withdrawAmount * 999) / 1000)); // due to user withdraws sooner than 3 days
        }
    }

    function _setup_DepositAssetToMint_OnHubToReceiveOnHub() internal {
        vm.selectFork(spokeFork);
        vm.recordLogs();
        uint256 depositAmount = 10 ether;
        uint256 mintAmount = 1000 * 1e18;
        (uint256 cost,) = spoke.quoteCrossChainPrice(hubChainId, depositAmount); // get cost on Front-end before calling depositAssetToMint
        vm.startPrank(alice);
        spoke.depositAssetToMint{value: cost}(hubChainId, depositAmount, mintAmount, address(alice));
        vm.stopPrank();
        performDelivery();

        vm.selectFork(hubFork);
        assertEq(hub.getTotalDepositedAsset(), depositAmount);
    }

    function _setup_DepositAssetToMint_OnSpokeToReceiveOnSpoke() internal {
        vm.selectFork(spokeFork);
        vm.recordLogs();
        uint256 depositAmount = 10 ether;
        uint256 mintAmount = 1000 * 1e18;
        (uint256 cost, uint256 secondaryCost) = spoke.quoteCrossChainPrice(spokeChainId, depositAmount); // get cost on Front-end before calling depositAssetToMint
        vm.startPrank(alice);
        spoke.depositAssetToMint{value: cost + secondaryCost}(spokeChainId, depositAmount, mintAmount, address(alice));
        vm.stopPrank();
        performDelivery();

        vm.selectFork(hubFork);
        performDelivery();

        assertEq(hub.getUserPosition(address(alice)).borrowed, mintAmount);
        assertEq(hub.getTotalDepositedAsset(), depositAmount);
    }

    function test_Redeem_OnHubToReceiveOnHub() public {
        setUpHenez();
        _setup_DepositAssetToMint_OnHubToReceiveOnHub();
        /// @dev test Alice redeem only on hub
        {
            uint256 zusdAmountToRedeem = 400 * 1e18;
            address provider = address(alice);

            vm.selectFork(hubFork);
            // transfer zUSD to bob so that he can redeem
            vm.prank(alice);
            hubZUSD.transfer(address(bob), zusdAmountToRedeem);
            uint256 zusdBalanceBeforeRedeem = hubZUSD.balanceOf(address(bob));
            uint256 balanceBeforeRedeem = bob.balance;
            (uint256 expectedCollateralAmountToReceive,) =
                hub.getCollateralAmountToReceiveWhenRedeem(zusdAmountToRedeem, provider);
            vm.startPrank(bob);
            uint256 minReceiveCollateralAmount = 0;
            hub.redeem(hubChainId, address(bob), provider, zusdAmountToRedeem, minReceiveCollateralAmount);
            vm.stopPrank();
            uint256 zusdBalanceAfterRedeem = hubZUSD.balanceOf(address(bob));
            uint256 balanceAfterRedeem = bob.balance;
            assertEq(balanceAfterRedeem - balanceBeforeRedeem, expectedCollateralAmountToReceive); // due to user withdraws sooner than 3 days

            assertEq(zusdBalanceBeforeRedeem - zusdAmountToRedeem, zusdBalanceAfterRedeem);
        }
    }

    function test_Redeem_OnHubToReceiveOnSpoke() public {
        setUpHenez();
        _setup_DepositAssetToMint_OnHubToReceiveOnHub();
        /// @dev test Alice redeem only on hub
        {
            uint256 zusdAmountToRedeem = 400 * 1e18;
            address provider = address(alice);
            vm.selectFork(spokeFork);
            uint256 balanceBeforeRedeem = bob.balance;
            vm.selectFork(hubFork);
            // transfer zUSD to bob so that he can redeem
            vm.prank(alice);
            hubZUSD.transfer(address(bob), zusdAmountToRedeem);
            uint256 zusdBalanceBeforeRedeem = hubZUSD.balanceOf(address(bob));
            vm.startPrank(bob);
            uint256 minReceiveCollateralAmount = 0;
            (uint256 expectedCollateralAmountToReceive,) =
                hub.getCollateralAmountToReceiveWhenRedeem(zusdAmountToRedeem, provider);
            uint256 cost = hub.quoteCrossChainPrice(spokeChainId, expectedCollateralAmountToReceive); // get cost on Front-end before calling withdraw
            uint256 crossChainGas = cost - expectedCollateralAmountToReceive;
            hub.redeem{value: crossChainGas}(
                spokeChainId, address(bob), provider, zusdAmountToRedeem, minReceiveCollateralAmount
            );
            vm.stopPrank();
            performDelivery();
            uint256 zusdBalanceAfterRedeem = hubZUSD.balanceOf(address(bob));

            vm.selectFork(spokeFork);
            uint256 balanceAfterRedeem = bob.balance;

            assertEq(balanceAfterRedeem - balanceBeforeRedeem, expectedCollateralAmountToReceive); // due to user withdraws sooner than 3 days

            assertEq(zusdBalanceBeforeRedeem - zusdAmountToRedeem, zusdBalanceAfterRedeem);
        }
    }

    function test_Redeem_OnSpokeToReceiveOnSpoke() public {
        setUpHenez();
        _setup_DepositAssetToMint_OnSpokeToReceiveOnSpoke();
        /// @dev test Alice redeem on spoke to receive on spoke
        {
            uint256 zusdAmountToRedeem = 400 * 1e18;
            address provider = address(alice);

            vm.selectFork(hubFork);
            (uint256 expectedCollateralAmountToReceive,) =
                hub.getCollateralAmountToReceiveWhenRedeem(zusdAmountToRedeem, provider);

            uint256 receiverValueContinueCrossChainForHub =
                hub.quoteCrossChainPrice(spokeChainId, expectedCollateralAmountToReceive);
            receiverValueContinueCrossChainForHub =
                receiverValueContinueCrossChainForHub - expectedCollateralAmountToReceive;
            vm.selectFork(spokeFork);
            uint256 balanceBeforeRedeem = bob.balance;
            // transfer zUSD to bob so that he can redeem
            vm.prank(alice);
            spokeZUSD.transfer(address(bob), zusdAmountToRedeem);
            uint256 zusdBalanceBeforeRedeem = spokeZUSD.balanceOf(address(bob));
            vm.startPrank(bob);
            uint256 minReceiveCollateralAmount = 0;
            (uint256 cost,) = spoke.quoteCrossChainPrice(hubChainId, receiverValueContinueCrossChainForHub); // get cost on Front-end before calling withdraw
            uint256 crossChainGas = cost;
            spoke.redeem{value: crossChainGas}(
                spokeChainId,
                address(bob),
                provider,
                zusdAmountToRedeem,
                minReceiveCollateralAmount,
                receiverValueContinueCrossChainForHub
            );
            vm.stopPrank();
            performDelivery();
            vm.selectFork(hubFork);
            performDelivery();

            vm.selectFork(spokeFork);
            uint256 zusdBalanceAfterRedeem = spokeZUSD.balanceOf(address(bob));
            uint256 balanceAfterRedeem = bob.balance;

            assertEq(balanceAfterRedeem - (balanceBeforeRedeem - crossChainGas), expectedCollateralAmountToReceive);

            assertEq(zusdBalanceBeforeRedeem - zusdAmountToRedeem, zusdBalanceAfterRedeem);
        }
    }

    function test_Redeem_OnSpokeToReceiveOnHub() public {
        setUpHenez();
        _setup_DepositAssetToMint_OnSpokeToReceiveOnSpoke();
        /// @dev test Alice redeem on spoke to receive on spoke
        {
            uint256 zusdAmountToRedeem = 400 * 1e18;
            address provider = address(alice);

            vm.selectFork(hubFork);
            (uint256 expectedCollateralAmountToReceive,) =
                hub.getCollateralAmountToReceiveWhenRedeem(zusdAmountToRedeem, provider);
            uint256 balanceBeforeRedeem = bob.balance;

            vm.selectFork(spokeFork);
            // transfer zUSD to bob so that he can redeem
            vm.prank(alice);
            spokeZUSD.transfer(address(bob), zusdAmountToRedeem);
            uint256 zusdBalanceBeforeRedeem = spokeZUSD.balanceOf(address(bob));
            vm.startPrank(bob);
            uint256 minReceiveCollateralAmount = 0;
            (uint256 cost, uint256 secondaryCost) = spoke.quoteCrossChainPrice(hubChainId, 0); // get cost on Front-end before calling withdraw
            uint256 crossChainGas = cost + secondaryCost;
            spoke.redeem{value: crossChainGas}(
                hubChainId,
                address(bob),
                provider,
                zusdAmountToRedeem,
                minReceiveCollateralAmount,
                0 // since hub sends no cross-chain message
            );
            vm.stopPrank();
            performDelivery();
            uint256 zusdBalanceAfterRedeem = spokeZUSD.balanceOf(address(bob));

            vm.selectFork(hubFork);
            uint256 balanceAfterRedeem = bob.balance;

            assertEq(balanceAfterRedeem - balanceBeforeRedeem, expectedCollateralAmountToReceive);

            assertEq(zusdBalanceBeforeRedeem - zusdAmountToRedeem, zusdBalanceAfterRedeem);
        }
    }

    function _setup_DepositAssetToMint_OnHubToReceiveOnHub(address actor_) internal {
        {
            vm.selectFork(hubFork);
            uint256 depositAmount = 10 ether;
            uint256 mintAmount = 10000 * 1e18;
            vm.startPrank(actor_);
            hub.depositAssetToMint{value: depositAmount}(hubChainId, depositAmount, mintAmount, address(actor_));
            vm.stopPrank();
            assertEq(hubZUSD.balanceOf(address(actor_)), mintAmount);
            assertEq(hub.getUserPosition(address(actor_)).depositedAmount, depositAmount);
            assertEq(hub.getUserPosition(address(actor_)).borrowed, mintAmount);
        }
    }

    function test_SuperLiquidation_OnHubToReceiveOnHub() public {
        setUpHenez();
        _setup_DepositAssetToMint_OnHubToReceiveOnHub(alice);
        _setup_DepositAssetToMint_OnHubToReceiveOnHub(bob);

        {
            vm.selectFork(hubFork);
            // alice provides ZUSD to liquidate bobs collateral
            address provider = address(alice);
            address borrower = address(bob);

            // bob mint more ZUSD to increase collateral ratio
            uint256 bobMintMoreAmount = hub.getUserMaxMintableZUSD(bob) / 2;
            vm.prank(bob);
            hub.mint(bobMintMoreAmount, hubChainId);

            uint256 bobBorrowedBeforeLiquidate = hub.getUserPosition(bob).borrowed;
            uint256 bobDepositedAmountBeforeLiquidate = hub.getUserPosition(bob).depositedAmount;

            vm.startPrank(alice);
            // set lower gas token price
            hub.setGasTokenPrice(uint64(1000 * 1e8));
            uint256 providerETHBalanceBefore = provider.balance;
            uint256 amountCollateralToLiquidate = 5 ether;
            hub.superLiquidation(provider, borrower, amountCollateralToLiquidate, hubChainId);
            hub.setGasTokenPrice(uint64(3000 * 1e8));
            vm.stopPrank();

            uint256 providerETHBalanceAfter = provider.balance;

            // validate test
            assertEq(providerETHBalanceAfter - providerETHBalanceBefore, amountCollateralToLiquidate);
            assertEq(
                bobDepositedAmountBeforeLiquidate - amountCollateralToLiquidate,
                hub.getUserPosition(bob).depositedAmount
            );
        }
    }

    function test_SuperLiquidation_OnHubToReceiveOnSpoke() public {
        setUpHenez();
        _setup_DepositAssetToMint_OnHubToReceiveOnHub(alice);
        _setup_DepositAssetToMint_OnHubToReceiveOnHub(bob);

        {
            // alice provides ZUSD to liquidate bobs collateral
            address provider = address(alice);
            address borrower = address(bob);

            vm.selectFork(spokeFork);
            uint256 providerETHBalanceBefore = provider.balance;
            vm.recordLogs();
            vm.selectFork(hubFork);
            // bob mint more ZUSD to increase collateral ratio
            uint256 bobMintMoreAmount = hub.getUserMaxMintableZUSD(bob) / 2;
            vm.prank(bob);
            hub.mint(bobMintMoreAmount, hubChainId);

            uint256 bobBorrowedBeforeLiquidate = hub.getUserPosition(bob).borrowed;
            uint256 bobDepositedAmountBeforeLiquidate = hub.getUserPosition(bob).depositedAmount;

            vm.startPrank(alice);
            // set lower gas token price
            hub.setGasTokenPrice(uint64(1000 * 1e8));
            uint256 amountCollateralToLiquidate = 5 ether;
            // cost for sending ETH to provider on targetChain
            uint256 cost = hub.quoteCrossChainPrice(spokeChainId, amountCollateralToLiquidate);

            hub.superLiquidation{value: cost}(provider, borrower, amountCollateralToLiquidate, spokeChainId);
            performDelivery();
            hub.setGasTokenPrice(uint64(3000 * 1e8));
            vm.stopPrank();

            assertEq(
                bobDepositedAmountBeforeLiquidate - amountCollateralToLiquidate,
                hub.getUserPosition(bob).depositedAmount
            );
            vm.selectFork(spokeFork);
            uint256 providerETHBalanceAfter = provider.balance;

            // validate test
            assertEq(providerETHBalanceAfter - providerETHBalanceBefore, amountCollateralToLiquidate);
        }
    }

    function test_RepayOnHub() public {
        setUpHenez();
        _setup_DepositAssetToMint_OnHubToReceiveOnHub();
        {
            uint256 repayAmount = 400 * 1e18;
            uint256 expectedAmount = 600 * 1e18;
            vm.startPrank(alice);
            hub.repay(repayAmount);
            vm.stopPrank();
            assertEq(hubZUSD.balanceOf(address(alice)), expectedAmount);
            assertEq(hub.getUserPosition(address(alice)).borrowed, expectedAmount);
        }
    }

    function test_RepayOnSpoke() public {
        setUpHenez();
        _setup_DepositAssetToMint_OnSpokeToReceiveOnSpoke();
        {
            vm.selectFork(spokeFork);
            uint256 repayAmount = 400 * 1e18;
            (uint256 cost,) = spoke.quoteCrossChainPrice(hubChainId, 0);
            vm.startPrank(alice);
            spoke.repay{value: cost}(repayAmount);
            vm.stopPrank();
            performDelivery();

            uint256 expectedAmount = 600 * 1e18;
            assertEq(spokeZUSD.balanceOf(address(alice)), expectedAmount);
            vm.selectFork(hubFork);
            assertEq(hub.getUserPosition(address(alice)).borrowed, expectedAmount);
        }
    }
}
