import { SavingsVault__factory, TestSavingsVault__factory } from '../../typechain-types'
import { impersonate } from '../../utils/evm'
import { parseEthAddress } from '../../utils/parser'
import { deploy, logger } from '../utils'

async function main() {
  logger.logTitle('Deploy TestSavingsVault')

  const account = await impersonate(parseEthAddress('ACCOUNT'))
  const vaultManager = await impersonate('0x56EbC6ed25ba2614A3eAAFFEfC5677efAc36F95f')

  const { contract: impl } = await deploy('TestSavingsVault implementation', new TestSavingsVault__factory(account))

  const savingsVault = SavingsVault__factory.connect(parseEthAddress('SAVINGS_VAULT'), vaultManager)
  await savingsVault.upgradeTo(impl.address)

  // const data = new TestSavingsVault__factory().interface.encodeFunctionData('initialize', [
  //   'USDC Savings Vault',
  //   'USV',
  //   '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
  //   3,
  //   '0x5D051DeB5db151C2172dCdCCD42e6A2953E27261',
  //   '0x1344A36A1B56144C3Bc62E7757377D288fDE0369',
  //   9750,
  //   '0x237a4d2166Eb65cB3f9fabBe55ef2eb5ed56bdb9'
  // ])
  // await deploy('TestSavingsVault proxy', new ERC1967Proxy__factory(deployer), impl.address, data, {})
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    logger.error(error)
    process.exit(1)
  })
