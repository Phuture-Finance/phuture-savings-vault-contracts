pragma solidity 0.8.13;

import "forge-std/Test.sol";
import { MarketParameters, AssetRateAdapter, NotionalGovernance } from "../src/notional/interfaces/INotional.sol";
import { IWrappedfCashComplete, IWrappedfCash } from "../src/notional/interfaces/IWrappedfCash.sol";
import "../src/notional/proxy/nUpgradeableBeacon.sol";
import "../src/notional/wfCashERC4626.sol";
import "../src/interfaces/IWETH9.sol";
import "../src/notional/proxy/WrappedfCashFactory.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "./mocks/MockFrpVault.sol";
import "../src/FRPVault.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/IFRPVault.sol";

contract FrpVaultTest is Test {
    using stdStorage for StdStorage;
    using Address for address;

    event FCashMinted(IWrappedfCashComplete indexed _fCashPosition, uint _assetAmount, uint _fCashAmount);
    event FCashRedeemed(IWrappedfCashComplete indexed _fCashPosition, uint _assetAmount, uint _fCashAmount);

    address setupMsgSender = address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);

    string name = "USDC Notional Vault";
    string symbol = "USDC_VAULT";
    uint16 currencyId = 3;
    uint16 maxLoss = 9800;

    address notionalRouter = address(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    address usdcWhale = address(0x0A59649758aa4d66E25f08Dd01271e891fe52199);
    ERC20Upgradeable usdc = ERC20Upgradeable(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));

    MockFrpVault FRPVaultImpl;
    MockFrpVault FRPVaultProxy;
    address wrappedfCashFactory;
    address feeRecipient;

    string mainnetHttpsUrl;
    uint mainnetFork;

    function setUp() public {
        mainnetHttpsUrl = vm.envString("MAINNET_HTTPS_URL");
        mainnetFork = vm.createSelectFork(mainnetHttpsUrl, 15_172_678); // this block works for the fetching of active markets

        wrappedfCashFactory = address(0x5D051DeB5db151C2172dCdCCD42e6A2953E27261);
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
                        maxLoss,
                        feeRecipient
                    )
                )
            )
        );
        FRPVaultProxy.grantRole(keccak256("VAULT_MANAGER_ROLE"), msg.sender);
    }

    function testInitialization() public {
        assertEq(FRPVaultProxy.name(), name);
        assertEq(FRPVaultProxy.symbol(), symbol);
        assertEq(FRPVaultProxy.asset(), address(usdc));
        assertEq(FRPVaultProxy.currencyId(), currencyId);
        assertEq(address(FRPVaultProxy.wrappedfCashFactory()), wrappedfCashFactory);
        assertEq(FRPVaultProxy.notionalRouter(), notionalRouter);
        assertEq(FRPVaultProxy._maxLoss(), maxLoss);
        assertEq(FRPVaultProxy._feeRecipient(), feeRecipient);
        assertEq(FRPVaultProxy._lastTransferTime(), block.timestamp);

        address[] memory positions = FRPVaultProxy._fCashPositions();
        assertEq(positions.length, 2);
        address lowestYieldFCash = address(0xF1e1a4213F241d8fE23990Fc16e14eAf37a27028);
        address highestYieldFCash = address(0x69c6B313506684f49c564B48bF0E4d41c0Cb1A3e);

        assertEq(positions[0], lowestYieldFCash);
        assertEq(positions[1], highestYieldFCash);

        assertEq(usdc.allowance(address(FRPVaultProxy), lowestYieldFCash), type(uint).max);
        assertEq(usdc.allowance(address(FRPVaultProxy), highestYieldFCash), type(uint).max);

        // assert roles, since the FRPVault is deployed by the testing contract
        assertTrue(FRPVaultProxy.hasRole(FRPVaultProxy._VAULT_ADMIN_ROLE(), address(this)));
        assertTrue(FRPVaultProxy.hasRole(FRPVaultProxy._VAULT_MANAGER_ROLE(), setupMsgSender));
    }

    function testCannotInitializeWithInvalidMaxLoss() public {
        vm.expectRevert(bytes("FRPVault: MAX_LOSS"));
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
                10_001,
                feeRecipient
            )
        );
    }

    function testCannotReInitializeExistingVault() public {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        FRPVaultProxy.initialize(
            name,
            symbol,
            address(usdc),
            currencyId,
            IWrappedfCashFactory(wrappedfCashFactory),
            notionalRouter,
            9800,
            feeRecipient
        );
    }

    function testSetMaxLoss() public {
        uint16 newMaxLoss = 9500;
        vm.prank(setupMsgSender);
        FRPVaultProxy.setMaxLoss(newMaxLoss);
        assertEq(FRPVaultProxy._maxLoss(), newMaxLoss);
    }

    function testCannotSetMaxLoss() public {
        uint16 invalidMaxLoss = 10_002;
        vm.prank(setupMsgSender);
        vm.expectRevert(bytes("FRPVault: MAX_LOSS"));
        FRPVaultProxy.setMaxLoss(invalidMaxLoss);

        vm.expectRevert(bytes("FRPVault: FORBIDDEN"));
        FRPVaultProxy.setMaxLoss(9500);
    }

    function testHarvesting() public {
        // USDC whale deposits some USDC in the FRPVault
        vm.startPrank(usdcWhale);
        uint amount = 1000_000 * 1e6;
        usdc.approve(address(FRPVaultProxy), amount);
        FRPVaultProxy.deposit(amount, usdcWhale);

        assertEq(FRPVaultProxy.totalSupply(), 1000_000 * 1e18);

        //*****1st case => Harvest with _maxDepositedAmount lower than the assetBalance******
        uint scalingAmount = 100_000 * 1e6;
        uint maxDepositedAmount = amount - scalingAmount;
        IWrappedfCashComplete highestYieldFCash = IWrappedfCashComplete(FRPVaultProxy._fCashPositions()[1]);
        uint fCashAmount = highestYieldFCash.previewDeposit(maxDepositedAmount);

        // invoke harvest and assert event emitted
        vm.expectEmit(true, false, false, true);
        emit FCashMinted(highestYieldFCash, maxDepositedAmount, fCashAmount);
        FRPVaultProxy.harvest(maxDepositedAmount);

        assertEq(FRPVaultProxy.totalAssets(), 999123917207);
        // fCash amount in the vault is according to wrappedfCash estimation
        assertEq(highestYieldFCash.balanceOf(address(FRPVaultProxy)), fCashAmount);

        // Estimation with using previewDeposit does not work according to the standard
        // so there is some additional leftover of USDC in the vault.
        assertEq(usdc.balanceOf(address(FRPVaultProxy)), scalingAmount + 713);

        //*****2nd case => Harvest with _maxDepositedAmount higher than the assetBalance******
        uint usdcAmountInTheVault = usdc.balanceOf(address(FRPVaultProxy));
        fCashAmount += highestYieldFCash.previewDeposit(usdcAmountInTheVault);

        FRPVaultProxy.harvest(usdcAmountInTheVault * 2);
        assertEq(FRPVaultProxy.totalAssets(), 999022195044);

        // fCash amount in the vault is according to wrappedfCash estimation
        assertEq(highestYieldFCash.balanceOf(address(FRPVaultProxy)), fCashAmount);

        // Estimation with using previewDeposit does not work according to the standard
        // so there is some additional leftover of USDC in the vault.
        assertEq(usdc.balanceOf(address(FRPVaultProxy)), 59);
        vm.stopPrank();
    }

    function testHarvestingFuzzing(uint amountToDeposit) public {
        vm.assume(amountToDeposit < 1_000_000 * 1e6);
        vm.startPrank(usdcWhale);
        usdc.approve(address(FRPVaultProxy), amountToDeposit);

        FRPVaultProxy.deposit(amountToDeposit, usdcWhale);
        FRPVaultProxy.harvest(amountToDeposit);

        // There is never greater than dust amount left in the vault
        assertLt(usdc.balanceOf(address(FRPVaultProxy)), 1_000);
        vm.stopPrank();
    }

    function testHarvestingWithZeroBalance() public {
        IWrappedfCashComplete highestYieldFCash = IWrappedfCashComplete(FRPVaultProxy._fCashPositions()[1]);
        FRPVaultProxy.harvest(type(uint).max);
        assertEq(highestYieldFCash.balanceOf(address(FRPVaultProxy)), 0);
    }

    function testFailSlippage() public {
        // set a very low slippage for the FRPVault
        FRPVaultProxy.setMaxLoss(9992);
        FRPVaultProxy.__convertAssetsTofCash(100_000 * 1e6, IWrappedfCashComplete(FRPVaultProxy._fCashPositions()[1]));
    }

    function testWithdrawal() public {
        vm.startPrank(usdcWhale);

        // Deposit and harvest
        uint balanceBeforeDeposit = usdc.balanceOf(usdcWhale);
        uint amount = 1_000_000 * 1e6;
        usdc.approve(address(FRPVaultProxy), type(uint).max);
        vm.warp(block.timestamp + 1_000);
        FRPVaultProxy.deposit(amount, usdcWhale);
        FRPVaultProxy.harvest(amount);

        // assert minting fee during deposit, it's initial deposit there is no AUMFee
        assertEq(FRPVaultProxy.balanceOf(feeRecipient), 2000000000000000000000);

        // withdrawing half of the amount
        IWrappedfCashComplete highestYieldFCash = IWrappedfCashComplete(FRPVaultProxy._fCashPositions()[1]);
        uint fCashAmount = highestYieldFCash.previewWithdraw(amount / 2 - usdc.balanceOf(address(FRPVaultProxy)));

        vm.warp(block.timestamp + 1_000);
        FRPVaultProxy.withdraw(amount / 2, usdcWhale, usdcWhale);
        assertEq(highestYieldFCash.balanceOf(address(FRPVaultProxy)), 50160346169526);
        assertEq(usdc.balanceOf(address(FRPVaultProxy)), 817);
        assertEq(FRPVaultProxy.balanceOf(feeRecipient), 3001314608482597823512);

        // withdrawing half of the remaining half
        fCashAmount = highestYieldFCash.previewWithdraw(amount / 4 - usdc.balanceOf(address(FRPVaultProxy)));
        FRPVaultProxy.withdraw(amount / 4, usdcWhale, usdcWhale);

        assertEq(highestYieldFCash.balanceOf(address(FRPVaultProxy)), 25009309626116);
        assertEq(usdc.balanceOf(address(FRPVaultProxy)), 824);
        assertEq(FRPVaultProxy.balanceOf(feeRecipient), 3501992294178046386603);

        // Redeeming the leftover amount
        FRPVaultProxy.redeem(FRPVaultProxy.balanceOf(usdcWhale), usdcWhale, usdcWhale);
        assertEq(FRPVaultProxy.balanceOf(usdcWhale), 0);
        assertEq(FRPVaultProxy.balanceOf(feeRecipient), 3993313907507667541103);

        // There is some usdc and fCash amount left in the vault due to difference between oracle and instant rate.
        assertEq(highestYieldFCash.balanceOf(address(FRPVaultProxy)), 386491496715);
        assertEq(usdc.balanceOf(address(FRPVaultProxy)), 929);

        // User losses certain amount of USDC due to slippage
        assertEq(balanceBeforeDeposit - usdc.balanceOf(usdcWhale), 5277_961_647);
    }

    function testWithdrawalFuzzing(uint assets) public {
        vm.assume(assets < 100_000 * 1e6 && assets > 0);

        // Fuzz testing withdrawal
        vm.startPrank(usdcWhale);
        usdc.approve(address(FRPVaultProxy), type(uint).max);
        FRPVaultProxy.deposit(assets, usdcWhale);
        assertEq(FRPVaultProxy._lastTransferTime(), block.timestamp);

        FRPVaultProxy.harvest(type(uint).max);

        uint amount = FRPVaultProxy.previewRedeem(FRPVaultProxy.balanceOf(usdcWhale));
        assertLt(amount, assets);

        FRPVaultProxy.withdraw(amount, usdcWhale, usdcWhale);

        vm.stopPrank();
    }

    function testRedeemFuzzing(uint assets) public {
        vm.assume(assets < 100_000 * 1e6 && assets > 0);

        // Fuzz testing withdrawal
        vm.startPrank(usdcWhale);
        usdc.approve(address(FRPVaultProxy), type(uint).max);
        FRPVaultProxy.deposit(assets, usdcWhale);
        FRPVaultProxy.harvest(type(uint).max);

        uint blockTimestamp = block.timestamp;
        vm.warp(blockTimestamp + 1_000);
        uint assetAmount = FRPVaultProxy.previewRedeem(FRPVaultProxy.balanceOf(usdcWhale));

        uint shares = FRPVaultProxy.previewWithdraw(assetAmount);
        uint burningFee = (shares * FRPVaultProxy.BURNING_FEE_IN_BP()) / 10_000;
        uint aumFee = FRPVaultProxy.getAUMFee(blockTimestamp + 1_000);

        uint feeRecipientBalanceBefore = FRPVaultProxy.balanceOf(feeRecipient);
        uint shareBalanceBeforeRedeem = FRPVaultProxy.balanceOf(usdcWhale);

        FRPVaultProxy.redeem(shares, usdcWhale, usdcWhale);
        assertEq(shareBalanceBeforeRedeem - FRPVaultProxy.balanceOf(usdcWhale), shares);

        assertEq(FRPVaultProxy.balanceOf(feeRecipient) - feeRecipientBalanceBefore, burningFee + aumFee);

        // Redeems the rest
        FRPVaultProxy.redeem(FRPVaultProxy.balanceOf(usdcWhale), usdcWhale, usdcWhale);
        assertEq(FRPVaultProxy.balanceOf(usdcWhale), 0);

        vm.stopPrank();
    }

    function testMaxRedeemFuzzing(uint assets) public {
        vm.assume(assets < 100_000 * 1e6 && assets > 1);

        vm.startPrank(usdcWhale);
        usdc.approve(address(FRPVaultProxy), type(uint).max);
        FRPVaultProxy.deposit(assets, usdcWhale);
        FRPVaultProxy.harvest(type(uint).max);

        uint blockTimestamp = block.timestamp;
        vm.warp(blockTimestamp + 1_000);
        uint maxShares = FRPVaultProxy.maxRedeem(usdcWhale);

        vm.expectRevert(bytes("FRPVault: redeem more than max"));
        FRPVaultProxy.redeem(maxShares + 1, usdcWhale, usdcWhale);

        assertLt(maxShares, FRPVaultProxy.convertToShares(assets));

        uint assetAmount = FRPVaultProxy.previewRedeem(maxShares);
        uint assetBalanceBeforeRedeem = usdc.balanceOf(usdcWhale);
        uint feeRecipientBalanceBefore = FRPVaultProxy.balanceOf(feeRecipient);
        uint burningFee = (maxShares * FRPVaultProxy.BURNING_FEE_IN_BP()) / FRPVaultProxy._BP();
        uint aumFee = FRPVaultProxy.getAUMFee(blockTimestamp + 1_000);

        assertEq(FRPVaultProxy.redeem(maxShares, usdcWhale, usdcWhale), assetAmount);
        // All shares were exchanged for the usdc
        assertEq(FRPVaultProxy.balanceOf(usdcWhale), 0);
        // The estimated assetAmount with previewRedeem matches the assets received
        assertEq(usdc.balanceOf(usdcWhale) - assetBalanceBeforeRedeem, assetAmount);

        // aumFee and burningFee are transferred to the feeRecipient
        assertEq(FRPVaultProxy.balanceOf(feeRecipient) - feeRecipientBalanceBefore, burningFee + aumFee);

        vm.stopPrank();
    }

    function testPreviewWithdraw() public {
        uint assets = 100_000 * 1e6;

        vm.startPrank(usdcWhale);
        usdc.approve(address(FRPVaultProxy), type(uint).max);
        FRPVaultProxy.deposit(assets, usdcWhale);
        FRPVaultProxy.harvest(type(uint).max);

        vm.warp(block.timestamp + 1_000);
        uint maxAssetAmount = FRPVaultProxy.maxWithdraw(usdcWhale);

        vm.expectRevert(bytes("FRPVault: withdraw more than max"));
        FRPVaultProxy.withdraw(maxAssetAmount + 1, usdcWhale, usdcWhale);
        assertLt(maxAssetAmount, assets);

        uint shares = FRPVaultProxy.previewWithdraw(maxAssetAmount);

        uint balanceOfUsdcBefore = usdc.balanceOf(usdcWhale);

        uint sharesBurned = FRPVaultProxy.withdraw(maxAssetAmount, usdcWhale, usdcWhale);

        // There is some leftover of shares due to inability to estimate maxWithdraw amount with 100% accuracy
        // https://eips.ethereum.org/EIPS/eip-4626#maxwithdraw => MUST return the maximum amount of assets that could be transferred from owner
        // through withdraw and not cause a revert, which MUST NOT be higher than the actual maximum that would be accepted
        // (it should underestimate if necessary).
        assertEq(FRPVaultProxy.balanceOf(usdcWhale), 10006060758);
        assertEq(sharesBurned, shares);
        assertEq(usdc.balanceOf(usdcWhale) - balanceOfUsdcBefore, maxAssetAmount);

        FRPVaultProxy.redeem(FRPVaultProxy.balanceOf(usdcWhale), usdcWhale, usdcWhale);
        assertEq(FRPVaultProxy.balanceOf(usdcWhale), 0);

        vm.stopPrank();
    }

    function testDepositFuzzing(uint assets) public {
        vm.assume(assets < 100_000 * 1e6 && assets > 1);

        vm.startPrank(usdcWhale);
        usdc.approve(address(FRPVaultProxy), type(uint).max);

        // Initial deposit
        FRPVaultProxy.deposit(1e6, usdcWhale);
        uint sharesInitialDeposit = FRPVaultProxy.balanceOf(usdcWhale);
        uint feeRecipientBalanceBefore = FRPVaultProxy.balanceOf(feeRecipient);
        uint usdcBalanceBefore = usdc.balanceOf(usdcWhale);

        uint blockTimestamp = block.timestamp;
        vm.warp(blockTimestamp + 1_000);
        uint sharesEstimated = FRPVaultProxy.previewDeposit(assets);

        uint sharesWithoutFee = FRPVaultProxy.convertToShares(assets);
        uint mintingFee = (sharesWithoutFee * FRPVaultProxy.MINTING_FEE_IN_BP()) / 10_000;
        uint aumFee = FRPVaultProxy.getAUMFee(blockTimestamp + 1_000);

        // deposit to assert
        uint sharesReceived = FRPVaultProxy.deposit(assets, usdcWhale);

        // depositor received exact number of shares and transferred exact Usdc
        assertEq(sharesEstimated, sharesReceived);
        assertEq(usdcBalanceBefore - usdc.balanceOf(usdcWhale), assets);
        assertEq(FRPVaultProxy.balanceOf(usdcWhale) - sharesInitialDeposit, sharesEstimated);

        // aum fee is newly minted, minting fee is subtracted from deposit
        assertEq(FRPVaultProxy.balanceOf(feeRecipient) - feeRecipientBalanceBefore, mintingFee + aumFee);

        vm.stopPrank();
    }

    function testMintFuzzing() public {
        uint shares = 100_000 * 1e18 + 1;

        vm.startPrank(usdcWhale);
        usdc.approve(address(FRPVaultProxy), type(uint).max);

        // Initial deposit
        FRPVaultProxy.deposit(1e6, usdcWhale);
        uint feeRecipientBalanceBefore = FRPVaultProxy.balanceOf(feeRecipient);
        uint sharesBalanceBefore = FRPVaultProxy.balanceOf(usdcWhale);

        uint blockTimestamp = block.timestamp;
        vm.warp(blockTimestamp + 1_000);
        uint assetsEstimated = FRPVaultProxy.previewMint(shares);

        uint assetsWithoutFee = FRPVaultProxy.convertToAssets(shares);
        uint mintingFee = FRPVaultProxy.convertToShares(
            (assetsWithoutFee * FRPVaultProxy.MINTING_FEE_IN_BP()) / 10_000
        );
        uint aumFee = FRPVaultProxy.getAUMFee(blockTimestamp + 1_000);

        // deposit to assert
        uint assetsTransferred = FRPVaultProxy.mint(shares, usdcWhale);

        // minter transferred usdc and received exact number of shares
        // https://eips.ethereum.org/EIPS/eip-4626#previewmint => discrepancy in 1 is ok. previewMint MUST return
        // as close to and no fewer than the exact amount of assets that would be deposited in a mint call in the same transaction.
        //I.e. mint should return the same or fewer assets as previewMint if called in the same transaction.
        assertEq(assetsTransferred, assetsEstimated - 1);
        assertEq(FRPVaultProxy.balanceOf(usdcWhale) - sharesBalanceBefore, shares);

        // aum fee is newly minted, minting fee is added on top of shares amount
        assertEq(FRPVaultProxy.balanceOf(feeRecipient) - feeRecipientBalanceBefore, mintingFee + aumFee);

        vm.stopPrank();
    }

    function testWithdrawalFromBothMaturities() public {
        vm.startPrank(usdcWhale);

        // Deposit and harvest
        uint balanceBeforeDeposit = usdc.balanceOf(usdcWhale);
        uint amount = 10_000 * 1e6;
        usdc.approve(address(FRPVaultProxy), type(uint).max);
        FRPVaultProxy.deposit(amount, usdcWhale);
        FRPVaultProxy.harvest(amount);

        FRPVaultProxy.deposit(amount, usdcWhale);
        IFRPVault.NotionalMarket[] memory markets = FRPVaultProxy.__getThreeAndSixMonthMarkets();
        MarketParameters[] memory mockedMarkets = new MarketParameters[](2);
        mockedMarkets[0] = getNotionalMarketParameters(markets[0].maturity, markets[1].oracleRate);
        mockedMarkets[1] = getNotionalMarketParameters(markets[1].maturity, markets[0].oracleRate);
        vm.mockCall(
            notionalRouter,
            abi.encodeWithSelector(NotionalViews.getActiveMarkets.selector, currencyId),
            abi.encode(mockedMarkets)
        );
        FRPVaultProxy.harvest(amount);

        // Deposit some usdc without harvesting
        FRPVaultProxy.deposit(6_000 * 1e6, usdcWhale);

        address[] memory positions = FRPVaultProxy._fCashPositions();
        IWrappedfCashComplete lowestYieldFCash = IWrappedfCashComplete(positions[0]);
        IWrappedfCashComplete highestYieldFCash = IWrappedfCashComplete(positions[1]);

        // withdrawing from a single maturity
        FRPVaultProxy.withdraw(amount / 2, usdcWhale, usdcWhale);
        assertEq(lowestYieldFCash.balanceOf(address(FRPVaultProxy)), 1005021519000);
        assertEq(highestYieldFCash.balanceOf(address(FRPVaultProxy)), 1009501065000);
        assertEq(usdc.balanceOf(address(FRPVaultProxy)), 1000_000_011);

        // withdrawing from both maturities
        vm.expectEmit(true, false, false, true);
        emit FCashRedeemed(lowestYieldFCash, 9_988_703_155, 1005021519000);
        vm.expectEmit(true, false, false, true);
        emit FCashRedeemed(highestYieldFCash, 9_888_549_841, 1000890183164);
        FRPVaultProxy.redeem(FRPVaultProxy.balanceOf(usdcWhale), usdcWhale, usdcWhale);

        assertEq(lowestYieldFCash.balanceOf(address(FRPVaultProxy)), 0);
        assertEq(highestYieldFCash.balanceOf(address(FRPVaultProxy)), 8610881836);
        assertEq(FRPVaultProxy.balanceOf(usdcWhale), 0);
        assertEq(usdc.balanceOf(address(FRPVaultProxy)), 997);

        uint balanceAfterWithdrawal = usdc.balanceOf(usdcWhale);
        // User losses certain amount of USDC due to slippage
        assertEq(balanceBeforeDeposit - balanceAfterWithdrawal, 122747990);
    }

    function testAssetWithDifferentDecimals() public {
        ERC20Upgradeable dai = ERC20Upgradeable(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
        MockFrpVault daiFRPVault = MockFrpVault(
            address(
                new ERC1967Proxy(
                    address(new MockFrpVault()),
                    abi.encodeWithSelector(
                        FRPVaultImpl.initialize.selector,
                        "Dai FRP Vault",
                        "DAI_FRP",
                        address(dai),
                        2,
                        wrappedfCashFactory,
                        notionalRouter,
                        maxLoss,
                        feeRecipient
                    )
                )
            )
        );
        daiFRPVault.grantRole(keccak256("VAULT_MANAGER_ROLE"), msg.sender);

        address daiWhale = address(0x5D38B4e4783E34e2301A2a36c39a03c45798C4dD);
        vm.startPrank(daiWhale);
        uint amount = 10_000 * 1e18;
        dai.approve(address(daiFRPVault), type(uint).max);
        daiFRPVault.deposit(amount, daiWhale);
        daiFRPVault.harvest(amount);

        assertEq(dai.balanceOf(address(daiFRPVault)), 2470000000000);

        IWrappedfCashComplete highestYieldFCash = IWrappedfCashComplete(daiFRPVault._fCashPositions()[1]);

        uint estimatedShares = daiFRPVault.previewWithdraw(amount / 2);

        uint shares = daiFRPVault.withdraw(amount / 2, daiWhale, daiWhale);
        assertEq(shares, estimatedShares);
        assertEq(highestYieldFCash.balanceOf(address(daiFRPVault)), 505786512060);
        assertEq(dai.balanceOf(address(daiFRPVault)), 995309949189560);

        vm.stopPrank();
    }

    function testSortMarketsByOracleRate() public {
        uint highestOracleRate = 100;
        uint lowestOracleRate = 10;
        uint threeMonthMaturity = 100 + block.timestamp;
        uint sixMonthMaturity = threeMonthMaturity + 90 * 86400;
        MarketParameters[] memory marketParameters = new MarketParameters[](4);
        marketParameters[0] = getNotionalMarketParameters(threeMonthMaturity, lowestOracleRate);
        marketParameters[1] = getNotionalMarketParameters(sixMonthMaturity, highestOracleRate);
        marketParameters[2] = getNotionalMarketParameters(block.timestamp + 9 * 30 * 86400, 50);
        marketParameters[3] = getNotionalMarketParameters(block.timestamp + 12 * 30 * 86400, 70);
        vm.mockCall(
            notionalRouter,
            abi.encodeWithSelector(NotionalViews.getActiveMarkets.selector, currencyId),
            abi.encode(marketParameters)
        );
        (uint lowestYieldMaturity, uint highestYieldMaturity) = FRPVaultProxy.__sortMarketsByOracleRate();

        assertEq(lowestYieldMaturity, threeMonthMaturity);
        assertEq(highestYieldMaturity, sixMonthMaturity);
    }

    function testUpgradeability() public {
        vm.startPrank(setupMsgSender);
        FRPVaultProxy.upgradeTo(address(new FRPVault()));
    }

    function testFailsUpgradeWithoutRole() public {
        FRPVaultProxy.upgradeTo(address(new FRPVault()));
    }

    function testStorage() public {
        bytes32 zeroValue = 0x0000000000000000000000000000000000000000000000000000000000000000;

        // 1st slot is occupied by Initializable =>  _initialized and _initializing;
        bytes32 zeroSlot = vm.load(address(FRPVaultProxy), bytes32(uint256(0)));
        assertEq(zeroSlot, bytes32(uint(1)));

        // Next 50 slots are _gap inside ContextUpgradeable contract
        for (uint i = 1; i < 51; i++) {
            bytes32 slot = vm.load(address(FRPVaultProxy), bytes32(uint256(i)));
            assertEq(slot, zeroValue);
        }

        // Next 3 slots are _balances, _allowances, _totalSupply mappings inside ERC20Upgradeable
        for (uint i = 51; i < 54; i++) {
            bytes32 slot = vm.load(address(FRPVaultProxy), bytes32(uint256(i)));
            assertEq(slot, zeroValue);
        }

        // Next slot is token name
        bytes32 slot54 = vm.load(address(FRPVaultProxy), bytes32(uint256(54)));
        assertEq(slot54, 0x55534443204e6f74696f6e616c205661756c7400000000000000000000000026);

        // Next slot is token symbol
        bytes32 slot55 = vm.load(address(FRPVaultProxy), bytes32(uint256(55)));
        assertEq(slot55, 0x555344435f5641554c5400000000000000000000000000000000000000000014);

        // Next 45 slots are _gap inside ERC20Upgradeable
        for (uint i = 56; i < 101; i++) {
            bytes32 slot = vm.load(address(FRPVaultProxy), bytes32(uint256(i)));
            assertEq(slot, zeroValue);
        }

        // Next slot is the address of usdc inside ERC4626Upgradeable
        bytes32 slot101 = vm.load(address(FRPVaultProxy), bytes32(uint256(101)));
        assertEq(slot101, 0x000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48);

        // Next 49 slots are _gap inside ERC4626Upgradeable
        for (uint i = 102; i < 151; i++) {
            bytes32 slot = vm.load(address(FRPVaultProxy), bytes32(uint256(i)));
            assertEq(slot, zeroValue);
        }

        // Next slot is _HASHED_NAME inside EIP712Upgradeable
        bytes32 slot151 = vm.load(address(FRPVaultProxy), bytes32(uint256(151)));
        assertEq(slot151, 0x318587b3a21ebf41642203d8f1916c85e928263edb04cf93c681903c93e27cc4);

        // Next slot is _HASHED_VERSION inside EIP712Upgradeable
        bytes32 slot152 = vm.load(address(FRPVaultProxy), bytes32(uint256(152)));
        assertEq(slot152, 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6);

        // Next 50 slots are _gap inside EIP712Upgradeable
        for (uint i = 153; i < 203; i++) {
            bytes32 slot = vm.load(address(FRPVaultProxy), bytes32(uint256(i)));
            assertEq(slot, zeroValue);
        }

        // Next slot is _nonces mapping inside ERC20PermitUpgradeable
        bytes32 slot203 = vm.load(address(FRPVaultProxy), bytes32(uint256(203)));
        assertEq(slot203, zeroValue);

        // Next slot is _PERMIT_TYPEHASH_DEPRECATED_SLOT mapping inside ERC20PermitUpgradeable
        bytes32 slot204 = vm.load(address(FRPVaultProxy), bytes32(uint256(204)));
        assertEq(slot204, zeroValue);

        // Next 49 slots are _gap inside ERC20PermitUpgradeable
        for (uint i = 205; i < 254; i++) {
            bytes32 slot = vm.load(address(FRPVaultProxy), bytes32(uint256(i)));
            assertEq(slot, zeroValue);
        }

        // Next 50 slots are _gap inside ERC165Upgradeable
        for (uint i = 254; i < 304; i++) {
            bytes32 slot = vm.load(address(FRPVaultProxy), bytes32(uint256(i)));
            assertEq(slot, zeroValue);
        }

        // Next slot is _roles mapping inside AccessControlUpgradeable
        bytes32 slot305 = vm.load(address(FRPVaultProxy), bytes32(uint256(305)));
        assertEq(slot305, zeroValue);

        // Next 49 slots are _gap inside AccessControlUpgradeable
        for (uint i = 306; i < 355; i++) {
            bytes32 slot = vm.load(address(FRPVaultProxy), bytes32(uint256(i)));
            assertEq(slot, zeroValue);
        }

        // Next 50 slots are _gap inside ERC1967UpgradeUpgradeable
        for (uint i = 355; i < 405; i++) {
            bytes32 slot = vm.load(address(FRPVaultProxy), bytes32(uint256(i)));
            assertEq(slot, zeroValue);
        }

        // Next 50 slots are _gap inside UUPSUpgradeable
        for (uint i = 405; i < 454; i++) {
            bytes32 slot = vm.load(address(FRPVaultProxy), bytes32(uint256(i)));
            assertEq(slot, zeroValue);
        }

        // Next slot is currencyId, maxLoss and notionalRouter inside FRPVault
        bytes32 slot454 = vm.load(address(FRPVaultProxy), bytes32(uint256(454)));
        assertEq(slot454, 0x00000000000000001344a36a1b56144c3bc62e7757377d288fde036926480003);

        // Next slot is wrappedfCashFactory inside FRPVault
        bytes32 slot455 = vm.load(address(FRPVaultProxy), bytes32(uint256(455)));
        assertEq(slot455, 0x0000000000000000000000005d051deb5db151c2172dcdccd42e6a2953e27261);

        // Next slot is fCashPositions inside FRPVault
        bytes32 slot456 = vm.load(address(FRPVaultProxy), bytes32(uint256(456)));
        assertEq(slot456, 0x0000000000000000000000000000000000000000000000000000000000000002);

        // Next slot is lastTransferTime and feeRecipient inside FRPVault
        bytes32 slot457 = vm.load(address(FRPVaultProxy), bytes32(uint256(457)));
        assertEq(slot457, 0x000000000000000000000000000000000000abcd000000000000000062d68ebe);
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
            lastImpliedRate: 20,
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
