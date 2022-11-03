import { SavingsVaultPriceViewer__factory } from '../../typechain-types'
import { parseWallet } from '../../utils/parser'
import { deploy, logger } from '../utils'

async function main() {
  logger.logTitle('Deploy SavingsVaultPriceViewer')

  const deployer = parseWallet('PRIVATE_KEY')
  await logger.logInputs.withConfirmation({
    deployer: deployer.address
  })
  await deploy.withVerification('SavingsVaultPriceViewer', new SavingsVaultPriceViewer__factory(deployer))
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
