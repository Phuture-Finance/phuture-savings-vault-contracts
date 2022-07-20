import '@nomiclabs/hardhat-waffle'
import '@typechain/hardhat'
import 'dotenv/config'
// eslint-disable-next-line unicorn/prefer-node-protocol
import fs from 'fs'
import 'hardhat-log-remover'
import 'hardhat-preprocessor'
import { HardhatUserConfig } from 'hardhat/config'

import { accounts } from './utils/accounts'

/* eslint-disable unicorn/prefer-regexp-test */

function getRemappings() {
  return fs
    .readFileSync('remappings.txt', 'utf8')
    .split('\n')
    .filter(Boolean)
    .map(line => line.trim().split('='))
}

// task("example", "Example task").setAction(example);

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.13',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  paths: {
    sources: './src', // Use ./src rather than ./contracts as Hardhat expects
    cache: './cache_hardhat' // Use a different cache for Hardhat than Foundry
  },
  // This fully resolves paths for imports in the ./lib directory for Hardhat
  preprocess: {
    eachLine: () => ({
      transform: (line: string) => {
        if (line.match(/^\s*import /i)) {
          for (const [find, replace] of getRemappings()) {
            if (line.match(find)) {
              line = line.replace(find, replace)
            }
          }
        }
        return line
      }
    })
  },
  networks: {
    hardhat: {
      accounts,
      forking: {
        enabled: !!process.env.FORK,
        url: process.env.MAINNET_HTTPS_URL as string
      },
      blockGasLimit: 30_000_000
    },
    frp: {
      url: 'https://chain.frp.phuture.finance/',
      timeout: 100_000_000
    }
  }
}

export default config
