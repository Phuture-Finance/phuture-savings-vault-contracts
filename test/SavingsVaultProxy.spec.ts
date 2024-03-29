import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { Contract } from 'ethers'
import { ethers, network } from 'hardhat'
import * as mainnetConfig from '../eth_mainnet.json'
import * as Keepr3rMock from '../out/Keepr3rMock.sol/Keepr3rMock.json'
import {
  IERC20,
  IERC20__factory,
  JobConfig,
  JobConfig__factory,
  NotionalProxy__factory,
  PhutureJob,
  PhutureJob__factory,
  SavingsVault,
  SavingsVaultViews,
  SavingsVaultViews__factory,
  SavingsVault__factory
} from '../typechain-types'
import { impersonate, reset, setBalance, snapshot } from '../utils/evm'
import { expandTo18Decimals, expandTo6Decimals, newProxyContract, randomAddress } from '../utils/helpers'
import { JOB_MANAGER_ROLE, VAULT_MANAGER_ROLE } from '../utils/roles'

describe('SavingsVault interaction with wrappedFCash [ @forked-mainnet]', function () {
  this.timeout(1e8)
  let signer: SignerWithAddress
  let usdcWhale: SignerWithAddress

  let USDC: IERC20

  let savingsVault: SavingsVault
  let savingsVaultViews: SavingsVaultViews
  let jobConfig: JobConfig
  let phutureJob: PhutureJob
  let keep3r: Contract

  let snapshotId: string

  before(async () => {
    ;[signer] = await ethers.getSigners()

    await reset({
      jsonRpcUrl: process.env.MAINNET_HTTPS_URL,
      blockNumber: 15_637_559
    })

    usdcWhale = await impersonate(mainnetConfig.whales.USDC)
    await setBalance(usdcWhale.address, expandTo18Decimals(1_000_000))

    USDC = IERC20__factory.connect(mainnetConfig.USDC, usdcWhale)
    await USDC.transfer(signer.address, expandTo6Decimals(1000))

    savingsVault = await newProxyContract(new SavingsVault__factory(usdcWhale), [
      'USDC Notional Vault',
      'USDC_VAULT',
      mainnetConfig.USDC,
      mainnetConfig.notional.currencyIdUSDC,
      mainnetConfig.notional.wrappedfCashFactory,
      mainnetConfig.notional.router,
      9900,
      randomAddress()
    ])

    savingsVaultViews = await new SavingsVaultViews__factory(usdcWhale).deploy()
    jobConfig = await new JobConfig__factory(usdcWhale).deploy(savingsVaultViews.address)
    await jobConfig.setHarvestingAmountSpecification(3)
    keep3r = await new ethers.ContractFactory(Keepr3rMock.abi, Keepr3rMock.bytecode, signer).deploy()
    phutureJob = await new PhutureJob__factory(usdcWhale).deploy(keep3r.address, jobConfig.address)
    await phutureJob.grantRole(JOB_MANAGER_ROLE, usdcWhale.address)
    await savingsVault.grantRole(VAULT_MANAGER_ROLE, usdcWhale.address)
    await phutureJob.unpause()

    await USDC.connect(usdcWhale).approve(savingsVault.address, ethers.constants.MaxUint256)
    await USDC.connect(signer).approve(savingsVault.address, ethers.constants.MaxUint256)

    snapshotId = await snapshot.take()
  })

  beforeEach(async function () {
    this.timeout(50_000)
    await snapshot.revert(snapshotId)
  })

  it('gas costs', async () => {
    // Initial flow to deposit/harvest
    await savingsVault.connect(usdcWhale).deposit(expandTo6Decimals(100), usdcWhale.address)
    await savingsVault.connect(usdcWhale).harvest(ethers.constants.MaxUint256)

    // To be used with the gas reporter
    await savingsVault.connect(usdcWhale).deposit(expandTo6Decimals(1_500_000), usdcWhale.address)

    await phutureJob.harvestWithPermission(savingsVault.address, { gasLimit: 5_000_000 })
    await network.provider.send('evm_increaseTime', [1_671_840_010])
    await NotionalProxy__factory.connect('0x1344A36A1B56144C3Bc62E7757377D288fDE0369', signer).initializeMarkets(
      3,
      false,
      {
        gasLimit: 10_000_000
      }
    )
    console.log(await phutureJob.estimateGas.settleAccount(savingsVault.address))
  })
})
