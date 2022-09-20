# Saving vault tests

To get index info you need to provide:

- `ACCOUNT` - address of sender
- `SAVINGS_VAULT` - address of `SavingsVault` contract
- `AMOUNT` - amount of assets/shares to deposit/redeem
- `RECEIVER` - address of assets/shares receiver

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
ACCOUNT={ACCOUNT} RECEIVER={RECEIVER} SAVINGS_VAULT={SAVINGS_VAULT} AMOUNT={AMOUNT} npx hardhat run --network local scripts/test/redeem.ts
```

## Harvest

```bash
ACCOUNT={ACCOUNT} SAVINGS_VAULT={SAVINGS_VAULT} JOB_CONFIG={JOB_CONFIG} npx hardhat run --network local scripts/test/harvest.ts
```
