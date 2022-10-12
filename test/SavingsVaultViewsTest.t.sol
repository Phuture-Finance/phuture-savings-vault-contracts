// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import { MarketParameters, AssetRateAdapter, NotionalGovernance } from "../src/external/notional/interfaces/INotional.sol";
import { IWrappedfCashComplete, IWrappedfCash } from "../src/external/notional/interfaces/IWrappedfCash.sol";
import "../src/external/notional/interfaces/NotionalProxy.sol";
import "../src/external/notional/proxy/nUpgradeableBeacon.sol";
import "../src/external/notional/wfCashERC4626.sol";
import "../src/external/interfaces/IWETH9.sol";
import "../src/external/notional/proxy/WrappedfCashFactory.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "./mocks/MockSavingsVault.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/interfaces/ISavingsVault.sol";
import "../src/SavingsVaultViews.sol";
import "../src/interfaces/ISavingsVault.sol";

contract SavingsVaultViewsTest is Test {
    using stdStorage for StdStorage;
    using Address for address;

    string name = "USDC Notional Vault";
    string symbol = "USDC_VAULT";
    uint16 currencyId = 3;

    address notionalRouter = address(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    address usdcWhale = address(0x0A59649758aa4d66E25f08Dd01271e891fe52199);
    ERC20Upgradeable usdc = ERC20Upgradeable(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));

    MockSavingsVault SavingsVaultImpl;
    MockSavingsVault SavingsVaultProxy;
    SavingsVaultViews views;
    address wrappedfCashFactory;
    address feeRecipient;

    string mainnetHttpsUrl;
    uint mainnetFork;
    uint blockNumber;

    function setUp() public {
        mainnetHttpsUrl = vm.envString("MAINNET_HTTPS_URL");
        blockNumber = 14_914_920;
        mainnetFork = vm.createSelectFork(mainnetHttpsUrl, blockNumber);

        upgradeNotionalProxy();
        wrappedfCashFactory = address(deployfCashFactory());
        feeRecipient = address(0xABCD);
        SavingsVaultImpl = new MockSavingsVault();
        SavingsVaultProxy = MockSavingsVault(
            address(
                new ERC1967Proxy(
                    address(SavingsVaultImpl),
                    abi.encodeWithSelector(
                        SavingsVaultImpl.initialize.selector,
                        name,
                        symbol,
                        address(usdc),
                        currencyId,
                        wrappedfCashFactory,
                        notionalRouter,
                        0,
                        feeRecipient
                    )
                )
            )
        );
        // Default msg.sender inside all functions is: 0x00a329c0648769a73afac7f9381e08fb43dbea72,
        // msg.sender inside setUp is 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
        SavingsVaultProxy.grantRole(keccak256("VAULT_MANAGER_ROLE"), msg.sender);
        SavingsVaultProxy.grantRole(keccak256("HARVESTER_ROLE"), msg.sender);
        SavingsVaultProxy.grantRole(keccak256("HARVESTER_ROLE"), usdcWhale);
        SavingsVaultProxy.grantRole(keccak256("VAULT_MANAGER_ROLE"), usdcWhale);
        views = new SavingsVaultViews();

        vm.startPrank(usdcWhale);
        usdc.approve(address(SavingsVaultProxy), type(uint).max);
    }

    function testAPY() public {
        SavingsVaultProxy.deposit(100 * 1e6, usdcWhale);
        assertEq(views.getAPY(SavingsVaultProxy), 0);

        SavingsVaultProxy.harvest(type(uint).max);

        // apy after investing into first maturity
        assertEq(views.getAPY(SavingsVaultProxy), 42173528);
        vm.warp(block.timestamp + 1 days + 1);

        SavingsVaultProxy.deposit(500 * 1e6, usdcWhale);
        ISavingsVault.NotionalMarket[] memory markets = SavingsVaultProxy.__getThreeAndSixMonthMarkets();
        MarketParameters[] memory mockedMarkets = new MarketParameters[](2);
        mockedMarkets[0] = getNotionalMarketParameters(markets[0].maturity, markets[1].oracleRate);
        mockedMarkets[1] = getNotionalMarketParameters(markets[1].maturity, markets[0].oracleRate);
        vm.mockCall(
            notionalRouter,
            abi.encodeWithSelector(NotionalViews.getActiveMarkets.selector, currencyId),
            abi.encode(mockedMarkets)
        );
        SavingsVaultProxy.harvest(type(uint).max);

        // apy after investing into second maturity
        assertEq(views.getAPY(SavingsVaultProxy), 37265026);

        // set time to 1 day before maturity
        vm.warp(markets[0].maturity - 86400);
        assertEq(views.getAPY(SavingsVaultProxy), 37264168);

        // set time to 1 day after maturity
        vm.warp(markets[0].maturity + 3600);
        NotionalProxy(notionalRouter).initializeMarkets(currencyId, false);
        SavingsVaultProxy.deposit(1 * 1e6, usdcWhale);

        assertEq(views.getAPY(SavingsVaultProxy), 42173271);
    }

    function testAPYCloseToMaturity() public {
        vm.stopPrank();
        vm.createSelectFork(mainnetHttpsUrl, 15605130);
        address scCorporate = address(0x56EbC6ed25ba2614A3eAAFFEfC5677efAc36F95f);
        SavingsVaultViews svViews = new SavingsVaultViews();

        vm.startPrank(scCorporate);
        SavingsVault savingsVault = SavingsVault(address(0x6bAD6A9BcFdA3fd60Da6834aCe5F93B8cFed9598));
        savingsVault.grantRole(keccak256("VAULT_MANAGER_ROLE"), scCorporate);

        savingsVault.upgradeTo(address(new SavingsVault()));
        vm.stopPrank();

        vm.startPrank(usdcWhale);
        usdc.approve(address(savingsVault), type(uint).max);

        address[2] memory markets = savingsVault.getfCashPositions();
        MarketParameters[] memory mockedMarkets = new MarketParameters[](2);
        mockedMarkets[0] = getNotionalMarketParameters(IWrappedfCashComplete(markets[0]).getMaturity(), 100);
        mockedMarkets[1] = getNotionalMarketParameters(IWrappedfCashComplete(markets[1]).getMaturity(), 10);
        vm.mockCall(
            notionalRouter,
            abi.encodeWithSelector(NotionalViews.getActiveMarkets.selector, currencyId),
            abi.encode(mockedMarkets)
        );
        savingsVault.deposit(1_000 * 1e6, usdcWhale);
        savingsVault.harvest(type(uint).max);
        vm.clearMockedCalls();

        uint snapshot = vm.snapshot();

        assertEq(svViews.getAPY(savingsVault), 3626544);

        savingsVault.deposit(1_000 * 1e6, usdcWhale);
        savingsVault.harvest(type(uint).max);
        assertEq(usdc.balanceOf(address(savingsVault)), 0);
        assertEq(svViews.getAPY(savingsVault), 21017104);

        vm.revertTo(snapshot);
        vm.warp(IWrappedfCashComplete(markets[0]).getMaturity() + 3600);
        NotionalProxy(notionalRouter).initializeMarkets(currencyId, false);
        savingsVault.deposit(1 * 1e6, usdcWhale);
        // This is the rate from the highest yield market, we assume all matured fCash has been pushed there
        assertEq(svViews.getAPY(savingsVault), 39181835);

        vm.stopPrank();
    }

    function testMainnetDeploymentAPYCloseToMaturity() public {
        vm.stopPrank();
        vm.createSelectFork(mainnetHttpsUrl, 15732423);
        SavingsVaultViews svViews = SavingsVaultViews(0xA04dF6ec0138B9366C28d018D16aCffd76531855);

        SavingsVault savingsVault = SavingsVault(address(0x6bAD6A9BcFdA3fd60Da6834aCe5F93B8cFed9598));

        vm.startPrank(usdcWhale);
        usdc.approve(address(savingsVault), type(uint).max);

        address[2] memory markets = savingsVault.getfCashPositions();
        MarketParameters[] memory mockedMarkets = new MarketParameters[](2);
        mockedMarkets[0] = getNotionalMarketParameters(IWrappedfCashComplete(markets[0]).getMaturity(), 100);
        mockedMarkets[1] = getNotionalMarketParameters(IWrappedfCashComplete(markets[1]).getMaturity(), 10);
        vm.mockCall(
            notionalRouter,
            abi.encodeWithSelector(NotionalViews.getActiveMarkets.selector, currencyId),
            abi.encode(mockedMarkets)
        );
        savingsVault.deposit(1_000 * 1e6, usdcWhale);
        savingsVault.harvest(type(uint).max);
        vm.clearMockedCalls();

        vm.warp(IWrappedfCashComplete(markets[0]).getMaturity() + 3600);
        NotionalProxy(notionalRouter).initializeMarkets(currencyId, false);
        savingsVault.deposit(1 * 1e6, usdcWhale);
        address[2] memory maturedMarkets = savingsVault.getfCashPositions();
        assertFalse(IWrappedfCashComplete(maturedMarkets[0]).hasMatured());
        assertTrue(IWrappedfCashComplete(maturedMarkets[1]).hasMatured());
        assertEq(IWrappedfCashComplete(maturedMarkets[0]).balanceOf(address(savingsVault)), 1562355611766);
        assertEq(IWrappedfCashComplete(maturedMarkets[1]).balanceOf(address(savingsVault)), 100833088384);
        (ISavingsVault.NotionalMarket memory lowestYieldMarket, ISavingsVault.NotionalMarket memory highestYieldMarket) = savingsVault.sortMarketsByOracleRate();
        console.log("lowestYieldMarket", lowestYieldMarket.oracleRate, lowestYieldMarket.maturity);
        console.log("highestYieldMarket", highestYieldMarket.oracleRate, highestYieldMarket.maturity);
        assertEq(svViews.getAPY(savingsVault), 30956605);

        vm.stopPrank();
    }

    function testMaxDepositedAmount() public {
        uint amount = 100 * 1e6;
        SavingsVaultProxy.deposit(amount, usdcWhale);

        assertEq(views.getMaxDepositedAmount(address(SavingsVaultProxy)), amount);
        SavingsVaultProxy.harvest(type(uint).max);
        assertEq(views.getMaxDepositedAmount(address(SavingsVaultProxy)), 0);
    }

    // Internal helper functions for setting-up the system

    function getNotionalMarketParameters(uint maturity, uint oracleRate)
        internal
        pure
        returns (MarketParameters memory marketParameters)
    {
        marketParameters = MarketParameters({
            storageSlot: "storageSlot",
            maturity: maturity,
            totalfCash: 0,
            totalAssetCash: 0,
            totalLiquidity: 0,
            lastImpliedRate: oracleRate,
            oracleRate: oracleRate,
            previousTradeTime: 1
        });
    }

    function upgradeNotionalProxy() internal {
        address ownerAddress = nUpgradeableBeacon(notionalRouter).owner();
        vm.startPrank(ownerAddress);
        nUpgradeableBeacon(notionalRouter).upgradeTo(address(0x16eD130F7A6dcAc7e3B0617A7bafa4b470189962));
        NotionalGovernance(notionalRouter).updateAssetRate(
            1,
            AssetRateAdapter(0x8E3D447eBE244db6D28E2303bCa86Ef3033CFAd6)
        );
        NotionalGovernance(notionalRouter).updateAssetRate(
            2,
            AssetRateAdapter(0x719993E82974f5b5eA0c5ebA25c260CD5AF78E00)
        );
        NotionalGovernance(notionalRouter).updateAssetRate(
            3,
            AssetRateAdapter(0x612741825ACedC6F88D8709319fe65bCB015C693)
        );
        NotionalGovernance(notionalRouter).updateAssetRate(
            4,
            AssetRateAdapter(0x39D9590721331B13C8e9A42941a2B961B513E69d)
        );
        vm.stopPrank();
    }

    function deployfCashFactory() internal returns (WrappedfCashFactory factory) {
        wfCashERC4626 wfCashImpl = new wfCashERC4626(
            INotionalV2(notionalRouter),
            IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
        );
        nUpgradeableBeacon beacon = new nUpgradeableBeacon(address(wfCashImpl));
        return new WrappedfCashFactory(address(beacon));
    }
}
