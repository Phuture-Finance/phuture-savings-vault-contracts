// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import {
    MarketParameters,
    AssetRateAdapter,
    NotionalGovernance,
    NotionalViews
} from "../src/external/notional/interfaces/INotional.sol";
import {IWrappedfCashComplete, IWrappedfCash} from "../src/external/notional/interfaces/IWrappedfCash.sol";
import "../src/external/notional/wfCashERC4626.sol";
import "../src/external/notional/proxy/WrappedfCashFactory.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "../src/SavingsVault.sol";

contract WrappedfCashTest is Test {
    using stdStorage for StdStorage;

    address notionalRouter = address(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    address usdcWhale = address(0x0A59649758aa4d66E25f08Dd01271e891fe52199);
    ERC20Upgradeable usdc = ERC20Upgradeable(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));

    uint16 currencyId = 3;

    address wrappedfCashFactory = address(0x5D051DeB5db151C2172dCdCCD42e6A2953E27261);

    string mainnetHttpsUrl;
    uint mainnetFork;

    function testfCashWithdrawal() public {
        vm.startPrank(usdcWhale);
        mainnetHttpsUrl = vm.envString("MAINNET_HTTPS_URL");
        mainnetFork = vm.createSelectFork(mainnetHttpsUrl, 15_364_981);
        MarketParameters[] memory marketParameters = NotionalViews(notionalRouter).getActiveMarkets(currencyId);
        uint maturity = marketParameters[0].maturity;
        console.log("oracleRate is: ", marketParameters[0].oracleRate);
        console.log("spot rate is: ", marketParameters[0].lastImpliedRate);
        IWrappedfCashComplete fCash =
            IWrappedfCashComplete(IWrappedfCashFactory(wrappedfCashFactory).deployWrapper(currencyId, uint40(maturity)));
        usdc.approve(address(fCash), type(uint).max);

        uint assetsToDeposit = 100_000 * 1e6;
        fCash.deposit(assetsToDeposit, usdcWhale);
        uint usdcBalanceBefore = usdc.balanceOf(usdcWhale);

        uint withdrawAmount = 90_000 * 1e6;
        uint shares = fCash.previewWithdraw(withdrawAmount);
        // I have tried using both redeem and redeemToUnderlying and they return the same result
        //        fCash.redeem(shares, usdcWhale, usdcWhale);
        fCash.redeemToUnderlying(shares, usdcWhale, type(uint32).max);
        uint usdcBalanceAfter = usdc.balanceOf(usdcWhale);
        uint netUsdcBalance = usdcBalanceAfter - usdcBalanceBefore;
        console.log("amount underestimated is: ", withdrawAmount - netUsdcBalance); // This should return 37
        console.log("amount requested is: ", withdrawAmount);
        console.log("amount actually recieved is: ", netUsdcBalance);
        vm.stopPrank();
    }

    function testPriceImpact() public {
        vm.startPrank(usdcWhale);
        mainnetHttpsUrl = vm.envString("MAINNET_HTTPS_URL");
        mainnetFork = vm.createSelectFork(mainnetHttpsUrl, 15_596_609);
        MarketParameters[] memory marketParameters = NotionalViews(notionalRouter).getActiveMarkets(currencyId);
        uint maturity = marketParameters[1].maturity;
        console.log("oracleRate is: ", marketParameters[1].oracleRate);
        console.log("spot rate is: ", marketParameters[1].lastImpliedRate);
        console.log("maturity is: ", marketParameters[1].maturity);
        IWrappedfCashComplete fCash =
            IWrappedfCashComplete(IWrappedfCashFactory(wrappedfCashFactory).deployWrapper(currencyId, uint40(maturity)));
        usdc.approve(address(fCash), type(uint).max);

        uint assetsToDeposit = 264076127011;
        uint maxLoss = 9799; // fails with 9800
        uint minImpliedRate = (marketParameters[1].oracleRate * maxLoss) / 10_000;
        uint fCashAmount = fCash.previewDeposit(assetsToDeposit);
        fCash.mintViaUnderlying(assetsToDeposit, uint88(fCashAmount), usdcWhale, uint32(minImpliedRate));

        vm.stopPrank();
    }

    function testDifferentMaturities() public {
        mainnetHttpsUrl = vm.envString("MAINNET_HTTPS_URL");
        mainnetFork = vm.createSelectFork(mainnetHttpsUrl, 15883016);
        MarketParameters[] memory marketParameters = NotionalViews(notionalRouter).getActiveMarkets(currencyId);
        uint threeMonthMaturity = marketParameters[0].maturity;
        uint sixMonthMaturity = marketParameters[1].maturity;
        uint oneYearMaturity = marketParameters[2].maturity;
        IWrappedfCashComplete threeMonthfCash = IWrappedfCashComplete(
            IWrappedfCashFactory(wrappedfCashFactory).deployWrapper(currencyId, uint40(threeMonthMaturity))
        );
        IWrappedfCashComplete sixMonthfCash = IWrappedfCashComplete(
            IWrappedfCashFactory(wrappedfCashFactory).deployWrapper(currencyId, uint40(sixMonthMaturity))
        );
        IWrappedfCashComplete oneYearfCash = IWrappedfCashComplete(
            IWrappedfCashFactory(wrappedfCashFactory).deployWrapper(currencyId, uint40(oneYearMaturity))
        );

        vm.startPrank(usdcWhale);
        usdc.approve(address(threeMonthfCash), type(uint).max);
        usdc.approve(address(sixMonthfCash), type(uint).max);
        usdc.approve(address(oneYearfCash), type(uint).max);

        uint usdcBalanceBefore = usdc.balanceOf(usdcWhale);

        uint assets = 10_000 * 1e6;
        threeMonthfCash.deposit(assets, usdcWhale);
        sixMonthfCash.deposit(assets, usdcWhale);
        oneYearfCash.deposit(assets, usdcWhale);

        uint threeMonthfCashBalance = threeMonthfCash.balanceOf(usdcWhale);
        uint sixMonthfCashBalance = sixMonthfCash.balanceOf(usdcWhale);
        uint oneYearfCashBalance = oneYearfCash.balanceOf(usdcWhale);

        console.log("threeMonthfCashBalance is: ", threeMonthfCashBalance); // 10_032 fCash
        console.log("sixMonthfCashBalance is: ", sixMonthfCashBalance); // 10_110 fCash
        console.log("oneYearfCashBalance is: ", oneYearfCashBalance); // 10_337 fCash

        vm.warp(block.timestamp + 1 days);

        threeMonthfCash.redeemToUnderlying(threeMonthfCashBalance, usdcWhale, type(uint32).max);
        uint threeMonthRedeemBalanceDiff = usdcBalanceBefore - 2 * assets - usdc.balanceOf(usdcWhale);
        uint threeMonthLoss = 7_814_382;
        assertEq(threeMonthRedeemBalanceDiff, threeMonthLoss); // Lost $7

        sixMonthfCash.redeemToUnderlying(sixMonthfCashBalance, usdcWhale, type(uint32).max);
        uint sixMonthRedeemBalanceDiff = usdcBalanceBefore - assets - usdc.balanceOf(usdcWhale) - threeMonthLoss;
        uint sixMonthLoss = 22_721_780;
        assertEq(sixMonthRedeemBalanceDiff, sixMonthLoss); // Lost $22

        oneYearfCash.redeemToUnderlying(oneYearfCashBalance, usdcWhale, type(uint32).max);
        uint oneYearRedeemBalanceDiff = usdcBalanceBefore - usdc.balanceOf(usdcWhale) - threeMonthLoss - sixMonthLoss;
        uint oneYearLoss = 52_966_032;
        assertEq(oneYearRedeemBalanceDiff, oneYearLoss); // Lost $52

        assertEq(usdcBalanceBefore - usdc.balanceOf(usdcWhale), threeMonthLoss + sixMonthLoss + oneYearLoss); // Altogether lost $82
        vm.stopPrank();
    }
}
