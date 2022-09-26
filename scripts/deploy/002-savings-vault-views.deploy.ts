import { SavingsVaultViews__factory } from '../../typechain-types'
import { parseWallet } from '../../utils/parser'
import { deploy, logger } from '../utils'

async function main() {
  logger.logTitle('Deploy SavingsVaultViews')

  const deployer = parseWallet('PRIVATE_KEY')
  await logger.logInputs.withConfirmation({
    deployer: deployer.address
  })
  await deploy.withVerification('SavingsVaultViews', new SavingsVaultViews__factory(deployer))
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
