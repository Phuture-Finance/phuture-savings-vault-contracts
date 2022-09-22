import { ethers } from 'ethers'
import { ERC20Upgradeable__factory, SavingsVault__factory } from '../../typechain-types'
import { impersonate, setBalance } from '../../utils/evm'
import { toUnit } from '../../utils/helpers'
import { parseBigNumber, parseEthAddress } from '../../utils/parser'
import { logger } from '../utils'

async function main() {
  const account = await impersonate(parseEthAddress('ACCOUNT'))
  const usdc = ERC20Upgradeable__factory.connect('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', account)
  const savingsVault = SavingsVault__factory.connect(parseEthAddress('SAVINGS_VAULT'), account)
  await usdc.approve(savingsVault.address, ethers.constants.MaxUint256)
  await setBalance(parseEthAddress('RECEIVER'), toUnit(10))
  await savingsVault.deposit(parseBigNumber('AMOUNT', 6), parseEthAddress('RECEIVER'))
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
