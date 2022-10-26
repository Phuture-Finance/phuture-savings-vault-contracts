import { JobConfig__factory, TestSavingsVault__factory } from '../../typechain-types'
import { impersonate } from '../../utils/evm'
import { parseBool, parseEthAddress } from '../../utils/parser'
import { logger } from '../utils'

async function main() {
  const account = await impersonate(parseEthAddress('ACCOUNT'))
  const savingsVault = TestSavingsVault__factory.connect(parseEthAddress('SAVINGS_VAULT'), account)
  const jobConfig = JobConfig__factory.connect(parseEthAddress('JOB_CONFIG'), account)
  const max = await jobConfig.getDepositedAmount(savingsVault.address)
  await savingsVault.harvestTo(max, parseBool('TO_LOWEST_YIELD'), { gasLimit: 2_000_000 })
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
