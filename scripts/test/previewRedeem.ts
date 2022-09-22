import { SavingsVault__factory } from '../../typechain-types'
import { impersonate } from '../../utils/evm'
import { parseBigNumber, parseEthAddress, parseString } from '../../utils/parser'
import { logger } from '../utils'
import { bnToFormattedString } from '../utils/formatter'

async function main() {
  const account = await impersonate(parseEthAddress('ACCOUNT'))
  const savingsVault = SavingsVault__factory.connect(parseEthAddress('SAVINGS_VAULT'), account)
  const assets = await savingsVault.previewRedeem(parseBigNumber('AMOUNT', 18))

  console.table({
    Assets: bnToFormattedString(assets, 6),
    Shares: parseString('AMOUNT').toString()
  })
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
