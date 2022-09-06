import '@nomiclabs/hardhat-etherscan'
import '@nomiclabs/hardhat-waffle'
import '@typechain/hardhat'
import 'dotenv/config'
// eslint-disable-next-line unicorn/prefer-node-protocol
import fs from 'fs'
import 'hardhat-gas-reporter'
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
const secret = process.env.PRIVATE_KEY as string

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.13',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      metadata: {
        bytecodeHash: 'none'
      },
      outputSelection: {
        '*': {
          '*': ['storageLayout']
        }
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
    savings_vault: {
      url: 'https://chain.frp.phuture.finance/',
      timeout: 100_000_000
    },
    ropsten: {
      url: `https://ropsten.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts: [secret]
    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts: [secret]
    }
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.ETHERSCAN_API_KEY as string
  },
  gasReporter: {
    enabled: !!process.env.REPORT_GAS,
    token: process.env.GAS_TOKEN,
    gasPriceApi: process.env.GAS_PRICE_API,
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    currency: process.env.COINMARKETCAP_DEFAULT_CURRENCY
  }
}

export default config
