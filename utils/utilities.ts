'use strict'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { BigNumber, BigNumberish, Contract, ContractTransaction } from 'ethers'
import { solidityPack } from 'ethers/lib/utils'
import { ethers } from 'hardhat'
import yesno from 'yesno'
import { parseBool } from './parse'

export function getUid(address: string, id: BigNumberish): string {
  return ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(['address', 'uint'], [address, id]))
}

export function expandTo18Decimals(n: number): BigNumber {
  return BigNumber.from(n).mul(BigNumber.from(10).pow(18))
}

export function expandTo6Decimals(n: number): BigNumber {
  return BigNumber.from(n).mul(BigNumber.from(10).pow(6))
}

export function logTitle(title: string): void {
  const formattedTitle = `*** ${title} ***`
  const border = Array(formattedTitle.length).fill('*').join('')
  console.log(`
${border}
${formattedTitle}
${border}
`)
}

export async function requestConfirmation(message = 'Ready to continue?'): Promise<void> {
  const ok = await yesno({
    yesValues: ['', 'yes', 'y', 'yes'],
    question: message
  })
  if (!ok) {
    throw new Error('Script cancelled.')
  }
}

export function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}

export function logAddress(address: string): void {
  console.log(`Address: \x1b[32m${address}\x1b[0m`)
}

export function logTxResult(txId: string): void {
  console.log(`Waiting for result of: \x1b[36m${txId}\x1b[0m`)
}

export async function deploy<T extends Contract>(name: string, promise: Promise<T>): Promise<T> {
  if (shouldRequestConfirmation()) {
    await requestConfirmation(`Would you like to deploy "${name}"?`)
  }
  console.log(`Deploying: "${name}"...`)
  const contract = await promise
  logAddress(contract.address)
  logTxResult(contract.deployTransaction.hash)
  await contract.deployTransaction.wait()
  console.log(`Successfully deployed: "${name}"`)
  return contract
}

export async function transaction(name: string, promise: Promise<ContractTransaction>): Promise<void> {
  if (shouldRequestConfirmation()) {
    await requestConfirmation(`Would you like to make transaction: "${name}"?`)
  }

  console.log(`Making transaction: "${name}"...`)
  const tx = await promise
  logTxResult(tx.hash)
  await tx.wait()
  console.log(`Successfully made transaction: "${name}"`)
}

function shouldRequestConfirmation(): boolean {
  const skipConfirmation = parseBool('SKIP_CONFIRMATION')
  return !skipConfirmation
}

export async function latestBlockTimestamp(provider: typeof ethers.provider): Promise<number> {
  const latestBlockNumber = await provider.getBlockNumber()
  const block = await provider.getBlock(latestBlockNumber)
  return block.timestamp
}

export async function impersonate(provider: typeof ethers.provider, address: string): Promise<SignerWithAddress> {
  await provider.send('hardhat_impersonateAccount', [address])
  return SignerWithAddress.create(ethers.provider.getSigner(address))
}

export async function setBalance(
  provider: typeof ethers.provider,
  address: string,
  amount: BigNumberish
): Promise<void> {
  await provider.send('hardhat_setBalance', [address, BigNumber.from(amount).toHexString()])
}

export async function mineBlocks(provider: typeof ethers.provider, count: number): Promise<void> {
  for (let i = 1; i < count; i++) {
    await provider.send('evm_mine', [])
  }
}

export function getUnixTimestamp(date: Date): number {
  return Math.floor(date.getTime() / 1000)
}

export async function mineBlockAtTime(provider: typeof ethers.provider, timestamp: number): Promise<void> {
  await provider.send('evm_mine', [timestamp])
}

export async function increaseTime(provider: typeof ethers.provider, timestamp: number): Promise<void> {
  await provider.send('evm_increaseTime', [timestamp])
}

export async function setAutomine(provider: typeof ethers.provider, automine: boolean): Promise<void> {
  await provider.send('evm_setAutomine', [automine])
}

export function formatJson(data: string): string {
  if (data[0] != '[') {
    const arr = '[' + data.replace(/\n$/, '').slice(0, -1) + ']' // We remove last character, because it was ,
    console.log(arr)
    return arr
  }
  return data
}

export const Q112 = BigNumber.from(2).pow(112)

export function toUQ112(value: BigNumberish): BigNumber {
  return BigNumber.from(value).mul(BigNumber.from(2).pow(112))
}

export function merkleHash(address: string, allocation: BigNumber): Buffer {
  const packed = solidityPack(['address', 'uint256'], [address, allocation])
  return Buffer.from(ethers.utils.arrayify(ethers.utils.keccak256(packed)))
}
