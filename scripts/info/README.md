# SavingsVault info

To get SavingsVault info you need to provide:

- `SAVINGS_VAULT` - address of `SavingsVault`
- `SAVINGS_VAULT_VIEWS` - address of `SavingsVaultViews`
- `NETWORK` - network from [hardhat config](/hardhat.config.ts)

### Get info

```bash
savingsVault={SAVINGS_VAULT} savingsVaultViews={SAVINGS_VAULT_VIEWS} npx hardhat run --network {NETWORK} ./scripts/info/savings-vault-details.ts
```