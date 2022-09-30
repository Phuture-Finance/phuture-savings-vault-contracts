import { ethers, network } from 'hardhat'
import { IWrappedfCashComplete__factory, NotionalProxy__factory, SavingsVault__factory } from '../../typechain-types'
import { impersonate } from '../../utils/evm'
import { parseEthAddress } from '../../utils/parser'
import { logger } from '../utils'

async function main() {
  const account = await impersonate(parseEthAddress('ACCOUNT'))
  const savingsVault = SavingsVault__factory.connect(parseEthAddress('SAVINGS_VAULT'), account)
  const fCashPositions = savingsVault.getfCashPositions()
  const lowestYieldFCash = IWrappedfCashComplete__factory.connect(fCashPositions[0], account)
  const highestYieldFCash = IWrappedfCashComplete__factory.connect(fCashPositions[1], account)
  const threeMonthMaturity =
    (await lowestYieldFCash.getMaturity()) < (await lowestYieldFCash.getMaturity())
      ? await lowestYieldFCash.getMaturity()
      : await highestYieldFCash.getMaturity()

  const latestBlockTimestamp = (await ethers.provider.getBlock('latest')).timestamp
  const timeToMaturity = threeMonthMaturity - latestBlockTimestamp
  await network.provider.send('evm_increaseTime', [timeToMaturity + 1000])
  await NotionalProxy__factory.connect('0x1344A36A1B56144C3Bc62E7757377D288fDE0369', account).initializeMarkets(
    3,
    false
  )
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
