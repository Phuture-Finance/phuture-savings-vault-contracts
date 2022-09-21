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
        blockNumber = 15_272_678;
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
                        feeRecipient,
                        1 days
                    )
                )
            )
        );
        views = new SavingsVaultViews();
        jobConfig = new JobConfig(views);
        keep3r = new Keepr3rMock();
        phutureJob = new PhutureJob(address(keep3r), address(jobConfig));
        phutureJob.unpause();
        // Default msg.sender inside all functions is: 0x00a329c0648769a73afac7f9381e08fb43dbea72,
        // msg.sender inside setUp is 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
        savingsVaultProxy.grantRole(keccak256("VAULT_MANAGER_ROLE"), msg.sender);
        savingsVaultProxy.grantRole(keccak256("VAULT_MANAGER_ROLE"), usdcWhale);
    }

    function testInitialization() public {
        assertEq(phutureJob.jobConfig(), address(jobConfig));
        assertEq(phutureJob.keep3r(), address(keep3r));
        assertFalse(phutureJob.paused());
    }

    function testCannotHarvest() public {
        phutureJob.setTimeout(5, address(savingsVaultProxy));
        vm.startPrank(usdcWhale);
        usdc.approve(address(savingsVaultProxy), type(uint).max);
        savingsVaultProxy.deposit(10_000 * 1e6, usdcWhale);
        phutureJob.harvest(address(savingsVaultProxy));
        savingsVaultProxy.redeem(savingsVaultProxy.balanceOf(usdcWhale), usdcWhale, usdcWhale);
        vm.stopPrank();

        // cannot harvest if TIMEOUT
        vm.expectRevert(bytes("PhutureJob:TIMEOUT"));
        phutureJob.harvest(address(savingsVaultProxy));
    }

    function testScaledAmount() public {
        address savingsVault = address(savingsVaultProxy);
        phutureJob.setTimeout(0, address(savingsVaultProxy));

        vm.startPrank(usdcWhale);
        usdc.approve(address(savingsVaultProxy), type(uint).max);

        // harvesting on zero reserves
        vm.expectRevert(bytes("PhutureJob:NOTHING_TO_DEPOSIT"));
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), 0);

        // harvests without scaling
        savingsVaultProxy.deposit(10_000 * 1e6, usdcWhale);
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), block.timestamp);
        assertEq(usdc.balanceOf(savingsVault), 8);
        vm.warp(block.timestamp + 10);

        // harvests without scaling
        savingsVaultProxy.deposit(100_000 * 1e6, usdcWhale);
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), block.timestamp);
        assertEq(usdc.balanceOf(savingsVault), 67);

        // harvests fails due to slippage constraint too strict
        savingsVaultProxy.setMaxLoss(9990);
        savingsVaultProxy.deposit(100_000 * 1e6, usdcWhale);
        vm.expectRevert(bytes("PhutureJob:NOTHING_TO_DEPOSIT"));
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), block.timestamp);
        assertEq(usdc.balanceOf(savingsVault), 100000000067);

        // harvests with scaling
        savingsVaultProxy.setMaxLoss(9500);
        savingsVaultProxy.deposit(900_000 * 1e6, usdcWhale);
        phutureJob.harvest(savingsVault);
        assertEq(phutureJob.lastHarvest(savingsVault), block.timestamp);
        assertEq(usdc.balanceOf(savingsVault), 600080593772);
    }

    function testSetHarvestingSpecification() public {
        jobConfig.setHarvestingAmountSpecification(IJobConfig.HarvestingSpecification.MAX_AMOUNT);
        IJobConfig.HarvestingSpecification spec = jobConfig.harvestingSpecification();
        assertEq(uint(spec), uint(IJobConfig.HarvestingSpecification.MAX_AMOUNT));
    }

    function testSetTimeout() public {
        phutureJob.setTimeout(5, address(savingsVaultProxy));
        assertEq(phutureJob.timeout(address(savingsVaultProxy)), 5);
    }
}
