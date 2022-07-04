'use strict'

import { BigNumber, Wallet } from 'ethers'
import { ethers } from 'hardhat'

export function assertDefined<T>(property: string, obj: T): asserts obj is NonNullable<T> {
  if (obj === undefined || obj === null) {
    throw new Error(`Undefined property: ${property}`)
  }
}

export function assertNotEmpty(property: string, value: string | undefined): string {
  assertDefined(property, value)
  if (!value) {
    throw new Error(`Empty property: ${property}`)
  }
  return value
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
  return new ethers.Wallet(value, ethers.provider)
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
  } catch (e) {
    throw new Error(`Invalid address ${property}: ${value}`)
  }
}

export function parseBool(property: string): boolean {
  return /true/i.test(process.env[property] ?? '')
}
