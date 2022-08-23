import { BigNumber, BigNumberish, ContractFactory } from 'ethers'
import { parseUnits } from 'ethers/lib/utils'
import { ethers } from 'hardhat'
import { randomAddress as randomAddr } from 'hardhat/internal/hardhat-network/provider/fork/random'
import { ERC1967Proxy__factory } from '../typechain-types'

export const toUnit = (value: number): BigNumber => {
  return parseUnits(value.toString())
}

export const expandToDecimals: (decimals: number) => (n: BigNumberish) => BigNumber =
  (decimals: number) =>
  (n: BigNumberish): BigNumber =>
    BigNumber.from(n).mul(BigNumber.from(10).pow(decimals))

export const expandTo6Decimals = expandToDecimals(6)
export const expandTo8Decimals = expandToDecimals(8)
export const expandTo16Decimals = expandToDecimals(16)
export const expandTo18Decimals = expandToDecimals(18)

export const addressFromNumber = (n: number): `0x${string}` =>
  `0x${'0000000000000000000000000000000000000000'.slice(n.toString().length)}${n.toString()}`

export const pipe =
  (...fns: any[]) =>
  (...arguments_: any[]): any =>
    fns.reduce((accumulator, function_) => function_(accumulator), arguments_)

export const randomInteger = (min = 1, max = 1000): number => {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

export const randomAddress: () => string = () => randomAddr().toString()

export const toEther = (wei: BigNumber): string => {
  return ethers.utils.formatEther(wei)
}

export async function newProxyContract<T extends ContractFactory>(
  factory: T,
  values: Parameters<T['interface']['encodeFunctionData']>[1],
  constructorArguments: Array<any> = []
): Promise<ReturnType<T['attach']>> {
  const impl = await factory.deploy(...constructorArguments)
  const proxy = await new ERC1967Proxy__factory(factory.signer).deploy(
    impl.address,
    impl.interface.encodeFunctionData('initialize', values)
  )

  return impl.attach(proxy.address) as ReturnType<T['attach']>
}
