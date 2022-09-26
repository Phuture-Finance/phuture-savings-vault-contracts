# <h1> Fixed rate product </h1>
This repository contains the smart contracts for integration with the [Notional protocol](https://github.com/notional-finance/wrapped-fcash). 
Fixed rate product is implemented according to the [ERC4626](https://eips.ethereum.org/EIPS/eip-4626) standard.

### Getting Started

 * Use Foundry: 
```bash
forge install
forge test
```

 * Use Hardhat:
```bash
npm install
npx hardhat test
```

### Features

 * Write / run tests with either Hardhat or Foundry:
```bash
forge test
# or
npx hardhat test
```

 * Use Hardhat's task framework
```bash
npx hardhat example
```

 * Install libraries with Foundry which work with Hardhat.
```bash
forge install rari-capital/solmate # Already in this repo, just an example
```

### Notes

Whenever you install new libraries using Foundry, make sure to update your `remappings.txt` file by running `forge remappings > remappings.txt`. This is required because we use `hardhat-preprocessor` and the `remappings.txt` file to allow Hardhat to resolve libraries you install with Foundry.

## Licensing

The primary license for Phuture Savings Vault V1 is the Business Source License 1.1 (`BUSL-1.1`), see [`LICENSE_PHUTURE`](./LICENSE_PHUTURE).

### Exceptions

- Files in `src/interfaces/` are licensed under `GPL-2.0-or-later` (as indicated in their SPDX headers), see [`src/interfaces/LICENSE_GPL`](./src/interfaces/LICENSE_GPL)
- Files in `src/libraries/` are licensed under `GPL-2.0-or-later` (as indicated in their SPDX headers), see [`src/libraries/LICENSE_GPL`](src/libraries/LICENSE_GPL)
- Files in `src/external/` are licensed under `MIT` (as indicated in their SPDX headers), see [`src/external/LICENSE_MIT`](src/external/LICENSE_MIT)
- All files in `test` remain unlicensed.
