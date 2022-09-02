import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { Contract } from 'ethers'
import { ethers } from 'hardhat'
import * as mainnetConfig from '../eth_mainnet.json'
import * as Keepr3rMock from '../out/Keepr3rMock.sol/Keepr3rMock.json'
import {
  FRPVault,
  FRPVault__factory,
  FRPViews,
  FRPViews__factory,
  IERC20,
  IERC20__factory,
  JobConfig,
  JobConfig__factory,
  PhutureJob,
  PhutureJob__factory
} from '../typechain-types'
import { impersonate, reset, setBalance, snapshot } from '../utils/evm'
import { expandTo18Decimals, expandTo6Decimals, newProxyContract, randomAddress } from '../utils/helpers'
import { HARVESTER_ROLE, VAULT_MANAGER_ROLE } from '../utils/roles'

describe('FrpVault interaction with wrappedFCash [ @forked-mainnet]', function () {
  this.timeout(1e8)
  let signer: SignerWithAddress
  let usdcWhale: SignerWithAddress

  let USDC: IERC20

  let frpVault: FRPVault
  let frpViews: FRPViews
  let jobConfig: JobConfig
  let phutureJob: PhutureJob
  let keep3r: Contract

  let snapshotId: string

  before(async () => {
    ;[signer] = await ethers.getSigners()

    await reset({
      jsonRpcUrl: process.env.MAINNET_HTTPS_URL,
      blockNumber: 15_272_678
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
      9900,
      randomAddress(),
      0
    ])

    frpViews = await new FRPViews__factory(signer).deploy()
    jobConfig = await new JobConfig__factory(signer).deploy(frpViews.address)
    keep3r = await new ethers.ContractFactory(Keepr3rMock.abi, Keepr3rMock.bytecode, signer).deploy()
    phutureJob = await new PhutureJob__factory(signer).deploy(keep3r.address, jobConfig.address)
    await phutureJob.unpause()
    await frpVault.grantRole(HARVESTER_ROLE, phutureJob.address)
    await frpVault.grantRole(VAULT_MANAGER_ROLE, usdcWhale.address)

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

    // To be used with the gas reporter
    await frpVault.connect(usdcWhale).deposit(expandTo6Decimals(1_500_000), usdcWhale.address)

    await frpVault.connect(usdcWhale).setMaxLoss(9550)
    await phutureJob.harvest(frpVault.address, { gasLimit: 5_000_000 })
  })
})
