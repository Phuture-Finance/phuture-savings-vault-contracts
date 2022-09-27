import Decimal from 'decimal.js'
import { BigNumber } from 'ethers'

export function bnToFormattedString(value: BigNumber | number, decimals: number): string {
  return new Decimal(value.toString()).div(BigNumber.from(10).pow(decimals).toString()).toString()
}

export function timestampToFormattedTime(timestamp: BigNumber): string {
  const date = new Date(timestamp.toNumber() * 1000)
  return date.toLocaleString()
}
