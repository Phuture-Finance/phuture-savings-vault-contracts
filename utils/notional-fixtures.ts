import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { Signer } from 'ethers'
import * as mainnetConfig from '../eth_mainnet.json'
import {
  NotionalGovernance__factory,
  NUpgradeableBeacon__factory,
  WfCashERC4626__factory,
  WrappedfCashFactory,
  WrappedfCashFactory__factory
} from '../typechain-types'
import { impersonate, setBalance } from './evm'
import { expandTo18Decimals } from './helpers'

// eslint-disable-next-line @typescript-eslint/explicit-module-boundary-types
export async function upgradeNotionalProxy(signer: Signer) {
  const notionalGovernance = NotionalGovernance__factory.connect(mainnetConfig.notional.router, signer)

  const notionalRouterOwnable = NUpgradeableBeacon__factory.connect(mainnetConfig.notional.router, signer)
  const ownerAddress = await notionalRouterOwnable.owner()
  const owner = await impersonate(ownerAddress)
  await setBalance(owner.address, expandTo18Decimals(1_000_000))

  await notionalRouterOwnable.connect(owner).upgradeTo('0x16eD130F7A6dcAc7e3B0617A7bafa4b470189962')
  await notionalGovernance.connect(owner).updateAssetRate(1, '0x8E3D447eBE244db6D28E2303bCa86Ef3033CFAd6')
  await notionalGovernance.connect(owner).updateAssetRate(2, '0x719993E82974f5b5eA0c5ebA25c260CD5AF78E00')
  await notionalGovernance.connect(owner).updateAssetRate(3, '0x612741825ACedC6F88D8709319fe65bCB015C693')
  await notionalGovernance.connect(owner).updateAssetRate(4, '0x39D9590721331B13C8e9A42941a2B961B513E69d')
}

export async function deployWrappedfCashFactory(signer: SignerWithAddress): Promise<WrappedfCashFactory> {
  const WfCashERC4626Impl = await new WfCashERC4626__factory(signer).deploy(
    mainnetConfig.notional.router,
    mainnetConfig.WETH
  )
  const beacon = await new NUpgradeableBeacon__factory(signer).deploy(WfCashERC4626Impl.address)
  return await new WrappedfCashFactory__factory(signer).deploy(beacon.address)
}
