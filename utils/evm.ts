import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import type { BigNumber, BigNumberish } from 'ethers'
import { BaseContract } from 'ethers'
import { ethers, network } from 'hardhat'

export async function impersonate(address: string): Promise<SignerWithAddress> {
  await network.provider.send('hardhat_impersonateAccount', [address])
  return SignerWithAddress.create(ethers.provider.getSigner(address))
}

export async function reset(forking?: { [key: string]: any }): Promise<void> {
  await network.provider.send('hardhat_reset', forking ? [{ forking }] : [])
}

export async function setBalance(address: string, amount: BigNumber): Promise<void> {
  await network.provider.send('hardhat_setBalance', [address, amount.toHexString()])
}

export async function increaseTimeAndBlock(timestamp: number): Promise<void> {
  await increaseTime(timestamp)
  await mineBlocks(1)
}

export async function mineBlock(timestamp: number): Promise<void> {
  await network.provider.send('evm_setNextBlockTimestamp', [timestamp])
}

export async function mineBlocks(count: number): Promise<void> {
  for (let index = 0; index < count; index++) {
    await network.provider.send('evm_mine', [])
  }
}

export async function mineBlockAtTime(timestamp: number): Promise<void> {
  await network.provider.send('evm_mine', [timestamp])
}

export async function increaseTime(timestamp: number): Promise<void> {
  await network.provider.send('evm_increaseTime', [timestamp])
}

export async function latestBlockTimestamp(): Promise<number> {
  const latestBlock = await ethers.provider.getBlock('latest')
  return latestBlock.timestamp
}

export async function getStorageAt(contract: BaseContract, slot: BigNumberish, hexStripZeroes = true): Promise<string> {
  const storage = await ethers.provider.getStorageAt(contract.address, slot)
  return hexStripZeroes ? ethers.utils.hexStripZeros(storage) : storage
}

class SnapshotManager {
  snapshots: { [id: string]: string } = {}

  async take(): Promise<string> {
    const id = await this.takeSnapshot()
    this.snapshots[id] = id
    return id
  }

  async revert(id: string): Promise<void> {
    await this.revertSnapshot(this.snapshots[id])
    this.snapshots[id] = await this.takeSnapshot()
  }

  private async takeSnapshot(): Promise<string> {
    return (await network.provider.request({
      method: 'evm_snapshot',
      params: []
    })) as string
  }

  private async revertSnapshot(id: string) {
    await network.provider.request({
      method: 'evm_revert',
      params: [id]
    })
  }
}

export const snapshot = new SnapshotManager()
