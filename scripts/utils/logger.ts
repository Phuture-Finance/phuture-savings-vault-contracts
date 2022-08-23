import chalk from 'chalk'
import { pipe } from '../../utils/helpers'
import { requestConfirmation, shouldRequestConfirmation } from './script'

export const log = console.log
export const info = pipe(chalk.blueBright.italic, console.info)
export const success = pipe(chalk.bgGreenBright.black.italic, console.info)
export const error = pipe(chalk.bgRedBright.black, console.error)
export const fatal = pipe(chalk.bgBlack.red, console.error, process.exit)

export const addr = chalk.yellowBright.italic
export const bytes = chalk.magentaBright.bold
export const number = chalk.greenBright.underline
export const tx = chalk.cyanBright.italic

/**
 * Logs a fancy title to the console.
 * @param {string} title
 */
export function logTitle(title: string): void {
  const formattedTitle = `*** ${title} ***`
  const border = '*'.repeat(formattedTitle.length)
  log(chalk.bgYellow.black.bold(border))
  log(chalk.bgYellow.black.bold(formattedTitle))
  log(chalk.bgYellow.black.bold(border))
  log()
}

export function logInputs<T extends { [key: string]: any }>(inputs: T): T {
  info('Script inputs: ')
  console.table(inputs)

  return inputs
}

logInputs.withConfirmation = async <T extends { [key: string]: any }>(inputs: T, message?: string): Promise<T> => {
  logInputs(inputs)
  if (shouldRequestConfirmation()) {
    await requestConfirmation(message)
  }

  return inputs
}

/**
 * Logs the address to the console.
 * @param {string} address
 */
export function logAddress(address: string): void {
  info(`Address: ${addr(address)}`)
}

/**
 * Logs the transaction result to the console.
 * @param {string} txId
 */
export function logTxResult(txId: string): void {
  info(`Waiting for result of: ${tx(txId)}`)
}
