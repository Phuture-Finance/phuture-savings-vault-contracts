import Decimal from 'decimal.js'
import { BigNumber } from 'ethers'
import {
  ERC20Upgradeable__factory,
  IWrappedfCashComplete__factory,
  JobConfig__factory,
  PhutureJob__factory,
  SavingsVaultViews__factory,
  SavingsVault__factory
} from '../../typechain-types'
import { parseEthAddress, parseString, parseWallet } from '../../utils/parser'
import { logger } from '../utils'

function bnToFormattedString(value: BigNumber, decimals: number): string {
  return new Decimal(value.toString()).div(BigNumber.from(10).pow(decimals).toString()).toString()
}

function timestampToFormattedTime(timestamp: BigNumber): string {
  const date = new Date(timestamp.toNumber() * 1000)
  return date.toLocaleString()
}

async function main() {
  const signer = parseWallet('PRIVATE_KEY')
  const { savingsVaultAddress, savingsVaultViewsAddress, jobConfigAddress, phutureJobAddress } = logger.logInputs({
    signer: signer.address,
    savingsVaultAddress: parseEthAddress('SAVINGS_VAULT'),
    savingsVaultViewsAddress: parseEthAddress('SAVINGS_VAULT_VIEWS'),
    jobConfigAddress: parseEthAddress('JOB_CONFIG'),
    phutureJobAddress: parseEthAddress('PHUTURE_JOB')
  })

  const savingsVault = SavingsVault__factory.connect(savingsVaultAddress, signer)
  const savingsVaultViews = SavingsVaultViews__factory.connect(savingsVaultViewsAddress, signer)
  const jobConfig = JobConfig__factory.connect(jobConfigAddress, signer)
  const phutureJob = PhutureJob__factory.connect(phutureJobAddress, signer)
  const usdc = ERC20Upgradeable__factory.connect(await savingsVault.asset(), signer)

  const totalAssetsOraclized = await savingsVault.totalAssets()
  const totalSupply = await savingsVault.totalSupply()

  console.log('USV data for deposit: ')
  console.table({
    'Total Assets': bnToFormattedString(totalAssetsOraclized, 6),
    'Total Supply': bnToFormattedString(totalSupply, 18)
  })

  let totalAssetsSpot = await usdc.balanceOf(savingsVaultAddress)
  const fCashPositions = await savingsVault.getfCashPositions()
  for (const fCashPosition_ of fCashPositions) {
    const fCashPosition = IWrappedfCashComplete__factory.connect(fCashPosition_, signer)
    const fCashPositionBalance = await fCashPosition.balanceOf(savingsVaultAddress)
    if (fCashPositionBalance != BigNumber.from(0)) {
      totalAssetsSpot = totalAssetsSpot.add(await fCashPosition.previewRedeem(fCashPositionBalance))
    }
  }

  console.log('USV data for redeem: ')
  console.table({
    'Total Assets': bnToFormattedString(totalAssetsSpot, 6),
    'Total Supply': bnToFormattedString(totalSupply, 18)
  })
  const lowestYieldFCash = IWrappedfCashComplete__factory.connect(fCashPositions[0], signer)
  const highestYieldFCash = IWrappedfCashComplete__factory.connect(fCashPositions[1], signer)
  const { lowestYieldMarket, highestYieldMarket } = await savingsVault.sortMarketsByOracleRate()

  console.log('Savings Vault constituents: ')
  console.table({
    'Lowest Yield Market Bond': {
      address: lowestYieldFCash.address,
      oracleRate: bnToFormattedString(lowestYieldMarket.oracleRate, 7) + '%',
      maturity: timestampToFormattedTime(lowestYieldMarket.maturity),
      fCashAmount: bnToFormattedString(await lowestYieldFCash.balanceOf(savingsVaultAddress), 8),
      usdcEquivalent: bnToFormattedString(
        await lowestYieldFCash.previewRedeem(await lowestYieldFCash.balanceOf(savingsVaultAddress)),
        6
      )
    },
    'Highest Yield Market Bond': {
      address: highestYieldFCash.address,
      oracleRate: bnToFormattedString(highestYieldMarket.oracleRate, 7) + '%',
      maturity: timestampToFormattedTime(highestYieldMarket.maturity),
      fCashAmount: bnToFormattedString(await highestYieldFCash.balanceOf(savingsVaultAddress), 8),
      usdcEquivalent: bnToFormattedString(
        await highestYieldFCash.previewRedeem(await highestYieldFCash.balanceOf(savingsVaultAddress)),
        6
      )
    },
    USDC: { usdcEquivalent: bnToFormattedString(await usdc.balanceOf(savingsVaultAddress), 6) }
  })

  console.log('Savings Vault Views data: ')
  console.table({
    'Max deposited amount': bnToFormattedString(await savingsVaultViews.getMaxDepositedAmount(savingsVault.address), 6),
    'Max loss': bnToFormattedString(BigNumber.from(await savingsVault.maxLoss()), 2) + '%',
    'Scaled Amount': bnToFormattedString(await jobConfig.getDepositedAmount(savingsVault.address), 6),
    APY: bnToFormattedString(await savingsVaultViews.getAPY(savingsVault.address), 7) + '%'
  })

  const signerAddress = signer.address
  const feeRecipientAddress = parseString('FEE_RECIPIENT')
  console.log('USV balances')
  console.table({
    signerAddress: bnToFormattedString(await savingsVault.balanceOf(signerAddress), 18),
    feeRecipientAddress: bnToFormattedString(await savingsVault.balanceOf(feeRecipientAddress), 18)
  })
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
