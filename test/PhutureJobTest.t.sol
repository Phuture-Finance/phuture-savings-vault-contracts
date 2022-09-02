// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import { IWrappedfCashComplete, IWrappedfCash } from "../src/external/notional/interfaces/IWrappedfCash.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "./mocks/MockFrpVault.sol";
import "../src/FRPVault.sol";
import "../src/interfaces/IFRPVault.sol";
import "../src/FRPViews.sol";
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

    MockFrpVault FRPVaultImpl;
    MockFrpVault FRPVaultProxy;

    FRPViews views;
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
                        feeRecipient,
                        1 days
                    )
                )
            )
        );
        views = new FRPViews();
        jobConfig = new JobConfig(address(views));
        keep3r = new Keepr3rMock();
        phutureJob = new PhutureJob(address(keep3r), address(jobConfig));
        phutureJob.unpause();
        // Default msg.sender inside all functions is: 0x00a329c0648769a73afac7f9381e08fb43dbea72,
        // msg.sender inside setUp is 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
        FRPVaultProxy.grantRole(keccak256("VAULT_MANAGER_ROLE"), msg.sender);
        FRPVaultProxy.grantRole(keccak256("HARVESTER_ROLE"), address(phutureJob));
        FRPVaultProxy.grantRole(keccak256("VAULT_MANAGER_ROLE"), usdcWhale);
    }

    function testInitialization() public {
        assertEq(phutureJob.jobConfig(), address(jobConfig));
        assertEq(phutureJob.keep3r(), address(keep3r));
        assertFalse(phutureJob.paused());
    }

    function testCannotHarvest() public {
        // cannot harvest if phuture job does not have a HARVESTER_ROLE
        FRPVaultProxy.revokeRole(keccak256("HARVESTER_ROLE"), address(phutureJob));
        vm.expectRevert(
            bytes(
                "AccessControl: account 0x0b7108e278c2e77e4e4f5c93d9e5e9a11ac837fc is missing role 0x3fc733b4d20d27a28452ddf0e9351aced28242fe03389a653cdb783955316b9b"
            )
        );
        phutureJob.harvest(FRPVaultProxy);

        // cannot harvest if TIMEOUT
        FRPVaultProxy.grantRole(keccak256("HARVESTER_ROLE"), address(phutureJob));
        phutureJob.harvest(FRPVaultProxy);
        vm.expectRevert(bytes("PhutureJob:TIMEOUT"));
        phutureJob.harvest(FRPVaultProxy);
    }

    function testScaledAmount() public {
        vm.startPrank(usdcWhale);
        FRPVaultProxy.setTimeout(0);
        usdc.approve(address(FRPVaultProxy), type(uint).max);

        // harvesting on zero reserves
        phutureJob.harvest(FRPVaultProxy);
        assertEq(FRPVaultProxy.lastHarvest(), block.timestamp);

        // harvests without scaling
        FRPVaultProxy.deposit(10_000 * 1e6, usdcWhale);
        phutureJob.harvest(FRPVaultProxy);
        assertEq(FRPVaultProxy.lastHarvest(), block.timestamp);
        assertEq(usdc.balanceOf(address(FRPVaultProxy)), 8);
        vm.warp(block.timestamp + 10);

        // harvests without scaling
        FRPVaultProxy.deposit(100_000 * 1e6, usdcWhale);
        phutureJob.harvest(FRPVaultProxy);
        assertEq(FRPVaultProxy.lastHarvest(), block.timestamp);
        assertEq(usdc.balanceOf(address(FRPVaultProxy)), 67);

        // harvests fails due to slippage constraint too strict
        FRPVaultProxy.setMaxLoss(9990);
        FRPVaultProxy.deposit(100_000 * 1e6, usdcWhale);
        phutureJob.harvest(FRPVaultProxy);
        assertEq(FRPVaultProxy.lastHarvest(), block.timestamp);
        assertEq(usdc.balanceOf(address(FRPVaultProxy)), 100000000067);

        // harvests with scaling
        FRPVaultProxy.setMaxLoss(9500);
        FRPVaultProxy.deposit(900_000 * 1e6, usdcWhale);
        phutureJob.harvest(FRPVaultProxy);
        assertEq(FRPVaultProxy.lastHarvest(), block.timestamp);
        assertEq(usdc.balanceOf(address(FRPVaultProxy)), 600080593772);
    }
}
