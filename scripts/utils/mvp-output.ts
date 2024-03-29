import * as wfCashBaseArtifact from '../../artifacts/src/external/notional/wfCashBase.sol/wfCashBase.json'
import * as SavingsVaultArtifact from '../../artifacts/src/SavingsVault.sol/SavingsVault.json'

import { existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const rootDirectory = join(process.cwd(), 'mvp-output')
const subgraph = join(rootDirectory, 'subgraph')
const frontend = join(rootDirectory, 'frontend')

const extract =
  <T>(properties: Record<keyof T, true>) =>
  <TActual extends T>(value: TActual): T => {
    const result = {} as unknown as T
    for (const property of Object.keys(properties) as Array<keyof T>) {
      result[property] = value[property]
    }

    return result
  }

interface FrontAddresses {
  Asset: string
  SavingsVault: string
}

const extractFrontAddresses = extract<FrontAddresses>({
  Asset: true,
  SavingsVault: true
})

interface SubgraphAddresses {
  Asset: string
  SavingsVault: string
}

const extractSubgraphAddresses = extract<SubgraphAddresses>({
  Asset: true,
  SavingsVault: true
})

export type DeploymentsAddresses = FrontAddresses & SubgraphAddresses

export interface DeploymentBlocks {
  SavingsVaultBlockNumber?: number
}

const frontedArtifacts = [SavingsVaultArtifact, wfCashBaseArtifact]

const subgraphArtifacts = [SavingsVaultArtifact, wfCashBaseArtifact]

export async function writeResults(addresses: DeploymentsAddresses, blocks: DeploymentBlocks): Promise<void> {
  createFolders()
  writeData(addresses, blocks)
  copyABIs()
}

function createFolders(): void {
  if (existsSync(rootDirectory)) {
    rmSync(rootDirectory, { recursive: true })
  }

  for (const directory of [subgraph, frontend]) mkdirSync(join(directory, 'abi'), { recursive: true, mode: 0o777 })
}

function writeData(addresses: DeploymentsAddresses, blocks: DeploymentBlocks): void {
  writeFileSync(`${frontend}/Addresses.json`, JSON.stringify(extractFrontAddresses(addresses)), 'utf8')
  writeFileSync(`${subgraph}/Addresses.json`, JSON.stringify(extractSubgraphAddresses(addresses)), 'utf8')
  writeFileSync(`${subgraph}/Blocks.json`, JSON.stringify(blocks), 'utf8')
}

function copyABIs(): void {
  for (const artifact of subgraphArtifacts) {
    writeFileSync(`${subgraph}/abi/${artifact.contractName}.json`, JSON.stringify(artifact.abi), 'utf8')
  }
  for (const artifact of frontedArtifacts) {
    writeFileSync(`${frontend}/abi/${artifact.contractName}.json`, JSON.stringify(artifact.abi), 'utf8')
  }
}
