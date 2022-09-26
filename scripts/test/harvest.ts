import { JobConfig__factory, SavingsVault__factory } from '../../typechain-types'
import { impersonate } from '../../utils/evm'
import { parseEthAddress } from '../../utils/parser'
import { logger } from '../utils'

async function main() {
  const account = await impersonate(parseEthAddress('ACCOUNT'))
  const savingsVault = SavingsVault__factory.connect(parseEthAddress('SAVINGS_VAULT'), account)
  const jobConfig = JobConfig__factory.connect(parseEthAddress('JOB_CONFIG'), account)
  const max = await jobConfig.getDepositedAmount(savingsVault.address)
  await savingsVault.harvest(max)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
