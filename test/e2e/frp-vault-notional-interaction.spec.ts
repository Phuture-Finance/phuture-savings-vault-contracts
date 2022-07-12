import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { BigNumber } from 'ethers'
import { ethers } from 'hardhat'
import * as mainnetConfig from '../../eth_mainnet.json'
import {
  FrpVault,
  FrpVaultLowestYieldWithdrawal__factory,
  FrpVaultMaturity__factory,
  FrpVault__factory,
  IERC20,
  IERC20__factory,
  WrappedfCashFactory
} from '../../typechain-types'
import { getStorageAt, impersonate, mineBlocks, reset, setBalance, snapshot } from '../../utils/evm'
import { expandTo18Decimals, expandTo6Decimals, newProxyContract } from '../../utils/helpers'
import { deployWrappedfCashFactory, upgradeNotionalProxy } from '../../utils/notional-fixtures'
import { VAULT_MANAGER_ROLE } from '../../utils/roles'

describe('FrpVault interaction with wrappedFCash [ @forked-mainnet]', function () {
  this.timeout(1e8)
  let signer: SignerWithAddress
  let usdcWhale: SignerWithAddress

  let USDC: IERC20

  let wrappedFCashFactory: WrappedfCashFactory
  let frpVault: FrpVault

  let snapshotId: string

  before(async () => {
    ;[signer] = await ethers.getSigners()

    await reset({
      jsonRpcUrl: process.env.MAINNET_HTTPS_URL,
      blockNumber: 14_990_487
    })

    usdcWhale = await impersonate(mainnetConfig.whales.USDC)
    await setBalance(usdcWhale.address, expandTo18Decimals(1_000_000))

    USDC = IERC20__factory.connect(mainnetConfig.USDC, usdcWhale)
    await USDC.transfer(signer.address, expandTo6Decimals(1000))

    await upgradeNotionalProxy(signer)
    wrappedFCashFactory = await deployWrappedfCashFactory(signer)

    frpVault = await newProxyContract(new FrpVault__factory(signer), [
      'USDC Notional Vault',
      'USDC_VAULT',
      mainnetConfig.USDC,
      mainnetConfig.notional.currencyIdUSDC,
      wrappedFCashFactory.address,
      mainnetConfig.notional.router,
      200
    ])

    await frpVault.grantRole(VAULT_MANAGER_ROLE, signer.address)

    await USDC.connect(usdcWhale).approve(frpVault.address, ethers.constants.MaxUint256)
    await USDC.connect(signer).approve(frpVault.address, ethers.constants.MaxUint256)

    snapshotId = await snapshot.take()
  })

  beforeEach(async function () {
    this.timeout(50_000)
    await snapshot.revert(snapshotId)
  })

  context('upgradeability', () => {
    it('fails if trying to reinitialize frpVault', async () => {
      await expect(
        frpVault.initialize(
          'USDC Notional Vault',
          'USDC_VAULT',
          mainnetConfig.USDC,
          mainnetConfig.notional.currencyIdUSDC,
          wrappedFCashFactory.address,
          mainnetConfig.notional.router,
          200
        )
      ).to.be.revertedWith('Initializable: contract is already initialized')
    })
    it('upgrades to new implementation', async () => {
      const newImpl = await new FrpVault__factory(signer).deploy()
      await frpVault.upgradeTo(newImpl.address)
    })
  })

  it('harvest/withdrawal flow', async () => {
    const amount = 100
    const usdcAmount = expandTo6Decimals(amount)
    const allowedDeviationPercent = 1

    // usdcWhale deposits USDC

    const shares = await frpVault.previewDeposit(usdcAmount)
    await frpVault.connect(usdcWhale).deposit(usdcAmount, usdcWhale.address)

    expect(expandTo18Decimals(amount)).to.be.eq(shares)
    expect(expandTo18Decimals(amount)).to.be.eq(await frpVault.balanceOf(usdcWhale.address))

    // signer deposits usdc
    const depositTx = await frpVault.deposit(usdcAmount, signer.address)
    const depositRecipient = await depositTx.wait()
    console.log('gas used during deposit', depositRecipient.gasUsed.toString())

    expect(expandTo18Decimals(amount)).to.be.eq(await frpVault.balanceOf(signer.address))
    expect(await frpVault.totalAssets()).to.be.eq(usdcAmount.mul(2))

    const harvestTx = await frpVault.harvest({ gasLimit: 30e6 })
    const harvestRecipient = await harvestTx.wait()
    console.log('gas used during harvest', harvestRecipient.gasUsed.toString())

    const usdcBalanceAfterHarvest = await frpVault.balanceOf(await frpVault.asset())
    await expect(usdcBalanceAfterHarvest).to.eq(0)

    // due to exchange losses shares are worth more
    const sharesAfterHarvest = await frpVault.previewDeposit(usdcAmount, {
      gasLimit: 30e6
    })
    expect(sharesAfterHarvest.sub(shares)).to.be.gte(
      BigNumber.from(86_624)
        .mul(100 - allowedDeviationPercent)
        .div(100)
    )

    const totalAssets = await frpVault.totalAssets()

    await mineBlocks(1000)

    // As time passes fCash appreciates in value
    // TODO: Review why there is some deviation
    const totalAssetsAfterNBlocks = await frpVault.totalAssets()
    expect(totalAssetsAfterNBlocks.sub(totalAssets)).to.be.gte(
      BigNumber.from(763)
        .mul(100 - allowedDeviationPercent)
        .div(100)
    )

    // usdcWhale deposits more USDC
    await frpVault.connect(usdcWhale).deposit(usdcAmount.mul(1000), usdcWhale.address, { gasLimit: 30e6 })

    const secHarvestTx = await frpVault.harvest({ gasLimit: 30e6 })
    const secHarvestRecipient = await secHarvestTx.wait()
    console.log('gas used during sec harvest', secHarvestRecipient.gasUsed.toString())

    await frpVault.connect(usdcWhale).approve(frpVault.address, ethers.constants.MaxUint256)
    await frpVault
      .connect(usdcWhale)
      ['withdraw(uint256,address,address)'](usdcAmount.mul(500), usdcWhale.address, usdcWhale.address, {
        gasLimit: 30e6
      })
  })

  it('harvest/withdrawal flow frpLowestYieldWithdrawal', async () => {
    const amount = 100
    const usdcAmount = expandTo6Decimals(amount)
    const allowedDeviationPercent = 1

    frpVault = await newProxyContract(new FrpVaultLowestYieldWithdrawal__factory(signer), [
      'USDC Notional Vault',
      'USDC_VAULT',
      mainnetConfig.USDC,
      mainnetConfig.notional.currencyIdUSDC,
      wrappedFCashFactory.address,
      mainnetConfig.notional.router,
      200
    ])

    // usdcWhale deposits USDC
    await USDC.connect(usdcWhale).approve(frpVault.address, ethers.constants.MaxUint256)
    await USDC.connect(signer).approve(frpVault.address, ethers.constants.MaxUint256)

    const shares = await frpVault.previewDeposit(usdcAmount)
    await frpVault.connect(usdcWhale).deposit(usdcAmount, usdcWhale.address)

    expect(expandTo18Decimals(amount)).to.be.eq(shares)
    expect(expandTo18Decimals(amount)).to.be.eq(await frpVault.balanceOf(usdcWhale.address))

    // signer deposits usdc
    const depositTx = await frpVault.deposit(usdcAmount, signer.address)
    const depositRecipient = await depositTx.wait()
    console.log('gas used during deposit', depositRecipient.gasUsed.toString())

    expect(expandTo18Decimals(amount)).to.be.eq(await frpVault.balanceOf(signer.address))
    expect(await frpVault.totalAssets()).to.be.eq(usdcAmount.mul(2))

    const harvestTx = await frpVault.harvest({ gasLimit: 30e6 })
    const harvestRecipient = await harvestTx.wait()
    console.log('gas used during harvest', harvestRecipient.gasUsed.toString())

    const usdcBalanceAfterHarvest = await frpVault.balanceOf(await frpVault.asset())
    await expect(usdcBalanceAfterHarvest).to.eq(0)

    // due to exchange losses shares are worth more
    const sharesAfterHarvest = await frpVault.previewDeposit(usdcAmount, {
      gasLimit: 30e6
    })
    expect(sharesAfterHarvest.sub(shares)).to.be.gte(
      BigNumber.from(86_624)
        .mul(100 - allowedDeviationPercent)
        .div(100)
    )

    const totalAssets = await frpVault.totalAssets()

    await mineBlocks(1000)

    // As time passes fCash appreciates in value
    // TODO: Review why there is some deviation
    const totalAssetsAfterNBlocks = await frpVault.totalAssets()
    expect(totalAssetsAfterNBlocks.sub(totalAssets)).to.be.gte(
      BigNumber.from(763)
        .mul(100 - allowedDeviationPercent)
        .div(100)
    )

    // usdcWhale deposits more USDC
    await frpVault.connect(usdcWhale).deposit(usdcAmount.mul(1000), usdcWhale.address, { gasLimit: 30e6 })

    const secHarvestTx = await frpVault.harvest({ gasLimit: 30e6 })
    const secHarvestRecipient = await secHarvestTx.wait()
    console.log('gas used during sec harvest', secHarvestRecipient.gasUsed.toString())

    await frpVault.connect(usdcWhale).approve(frpVault.address, ethers.constants.MaxUint256)
    const withdrawTx = await frpVault
      .connect(usdcWhale)
      ['withdraw(uint256,address,address)'](usdcAmount.mul(100), usdcWhale.address, usdcWhale.address, {
        gasLimit: 30e6
      })
    const withdrawRecipient = await withdrawTx.wait()
    console.log('gas used during withdrawal', withdrawRecipient.gasUsed.toString())

    // There is usdc dust remaining in the vault
    console.log('USDC balance in the frp:', await USDC.balanceOf(frpVault.address))
  })

  it('harvest/withdrawal flow frp sorted by maturity', async () => {
    const amount = 100
    const usdcAmount = expandTo6Decimals(amount)
    const allowedDeviationPercent = 1

    frpVault = await newProxyContract(new FrpVaultMaturity__factory(signer), [
      'USDC Notional Vault',
      'USDC_VAULT',
      mainnetConfig.USDC,
      mainnetConfig.notional.currencyIdUSDC,
      wrappedFCashFactory.address,
      mainnetConfig.notional.router,
      200
    ])
    // usdcWhale deposits USDC
    await USDC.connect(usdcWhale).approve(frpVault.address, ethers.constants.MaxUint256)
    await USDC.connect(signer).approve(frpVault.address, ethers.constants.MaxUint256)

    const shares = await frpVault.previewDeposit(usdcAmount)
    console.log('preview deposit gas cost is:', await frpVault.estimateGas.previewDeposit(usdcAmount))
    console.log('preview withdraw gas cost is:', await frpVault.estimateGas.previewWithdraw(usdcAmount))
    await frpVault.connect(usdcWhale).deposit(usdcAmount, usdcWhale.address)

    expect(expandTo18Decimals(amount)).to.be.eq(shares)
    expect(expandTo18Decimals(amount)).to.be.eq(await frpVault.balanceOf(usdcWhale.address))

    // signer deposits usdc
    const depositTx = await frpVault.deposit(usdcAmount, signer.address)
    const depositRecipient = await depositTx.wait()
    console.log('gas used during deposit', depositRecipient.gasUsed.toString())

    expect(expandTo18Decimals(amount)).to.be.eq(await frpVault.balanceOf(signer.address))
    expect(await frpVault.totalAssets()).to.be.eq(usdcAmount.mul(2))

    const harvestTx = await frpVault.harvest({ gasLimit: 30e6 })
    const harvestRecipient = await harvestTx.wait()
    console.log('gas used during harvest', harvestRecipient.gasUsed.toString())

    const usdcBalanceAfterHarvest = await frpVault.balanceOf(await frpVault.asset())
    await expect(usdcBalanceAfterHarvest).to.eq(0)

    // due to exchange losses shares are worth more
    const sharesAfterHarvest = await frpVault.previewDeposit(usdcAmount, {
      gasLimit: 30e6
    })
    expect(sharesAfterHarvest.sub(shares)).to.be.gte(
      BigNumber.from(86_624)
        .mul(100 - allowedDeviationPercent)
        .div(100)
    )

    const totalAssets = await frpVault.totalAssets()

    await mineBlocks(1000)

    // As time passes fCash appreciates in value
    // TODO: Review why there is some deviation
    const totalAssetsAfterNBlocks = await frpVault.totalAssets()
    expect(totalAssetsAfterNBlocks.sub(totalAssets)).to.be.gte(
      BigNumber.from(763)
        .mul(100 - allowedDeviationPercent)
        .div(100)
    )

    // usdcWhale deposits more USDC
    await frpVault.connect(usdcWhale).deposit(usdcAmount.mul(1000), usdcWhale.address, { gasLimit: 30e6 })

    const secHarvestTx = await frpVault.harvest({ gasLimit: 30e6 })
    const secHarvestRecipient = await secHarvestTx.wait()
    console.log('gas used during sec harvest', secHarvestRecipient.gasUsed.toString())

    await frpVault.connect(usdcWhale).approve(frpVault.address, ethers.constants.MaxUint256)
    const withdrawTx = await frpVault
      .connect(usdcWhale)
      ['withdraw(uint256,address,address)'](usdcAmount.mul(100), usdcWhale.address, usdcWhale.address, {
        gasLimit: 30e6
      })
    const withdrawRecipient = await withdrawTx.wait()
    console.log('gas used during withdrawal', withdrawRecipient.gasUsed.toString())

    // There is usdc dust remaining in the vault
    console.log('USDC balance in the frp:', await USDC.balanceOf(frpVault.address))
  })

  it('fails on harvest with large amounts', async () => {
    await frpVault.connect(usdcWhale).deposit(expandTo6Decimals(1_500_000), usdcWhale.address)
    await expect(frpVault.harvest({ gasLimit: 30e6 })).to.be.revertedWith('FrpVault: PRICE_IMPACT')
  })

  context('upgrading slippage', () => {
    it('fails', async () => {
      await expect(frpVault.connect(usdcWhale).setSlippage(20)).to.be.revertedWith('FrpVault: FORBIDDEN')
    })

    it('successfully', async () => {
      const newSlippage = 50
      await frpVault.connect(signer).setSlippage(newSlippage)
      const actualSlippage = await getStorageAt(frpVault, 458)
      await expect(BigNumber.from(actualSlippage)).to.eq(BigNumber.from(newSlippage))
    })
  })
})
