import type { AccessControlUpgradeable } from '@types'
import { parseBool } from '@utils/parser'
import type { BytesLike, Contract, ContractFactory, ContractReceipt, Overrides } from 'ethers'
import hre from 'hardhat'
import yesno from 'yesno'
import * as logger from './logger'

/**
 * Requests user confirmation before proceeding or exiting with an error message if the user declines.
 * @param {string} message
 * @returns {Promise<void>}
 */
export async function requestConfirmation(message = 'Ready to continue?'): Promise<void> {
  const ok = await yesno({
    yesValues: ['', 'y', 'yes'],
    question: message
  })
  if (!ok) {
    throw new Error('Script cancelled.')
  }
}

interface DeployInfo<T extends ContractFactory> {
  contract: Awaited<ReturnType<T['deploy']>>
  receipt: ContractReceipt
}

export async function deploy<T extends ContractFactory>(
  name: string,
  factory: T,
  ...parameters: Parameters<T['deploy']>
): Promise<DeployInfo<T>> {
  if (shouldRequestConfirmation()) {
    await requestConfirmation(`Would you like to deploy "${name}"?`)
  }

  try {
    logger.info(`Deploying: "${name}"...`)
    const contract = (await factory.deploy(...parameters)) as Awaited<ReturnType<T['deploy']>>
    logger.logAddress(contract.address)
    logger.logTxResult(contract.deployTransaction.hash)

    const receipt = await contract.deployTransaction.wait()
    logger.success(`Successfully deployed: "${name}"\n`)

    return { contract, receipt }
  } catch (error) {
    logger.error(`Error: ${error}`)
    await requestConfirmation('Retry?')

    return deploy(name, factory, ...parameters)
  }
}

/**
 * @see {@link https://github.com/NomicFoundation/hardhat/tree/master/packages/hardhat-etherscan#using-programmatically}
 */
deploy.withVerification = async <T extends ContractFactory>(
  name: string,
  factory: T,
  ...parameters: Parameters<T['deploy']>
): Promise<DeployInfo<T>> => {
  const result = await deploy(name, factory, ...parameters)

  try {
    await requestConfirmation(`Would you like to verify ${name} on Etherscan?`)
  } catch {
    return result
  }

  if (parameters.length === factory.interface.deploy.inputs.length + 1) {
    parameters.pop()
  }

  await hre.run('verify:verify', {
    address: result.contract.address,
    constructorArguments: parameters
  })

  return result
}

export async function transaction<T extends Contract, M extends keyof T>(
  name: string,
  contract: T,
  method: M,
  ...parameters: Parameters<T[M]>
): Promise<void> {
  if (shouldRequestConfirmation()) {
    await requestConfirmation(`Would you like to make transaction: "${name}"?`)
  }

  try {
    logger.info(`Making transaction: "${name}"...`)
    const tx = await contract[method](...parameters)
    logger.logTxResult(tx.hash)
    await tx.wait()
    logger.success(`Successfully made transaction: "${name}"\n`)
  } catch (error) {
    logger.error(`Error: ${error}`)
    await requestConfirmation('Retry?')
    await transaction(name, contract, method, ...parameters)
  }
}

export async function grantRole(
  accessControl: AccessControlUpgradeable,
  role: BytesLike,
  address: string,
  overrides?: Overrides & { from?: string | Promise<string> }
): Promise<void> {
  if (await accessControl.hasRole(role, address)) {
    return logger.info(`${logger.addr(address)} already has role ${logger.bytes(`"${role}"`)}\n`)
  }

  if (shouldRequestConfirmation()) {
    await requestConfirmation(`Would you like to grant role ${logger.bytes(`"${role}"`)} to: ${logger.addr(address)}?`)
  }

  try {
    logger.info(`Granting role: ${logger.bytes(`"${role}"`)} to: ${logger.addr(address)}...`)
    const tx = await accessControl.grantRole(role, address, overrides)
    logger.logTxResult(tx.hash)
    await tx.wait()
    logger.success(`Successfully granted role "${role}" to: "${address}"\n`)
  } catch (error) {
    logger.error(`Error: ${error}`)
    await requestConfirmation('Retry?')
    await grantRole(accessControl, role, address, overrides)
  }
}

export const shouldRequestConfirmation = (): boolean => !parseBool('SKIP_CONFIRMATION')
