import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { ethers } from 'hardhat'
import * as mainnetConfig from '../../eth_mainnet.json'
import { FRPVault, FRPVault__factory, IERC20, IERC20__factory, WrappedfCashFactory } from '../../typechain-types'
import { impersonate, mineBlocks, reset, setBalance, snapshot } from '../../utils/evm'
import { deployWrappedfCashFactory, upgradeNotionalProxy } from '../../utils/notional-fixtures'
import { expandTo18Decimals, expandTo6Decimals } from '../../utils/utilities'

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
      blockNumber: 14990487
    })

    usdcWhale = await impersonate(mainnetConfig.whales.USDC)
    await setBalance(usdcWhale.address, expandTo18Decimals(1000000))

    USDC = IERC20__factory.connect(mainnetConfig.USDC, usdcWhale)
    await USDC.transfer(signer.address, expandTo6Decimals(1_000))

    await upgradeNotionalProxy(signer)
    wrappedFCashFactory = await deployWrappedfCashFactory(signer)
    frpVault = await new FRPVault__factory(signer).deploy(
      mainnetConfig.USDC,
      'USDC Notional Vault',
      'USDC_VAULT',
      mainnetConfig.notional.currencyIdUSDC,
      wrappedFCashFactory.address,
      mainnetConfig.notional.router
    )

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

    // due to exchange losses shares are worth more
    const sharesAfterHarvest = await frpVault.previewDeposit(amount, {
      gasLimit: 30e6
    })
    expect(sharesAfterHarvest.sub(shares)).to.be.eq(86624)

    const totalAssets = await frpVault.totalAssets()

    await mineBlocks(1000)

    // As time passes fCash appreciates in value
    expect((await frpVault.totalAssets()).sub(totalAssets)).to.be.eq(763)

    // usdcWhale deposits more USDC
    await frpVault.connect(usdcWhale).deposit(amount.mul(100), usdcWhale.address, { gasLimit: 30e6 })

    await frpVault.harvest({ gasLimit: 30e6 })
  })

  it('fails on harvest with large amounts', async () => {
    await frpVault.connect(usdcWhale).deposit(expandTo6Decimals(1_500_000), usdcWhale.address)
    await expect(frpVault.harvest({ gasLimit: 30e6 })).to.be.revertedWith('FRP_VAULT: PRICE_IMPACT')
  })
})
