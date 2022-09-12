import { PhutureJob__factory } from '../../typechain-types'
import { parseEthAddress, parseWallet } from '../../utils/parser'
import { deploy, logger } from '../utils'

async function main() {
  logger.logTitle('Deploy PhutureJob')

  const deployer = parseWallet('PRIVATE_KEY')

  const { keeperAddress, jobConfig } = await logger.logInputs.withConfirmation({
    deployer: deployer.address,
    keeperAddress: parseEthAddress('KEEPER'),
    jobConfig: parseEthAddress('JOB_CONFIG')
  })
  await deploy.withVerification('PhutureJob', new PhutureJob__factory(deployer), keeperAddress, jobConfig)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
