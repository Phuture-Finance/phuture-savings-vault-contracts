import { formatBytes32String, id } from 'ethers/lib/utils'

export const DEFAULT_ADMIN_ROLE = formatBytes32String('')

export const VAULT_ADMIN_ROLE = id('VAULT_ADMIN_ROLE')
export const VAULT_MANAGER_ROLE = id('VAULT_MANAGER_ROLE')
export const HARVESTER_ROLE = id('HARVESTER_ROLE')
