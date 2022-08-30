import { ERC1967Proxy__factory, FRPVault__factory } from '../../typechain-types'
import { parseBigNumber, parseEthAddress, parseString, parseWallet } from '../../utils/parser'
import { deploy, logger } from '../utils'

async function main() {
  logger.logTitle('Deploy FRPVault')

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
    timeout,
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
    timeout: parseBigNumber('TIMEOUT', 0),
    gasPrice: parseBigNumber('GAS_PRICE_GWEI', 9).toString(),
    gasLimitImpl: parseBigNumber('GAS_LIMIT_IMPLEMENTATION', 6).toString(),
    gasLimitProxy: parseBigNumber('GAS_LIMIT_PROXY', 6).toString()
  })

  const { contract: impl } = await deploy.withVerification('FRPVault implementation', new FRPVault__factory(deployer), {
    gasPrice,
    gasLimit: gasLimitImpl
  })

  const data = new FRPVault__factory().interface.encodeFunctionData('initialize', [
    name,
    symbol,
    asset,
    currencyId,
    wrappedfCashFactory,
    notionalRouter,
    maxLoss,
    feeRecipient,
    timeout
  ])
  await deploy.withVerification('FRPVault proxy', new ERC1967Proxy__factory(deployer), impl.address, data, {
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
