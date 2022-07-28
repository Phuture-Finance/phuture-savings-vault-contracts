import { ethers } from 'hardhat'
import * as mainnetConfig from '../eth_mainnet.json'
import { ERC1967Proxy__factory, ERC20Upgradeable__factory, FRPVault__factory } from '../typechain-types'
import { expandTo18Decimals, expandTo6Decimals } from '../utils/helpers'
import { VAULT_MANAGER_ROLE } from '../utils/roles'
import { deploy, logger, transaction } from './utils'
import { DeploymentBlocks, DeploymentsAddresses, writeResults } from './utils/mvp-output'

async function main() {
  logger.logTitle('Frp deployment')

  const [admin, alice, bob] = await ethers.getSigners()

  const USDC = ERC20Upgradeable__factory.connect(mainnetConfig.USDC, admin)

  let { contract: FRPVault } = await deploy('FRPVault', new FRPVault__factory(admin))
  const { contract: FRPVaultProxy, receipt: FRPVaultProxyReceipt } = await deploy(
    'FrpVault proxy',
    new ERC1967Proxy__factory(admin),
    FRPVault.address,
    FRPVault.interface.encodeFunctionData('initialize', [
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
  FRPVault = FRPVault.attach(FRPVaultProxy.address)

  await transaction('Grant VAULT_MANAGER_ROLE', FRPVault, 'grantRole', VAULT_MANAGER_ROLE, admin.address)

  // Admin mints FRP
  const usdcAmount = expandTo6Decimals(1000)
  await transaction('Approve USDC for FRPVault', USDC, 'approve', FRPVault.address, ethers.constants.MaxUint256)
  await transaction('FRPVault deposit', FRPVault, 'deposit', usdcAmount, admin.address)

  // Admin transfers FRP to alice and bob
  await transaction('FRPVault transfer', FRPVault, 'transfer', alice.address, expandTo18Decimals(250))
  await transaction('FRPVault transfer', FRPVault, 'transfer', bob.address, expandTo18Decimals(250))

  // Admin transfers USDC to alice and bob
  await transaction('USDC transfer', USDC, 'transfer', alice.address, expandTo6Decimals(100))
  await transaction('USDC transfer', USDC, 'transfer', bob.address, expandTo6Decimals(100))

  // harvesting
  await transaction('FRPVault harvest', FRPVault, 'harvest', ethers.constants.MaxUint256)

  // alice and bob deposit their USDC
  await transaction(
    'Approve USDC for FRPVault',
    USDC.connect(alice),
    'approve',
    FRPVault.address,
    ethers.constants.MaxUint256
  )
  await transaction(
    'Approve USDC for FRPVault',
    USDC.connect(bob),
    'approve',
    FRPVault.address,
    ethers.constants.MaxUint256
  )
  await transaction('FRPVault deposit', FRPVault.connect(alice), 'deposit', expandTo6Decimals(100), alice.address)
  await transaction('FRPVault deposit', FRPVault.connect(bob), 'deposit', expandTo6Decimals(100), bob.address)

  // harvesting
  await transaction('FRPVault harvest', FRPVault, 'harvest', ethers.constants.MaxUint256)

  // admin, alice and bob harvest
  await transaction('FRPVault withdraw', FRPVault, 'withdraw', expandTo6Decimals(500), admin.address, admin.address)
  await transaction(
    'FRPVault withdraw',
    FRPVault.connect(alice),
    'withdraw',
    expandTo6Decimals(100),
    alice.address,
    alice.address
  )
  await transaction(
    'FRPVault withdraw',
    FRPVault.connect(bob),
    'withdraw',
    expandTo6Decimals(100),
    bob.address,
    bob.address
  )

  const addresses: DeploymentsAddresses = {
    FrpVault: FRPVaultProxy.address,
    Asset: USDC.address
  }
  console.table(addresses)

  const blocks: DeploymentBlocks = {
    FrpVaultBlockNumber: FRPVaultProxyReceipt.blockNumber
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
