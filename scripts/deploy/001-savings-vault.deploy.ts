import { ERC1967Proxy__factory, SavingsVault__factory } from '../../typechain-types'
import { parseBigNumber, parseEthAddress, parseString, parseWallet } from '../../utils/parser'
import { deploy, logger } from '../utils'

async function main() {
  logger.logTitle('Deploy SavingsVault')

  const deployer = parseWallet('PRIVATE_KEY')
  const {
    name,
    symbol,
    asset,
    currencyId,
    wrappedfCashFactory,
    notionalRouter,
    maxLoss,
    feeRecipient,
    gasPrice,
    gasLimitImpl,
    gasLimitProxy
  } = await logger.logInputs.withConfirmation({
    deployer: deployer.address,
    name: parseString('NAME'),
    symbol: parseString('SYMBOL'),
    asset: parseEthAddress('ASSET'),
    currencyId: parseBigNumber('CURRENCY_ID', 0),
    wrappedfCashFactory: parseEthAddress('WRAPPED_FCASH_FACTORY'),
    notionalRouter: parseEthAddress('NOTIONAL_ROUTER'),
    maxLoss: parseBigNumber('MAX_LOSS', 0),
    feeRecipient: parseEthAddress('FEE_RECIPIENT'),
    gasPrice: parseBigNumber('GAS_PRICE_GWEI', 9).toString(),
    gasLimitImpl: parseBigNumber('GAS_LIMIT_IMPLEMENTATION', 6).toString(),
    gasLimitProxy: parseBigNumber('GAS_LIMIT_PROXY', 6).toString()
  })

  const { contract: impl } = await deploy.withVerification(
    'SavingsVault implementation',
    new SavingsVault__factory(deployer),
    {
      gasPrice,
      gasLimit: gasLimitImpl
    }
  )

  const data = new SavingsVault__factory().interface.encodeFunctionData('initialize', [
    name,
    symbol,
    asset,
    currencyId,
    wrappedfCashFactory,
    notionalRouter,
    maxLoss,
    feeRecipient
  ])
  await deploy.withVerification('SavingsVault proxy', new ERC1967Proxy__factory(deployer), impl.address, data, {
    gasPrice,
    gasLimit: gasLimitProxy
  })
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
