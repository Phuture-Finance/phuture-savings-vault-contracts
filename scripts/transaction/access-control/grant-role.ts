import { AccessControlUpgradeable__factory } from '../../../typechain-types'
import { parseBigNumber, parseEthAddress, parseString, parseWallet } from '../../../utils/parser'
import { grantRole, logger } from '../../utils'

async function main() {
  logger.logTitle('Grant Role')

  const signer = parseWallet('PRIVATE_KEY')
  const { savingsVaultAddress, address, role, gasPrice } = await logger.logInputs.withConfirmation({
    signer: signer.address,
    savingsVaultAddress: parseEthAddress('SAVINGS_VAULT'),
    address: parseEthAddress('ADDRESS'),
    role: parseString('ROLE'),
    gasPrice: parseBigNumber('GAS_PRICE_GWEI', 9).toString()
  })

  const savingsVault = AccessControlUpgradeable__factory.connect(savingsVaultAddress, signer)
  await grantRole(savingsVault, role, address, { gasPrice })
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
