import { BigNumber, Wallet } from 'ethers'
import { ethers } from 'hardhat'

export function assert<T>(property: string, value: T | undefined): T {
  assertDefined(property, value)
  return value
}

export function assertNotEmpty(property: string, value: string | undefined): string {
  assertDefined(property, value)
  if (!value) {
    throw new Error(`Empty property: ${property}`)
  }
  return value
}

export function assertNotEmptyArray<T>(property: string, value: T[] | undefined): T[] {
  if (!Array.isArray(value)) {
    throw new TypeError(`Empty property: ${property} is not array`)
  }
  if (value.length === 0) {
    throw new Error(`Empty property: ${property} is empty array`)
  }
  return value
}

export function assertDefined<T>(property: string, object: T): asserts object is NonNullable<T> {
  if (object === undefined || object === null) {
    throw new Error(`Undefined property: ${property}`)
  }
}

export function parseETH(property: string): BigNumber {
  return parseBigNumber(property, 18)
}

export function parseString(property: string): string {
  const value = process.env[property]
  assertDefined(property, value)
  assertNotEmpty(property, value)
  return value
}

export function parseWallet(property: string): Wallet {
  const value = process.env[property]
  assertDefined(property, value)
  assertNotEmpty(property, value)
  return new Wallet(value, ethers.provider)
}

export function parseBigNumber(property: string, decimals: number): BigNumber {
  const value = process.env[property]
  assertDefined(property, value)
  assertNotEmpty(property, value)
  return ethers.utils.parseUnits(value, decimals)
}

export function parseEthAddress(property: string): string {
  const value = process.env[property]
  assertDefined(property, value)
  try {
    return ethers.utils.getAddress(value)
  } catch {
    throw new Error(`Invalid address ${property}: ${value}`)
  }
}

export function parseBool(property: string): boolean {
  return /true/i.test(process.env[property] ?? '')
}
