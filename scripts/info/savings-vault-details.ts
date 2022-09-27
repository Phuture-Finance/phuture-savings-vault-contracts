import { BigNumber, Signer } from 'ethers'
import {
  ERC20Upgradeable__factory,
  IWrappedfCashComplete__factory,
  JobConfig__factory,
  SavingsVault,
  SavingsVaultViews__factory,
  SavingsVault__factory
} from '../../typechain-types'
import { parseEthAddress, parseString, parseWallet } from '../../utils/parser'
import { logger } from '../utils'
import { bnToFormattedString, timestampToFormattedTime } from '../utils/formatter'

async function generateNotionalMarket(
  fCash: string,
  savingsVault: SavingsVault,
  signer: Signer
): Promise<NotionalMarket> {
  const { lowestYieldMarket, highestYieldMarket } = await savingsVault.sortMarketsByOracleRate()
  const fCashPosition = IWrappedfCashComplete__factory.connect(fCash, signer)
  const maturity = BigNumber.from(await fCashPosition.getMaturity())
  let oracleRate
  if (await fCashPosition.hasMatured()) {
    oracleRate = 0
  } else if (maturity.eq(lowestYieldMarket.maturity)) {
    oracleRate = lowestYieldMarket.oracleRate
  } else if(maturity.eq(highestYieldMarket.maturity)) {
    oracleRate = highestYieldMarket.oracleRate
  } else {
    throw Error("fCash position doesn't belong to any market")
  }
  const fCashAmount: BigNumber = await fCashPosition.balanceOf(savingsVault.address)
  return {
    address: fCash,
    maturity: timestampToFormattedTime(BigNumber.from(maturity)),
    oracleRate: bnToFormattedString(oracleRate, 7) + '%',
    fCashAmount: bnToFormattedString(fCashAmount, 8),
    usdcEquivalent: bnToFormattedString(
      fCashAmount > BigNumber.from(0) ? await fCashPosition.previewRedeem(fCashAmount) : BigNumber.from(0),
      6
    )
  }
}

interface NotionalMarket {
  address: string
  maturity: string
  oracleRate: string
  fCashAmount: string
  usdcEquivalent: string
}

async function main() {
  const signer = parseWallet('PRIVATE_KEY')
  const { savingsVaultAddress, savingsVaultViewsAddress, jobConfigAddress } = logger.logInputs({
    signer: signer.address,
    savingsVaultAddress: parseEthAddress('SAVINGS_VAULT'),
    savingsVaultViewsAddress: parseEthAddress('SAVINGS_VAULT_VIEWS'),
    jobConfigAddress: parseEthAddress('JOB_CONFIG')
  })

  const savingsVault: SavingsVault = SavingsVault__factory.connect(savingsVaultAddress, signer)
  const savingsVaultViews = SavingsVaultViews__factory.connect(savingsVaultViewsAddress, signer)
  const jobConfig = JobConfig__factory.connect(jobConfigAddress, signer)
  const usdc = ERC20Upgradeable__factory.connect(await savingsVault.asset(), signer)

  const totalAssetsOraclized = await savingsVault.totalAssets()
  const totalSupply = await savingsVault.totalSupply()

  console.log('USV data for deposit: ')
  console.table({
    'Total Assets': bnToFormattedString(totalAssetsOraclized, 6),
    'Total Supply': bnToFormattedString(totalSupply, 18)
  })

  let totalAssetsSpot = await usdc.balanceOf(savingsVaultAddress)
  const fCashPositions: string[] = await savingsVault.getfCashPositions()
  for (const fCashPosition_ of fCashPositions) {
    const fCashPosition = IWrappedfCashComplete__factory.connect(fCashPosition_, signer)
    const fCashPositionBalance = await fCashPosition.balanceOf(savingsVaultAddress)
    if (!BigNumber.from(0).eq(fCashPositionBalance)) {
      totalAssetsSpot = totalAssetsSpot.add(await fCashPosition.previewRedeem(fCashPositionBalance))
    }
  }
  console.log('USV data for redeem: ')
  console.table({
    'Total Assets': bnToFormattedString(totalAssetsSpot, 6),
    'Total Supply': bnToFormattedString(totalSupply, 18)
  })

  console.table({
    'Lowest Yield Market Bond': await generateNotionalMarket(fCashPositions[0], savingsVault, signer),
    'Highest Yield Market Bond': await generateNotionalMarket(fCashPositions[1], savingsVault, signer),
    USDC: { usdcEquivalent: bnToFormattedString(await usdc.balanceOf(savingsVaultAddress), 6) }
  })

  console.log('Savings Vault Views data: ')
  console.table({
    'Max deposited amount': bnToFormattedString(await savingsVaultViews.getMaxDepositedAmount(savingsVault.address), 6),
    'Max loss': bnToFormattedString(BigNumber.from(await savingsVault.maxLoss()), 2) + '%',
    'Scaled Amount': bnToFormattedString(await jobConfig.getDepositedAmount(savingsVault.address), 6),
    APY: bnToFormattedString(await savingsVaultViews.getAPY(savingsVault.address), 7) + '%'
  })

  console.log('USV balances')
  console.table({
    signer: bnToFormattedString(await savingsVault.balanceOf(signer.address), 18),
    feeRecipient: bnToFormattedString(await savingsVault.balanceOf(parseString('FEE_RECIPIENT')), 18)
  })
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
