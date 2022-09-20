// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import { MarketParameters } from "../src/external/notional/interfaces/INotional.sol";
import "../src/external/notional/interfaces/INotionalV2.sol";
import { IWrappedfCashComplete, IWrappedfCash } from "../src/external/notional/interfaces/IWrappedfCash.sol";
import "../src/external/notional/proxy/WrappedfCashFactory.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "./mocks/MockSavingsVault.sol";
import "./utils/SigUtils.sol";
import "../src/SavingsVault.sol";
import "../src/interfaces/ISavingsVault.sol";

contract SavingsVaultTest is Test {
    using stdStorage for StdStorage;
    using Address for address;

    event FCashMinted(IWrappedfCashComplete indexed _fCashPosition, uint _assetAmount, uint _fCashAmount);
    event FCashRedeemed(IWrappedfCashComplete indexed _fCashPosition, uint _assetAmount, uint _fCashAmount);

    address setupMsgSender = address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);

    string name = "USDC Notional Vault";
    string symbol = "USDC_VAULT";
    uint16 currencyId = 3;
    uint16 maxLoss = 9000;

    address notionalRouter = address(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    address usdcWhale = address(0x0A59649758aa4d66E25f08Dd01271e891fe52199);
    ERC20Upgradeable usdc = ERC20Upgradeable(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));

    MockSavingsVault SavingsVaultImpl;
    MockSavingsVault SavingsVaultProxy;
    address wrappedfCashFactory;
    address feeRecipient;

    string mainnetHttpsUrl;
    uint mainnetFork;
    uint blockNumber;

    function setUp() public {
        mainnetHttpsUrl = vm.envString("MAINNET_HTTPS_URL");
        blockNumber = 15_172_678;
        mainnetFork = vm.createSelectFork(mainnetHttpsUrl, blockNumber);

        wrappedfCashFactory = address(0x5D051DeB5db151C2172dCdCCD42e6A2953E27261);
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
                        maxLoss,
                        feeRecipient,
                        1 days
                    )
                )
            )
        );
        // Default msg.sender inside all functions is: 0x00a329c0648769a73afac7f9381e08fb43dbea72,
        // msg.sender inside setUp is 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
        SavingsVaultProxy.grantRole(keccak256("VAULT_MANAGER_ROLE"), msg.sender);
        SavingsVaultProxy.grantRole(keccak256("VAULT_MANAGER_ROLE"), usdcWhale);
    }

    function testMainnetDeployment() public {
        vm.createSelectFork(mainnetHttpsUrl);
        SavingsVault savingsVault = SavingsVault(0x5cE40e68C1A011c1782499bF5fF01C910c792Ba6);
        address[2] memory positions = savingsVault.getfCashPositions();
        assertEq(positions[0], 0x69c6B313506684f49c564B48bF0E4d41c0Cb1A3e);
        assertEq(positions[1], 0xF1e1a4213F241d8fE23990Fc16e14eAf37a27028);
    }

    function testInitialization() public {
        assertEq(SavingsVaultProxy.name(), name);
        assertEq(SavingsVaultProxy.symbol(), symbol);
        assertEq(SavingsVaultProxy.asset(), address(usdc));
        assertEq(SavingsVaultProxy.currencyId(), currencyId);
        assertEq(address(SavingsVaultProxy.wrappedfCashFactory()), wrappedfCashFactory);
        assertEq(SavingsVaultProxy.notionalRouter(), notionalRouter);
        assertEq(SavingsVaultProxy.maxLoss(), maxLoss);
        assertEq(SavingsVaultProxy._feeRecipient(), feeRecipient);
        assertEq(SavingsVaultProxy._lastTransferTime(), block.timestamp);

        address[] memory positions = SavingsVaultProxy._fCashPositions();
        assertEq(positions.length, 2);
        address lowestYieldFCash = address(0xF1e1a4213F241d8fE23990Fc16e14eAf37a27028);
        address highestYieldFCash = address(0x69c6B313506684f49c564B48bF0E4d41c0Cb1A3e);

        assertEq(positions[0], lowestYieldFCash);
        assertEq(positions[1], highestYieldFCash);

        assertEq(usdc.allowance(address(SavingsVaultProxy), lowestYieldFCash), 0);
        assertEq(usdc.allowance(address(SavingsVaultProxy), highestYieldFCash), 0);

        // assert roles, since the SavingsVault is deployed by the testing contract
        assertTrue(SavingsVaultProxy.hasRole(SavingsVaultProxy._VAULT_ADMIN_ROLE(), address(this)));
        assertTrue(SavingsVaultProxy.hasRole(SavingsVaultProxy._VAULT_MANAGER_ROLE(), setupMsgSender));
    }

    function testCannotInitializeWithInvalidMaxLoss() public {
        vm.expectRevert(bytes("Max_loss"));
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
                10_001,
                feeRecipient
            )
        );
    }

    function testCannotReInitializeExistingVault() public {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        SavingsVaultProxy.initialize(
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
        SavingsVaultProxy.setMaxLoss(newMaxLoss);
        assertEq(SavingsVaultProxy.maxLoss(), newMaxLoss);
    }

    function testCannotSetMaxLoss() public {
        uint16 invalidMaxLoss = 10_002;
        vm.prank(setupMsgSender);
        vm.expectRevert(bytes("Max_loss"));
        SavingsVaultProxy.setMaxLoss(invalidMaxLoss);

        vm.expectRevert(
            bytes(
                "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0xd1473398bb66596de5d1ea1fc8e303ff2ac23265adc9144b1b52065dc4f0934b"
            )
        );
        SavingsVaultProxy.setMaxLoss(9500);
    }

    function testSetFeeRecipient() public {
        address newFeeRecipient = address(0xABCDE);
        vm.prank(setupMsgSender);
        SavingsVaultProxy.setFeeRecipient(newFeeRecipient);
        assertEq(SavingsVaultProxy._feeRecipient(), newFeeRecipient);
    }

    function testCannotSetFeeRecipient() public {
        vm.expectRevert(
            bytes(
                "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0xd1473398bb66596de5d1ea1fc8e303ff2ac23265adc9144b1b52065dc4f0934b"
            )
        );
        SavingsVaultProxy.setFeeRecipient(address(0xABCDE));
    }

    function testHarvesting() public {
        // USDC whale deposits some USDC in the SavingsVault
        vm.startPrank(usdcWhale);
        uint amount = 1_000_000 * 1e6;
        usdc.approve(address(SavingsVaultProxy), amount);
        SavingsVaultProxy.deposit(amount, usdcWhale);

        assertEq(SavingsVaultProxy.totalSupply(), 1000_000 * 1e18);

        //*****1st case => Harvest with _maxDepositedAmount lower than the assetBalance******
        uint scalingAmount = 100_000 * 1e6;
        uint maxDepositedAmount = amount - scalingAmount;
        IWrappedfCashComplete highestYieldFCash = IWrappedfCashComplete(SavingsVaultProxy._fCashPositions()[1]);
        uint fCashAmount = highestYieldFCash.previewDeposit(maxDepositedAmount);

        // invoke harvest and assert event emitted
        vm.expectEmit(true, false, false, true);
        emit FCashMinted(highestYieldFCash, maxDepositedAmount, fCashAmount);
        SavingsVaultProxy.harvest(maxDepositedAmount);
        vm.warp(block.timestamp + 1 days + 1);

        assertEq(SavingsVaultProxy.totalAssets(), 999561212039);
        //         fCash amount in the vault is according to wrappedfCash estimation
        assertEq(highestYieldFCash.balanceOf(address(SavingsVaultProxy)), fCashAmount);
        assertEq(usdc.allowance(address(SavingsVaultProxy), address(highestYieldFCash)), 0);

        // Estimation with using previewDeposit does not work according to the standard
        // so there is some additional leftover of USDC in the vault.
        assertEq(usdc.balanceOf(address(SavingsVaultProxy)), scalingAmount + 713);

        //*****2nd case => Harvest with _maxDepositedAmount higher than the assetBalance******
        uint usdcAmountInTheVault = usdc.balanceOf(address(SavingsVaultProxy));
        fCashAmount += highestYieldFCash.previewDeposit(usdcAmountInTheVault);

        SavingsVaultProxy.harvest(usdcAmountInTheVault * 2);
        assertEq(SavingsVaultProxy.totalAssets(), 999501330256);

        // fCash amount in the vault is according to wrappedfCash estimation
        assertEq(highestYieldFCash.balanceOf(address(SavingsVaultProxy)), fCashAmount);

        // Estimation with using previewDeposit does not work according to the standard
        // so there is some additional leftover of USDC in the vault.
        assertEq(usdc.balanceOf(address(SavingsVaultProxy)), 29);
        vm.stopPrank();
    }

    function testSlippage() public {
        vm.startPrank(usdcWhale);
        usdc.approve(address(SavingsVaultProxy), type(uint).max);
        SavingsVaultProxy.deposit(2_000_000 * 1e6, usdcWhale);
        vm.expectRevert(bytes("Trade failed, slippage"));
        SavingsVaultProxy.harvest(type(uint).max);
        vm.stopPrank();
    }

    function testHarvestingFuzzing(uint amountToDeposit) public {
        vm.assume(amountToDeposit < 1_000_000 * 1e6);
        vm.startPrank(usdcWhale);
        usdc.approve(address(SavingsVaultProxy), amountToDeposit);

        SavingsVaultProxy.deposit(amountToDeposit, usdcWhale);
        SavingsVaultProxy.harvest(amountToDeposit);

        // There is never greater than dust amount of usdc left in the vault
        assertLt(usdc.balanceOf(address(SavingsVaultProxy)), 1_000);
        vm.stopPrank();
    }

    function testHarvestingWithZeroBalance() public {
        IWrappedfCashComplete highestYieldFCash = IWrappedfCashComplete(SavingsVaultProxy._fCashPositions()[1]);
        vm.prank(setupMsgSender);
        SavingsVaultProxy.harvest(type(uint).max);
        assertEq(highestYieldFCash.balanceOf(address(SavingsVaultProxy)), 0);
    }

    function testWithdrawal() public {
        vm.startPrank(usdcWhale);

        // Deposit and harvest
        uint balanceBeforeDeposit = usdc.balanceOf(usdcWhale);
        uint amount = 1_000_000 * 1e6;
        usdc.approve(address(SavingsVaultProxy), type(uint).max);
        vm.warp(block.timestamp + 1_000);
        SavingsVaultProxy.setMaxLoss(0);
        SavingsVaultProxy.deposit(amount, usdcWhale);
        SavingsVaultProxy.harvest(amount);

        // assert minting fee during deposit, it's initial deposit there is no AUMFee
        assertEq(SavingsVaultProxy.balanceOf(feeRecipient), 1996007984031936127744);

        // withdrawing half of the amount
        IWrappedfCashComplete highestYieldFCash = IWrappedfCashComplete(SavingsVaultProxy._fCashPositions()[1]);
        uint fCashAmount = highestYieldFCash.previewWithdraw(amount / 2 - usdc.balanceOf(address(SavingsVaultProxy)));

        vm.warp(block.timestamp + 1_000);
        SavingsVaultProxy.withdraw(amount / 2, usdcWhale, usdcWhale);
        assertEq(highestYieldFCash.balanceOf(address(SavingsVaultProxy)), 50178254919681);
        assertEq(usdc.balanceOf(address(SavingsVaultProxy)), 0);
        assertEq(SavingsVaultProxy.balanceOf(feeRecipient), 4499137477375791733362);

        // withdrawing half of the remaining half
        fCashAmount = highestYieldFCash.previewWithdraw(amount / 4 - usdc.balanceOf(address(SavingsVaultProxy)));
        SavingsVaultProxy.withdraw(amount / 4, usdcWhale, usdcWhale);

        assertEq(highestYieldFCash.balanceOf(address(SavingsVaultProxy)), 25039032169466);
        assertEq(usdc.balanceOf(address(SavingsVaultProxy)), 0);
        assertEq(SavingsVaultProxy.balanceOf(feeRecipient), 5750385759468507102121);

        // Redeeming the leftover amount
        SavingsVaultProxy.redeem(SavingsVaultProxy.balanceOf(usdcWhale), usdcWhale, usdcWhale);
        assertEq(SavingsVaultProxy.balanceOf(usdcWhale), 0);
        assertEq(SavingsVaultProxy.balanceOf(feeRecipient), 6961838090250646297347);

        // There is some usdc and fCash amount left in the vault due to difference between oracle and instant rate.
        assertEq(highestYieldFCash.balanceOf(address(SavingsVaultProxy)), 699362392788);
        assertEq(usdc.balanceOf(address(SavingsVaultProxy)), 0);

        // User losses certain amount of USDC due to slippage
        assertEq(balanceBeforeDeposit - usdc.balanceOf(usdcWhale), 8387163064);
    }

    function testWithdrawalFuzzing(uint assets) public {
        vm.assume(assets < 100_000 * 1e6 && assets > 1);

        // Fuzz testing withdrawal
        vm.startPrank(usdcWhale);
        usdc.approve(address(SavingsVaultProxy), type(uint).max);
        SavingsVaultProxy.deposit(assets, usdcWhale);
        assertEq(SavingsVaultProxy._lastTransferTime(), block.timestamp);

        SavingsVaultProxy.harvest(type(uint).max);

        // deposit some amount without harvesting
        SavingsVaultProxy.deposit(assets, usdcWhale);

        uint amount = SavingsVaultProxy.previewRedeem(SavingsVaultProxy.balanceOf(usdcWhale));
        assertLt(amount, assets * 2);

        SavingsVaultProxy.withdraw(amount, usdcWhale, usdcWhale);

        vm.stopPrank();
    }

    function testRedeemFuzzing(uint assets) public {
        vm.assume(assets < 100_000 * 1e6 && assets > 0);

        // Fuzz testing withdrawal
        vm.startPrank(usdcWhale);
        usdc.approve(address(SavingsVaultProxy), type(uint).max);
        SavingsVaultProxy.setMaxLoss(0);
        SavingsVaultProxy.deposit(assets, usdcWhale);
        SavingsVaultProxy.harvest(type(uint).max);

        uint blockTimestamp = block.timestamp;
        vm.warp(blockTimestamp + 1_000);
        uint assetAmount = SavingsVaultProxy.previewRedeem(SavingsVaultProxy.balanceOf(usdcWhale));

        uint shares = SavingsVaultProxy.previewWithdraw(assetAmount);
        uint burningFee = shares -
            ((shares * SavingsVaultProxy.BP()) / (SavingsVaultProxy.BURNING_FEE_IN_BP() + SavingsVaultProxy.BP()));
        uint aumFee = SavingsVaultProxy.getAUMFee(blockTimestamp + 1_000);

        uint feeRecipientBalanceBefore = SavingsVaultProxy.balanceOf(feeRecipient);
        uint shareBalanceBeforeRedeem = SavingsVaultProxy.balanceOf(usdcWhale);

        SavingsVaultProxy.redeem(shares, usdcWhale, usdcWhale);
        assertEq(shareBalanceBeforeRedeem - SavingsVaultProxy.balanceOf(usdcWhale), shares);

        assertEq(SavingsVaultProxy.balanceOf(feeRecipient) - feeRecipientBalanceBefore, burningFee + aumFee);

        // Redeems the rest
        SavingsVaultProxy.redeem(SavingsVaultProxy.balanceOf(usdcWhale), usdcWhale, usdcWhale);
        assertEq(SavingsVaultProxy.balanceOf(usdcWhale), 0);

        vm.stopPrank();
    }

    function testMaxRedeemFuzzing(uint assets) public {
        vm.assume(assets < 100_000 * 1e6 && assets > 1);

        vm.startPrank(usdcWhale);
        usdc.approve(address(SavingsVaultProxy), type(uint).max);
        SavingsVaultProxy.setMaxLoss(0);
        SavingsVaultProxy.deposit(assets, usdcWhale);
        SavingsVaultProxy.harvest(type(uint).max);

        uint blockTimestamp = block.timestamp;
        vm.warp(blockTimestamp + 1_000);
        uint maxShares = SavingsVaultProxy.maxRedeem(usdcWhale);

        vm.expectRevert(bytes("Redeem_max"));
        SavingsVaultProxy.redeem(maxShares + 1, usdcWhale, usdcWhale);

        assertLt(maxShares, SavingsVaultProxy.convertToShares(assets));

        uint assetAmount = SavingsVaultProxy.previewRedeem(maxShares);
        uint assetBalanceBeforeRedeem = usdc.balanceOf(usdcWhale);
        uint feeRecipientBalanceBefore = SavingsVaultProxy.balanceOf(feeRecipient);
        uint burningFee = maxShares -
            ((maxShares * SavingsVaultProxy.BP()) / (SavingsVaultProxy.BURNING_FEE_IN_BP() + SavingsVaultProxy.BP()));
        uint aumFee = SavingsVaultProxy.getAUMFee(blockTimestamp + 1_000);

        assertGe(SavingsVaultProxy.redeem(maxShares, usdcWhale, usdcWhale), assetAmount);
        // All shares were exchanged for the usdc
        assertEq(SavingsVaultProxy.balanceOf(usdcWhale), 0);
        // The estimated assetAmount with previewRedeem matches the assets received
        assertGe(usdc.balanceOf(usdcWhale) - assetBalanceBeforeRedeem, assetAmount);

        // aumFee and burningFee are transferred to the feeRecipient
        assertEq(SavingsVaultProxy.balanceOf(feeRecipient) - feeRecipientBalanceBefore, burningFee + aumFee);

        vm.stopPrank();
    }

    function testPreviewWithdraw() public {
        uint assets = 100_000 * 1e6;

        vm.startPrank(usdcWhale);
        usdc.approve(address(SavingsVaultProxy), type(uint).max);
        SavingsVaultProxy.setMaxLoss(0);
        SavingsVaultProxy.deposit(assets, usdcWhale);
        SavingsVaultProxy.harvest(type(uint).max);

        vm.warp(block.timestamp + 1_000);
        uint maxAssetAmount = SavingsVaultProxy.maxWithdraw(usdcWhale);

        vm.expectRevert(bytes("Withdraw_max"));
        SavingsVaultProxy.withdraw(maxAssetAmount + 1, usdcWhale, usdcWhale);
        assertLt(maxAssetAmount, assets);

        uint shares = SavingsVaultProxy.previewWithdraw(maxAssetAmount);

        uint balanceOfUsdcBefore = usdc.balanceOf(usdcWhale);

        uint sharesBurned = SavingsVaultProxy.withdraw(maxAssetAmount, usdcWhale, usdcWhale);

        // There is some leftover of shares due to inability to estimate maxWithdraw amount with 100% accuracy
        // https://eips.ethereum.org/EIPS/eip-4626#maxwithdraw => MUST return the maximum amount of assets that could be transferred from owner
        // through withdraw and not cause a revert, which MUST NOT be higher than the actual maximum that would be accepted
        // (it should underestimate if necessary).
        assertEq(SavingsVaultProxy.balanceOf(usdcWhale), 535314264382);
        assertEq(sharesBurned, shares);
        assertEq(usdc.balanceOf(usdcWhale) - balanceOfUsdcBefore, maxAssetAmount - 56028848);

        SavingsVaultProxy.redeem(SavingsVaultProxy.balanceOf(usdcWhale), usdcWhale, usdcWhale);
        assertEq(SavingsVaultProxy.balanceOf(usdcWhale), 0);

        vm.stopPrank();
    }

    function testDepositFuzzing(uint assets) public {
        vm.assume(assets < 100_000 * 1e6 && assets > 1);

        vm.startPrank(usdcWhale);
        usdc.approve(address(SavingsVaultProxy), type(uint).max);

        // Initial deposit
        SavingsVaultProxy.deposit(1e6, usdcWhale);
        SavingsVaultProxy.harvest(type(uint).max);
        uint sharesInitialDeposit = SavingsVaultProxy.balanceOf(usdcWhale);
        uint feeRecipientBalanceBefore = SavingsVaultProxy.balanceOf(feeRecipient);
        uint usdcBalanceBefore = usdc.balanceOf(usdcWhale);

        uint blockTimestamp = block.timestamp;
        vm.warp(blockTimestamp + 1_000);
        uint sharesEstimated = SavingsVaultProxy.previewDeposit(assets);

        uint sharesWithoutFee = SavingsVaultProxy.convertToShares(assets);
        uint mintingFee = (sharesWithoutFee * SavingsVaultProxy.MINTING_FEE_IN_BP()) /
            (SavingsVaultProxy.BP() + SavingsVaultProxy.MINTING_FEE_IN_BP());
        uint aumFee = SavingsVaultProxy.getAUMFee(blockTimestamp + 1_000);

        // deposit to assert
        uint sharesReceived = SavingsVaultProxy.deposit(assets, usdcWhale);

        // depositor received exact number of shares and transferred exact usdc
        assertEq(sharesEstimated, sharesReceived);
        assertEq(usdcBalanceBefore - usdc.balanceOf(usdcWhale), assets);
        assertEq(SavingsVaultProxy.balanceOf(usdcWhale) - sharesInitialDeposit, sharesEstimated);

        // aum fee is newly minted, minting fee is subtracted from deposit
        assertEq(SavingsVaultProxy.balanceOf(feeRecipient) - feeRecipientBalanceBefore, mintingFee + aumFee);

        vm.stopPrank();
    }

    function testMintFuzzing(uint shares) public {
        vm.assume(shares < 100_000 * 1e6 && shares > 1);
        vm.startPrank(usdcWhale);
        usdc.approve(address(SavingsVaultProxy), type(uint).max);

        // Initial deposit/harvest
        SavingsVaultProxy.deposit(1e6, usdcWhale);
        SavingsVaultProxy.harvest(type(uint).max);
        uint feeRecipientBalanceBefore = SavingsVaultProxy.balanceOf(feeRecipient);
        uint sharesBalanceBefore = SavingsVaultProxy.balanceOf(usdcWhale);

        uint blockTimestamp = block.timestamp;
        vm.warp(blockTimestamp + 1_000);
        uint assetsEstimated = SavingsVaultProxy.previewMint(shares);

        uint mintingFee = (shares * SavingsVaultProxy.MINTING_FEE_IN_BP()) / 10_000;
        uint aumFee = SavingsVaultProxy.getAUMFee(blockTimestamp + 1_000);

        // deposit to assert
        uint assetsTransferred = SavingsVaultProxy.mint(shares, usdcWhale);

        // minter transferred usdc and received exact number of shares
        // https://eips.ethereum.org/EIPS/eip-4626#previewmint => small discrepancy is ok. previewMint MUST return
        // as close to and no fewer than the exact amount of assets that would be deposited in a mint call in the same transaction.
        //I.e. mint should return the same or fewer assets as previewMint if called in the same transaction.
        assertLt(assetsEstimated - assetsTransferred, 5);
        assertEq(SavingsVaultProxy.balanceOf(usdcWhale) - sharesBalanceBefore, shares);

        // aum fee is newly minted, minting fee is added on top of shares amount
        assertEq(SavingsVaultProxy.balanceOf(feeRecipient) - feeRecipientBalanceBefore, mintingFee + aumFee);

        vm.stopPrank();
    }

    function testCrossRedeemWithdraw() public {
        uint assets = 100_000 * 1e6;

        vm.startPrank(usdcWhale);
        usdc.approve(address(SavingsVaultProxy), type(uint).max);
        SavingsVaultProxy.deposit(assets, usdcWhale);
        SavingsVaultProxy.harvest(type(uint).max);

        uint assetsToWithdraw = 50_000 * 1e6;
        uint usdcBalanceBefore = usdc.balanceOf(usdcWhale);
        uint sharesBalanceBefore = SavingsVaultProxy.balanceOf(usdcWhale);
        uint feeRecipientBalanceBefore = SavingsVaultProxy.balanceOf(feeRecipient);

        uint fee = 250152290415505410775;
        uint sharesBurnt = 50280610373516587565893;

        assertEq(SavingsVaultProxy.previewRedeem(sharesBurnt), assetsToWithdraw - 26989708);
        assertEq(SavingsVaultProxy.previewWithdraw(assetsToWithdraw), sharesBurnt);

        uint snapshot = vm.snapshot();

        SavingsVaultProxy.withdraw(assetsToWithdraw, usdcWhale, usdcWhale);
        assertEq(SavingsVaultProxy.balanceOf(feeRecipient) - feeRecipientBalanceBefore, fee);
        // less assets are withdrawn that estimated due to slippage
        assertEq(usdc.balanceOf(usdcWhale) - usdcBalanceBefore, assetsToWithdraw - 26989707);
        assertEq(sharesBalanceBefore - SavingsVaultProxy.balanceOf(usdcWhale), sharesBurnt);

        vm.revertTo(snapshot);
        SavingsVaultProxy.redeem(sharesBurnt, usdcWhale, usdcWhale);
        assertEq(SavingsVaultProxy.balanceOf(feeRecipient) - feeRecipientBalanceBefore, fee + 1);
        // less assets are withdrawn that estimated due to slippage
        assertEq(usdc.balanceOf(usdcWhale) - usdcBalanceBefore, assetsToWithdraw - 26989708);
        assertEq(sharesBalanceBefore - SavingsVaultProxy.balanceOf(usdcWhale), sharesBurnt);

        vm.stopPrank();
    }

    function testCrossDepositMint() public {
        vm.startPrank(usdcWhale);
        usdc.approve(address(SavingsVaultProxy), type(uint).max);

        uint assetsToDeposit = 50_000 * 1e6;
        uint usdcBalanceBefore = usdc.balanceOf(usdcWhale);

        uint fee = 99800399201596806387;
        uint sharesMinted = 49900199600798403193613;

        assertEq(SavingsVaultProxy.previewMint(sharesMinted), assetsToDeposit);
        assertEq(SavingsVaultProxy.previewDeposit(assetsToDeposit), sharesMinted);

        uint snapshot = vm.snapshot();

        SavingsVaultProxy.deposit(assetsToDeposit, usdcWhale);
        assertEq(SavingsVaultProxy.balanceOf(feeRecipient), fee);
        assertEq(usdcBalanceBefore - usdc.balanceOf(usdcWhale), assetsToDeposit);
        assertEq(SavingsVaultProxy.balanceOf(usdcWhale), sharesMinted);

        vm.revertTo(snapshot);
        SavingsVaultProxy.mint(sharesMinted, usdcWhale);
        assertEq(SavingsVaultProxy.balanceOf(feeRecipient), fee);
        assertEq(usdcBalanceBefore - usdc.balanceOf(usdcWhale), assetsToDeposit);
        assertEq(SavingsVaultProxy.balanceOf(usdcWhale), sharesMinted);
        vm.stopPrank();
    }

    function testWithdrawalFromBothMaturities() public {
        vm.startPrank(usdcWhale);
        SavingsVaultProxy.setMaxLoss(0);

        // Deposit and harvest
        uint balanceBeforeDeposit = usdc.balanceOf(usdcWhale);
        uint amount = 10_000 * 1e6;
        usdc.approve(address(SavingsVaultProxy), type(uint).max);
        SavingsVaultProxy.deposit(amount, usdcWhale);
        SavingsVaultProxy.harvest(amount);
        vm.warp(block.timestamp + 1 days + 1);

        SavingsVaultProxy.deposit(amount, usdcWhale);
        ISavingsVault.NotionalMarket[] memory markets = SavingsVaultProxy.__getThreeAndSixMonthMarkets();
        MarketParameters[] memory mockedMarkets = new MarketParameters[](2);
        mockedMarkets[0] = getNotionalMarketParameters(markets[0].maturity, markets[1].oracleRate);
        mockedMarkets[1] = getNotionalMarketParameters(markets[1].maturity, markets[0].oracleRate);
        vm.mockCall(
            notionalRouter,
            abi.encodeWithSelector(NotionalViews.getActiveMarkets.selector, currencyId),
            abi.encode(mockedMarkets)
        );
        SavingsVaultProxy.harvest(amount);

        // Deposit some usdc without harvesting
        SavingsVaultProxy.deposit(6_000 * 1e6, usdcWhale);

        address[] memory positions = SavingsVaultProxy._fCashPositions();
        IWrappedfCashComplete lowestYieldFCash = IWrappedfCashComplete(positions[0]);
        IWrappedfCashComplete highestYieldFCash = IWrappedfCashComplete(positions[1]);

        // withdrawing from a single maturity
        SavingsVaultProxy.withdraw(amount / 2, usdcWhale, usdcWhale);
        assertEq(lowestYieldFCash.balanceOf(address(SavingsVaultProxy)), 1005021519000);
        assertEq(highestYieldFCash.balanceOf(address(SavingsVaultProxy)), 1009440472000);
        assertEq(usdc.balanceOf(address(SavingsVaultProxy)), 1000000015);

        // withdrawing from both maturities
        SavingsVaultProxy.redeem(SavingsVaultProxy.balanceOf(usdcWhale), usdcWhale, usdcWhale);

        assertEq(lowestYieldFCash.balanceOf(address(SavingsVaultProxy)), 0);
        assertEq(highestYieldFCash.balanceOf(address(SavingsVaultProxy)), 17744358555);
        assertEq(SavingsVaultProxy.balanceOf(usdcWhale), 0);
        assertEq(usdc.balanceOf(address(SavingsVaultProxy)), 0);

        uint balanceAfterWithdrawal = usdc.balanceOf(usdcWhale);
        // User losses certain amount of USDC due to slippage
        assertEq(balanceBeforeDeposit - balanceAfterWithdrawal, 211920397);

        vm.stopPrank();
    }

    function testAssetWithDifferentDecimals() public {
        ERC20Upgradeable dai = ERC20Upgradeable(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
        MockSavingsVault daiSavingsVault = MockSavingsVault(
            address(
                new ERC1967Proxy(
                    address(new MockSavingsVault()),
                    abi.encodeWithSelector(
                        SavingsVaultImpl.initialize.selector,
                        "Dai Savings Vault",
                        "DAI_SAVINGS_VAULT",
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
        address daiWhale = address(0x5D38B4e4783E34e2301A2a36c39a03c45798C4dD);
        daiSavingsVault.grantRole(keccak256("VAULT_MANAGER_ROLE"), msg.sender);
        daiSavingsVault.grantRole(keccak256("HARVESTER_ROLE"), daiWhale);

        vm.startPrank(daiWhale);
        uint amount = 10_000 * 1e18;
        dai.approve(address(daiSavingsVault), type(uint).max);
        daiSavingsVault.deposit(amount, daiWhale);
        daiSavingsVault.harvest(amount);

        assertEq(dai.balanceOf(address(daiSavingsVault)), 2470000000000);

        IWrappedfCashComplete highestYieldFCash = IWrappedfCashComplete(daiSavingsVault._fCashPositions()[1]);

        uint estimatedShares = daiSavingsVault.previewWithdraw(amount / 2);

        uint shares = daiSavingsVault.withdraw(amount / 2, daiWhale, daiWhale);
        assertEq(shares, estimatedShares);
        assertEq(highestYieldFCash.balanceOf(address(daiSavingsVault)), 506450873211);
        assertEq(dai.balanceOf(address(daiSavingsVault)), 0);

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
        (
            ISavingsVault.NotionalMarket memory lowestYieldMarket,
            ISavingsVault.NotionalMarket memory highestYieldMarket
        ) = SavingsVaultProxy.sortMarketsByOracleRate();

        assertEq(lowestYieldMarket.maturity, threeMonthMaturity);
        assertEq(highestYieldMarket.maturity, sixMonthMaturity);
    }

    function testUpgradeability() public {
        vm.startPrank(setupMsgSender);
        SavingsVaultProxy.upgradeTo(address(new SavingsVault()));
    }

    function testFailsUpgradeWithoutRole() public {
        SavingsVaultProxy.upgradeTo(address(new SavingsVault()));
    }

    function testDepositWithPermit() public {
        vm.startPrank(usdcWhale);
        uint signerPrivateKey = 0xA11CE;
        address signer = vm.addr(signerPrivateKey);
        usdc.transfer(signer, 100_00e6);
        vm.stopPrank();

        SigUtils sigUtils = new SigUtils(ERC20PermitUpgradeable(address(usdc)).DOMAIN_SEPARATOR());

        uint assets = 100e6;
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: signer,
            spender: address(SavingsVaultProxy),
            value: assets,
            nonce: ERC20PermitUpgradeable(address(usdc)).nonces(signer),
            deadline: block.timestamp + 1 days
        });
        bytes32 digest = sigUtils.getTypedDataHash(permit);

        vm.startPrank(signer);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        SavingsVaultProxy.depositWithPermit(assets, signer, permit.deadline, v, r, s);
        vm.stopPrank();

        assertEq(SavingsVaultProxy.balanceOf(signer), 99800399201596806388);
    }

    function testStorage() public {
        address cont = address(SavingsVaultProxy);
        bytes32 zeroValue = 0x0000000000000000000000000000000000000000000000000000000000000000;

        // 1st slot is occupied by Initializable =>  _initialized and _initializing;
        assertEq(load(cont, 0), bytes32(uint(1)));

        // Next 50 slots are _gap inside ContextUpgradeable contract
        for (uint i = 1; i < 51; i++) {
            assertEq(load(cont, i), zeroValue);
        }

        // Next 3 slots are _balances, _allowances, _totalSupply mappings inside ERC20Upgradeable
        for (uint i = 51; i < 54; i++) {
            assertEq(load(cont, i), zeroValue);
        }

        // Next slot is token name
        assertEq(load(cont, 54), 0x55534443204e6f74696f6e616c205661756c7400000000000000000000000026);

        // Next slot is token symbol
        assertEq(load(cont, 55), 0x555344435f5641554c5400000000000000000000000000000000000000000014);

        // Next 45 slots are _gap inside ERC20Upgradeable
        for (uint i = 56; i < 101; i++) {
            assertEq(load(cont, i), zeroValue);
        }

        // Next slot is the address of usdc inside ERC4626Upgradeable
        assertEq(load(cont, 101), 0x000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48);

        // Next 49 slots are _gap inside ERC4626Upgradeable
        for (uint i = 102; i < 151; i++) {
            assertEq(load(cont, i), zeroValue);
        }

        // Next slot is _HASHED_NAME inside EIP712Upgradeable
        assertEq(load(cont, 151), 0x318587b3a21ebf41642203d8f1916c85e928263edb04cf93c681903c93e27cc4);

        // Next slot is _HASHED_VERSION inside EIP712Upgradeable
        assertEq(load(cont, 152), 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6);

        // Next 50 slots are _gap inside EIP712Upgradeable
        for (uint i = 153; i < 203; i++) {
            assertEq(load(cont, i), zeroValue);
        }

        // Next slot is _nonces mapping inside ERC20PermitUpgradeable
        assertEq(load(cont, 203), zeroValue);

        // Next slot is _PERMIT_TYPEHASH_DEPRECATED_SLOT mapping inside ERC20PermitUpgradeable
        assertEq(load(cont, 204), zeroValue);

        // Next 49 slots are _gap inside ERC20PermitUpgradeable
        for (uint i = 205; i < 254; i++) {
            assertEq(load(cont, i), zeroValue);
        }

        // Next 50 slots are _gap inside ERC165Upgradeable
        for (uint i = 254; i < 304; i++) {
            assertEq(load(cont, i), zeroValue);
        }

        // Next slot is _roles mapping inside AccessControlUpgradeable
        assertEq(load(cont, 305), zeroValue);

        // Next 49 slots are _gap inside AccessControlUpgradeable
        for (uint i = 306; i < 355; i++) {
            assertEq(load(cont, i), zeroValue);
        }

        // Next 50 slots are _gap inside ERC1967UpgradeUpgradeable
        for (uint i = 355; i < 405; i++) {
            assertEq(load(cont, i), zeroValue);
        }

        // Next 50 slots are _gap inside UUPSUpgradeable
        for (uint i = 405; i < 454; i++) {
            assertEq(load(cont, i), zeroValue);
        }

        // Next slot is _status inside ReentrancyGuardUpgradeable
        assertEq(load(cont, 454), 0x0000000000000000000000000000000000000000000000000000000000000001);

        // Next 50 slots are _gap inside UUPSUpgradeable
        for (uint i = 455; i < 504; i++) {
            assertEq(load(cont, i), zeroValue);
        }

        // Next slot is timeout, currencyId, maxLoss and notionalRouter inside SavingsVault
        assertEq(
            load(address(SavingsVaultProxy), 504),
            0x00000000000000001344a36a1b56144c3bc62e7757377d288fde036923280003
        );

        // Next slot is wrappedfCashFactory inside SavingsVault
        assertEq(
            load(address(SavingsVaultProxy), 505),
            0x0000000000000000000000005d051deb5db151c2172dcdccd42e6a2953e27261
        );

        // Next slot is fCashPosition inside SavingsVault
        assertEq(
            load(address(SavingsVaultProxy), 506),
            0x000000000000000000000000f1e1a4213f241d8fe23990fc16e14eaf37a27028
        );

        // Next slot is fCashPosition inside SavingsVault
        assertEq(
            load(address(SavingsVaultProxy), 507),
            0x00000000000000000000000069c6b313506684f49c564b48bf0e4d41c0cb1a3e
        );

        // Next slot is lastTransferTime and feeRecipient inside SavingsVault
        assertEq(
            load(address(SavingsVaultProxy), 508),
            0x000000000000000000000000000000000000abcd000000000000000062d68ebe
        );
    }

    function testMaxImpliedRateFuzzing(uint16 _maxLoss) public {
        vm.assume(_maxLoss < 10_000 && _maxLoss > 0);
        vm.startPrank(usdcWhale);
        SavingsVaultProxy.setMaxLoss(_maxLoss);
        assertLt(SavingsVaultProxy.__getMaxImpliedRate(311111111), type(uint32).max);
        vm.stopPrank();
    }

    function testMaxImpliedRate() public {
        vm.startPrank(usdcWhale);
        SavingsVaultProxy.setMaxLoss(0);
        assertEq(SavingsVaultProxy.__getMaxImpliedRate(311111111), type(uint32).max);
        SavingsVaultProxy.setMaxLoss(9500);
        assertEq(SavingsVaultProxy.__getMaxImpliedRate(type(uint32).max), type(uint32).max);
    }

    function testredeem() public {
        vm.startPrank(usdcWhale);
        usdc.approve(address(SavingsVaultProxy), type(uint).max);
        SavingsVaultProxy.deposit(100_000 * 1e6, usdcWhale);
        SavingsVaultProxy.harvest(type(uint).max);
        SavingsVaultProxy.redeem(100_000 * 1e6, usdcWhale, usdcWhale, 0);
        SavingsVaultProxy.redeem(100_000 * 1e6, usdcWhale, usdcWhale, 10_000);
        vm.expectRevert(bytes("Max_loss"));
        SavingsVaultProxy.redeem(100_000 * 1e6, usdcWhale, usdcWhale, 10_001);
        SavingsVaultProxy.redeem(SavingsVaultProxy.balanceOf(usdcWhale), usdcWhale, usdcWhale, 9200);
        vm.stopPrank();
    }

    // Notional tests

    function testGetfCashLendFromDeposit(uint32 minImpliedRate) public {
        uint assets = 5_000_000 * 1e6;
        vm.assume(minImpliedRate < type(uint32).max && minImpliedRate > 0);
        INotionalV2 calculationViews = INotionalV2(notionalRouter);
        address[] memory positions = SavingsVaultProxy._fCashPositions();
        IWrappedfCashComplete fCash = IWrappedfCashComplete(positions[0]);
        (uint fCashAmount, , ) = calculationViews.getfCashLendFromDeposit(
            currencyId,
            assets,
            fCash.getMaturity(),
            minImpliedRate,
            block.timestamp,
            true
        );
        // No price impact taken into account, always returns the same value
        assertGt(fCashAmount + 1, assets * 100);
    }

    function testFailsGetfCashLendFromDepositReverts(uint32 minImpliedRate) public {
        vm.assume(minImpliedRate < type(uint32).max && minImpliedRate > 0);
        INotionalV2 calculationViews = INotionalV2(notionalRouter);
        address[] memory positions = SavingsVaultProxy._fCashPositions();
        IWrappedfCashComplete fCash = IWrappedfCashComplete(positions[0]);
        // Function fails at around 6.3 million usdc
        (uint fCashAmount, , ) = calculationViews.getfCashLendFromDeposit(
            currencyId,
            6386110134609,
            fCash.getMaturity(),
            minImpliedRate,
            block.timestamp,
            true
        );
    }

    function testGetDepositFromfCashLend(uint32 minImpliedRate) public {
        vm.assume(minImpliedRate < 27309715 && minImpliedRate > 0);
        (, ISavingsVault.NotionalMarket memory highestYieldMarket) = SavingsVaultProxy.sortMarketsByOracleRate();
        IWrappedfCashComplete fCash = IWrappedfCashComplete(
            IWrappedfCashFactory(wrappedfCashFactory).deployWrapper(currencyId, uint40(highestYieldMarket.maturity))
        );
        // Trade fails at 27_309_715
        uint fCashAmount = 1_000_000 * 1e8;
        (uint amountUnderlyingSlippage, , , ) = INotionalV2(notionalRouter).getDepositFromfCashLend(
            currencyId,
            fCashAmount,
            fCash.getMaturity(),
            minImpliedRate,
            block.timestamp
        );
        // below the rate it fails it always returns the same cash amount
        assertEq(amountUnderlyingSlippage, 995450937379);

        // Trying to buy the actual fCash
        vm.startPrank(usdcWhale);
        usdc.approve(address(fCash), 995450937379);
        fCash.mintViaUnderlying(995450937379, 1_000_000 * 1e8, usdcWhale, 27309714);
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

    function load(address cont, uint position) internal returns (bytes32 slot) {
        slot = vm.load(cont, bytes32(uint256(position)));
    }
}
