import { ethers } from 'ethers'
import { SavingsVault__factory } from '../../typechain-types'
import { impersonate } from '../../utils/evm'
import { parseBigNumber, parseEthAddress } from '../../utils/parser'
import { logger } from '../utils'

async function main() {
  const account = await impersonate(parseEthAddress('ACCOUNT'))
  const savingsVault = SavingsVault__factory.connect(parseEthAddress('SAVINGS_VAULT'), account)
  await savingsVault.approve(savingsVault.address, ethers.constants.MaxUint256)
  await savingsVault['redeem(uint256,address,address)'](
    parseBigNumber('AMOUNT', 6),
    parseEthAddress('RECEIVER'),
    account.address
  )
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
