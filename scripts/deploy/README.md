# Deployment Scenario

## Common environment variables

- `NETWORK` - network from [hardhat config](/hardhat.config.ts)
- `GAS_PRICE_GWEI` - estimated gas price for tx execution

## Deployment scripts

### 1. Deploy SavingsVault implementation and proxy contracts

- `NAME` - name of the ERC4626 vault
- `SYMBOL` - symbol of the ERC4626 vault
- `ASSET` - address of Base asset contract _(
  e.g. [0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48](https://etherscan.io/address/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
  for USDC )_
- `CURRENCY_ID` - Currency id of the asset on Notional (e.g. 3 for USDC)
- `WRAPPED_FCASH_FACTORY` - [address of wrappedfCash Factory](https://docs.notional.finance/developer-documentation/#deployed-contract-addresses)
- `NOTIONAL_ROUTER` - [address of Notional router](https://docs.notional.finance/developer-documentation/#deployed-contract-addresses)
- `MAX_LOSS` - maxLoss allowed during harvesting/withdrawal in [0 - 10_00] range
- `FEE_RECIPIENT` - address to receive fees during minting/burning
- `GAS_LIMIT_IMPLEMENTATION` - gas limit for implementation deployment
- `GAS_LIMIT_PROXY` - gas limit for proxy deployment and initialization

```shell
gasPriceGwei={GAS_PRICE_GWEI} name={NAME} symbol={SYMBOL} asset={ASSET} currencyId={CURRENCY_ID} wrappedfCashFactory={WRAPPED_FCASH_FACTORY} notionalRouter={NOTIONAL_ROUTER} maxLoss={MAX_LOSS} feeRecipient={FEE_RECIPIENT} gasLimitImpl={GAS_LIMIT_IMPLEMENTATION} gasLimitProxy={GAS_LIMIT_PROXY} npx hardhat run --network {NETWORK} scripts/deploy/001-savings-vault.deploy.ts 
```

### 2. Deploy SavingsVaultViews

```shell
npx hardhat run --network {NETWORK} scripts/deploy/002-savings-vault-views.deploy.ts 
```

### 3. Deploy JobConfig
- `SAVINGS_VAULT_VIEWS` - address of [`SavingsVaultViews`](#1-deploy-savingsvault-implementation-and-proxy-contracts) contract

```shell
savingsVaultViews={SAVINGS_VAULT_VIEWS} npx hardhat run --network {NETWORK} scripts/deploy/003-phuture-job-config.deploy.ts 
```


### 4. Deploy PhutureJob
- `KEEPER` - address of [`Keep3r V2`](https://docs.keep3r.network/registry) contract
- `JOB_CONFIG` - address of [`JobConfig`](#3-deploy-jobconfig) contract

```shell
keeperAddress={KEEPER} jobConfig={JOB_CONFIG} npx hardhat run --network {NETWORK} scripts/deploy/004-phuture-job.deploy.ts 
```

### 5. Deploy SavinsgVaultPriceViewer

```shell
npx hardhat run --network {NETWORK} scripts/deploy/005-savings-vault-price-viewer.deploy.ts 
```
