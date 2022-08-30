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
import "./mocks/MockFrpVault.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/interfaces/IFRPVault.sol";
import "../src/FRPViews.sol";

contract FrpViewesTest is Test {
    using stdStorage for StdStorage;
    using Address for address;

    string name = "USDC Notional Vault";
    string symbol = "USDC_VAULT";
    uint16 currencyId = 3;

    address notionalRouter = address(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    address usdcWhale = address(0x0A59649758aa4d66E25f08Dd01271e891fe52199);
    ERC20Upgradeable usdc = ERC20Upgradeable(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));

    MockFrpVault FRPVaultImpl;
    MockFrpVault FRPVaultProxy;
    FRPViews views;
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
        FRPVaultImpl = new MockFrpVault();
        FRPVaultProxy = MockFrpVault(
            address(
                new ERC1967Proxy(
                    address(FRPVaultImpl),
                    abi.encodeWithSelector(
                        FRPVaultImpl.initialize.selector,
                        name,
                        symbol,
                        address(usdc),
                        currencyId,
                        wrappedfCashFactory,
                        notionalRouter,
                        0,
                        feeRecipient,
                        1 days
                    )
                )
            )
        );
        // Default msg.sender inside all functions is: 0x00a329c0648769a73afac7f9381e08fb43dbea72,
        // msg.sender inside setUp is 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
        FRPVaultProxy.grantRole(keccak256("VAULT_MANAGER_ROLE"), msg.sender);
        FRPVaultProxy.grantRole(keccak256("HARVESTER_ROLE"), msg.sender);
        FRPVaultProxy.grantRole(keccak256("HARVESTER_ROLE"), usdcWhale);
        FRPVaultProxy.grantRole(keccak256("VAULT_MANAGER_ROLE"), usdcWhale);
        views = new FRPViews();

        vm.startPrank(usdcWhale);
        usdc.approve(address(FRPVaultProxy), type(uint).max);
    }

    function testAPY() public {
        FRPVaultProxy.deposit(100 * 1e6, usdcWhale);
        assertEq(views.getAPY(FRPVaultProxy), 0);

        FRPVaultProxy.harvest(type(uint).max);

        // apy after investing into first maturity
        assertEq(views.getAPY(FRPVaultProxy), 42173528);
        vm.warp(block.timestamp + FRPVaultProxy.timeout() + 1);

        FRPVaultProxy.deposit(500 * 1e6, usdcWhale);
        IFRPVault.NotionalMarket[] memory markets = FRPVaultProxy.__getThreeAndSixMonthMarkets();
        MarketParameters[] memory mockedMarkets = new MarketParameters[](2);
        mockedMarkets[0] = getNotionalMarketParameters(markets[0].maturity, markets[1].oracleRate);
        mockedMarkets[1] = getNotionalMarketParameters(markets[1].maturity, markets[0].oracleRate);
        vm.mockCall(
            notionalRouter,
            abi.encodeWithSelector(NotionalViews.getActiveMarkets.selector, currencyId),
            abi.encode(mockedMarkets)
        );
        FRPVaultProxy.harvest(type(uint).max);

        // apy after investing into second maturity
        assertEq(views.getAPY(FRPVaultProxy), 37265026);

        // set time to 1 day before maturity
        vm.warp(markets[0].maturity - 86400);
        assertEq(views.getAPY(FRPVaultProxy), 37264168);

        // set time to 1 day after maturity
        vm.warp(markets[0].maturity + 3600);
        NotionalProxy(notionalRouter).initializeMarkets(currencyId, false);

        assertEq(views.getAPY(FRPVaultProxy), 42173271);
    }

    function testMaxDepositedAmount() public {
        uint amount = 100 * 1e6;
        FRPVaultProxy.deposit(amount, usdcWhale);
        assertEq(views.getMaxDepositedAmount(address(FRPVaultProxy)), amount);

        FRPVaultProxy.harvest(type(uint).max);
        assertEq(views.getMaxDepositedAmount(address(FRPVaultProxy)), 0);
    }

    function testCanHarvestMaxDepositedAmount() public {
        uint amount = 5_000_00 * 1e6;
        FRPVaultProxy.setMaxLoss(9800);
        FRPVaultProxy.deposit(amount, usdcWhale);
        (bool canHarvest, uint maxDepositedAmount) = views.canHarvestMaxDepositedAmount(address(FRPVaultProxy));
        assertEq(maxDepositedAmount, amount);
        assertTrue(canHarvest);

        FRPVaultProxy.setMaxLoss(9990);
        (canHarvest, maxDepositedAmount) = views.canHarvestMaxDepositedAmount(address(FRPVaultProxy));
        assertEq(maxDepositedAmount, amount);
        assertFalse(canHarvest);
    }

    function testCanHarvestAmount() public {
        IWrappedfCashComplete highestYieldFCash = IWrappedfCashComplete(
            views.getHighestYieldfCash(address(FRPVaultProxy))
        );
        uint amount = 500_000 * 1e6;
        FRPVaultProxy.setMaxLoss(9990);
        FRPVaultProxy.deposit(amount, usdcWhale);
        assertTrue(views.canHarvestAmount(amount / 8, address(FRPVaultProxy), highestYieldFCash));
        assertFalse(views.canHarvestAmount(amount, address(FRPVaultProxy), highestYieldFCash));
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
