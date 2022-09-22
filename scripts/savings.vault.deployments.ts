import { BigNumber } from 'ethers'
import { ethers } from 'hardhat'
import * as mainnetConfig from '../eth_mainnet.json'
import { ERC1967Proxy__factory, ERC20Upgradeable__factory, SavingsVault__factory } from '../typechain-types'
import { expandTo18Decimals, expandTo6Decimals } from '../utils/helpers'
import { HARVESTER_ROLE, VAULT_MANAGER_ROLE } from '../utils/roles'
import { deploy, logger, transaction } from './utils'
import { DeploymentBlocks, DeploymentsAddresses, writeResults } from './utils/mvp-output'

async function main() {
  logger.logTitle('SavingsVault deployment')

  const [admin, alice, bob] = await ethers.getSigners()
  // console.log("admin is: ", admin.address)

  const USDC = ERC20Upgradeable__factory.connect(mainnetConfig.USDC, admin)

  let { contract: SavingsVault } = await deploy('SavingsVault', new SavingsVault__factory(admin))
  const { contract: SavingsVaultProxy, receipt: SavingsVaultProxyReceipt } = await deploy(
    'SavingsVault proxy',
    new ERC1967Proxy__factory(admin),
    SavingsVault.address,
    SavingsVault.interface.encodeFunctionData('initialize', [
      'USDC Notional Vault',
      'USDC_VAULT',
      mainnetConfig.USDC,
      mainnetConfig.notional.currencyIdUSDC,
      mainnetConfig.notional.wrappedfCashFactory,
      mainnetConfig.notional.router,
      9800,
      admin.address
    ])
  )
  SavingsVault = SavingsVault.attach(SavingsVaultProxy.address)

  await transaction('Grant VAULT_MANAGER_ROLE', SavingsVault, 'grantRole', VAULT_MANAGER_ROLE, admin.address)
  await transaction('Grant HARVESTER_ROLE', SavingsVault, 'grantRole', HARVESTER_ROLE, admin.address)

  // Admin mints SavingsVault
  const usdcAmount = expandTo6Decimals(1000)
  await transaction('Approve USDC for SavingsVault', USDC, 'approve', SavingsVault.address, ethers.constants.MaxUint256)
  await transaction('SavingsVault deposit', SavingsVault, 'deposit', usdcAmount, admin.address)

  // Admin transfers SavingsVault shares to alice and bob
  await transaction('SavingsVault transfer', SavingsVault, 'transfer', alice.address, expandTo18Decimals(250))
  await transaction('SavingsVault transfer', SavingsVault, 'transfer', bob.address, expandTo18Decimals(250))

  // Admin transfers USDC to alice and bob
  await transaction('USDC transfer', USDC, 'transfer', alice.address, expandTo6Decimals(100))
  await transaction('USDC transfer', USDC, 'transfer', bob.address, expandTo6Decimals(100))

  // harvesting
  await SavingsVault.connect(admin).harvest(ethers.constants.MaxUint256, {
    gasPrice: BigNumber.from(200 * 10 ** 9),
    gasLimit: BigNumber.from(10 * 10 ** 6)
  })

  // alice and bob deposit their USDC
  await transaction(
    'Approve USDC for SavingsVault',
    USDC.connect(alice),
    'approve',
    SavingsVault.address,
    ethers.constants.MaxUint256
  )
  await transaction(
    'Approve USDC for SavingsVault',
    USDC.connect(bob),
    'approve',
    SavingsVault.address,
    ethers.constants.MaxUint256
  )
  await transaction(
    'SavingsVault deposit',
    SavingsVault.connect(alice),
    'deposit',
    expandTo6Decimals(100),
    alice.address
  )
  await transaction('SavingsVault deposit', SavingsVault.connect(bob), 'deposit', expandTo6Decimals(100), bob.address)

  // harvesting
  await SavingsVault.connect(admin).harvest(ethers.constants.MaxUint256, {
    gasPrice: BigNumber.from(200 * 10 ** 9),
    gasLimit: BigNumber.from(10 * 10 ** 6)
  })

  // admin, alice and bob harvest
  await transaction(
    'SavingsVault withdraw',
    SavingsVault,
    'withdraw',
    expandTo6Decimals(50),
    admin.address,
    admin.address
  )
  await transaction(
    'SavingsVault withdraw',
    SavingsVault.connect(alice),
    'withdraw',
    expandTo6Decimals(50),
    alice.address,
    alice.address
  )
  await transaction(
    'SavingsVault withdraw',
    SavingsVault.connect(bob),
    'withdraw',
    expandTo6Decimals(50),
    bob.address,
    bob.address
  )

  const addresses: DeploymentsAddresses = {
    SavingsVault: SavingsVaultProxy.address,
    Asset: USDC.address
  }
  console.table(addresses)

  const blocks: DeploymentBlocks = {
    SavingsVaultBlockNumber: SavingsVaultProxyReceipt.blockNumber
  }
  console.table(blocks)

  await writeResults(addresses, blocks)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
