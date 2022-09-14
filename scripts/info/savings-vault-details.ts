import Decimal from 'decimal.js'
import { BigNumber } from 'ethers'
import { ERC20Upgradeable__factory, IWrappedfCashComplete__factory, SavingsVault__factory } from '../../typechain-types'
import {parseEthAddress, parseWallet} from "../../utils/parser";
import { logger } from '../utils'

function bnToFormattedString(value: BigNumber, decimals: number): string {
  return new Decimal(value.toString()).div(BigNumber.from(10).pow(decimals).toString()).toString()
}

async function main() {
  const signer = parseWallet('PRIVATE_KEY')
  const { savingsVaultAddress } = logger.logInputs({
    signer: signer.address,
    savingsVaultAddress: parseEthAddress('SAVINGS_VAULT')
  })

  const savingsVault = SavingsVault__factory.connect(savingsVaultAddress, signer)
  const usdc = ERC20Upgradeable__factory.connect(await savingsVault.asset(), signer)

  const totalAssetsOraclized = await savingsVault.totalAssets()
  const totalSupply = await savingsVault.totalSupply()

  console.log('USV data for deposit:')
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

  console.log('USV data for redeem:')
  console.table({
    'Total Assets': bnToFormattedString(totalAssetsSpot, 6),
    'Total Supply': bnToFormattedString(totalSupply, 18)
  })
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
