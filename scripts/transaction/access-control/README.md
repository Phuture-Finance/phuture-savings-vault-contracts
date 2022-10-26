# Access Control

To grant or revoke role you need to provide:

- `SAVINGS_VAULT` - address of `SavingsVault` contract
- `ADDRESS` - address of account you want to grant/revoke role
- `ROLE` - keccak256 of role
- `NETWORK` - network from [hardhat config](/hardhat.config.ts)

## Grant role

```bash
SAVINGS_VAULT={SAVINGS_VAULT} ADDRESS={ADDRESS} ROLE={ROLE} npx hardhat run --network {NETWORK} ./scripts/transaction/access-control/grant-role.ts
```

## Revoke role

```bash
SAVINGS_VAULT={SAVINGS_VAULT} ADDRESS={ADDRESS} ROLE={ROLE} npx hardhat run --network {NETWORK} ./scripts/transaction/access-control/revoke-role.ts
```

## Roles

| Role                | keccak256                                                            |
|---------------------|----------------------------------------------------------------------|
| DEFAULT_ADMIN_ROLE  | `0x0000000000000000000000000000000000000000000000000000000000000000` |
| VAULT_ADMIN_ROLE    | `0x7edcee67725a77bfa311b39349d7e96df9b23fbdbdcb328dfc17d77926920c13` |
| VAULT_MANAGER_ROLE  | `0xd1473398bb66596de5d1ea1fc8e303ff2ac23265adc9144b1b52065dc4f0934b` |
| JOB_ADMIN_ROLE      | `0x62f07d7d1d0d6a5149a535e13640259eab4facaf14c5d017e412e9cb10de5202` |
| JOB_MANAGER_ROLE    | `0x9314fad2def8e56f9df1fa7f30dc3dafd695603f8f7676a295739a12b879d2f6` |
