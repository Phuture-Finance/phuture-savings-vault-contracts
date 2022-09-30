import { ethers } from 'ethers'
import {
  ERC20Upgradeable__factory,
  IERC20__factory,
  IWrappedfCashComplete__factory, IWrappedfCashFactory__factory,
  SavingsVault__factory
} from '../../typechain-types'
import { impersonate, setBalance } from '../../utils/evm'
import { toUnit } from '../../utils/helpers'
import { parseBigNumber, parseEthAddress } from '../../utils/parser'
import { logger } from '../utils'

async function main() {
  const account = await impersonate(parseEthAddress('ACCOUNT'))
  const usdc = ERC20Upgradeable__factory.connect('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', account)
  const savingsVault = SavingsVault__factory.connect(parseEthAddress('SAVINGS_VAULT'), account)
  const {lowestYieldMarket, highestYieldMarket} = await savingsVault.sortMarketsByOracleRate()
  const wrappedFCashFactory = IWrappedfCashFactory__factory.connect('0x5D051DeB5db151C2172dCdCCD42e6A2953E27261', account)
  await wrappedFCashFactory.deployWrapper(3, lowestYieldMarket.maturity)
  await wrappedFCashFactory.deployWrapper(3, highestYieldMarket.maturity)
  const lowestYieldfCash = IWrappedfCashComplete__factory.connect(await wrappedFCashFactory.computeAddress(3, lowestYieldMarket.maturity), account)
  const highestYieldfCash = IWrappedfCashComplete__factory.connect(await wrappedFCashFactory.computeAddress(3, highestYieldMarket.maturity), account)
  await setBalance(parseEthAddress('ACCOUNT'), toUnit(10))

  await usdc.approve(lowestYieldfCash.address, ethers.constants.MaxUint256)
  await usdc.approve(highestYieldfCash.address, ethers.constants.MaxUint256)

  await lowestYieldfCash.deposit(parseBigNumber('AMOUNT', 6), account.address)
  await highestYieldfCash.deposit(parseBigNumber('AMOUNT', 6), account.address)

  await IERC20__factory.connect(lowestYieldfCash.address, account).transfer(
    savingsVault.address,
    await lowestYieldfCash.balanceOf(account.address)
  )
  await IERC20__factory.connect(highestYieldfCash.address, account).transfer(
    savingsVault.address,
    await highestYieldfCash.balanceOf(account.address)
  )
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
