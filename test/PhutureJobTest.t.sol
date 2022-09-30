// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import { IWrappedfCashComplete, IWrappedfCash } from "../src/external/notional/interfaces/IWrappedfCash.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "./mocks/MockSavingsVault.sol";
import "../src/SavingsVault.sol";
import "../src/interfaces/ISavingsVault.sol";
import "../src/SavingsVaultViews.sol";
import "../src/JobConfig.sol";
import "../src/PhutureJob.sol";
import "../src/external/interfaces/IKeep3r.sol";
import "./mocks/Keepr3rMock.sol";

contract PhutureJobTest is Test {
    using stdStorage for StdStorage;
    using Address for address;

    string name = "USDC Notional Vault";
    string symbol = "USDC_VAULT";
    uint16 currencyId = 3;
    uint16 maxLoss = 9900;

    address notionalRouter = address(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    address usdcWhale = address(0x0A59649758aa4d66E25f08Dd01271e891fe52199);
    ERC20Upgradeable usdc = ERC20Upgradeable(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));

    MockSavingsVault savingsVaultImpl;
    MockSavingsVault savingsVaultProxy;

    SavingsVaultViews views;
    JobConfig jobConfig;
    PhutureJob phutureJob;
    IKeep3r keep3r;

    address wrappedfCashFactory = address(0x5D051DeB5db151C2172dCdCCD42e6A2953E27261);
    address feeRecipient = address(0xABCD);

    string mainnetHttpsUrl;
    uint mainnetFork;
    uint blockNumber;

    function setUp() public {
        mainnetHttpsUrl = vm.envString("MAINNET_HTTPS_URL");
        blockNumber = 15_637_559;
        mainnetFork = vm.createSelectFork(mainnetHttpsUrl, blockNumber);

        savingsVaultImpl = new MockSavingsVault();
        savingsVaultProxy = MockSavingsVault(
            address(
                new ERC1967Proxy(
                    address(savingsVaultImpl),
                    abi.encodeWithSelector(
                        savingsVaultImpl.initialize.selector,
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
        views = new SavingsVaultViews();
        jobConfig = new JobConfig(views);
        keep3r = new Keepr3rMock();
        phutureJob = new PhutureJob(address(keep3r), address(jobConfig));
        // Default msg.sender inside all functions is: 0x00a329c0648769a73afac7f9381e08fb43dbea72,
        // msg.sender inside setUp is 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
        savingsVaultProxy.grantRole(keccak256("VAULT_MANAGER_ROLE"), msg.sender);
        savingsVaultProxy.grantRole(keccak256("VAULT_MANAGER_ROLE"), usdcWhale);
        phutureJob.grantRole(keccak256("JOB_MANAGER_ROLE"), msg.sender);
        phutureJob.grantRole(keccak256("JOB_MANAGER_ROLE"), address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84));
        phutureJob.grantRole(keccak256("JOB_MANAGER_ROLE"), usdcWhale);
        phutureJob.unpause();
    }

    function testInitialization() public {
        assertEq(phutureJob.jobConfig(), address(jobConfig));
        assertEq(phutureJob.keep3r(), address(keep3r));
        assertFalse(phutureJob.paused());
    }

    function testCannotHarvest() public {
        vm.startPrank(feeRecipient);
        vm.expectRevert(
            bytes(
                "AccessControl: account 0x000000000000000000000000000000000000abcd is missing role 0x9314fad2def8e56f9df1fa7f30dc3dafd695603f8f7676a295739a12b879d2f6"
            )
        );
        console.logBytes32(keccak256("JOB_MANAGER_ROLE"));
        phutureJob.harvestWithPermission(address(savingsVaultProxy));
        vm.stopPrank();

        phutureJob.setTimeout(5, address(savingsVaultProxy));
        vm.startPrank(usdcWhale);
        usdc.approve(address(savingsVaultProxy), type(uint).max);
        savingsVaultProxy.deposit(10_000 * 1e6, usdcWhale);
        phutureJob.harvest(address(savingsVaultProxy));
        savingsVaultProxy.redeem(savingsVaultProxy.balanceOf(usdcWhale), usdcWhale, usdcWhale);
        vm.stopPrank();

        // cannot harvest if TIMEOUT
        vm.expectRevert(bytes("PhutureJob: TIMEOUT"));
        phutureJob.harvest(address(savingsVaultProxy));
    }

    function testScaledAmount() public {
        address savingsVault = address(savingsVaultProxy);
        phutureJob.setTimeout(0, address(savingsVaultProxy));
        jobConfig.setHarvestingAmountSpecification(IJobConfig.HarvestingSpecification.SCALED_AMOUNT);

        vm.startPrank(usdcWhale);
        usdc.approve(address(savingsVaultProxy), type(uint).max);

        // harvesting on zero reserves
        vm.expectRevert(bytes("PhutureJob: ZERO"));
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), 0);

        // harvests without scaling
        savingsVaultProxy.deposit(10_000 * 1e6, usdcWhale);
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), block.timestamp);
        assertEq(usdc.balanceOf(savingsVault), 8);
        vm.warp(block.timestamp + 10);

        // harvests with scaling
        savingsVaultProxy.deposit(100_000 * 1e6, usdcWhale);
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), block.timestamp);
        assertEq(usdc.balanceOf(savingsVault), 30003968581);

        // harvests fails due to slippage constraint too strict
        savingsVaultProxy.setMaxLoss(9990);
        savingsVaultProxy.deposit(100_000 * 1e6, usdcWhale);
        vm.expectRevert(bytes("PhutureJob: ZERO"));
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), block.timestamp);
        assertEq(usdc.balanceOf(savingsVault), 130003968581);

        // harvests with scaling
        savingsVaultProxy.setMaxLoss(9500);
        savingsVaultProxy.deposit(900_000 * 1e6, usdcWhale);
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), block.timestamp);
        assertEq(usdc.balanceOf(savingsVault), 927185576203);
    }

    function testBinarySearchScaled() public {
        address savingsVault = address(savingsVaultProxy);
        phutureJob.setTimeout(0, address(savingsVaultProxy));

        vm.startPrank(usdcWhale);
        usdc.approve(address(savingsVaultProxy), type(uint).max);

        uint snapshot = vm.snapshot();

        // harvesting on zero reserves
        vm.expectRevert(bytes("PhutureJob: ZERO"));
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), 0);

        // harvests without scaling
        savingsVaultProxy.deposit(10_000 * 1e6, usdcWhale);
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), block.timestamp);
        assertEq(usdc.balanceOf(savingsVault), 8);
        vm.warp(block.timestamp + 10);

        // harvests with scaling
        savingsVaultProxy.deposit(100_000 * 1e6, usdcWhale);
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), block.timestamp);
        assertEq(usdc.balanceOf(savingsVault), 25540703051);

        // harvests fails due to slippage constraint too strict
        savingsVaultProxy.setMaxLoss(9990);
        savingsVaultProxy.deposit(100_000 * 1e6, usdcWhale);
        vm.expectRevert(bytes("PhutureJob: ZERO"));
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), block.timestamp);
        assertEq(usdc.balanceOf(savingsVault), 125540703051);

        // harvests with scaling
        savingsVaultProxy.setMaxLoss(9500);
        savingsVaultProxy.deposit(900_000 * 1e6, usdcWhale);
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), block.timestamp);
        assertEq(usdc.balanceOf(savingsVault), 688978025768);

        uint usdcAmount = 5_000_000 * 1e6;

        // harvests with scaling 1% slippage
        vm.revertTo(snapshot);
        savingsVaultProxy.setMaxLoss(9990);
        savingsVaultProxy.deposit(usdcAmount, usdcWhale);
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), block.timestamp);
        uint usdcBalanceAfterHarvest = usdc.balanceOf(savingsVault);
        assertEq(usdcBalanceAfterHarvest, 4992752034490);
        // Amount which was actually harvested
        assertEq(usdcAmount - usdcBalanceAfterHarvest, 7247965510);
    }

    function testBinarySearchZeroPointZeroFivePercent() public {
        address savingsVault = address(savingsVaultProxy);
        phutureJob.setTimeout(0, address(savingsVaultProxy));
        jobConfig.setHarvestingAmountSpecification(IJobConfig.HarvestingSpecification.BINARY_SEARCH_SCALED_AMOUNT);
        uint usdcAmount = 5_000_000 * 1e6;
        vm.startPrank(usdcWhale);
        savingsVaultProxy.setMaxLoss(9995);
        usdc.approve(address(savingsVaultProxy), type(uint).max);
        savingsVaultProxy.deposit(usdcAmount, usdcWhale);
        phutureJob.harvest(savingsVault);
        uint usdcBalanceAfterHarvest = usdc.balanceOf(savingsVault);
        assertEq(usdcBalanceAfterHarvest, 4997584033535);
        assertEq(usdcAmount - usdcBalanceAfterHarvest, 2415966465); // 2.4k usdc pushed to Notional
        vm.stopPrank();
    }

    function testBinarySearchZeroPointOnePercent() public {
        address savingsVault = address(savingsVaultProxy);
        phutureJob.setTimeout(0, address(savingsVaultProxy));
        jobConfig.setHarvestingAmountSpecification(IJobConfig.HarvestingSpecification.BINARY_SEARCH_SCALED_AMOUNT);
        uint usdcAmount = 5_000_000 * 1e6;
        vm.startPrank(usdcWhale);
        savingsVaultProxy.setMaxLoss(9990);
        usdc.approve(address(savingsVaultProxy), type(uint).max);
        savingsVaultProxy.deposit(usdcAmount, usdcWhale);
        phutureJob.harvest(savingsVault);
        uint usdcBalanceAfterHarvest = usdc.balanceOf(savingsVault);
        assertEq(usdcBalanceAfterHarvest, 4992752034490);
        assertEq(usdcAmount - usdcBalanceAfterHarvest, 7247965510); // 7k usdc pushed to Notional
        vm.stopPrank();
    }

    function testBinarySearchOnePercent() public {
        address savingsVault = address(savingsVaultProxy);
        phutureJob.setTimeout(0, address(savingsVaultProxy));
        jobConfig.setHarvestingAmountSpecification(IJobConfig.HarvestingSpecification.BINARY_SEARCH_SCALED_AMOUNT);
        uint usdcAmount = 5_000_000 * 1e6;
        vm.startPrank(usdcWhale);
        savingsVaultProxy.setMaxLoss(9900);
        usdc.approve(address(savingsVaultProxy), type(uint).max);
        savingsVaultProxy.deposit(usdcAmount, usdcWhale);
        phutureJob.harvest(savingsVault);
        uint usdcBalanceAfterHarvest = usdc.balanceOf(savingsVault);
        assertEq(usdcBalanceAfterHarvest, 4917844769729);
        assertEq(usdcAmount - usdcBalanceAfterHarvest, 82155230271); // 82k usdc pushed to Notional
        vm.stopPrank();
    }

    function testBinarySearchTwoPercent() public {
        address savingsVault = address(savingsVaultProxy);
        phutureJob.setTimeout(0, address(savingsVaultProxy));
        jobConfig.setHarvestingAmountSpecification(IJobConfig.HarvestingSpecification.BINARY_SEARCH_SCALED_AMOUNT);
        uint usdcAmount = 5_000_000 * 1e6;
        vm.startPrank(usdcWhale);
        savingsVaultProxy.setMaxLoss(9800);
        usdc.approve(address(savingsVaultProxy), type(uint).max);
        savingsVaultProxy.deposit(usdcAmount, usdcWhale);
        phutureJob.harvest(savingsVault);
        uint usdcBalanceAfterHarvest = usdc.balanceOf(savingsVault);
        assertEq(usdcBalanceAfterHarvest, 4833246546902);
        assertEq(usdcAmount - usdcBalanceAfterHarvest, 166753453098); // 166k usdc
        vm.stopPrank();
    }

    function testBinarySearchThreePercent() public {
        address savingsVault = address(savingsVaultProxy);
        phutureJob.setTimeout(0, address(savingsVaultProxy));
        jobConfig.setHarvestingAmountSpecification(IJobConfig.HarvestingSpecification.BINARY_SEARCH_SCALED_AMOUNT);
        uint usdcAmount = 5_000_000 * 1e6;
        vm.startPrank(usdcWhale);
        savingsVaultProxy.setMaxLoss(9700);
        usdc.approve(address(savingsVaultProxy), type(uint).max);
        savingsVaultProxy.deposit(usdcAmount, usdcWhale);
        phutureJob.harvest(savingsVault);
        uint usdcBalanceAfterHarvest = usdc.balanceOf(savingsVault);
        assertEq(usdcBalanceAfterHarvest, 4748621214849);
        assertEq(usdcAmount - usdcBalanceAfterHarvest, 251378785151); // 251k usdc
        vm.stopPrank();
    }

    function testBinarySearchThreePercentFuzzing(uint assets) public {
        address savingsVault = address(savingsVaultProxy);
        phutureJob.setTimeout(0, address(savingsVaultProxy));
        jobConfig.setHarvestingAmountSpecification(IJobConfig.HarvestingSpecification.MAX_DEPOSITED_AMOUNT);
        vm.startPrank(usdcWhale);
        savingsVaultProxy.setMaxLoss(9700);
        usdc.approve(address(savingsVaultProxy), type(uint).max);
        savingsVaultProxy.deposit(253178436187, usdcWhale); // this is the maximum amount available to deposit 253K usdc
        phutureJob.harvest(savingsVault);
        vm.stopPrank();
    }

    function testSetHarvestingSpecification() public {
        jobConfig.setHarvestingAmountSpecification(IJobConfig.HarvestingSpecification.MAX_AMOUNT);
        IJobConfig.HarvestingSpecification spec = jobConfig.harvestingSpecification();
        assertEq(uint(spec), uint(IJobConfig.HarvestingSpecification.MAX_AMOUNT));
    }

    function testSetTimeout() public {
        console.logBytes32(keccak256("VAULT_MANAGER_ROLE"));
        phutureJob.setTimeout(5, address(savingsVaultProxy));
        assertEq(phutureJob.timeout(address(savingsVaultProxy)), 5);
    }

    function testUpgrading() public {
        vm.createSelectFork(mainnetHttpsUrl, 15644824);

        vm.startPrank(0x56EbC6ed25ba2614A3eAAFFEfC5677efAc36F95f);
        SavingsVault savingsVault = SavingsVault(address(0x6bAD6A9BcFdA3fd60Da6834aCe5F93B8cFed9598));
        SavingsVault newImpl = new SavingsVault();
        savingsVault.upgradeTo(address(0x564B7462b0BEfbc0296b1230CB5Ca8753D633F9A));
        address[2] memory positions = savingsVault.getfCashPositions();
        console.log("fCash 0: %s", positions[0]);
        console.log("fCash 1: %s", positions[1]);
        vm.stopPrank();

        vm.startPrank(usdcWhale);
        SavingsVaultViews views = SavingsVaultViews(0xE574beBdDB460e3E0588F1001D24441102339429);
        JobConfig jobConfig = JobConfig(0x848c8b8b1490E9799Dbe4fe227545f33C0456E08);
        Keepr3rMock keep3r = new Keepr3rMock();
        PhutureJob phutureJob = new PhutureJob(address(keep3r), address(jobConfig));
        phutureJob.grantRole(keccak256("JOB_MANAGER_ROLE"), usdcWhale);

        usdc.approve(address(savingsVault), type(uint256).max);
        savingsVault.deposit(1_000_000 * 1e6, usdcWhale);
        console.log("totalAssets are: ", savingsVault.totalAssets());

        vm.expectRevert(bytes("Trade failed, slippage"));
        savingsVault.harvest(type(uint256).max);
        console.log("scaledAmount with binary search is: ", jobConfig.getDepositedAmount(address(savingsVault)));
        phutureJob.harvestWithPermission(address(savingsVault));
        console.log("usdc balance after harvest is: ", usdc.balanceOf(address(savingsVault)));

        positions = savingsVault.getfCashPositions();
        console.log("fCash 0: %s", positions[0]);
        console.log("fCash 1: %s", positions[1]);
        console.log("highest yield fCash is: ", IWrappedfCashComplete(positions[1]).balanceOf(address(savingsVault)));
        savingsVault.redeem(savingsVault.balanceOf(usdcWhale), usdcWhale, usdcWhale);
        console.log("totalAssets are: ", savingsVault.totalAssets());
        console.log(savingsVault.previewRedeem(savingsVault.balanceOf(usdcWhale)));
        vm.expectRevert(bytes("SavingsVault: MAX"));
        savingsVault.redeem(1, usdcWhale, usdcWhale);
        vm.stopPrank();
    }
}
