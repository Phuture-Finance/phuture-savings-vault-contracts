import { ethers } from 'hardhat'
import * as mainnetConfig from '../eth_mainnet.json'
import { ERC1967Proxy__factory, ERC20Upgradeable__factory, FRPVault__factory } from '../typechain-types'
import { expandTo6Decimals } from '../utils/helpers'
import { VAULT_MANAGER_ROLE } from '../utils/roles'
import { deploy, logger, transaction } from './utils'
import { DeploymentBlocks, DeploymentsAddresses, writeResults } from './utils/mvp-output'

async function main() {
  logger.logTitle('Frp deployment')

  const [account] = await ethers.getSigners()

  const USDC = ERC20Upgradeable__factory.connect(mainnetConfig.USDC, account)

  let { contract: FRPVault } = await deploy('FRPVault', new FRPVault__factory(account))
  const { contract: FRPVaultProxy, receipt: FRPVaultProxyReceipt } = await deploy(
    'FrpVault proxy',
    new ERC1967Proxy__factory(account),
    FRPVault.address,
    FRPVault.interface.encodeFunctionData('initialize', [
      'USDC Notional Vault',
      'USDC_VAULT',
      mainnetConfig.USDC,
      mainnetConfig.notional.currencyIdUSDC,
      mainnetConfig.notional.wrappedfCashFactory,
      mainnetConfig.notional.router,
      9800
    ])
  )
  FRPVault = FRPVault.attach(FRPVaultProxy.address)

  await transaction('Grant VAULT_MANAGER_ROLE', FRPVault, 'grantRole', VAULT_MANAGER_ROLE, account.address)

  await transaction('Approve USDC for FRPVault', USDC, 'approve', FRPVault.address, ethers.constants.MaxUint256)

  await transaction('FRPVault deposit', FRPVault, 'deposit', expandTo6Decimals(1000), account.address)

  await transaction('FRPVault harvest', FRPVault, 'harvest', ethers.constants.MaxUint256)

  await transaction('FRPVault withdraw', FRPVault, 'withdraw', expandTo6Decimals(500), account.address, account.address)

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
