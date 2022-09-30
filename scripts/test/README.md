# Saving vault tests

To execute savings vault transactions you need to provide:

- `ACCOUNT` - address of sender
- `SAVINGS_VAULT` - address of `SavingsVault` contract
- `JOB_CONFIG` - address of `JobConfig` contract
- `AMOUNT` - amount of assets/shares to deposit/redeem
- `RECEIVER` - address of assets/shares receiver
- `MAX_LOSS` - max loss

## Run node

```bash
npx hardhat node --fork https://eth-mainnet.alchemyapi.io/v2/<API KEY> --fork-block-number <BLOCK NUMBER>
```

## Deposit

```bash
ACCOUNT={ACCOUNT} RECEIVER={RECEIVER} SAVINGS_VAULT={SAVINGS_VAULT} AMOUNT={AMOUNT} npx hardhat run --network local scripts/test/deposit.ts
```

## Redeem

```bash
ACCOUNT={ACCOUNT} RECEIVER={RECEIVER} SAVINGS_VAULT={SAVINGS_VAULT} AMOUNT={AMOUNT} MAX_LOSS={MAX_LOSS} npx hardhat run --network local scripts/test/redeem.ts
```

## Harvest

```bash
ACCOUNT={ACCOUNT} SAVINGS_VAULT={SAVINGS_VAULT} JOB_CONFIG={JOB_CONFIG} npx hardhat run --network local scripts/test/harvest.ts
```

## Preview redeem

```bash
ACCOUNT={ACCOUNT} SAVINGS_VAULT={SAVINGS_VAULT} AMOUNT={AMOUNT} npx hardhat run --network local scripts/test/previewRedeem.ts
```

## Transfer fCash

```bash
ACCOUNT={ACCOUNT} SAVINGS_VAULT={SAVINGS_VAULT} AMOUNT={AMOUNT} npx hardhat run --network local scripts/test/transferfCash.ts
```

## Deploy TestSavingsVault

```bash
PRIVATE_KEY={PRIVATE_KEY} npx hardhat run --network local scripts/test/deployTestSavingsVault.ts
```

## Harvest to the lowest yield

```bash
ACCOUNT={ACCOUNT} SAVINGS_VAULT={SAVINGS_VAULT} JOB_CONFIG={JOB_CONFIG} TO_LOWEST_YIELD={TO_LOWEST_YIELD} npx hardhat run --network local scripts/test/harvestFromMaturity.ts
```
