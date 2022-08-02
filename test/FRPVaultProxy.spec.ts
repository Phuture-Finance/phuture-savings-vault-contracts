import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { ethers } from 'hardhat'
import * as mainnetConfig from '../eth_mainnet.json'
import { FRPVault, FRPVault__factory, IERC20, IERC20__factory } from '../typechain-types'
import { impersonate, reset, setBalance, snapshot } from '../utils/evm'
import { expandTo18Decimals, expandTo6Decimals, newProxyContract, randomAddress } from '../utils/helpers'

describe('FrpVault interaction with wrappedFCash [ @forked-mainnet]', function () {
  this.timeout(1e8)
  let signer: SignerWithAddress
  let usdcWhale: SignerWithAddress

  let USDC: IERC20

  let frpVault: FRPVault

  let snapshotId: string

  before(async () => {
    ;[signer] = await ethers.getSigners()

    await reset({
      jsonRpcUrl: process.env.MAINNET_HTTPS_URL,
      blockNumber: 15_172_678
    })

    usdcWhale = await impersonate(mainnetConfig.whales.USDC)
    await setBalance(usdcWhale.address, expandTo18Decimals(1_000_000))

    USDC = IERC20__factory.connect(mainnetConfig.USDC, usdcWhale)
    await USDC.transfer(signer.address, expandTo6Decimals(1000))

    frpVault = await newProxyContract(new FRPVault__factory(signer), [
      'USDC Notional Vault',
      'USDC_VAULT',
      mainnetConfig.USDC,
      mainnetConfig.notional.currencyIdUSDC,
      mainnetConfig.notional.wrappedfCashFactory,
      mainnetConfig.notional.router,
      9800,
      randomAddress()
    ])

    await USDC.connect(usdcWhale).approve(frpVault.address, ethers.constants.MaxUint256)
    await USDC.connect(signer).approve(frpVault.address, ethers.constants.MaxUint256)

    snapshotId = await snapshot.take()
  })

  beforeEach(async function () {
    this.timeout(50_000)
    await snapshot.revert(snapshotId)
  })

  it('gas costs', async () => {
    // Initial flow to deposit/harvest
    await frpVault.connect(usdcWhale).deposit(expandTo6Decimals(100), usdcWhale.address)
    await frpVault.connect(usdcWhale).harvest(ethers.constants.MaxUint256)

    const mintGasEstimate = await frpVault
      .connect(usdcWhale)
      .estimateGas.mint(expandTo18Decimals(1000), usdcWhale.address)
    console.log(`mint gas cost is: ${mintGasEstimate}`)

    const depositGasEstimate = await frpVault
      .connect(usdcWhale)
      .estimateGas.deposit(expandTo6Decimals(1000), usdcWhale.address)
    console.log(`deposit gas cost is: ${depositGasEstimate}`)

    // To be used with the gas reporter
    await frpVault.connect(usdcWhale).deposit(expandTo6Decimals(100), usdcWhale.address)
    await frpVault.connect(usdcWhale).mint(expandTo18Decimals(100), usdcWhale.address)
  })
})
