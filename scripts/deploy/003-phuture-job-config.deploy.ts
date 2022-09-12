import { JobConfig__factory } from '../../typechain-types'
import { parseEthAddress, parseWallet } from '../../utils/parser'
import { deploy, logger } from '../utils'

async function main() {
  logger.logTitle('Deploy JobConfig')

  const deployer = parseWallet('PRIVATE_KEY')

  const { savingsVaultViews } = await logger.logInputs.withConfirmation({
    deployer: deployer.address,
    savingsVaultViews: parseEthAddress('SAVINGS_VAULT_VIEWS')
  })
  await deploy.withVerification('JobConfig', new JobConfig__factory(deployer), savingsVaultViews)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
