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
- `TIMEOUT` - minimum time required to pass between two harvests
- `GAS_LIMIT_IMPLEMENTATION` - gas limit for implementation deployment
- `GAS_LIMIT_PROXY` - gas limit for proxy deployment and initialization

```shell
GAS_PRICE_GWEI={GAS_PRICE_GWEI} name={NAME} symbol={SYMBOL} asset={ASSET} currencyId={CURRENCY_ID} wrappedfCashFactory={WRAPPED_FCASH_FACTORY} notionalRouter={NOTIONAL_ROUTER} maxLoss={MAX_LOSS} feeRecipient={FEE_RECIPIENT} timeout={TIMEOUT} gasLimitImpl={GAS_LIMIT_IMPLEMENTATION} gasLimitProxy={GAS_LIMIT_PROXY} npx hardhat run --network {NETWORK} scripts/deploy/001-savings-vault.deploy.ts 
```