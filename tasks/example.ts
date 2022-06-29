
import { ethers } from 'hardhat'
import { ICToken__factory, IERC20__factory, INotionalV2__factory, NotionalGovernance__factory, NotionalViews__factory, NUpgradeableBeacon__factory, WfCashERC4626__factory, WrappedfCashFactory__factory} from '../typechain-types'
import { expandTo18Decimals, expandTo6Decimals, impersonate, latestBlockTimestamp, setBalance } from '../utils/utilities'
import * as mainnetConfig from '../eth_mainnet.json'

async function main() {
    const signer = await impersonate(ethers.provider, mainnetConfig.whales.USDC)
    await setBalance(ethers.provider, signer.address, expandTo18Decimals(1000000))

    const notionalRouter = NotionalViews__factory.connect(mainnetConfig.notional.router, signer)
    const notionalGovernance = NotionalGovernance__factory.connect(mainnetConfig.notional.router, signer)
    const notionalV2 = INotionalV2__factory.connect(mainnetConfig.notional.router, signer)

    const notionalRouterOwnable = NUpgradeableBeacon__factory.connect(mainnetConfig.notional.router, signer)
    const ownerAddress = await notionalRouterOwnable.owner();
    const owner = await impersonate(ethers.provider, ownerAddress)
    await setBalance(ethers.provider, owner.address, expandTo18Decimals(1000000))

    await notionalRouterOwnable.connect(owner).upgradeTo('0x16eD130F7A6dcAc7e3B0617A7bafa4b470189962')
    await notionalGovernance.connect(owner).updateAssetRate(1, "0x8E3D447eBE244db6D28E2303bCa86Ef3033CFAd6")
    await notionalGovernance.connect(owner).updateAssetRate(2, "0x719993E82974f5b5eA0c5ebA25c260CD5AF78E00")
    await notionalGovernance.connect(owner).updateAssetRate(3, "0x612741825ACedC6F88D8709319fe65bCB015C693")
    await notionalGovernance.connect(owner).updateAssetRate(4, "0x39D9590721331B13C8e9A42941a2B961B513E69d")

    const USDC = IERC20__factory.connect(mainnetConfig.USDC, signer)
    const USDCBalance = await USDC.balanceOf(signer.address)

    const WfCashERC4626Impl = await new WfCashERC4626__factory(signer).deploy(
      mainnetConfig.notional.router,
      mainnetConfig.WETH
    )
    const beacon = await new NUpgradeableBeacon__factory(signer).deploy(WfCashERC4626Impl.address)
    const wrappedfCashFactory = await new WrappedfCashFactory__factory(signer).deploy(beacon.address)
    const markets = await notionalRouter.getActiveMarkets(mainnetConfig.notional.currencyIdUSDC)
    const {maturity, oracleRate} = markets[1]
    await wrappedfCashFactory.deployWrapper(mainnetConfig.notional.currencyIdUSDC, maturity)
    const wrappedfCashAddress = await wrappedfCashFactory.computeAddress(mainnetConfig.notional.currencyIdUSDC, maturity)
    const wrappedfCash = await new WfCashERC4626__factory(signer).attach(wrappedfCashAddress)
    const notional = await wrappedfCash.NotionalV2()

    await USDC.approve(wrappedfCash.address, ethers.constants.MaxUint256)

    const deposited = expandTo6Decimals(100000)
    const blockTime = await latestBlockTimestamp(ethers.provider)
    const fCash = await wrappedfCash.convertToShares(deposited)

    const depositPreview = await notionalV2.getfCashLendFromDeposit(mainnetConfig.notional.currencyIdUSDC, deposited, maturity, 0, blockTime, true)

    await wrappedfCash.deposit(deposited, signer.address, {gasLimit: 30e6})
    const fCashFromDeposit = await wrappedfCash.balanceOf(signer.address)
    const assets = await wrappedfCash.convertToAssets(fCashFromDeposit)

    const oracleRateDenom = 1000000000;
    const oracleValue = deposited.mul(oracleRate.add(oracleRateDenom)).div(oracleRateDenom)

    const priceImpact = assets.mul(100_000).div(deposited).toNumber() / 100_000;

    const {assetToken} = await wrappedfCash.getAssetToken()
    const cToken = ICToken__factory.connect(assetToken, signer)

    await USDC.approve(cToken.address, ethers.constants.MaxUint256)
    const tx = await cToken.mint(expandTo6Decimals(1000))
    const txResult = await tx.wait()

    const lastBalance = await USDC.balanceOf(signer.address)
    await wrappedfCash['redeem(uint256,address,address)'](fCashFromDeposit, signer.address, signer.address)
    const gains = (await USDC.balanceOf(signer.address)).sub(lastBalance)


    const conversionTx = await wrappedfCash.DEBUG_convertInternal(fCash, 3)
    const conversionTxResult=  await conversionTx.wait()

    console.log('conversionTxResult', conversionTxResult.gasUsed)
    console.log('gains', deposited, gains)
    console.log('wrappedfCashAddress0', priceImpact)
    console.log('txResult.gasUsed', assetToken, txResult.gasUsed)
    console.log('USDC Balance', fCashFromDeposit, oracleValue, depositPreview.fCashAmount)
    console.log('Market', markets[1])
  }

  main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })