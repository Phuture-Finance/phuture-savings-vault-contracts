# <h1> Savings Vault </h1>
This repository contains the smart contracts for integration with the [Notional protocol](https://github.com/notional-finance/wrapped-fcash). 
Savings Vault is implemented according to the [ERC4626](https://eips.ethereum.org/EIPS/eip-4626) standard.

### Environment
> Scripts & tests depend on several environment variables to work, as well as external services for some additional functionality.

#### Providing environment vars

You will need to create an `.env` file in the root folder and provides values for variables according to the [`.env.example`](.env.example) file.

```shell
cp .env.example .env
```

### Getting Started
In case you don't have `Foundry installed make sure to follow the steps described in the following [link](https://github.com/foundry-rs/foundry).

 * Use Foundry: 
```bash
forge install
forge build
```

 * Use Hardhat:
```bash
npm install
npx hardhat compile
```

### Features

 * Write / run tests with either Hardhat or Foundry:
```bash
forge test
# or
npx hardhat test
```

 * Install libraries with Foundry which work with Hardhat.
```bash
forge install rari-capital/solmate # Already in this repo, just an example
```
### Update dependencies

 * [Update libraries](https://book.getfoundry.sh/reference/forge/forge-update?highlight=forge%20update#forge-update) with Foundry:
```bash
forge update
```

### Notes

Whenever you install new libraries using Foundry, make sure to update your `remappings.txt` file by running `forge remappings > remappings.txt`. This is required because we use `hardhat-preprocessor` and the `remappings.txt` file to allow Hardhat to resolve libraries you install with Foundry.

The openzeppelin-contract-upgradeable library has been set to commit `54803be6` since there were some changes to how `ERC4626Upgradeable` contract handles the decimals of underlying asset in later versions. In case this library is updated, be aware that some tests are going to be failing. 

## Licensing

The primary license for Phuture Savings Vault V1 is the Business Source License 1.1 (`BUSL-1.1`), see [`LICENSE_PHUTURE`](./LICENSE_PHUTURE).

### Exceptions

- Files in `src/interfaces/` are licensed under `GPL-2.0-or-later` (as indicated in their SPDX headers), see [`src/interfaces/LICENSE_GPL`](./src/interfaces/LICENSE_GPL)
- Files in `src/libraries/` are licensed under `GPL-2.0-or-later` (as indicated in their SPDX headers), see [`src/libraries/LICENSE_GPL`](src/libraries/LICENSE_GPL)
- Files in `src/external/` are licensed under `MIT` (as indicated in their SPDX headers), see [`src/external/LICENSE_MIT`](src/external/LICENSE_MIT)
- All files in `test` remain unlicensed.
