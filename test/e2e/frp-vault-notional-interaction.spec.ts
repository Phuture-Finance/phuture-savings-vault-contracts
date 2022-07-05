import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { BigNumber } from 'ethers'
import { ethers } from 'hardhat'
import * as mainnetConfig from '../../eth_mainnet.json'
import { FRPVault, FRPVault__factory, IERC20, IERC20__factory, WrappedfCashFactory } from '../../typechain-types'
import { getStorageAt, impersonate, mineBlocks, reset, setBalance, snapshot } from '../../utils/evm'
import { expandTo18Decimals, expandTo6Decimals } from '../../utils/helpers'
import { deployWrappedfCashFactory, upgradeNotionalProxy } from '../../utils/notional-fixtures'
import { VAULT_MANAGER_ROLE } from '../../utils/roles'

describe('FrpVault interaction with wrappedFCash [ @forked-mainnet]', function () {
  this.timeout(1e8)
  let signer: SignerWithAddress
  let usdcWhale: SignerWithAddress

  let USDC: IERC20

  let wrappedFCashFactory: WrappedfCashFactory
  let frpVault: FRPVault

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
    frpVault = await new FRPVault__factory(signer).deploy(
      mainnetConfig.USDC,
      'USDC Notional Vault',
      'USDC_VAULT',
      mainnetConfig.notional.currencyIdUSDC,
      wrappedFCashFactory.address,
      mainnetConfig.notional.router,
      200
    )
    await frpVault.grantRole(VAULT_MANAGER_ROLE, signer.address)

    await USDC.connect(usdcWhale).approve(frpVault.address, ethers.constants.MaxUint256)
    await USDC.connect(signer).approve(frpVault.address, ethers.constants.MaxUint256)

    snapshotId = await snapshot.take()
  })

  beforeEach(async function () {
    this.timeout(50_000)
    await snapshot.revert(snapshotId)
  })

  it('harvests deposited USDC', async () => {
    const amount = expandTo6Decimals(100)
    const allowedDeviationPercent = 1

    // usdcWhale deposits USDC

    const shares = await frpVault.previewDeposit(amount)
    await frpVault.connect(usdcWhale).deposit(amount, usdcWhale.address)

    expect(amount).to.be.eq(shares)
    expect(amount).to.be.eq(await frpVault.balanceOf(usdcWhale.address))

    // signer deposits usdc
    await frpVault.deposit(amount, signer.address)

    expect(amount).to.be.eq(await frpVault.balanceOf(signer.address))
    expect(await frpVault.totalAssets()).to.be.eq(amount.mul(2))

    await frpVault.harvest({ gasLimit: 30e6 })
    const usdcBalanceAfterHarvest = await frpVault.balanceOf(await frpVault.asset())
    await expect(usdcBalanceAfterHarvest).to.eq(0)

    // due to exchange losses shares are worth more
    const sharesAfterHarvest = await frpVault.previewDeposit(amount, {
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
    await frpVault.connect(usdcWhale).deposit(amount.mul(100), usdcWhale.address, { gasLimit: 30e6 })

    await frpVault.harvest({ gasLimit: 30e6 })
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
      const actualSlippage = await getStorageAt(frpVault, 9)
      await expect(BigNumber.from(actualSlippage)).to.eq(BigNumber.from(newSlippage))
    })
  })
})
