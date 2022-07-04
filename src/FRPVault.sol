// TODO provide appropriate license
pragma solidity 0.8.13;

import { ERC4626 } from "solmate/mixins/ERC4626.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { NotionalViews, MarketParameters } from "./notional/interfaces/INotional.sol";
import { IWrappedfCashFactory } from "./notional/interfaces/IWrappedfCashFactory.sol";
import { IWrappedfCashComplete } from "./notional/interfaces/IWrappedfCash.sol";
import { Constants } from "./notional/lib/Constants.sol";
import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

contract FRPVault is ERC4626 {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint16 public immutable currencyId;
    IWrappedfCashFactory public immutable wrappedfCashFactory;
    address public immutable notionalRouter;

    // TODO determine the correct slippage to pass
    uint public constant SLIPPAGE = 200;

    EnumerableSet.AddressSet internal fCashPositions;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint16 _currencyId,
        IWrappedfCashFactory _wrappedfCashFactory,
        address _notionalRouter
    ) ERC4626(_asset, _name, _symbol) {
        currencyId = _currencyId;
        wrappedfCashFactory = _wrappedfCashFactory;
        notionalRouter = _notionalRouter;
    }

    function totalAssets() public view override returns (uint) {
        uint assetBalance = asset.balanceOf(address(this));
        uint fCashPositionLength = fCashPositions.length();
        for (uint i = 0; i < fCashPositionLength; i++) {
            IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions.at(i));
            assetBalance = assetBalance + fCashPosition.convertToAssets(fCashPosition.balanceOf(address(this)));
        }
        return assetBalance;
    }

    function beforeWithdraw(uint assets, uint shares) internal override {
        if (asset.balanceOf(address(this)) < assets) {
            // first withdraw from the matured markets
            redeemAssetsIfMarketMatured();
            uint assetBalance = asset.balanceOf(address(this));
            if (assetBalance < assets) {
                // TODO withdraw from active maturities
            }
        }
    }

    function harvest() external {
        redeemAssetsIfMarketMatured();

        uint assetBalance = asset.balanceOf(address(this));
        if (assetBalance == 0) return;
        uint highestYieldMaturity = getHighestYieldMaturity();

        IWrappedfCashComplete highestYieldWrappedFCash = IWrappedfCashComplete(
            wrappedfCashFactory.deployWrapper(currencyId, uint40(highestYieldMaturity))
        );
        cacheFCashPosition(address(highestYieldWrappedFCash));
        uint shares = convertToShares(assetBalance, highestYieldWrappedFCash);
        highestYieldWrappedFCash.mintViaUnderlying(assetBalance, uint88(shares), address(this), 0);
    }

    function getHighestYieldMaturity() public returns (uint highestYieldMaturity) {
        MarketParameters[] memory marketParameters = NotionalViews(notionalRouter).getActiveMarkets(currencyId);
        uint highestOracleRate;
        for (uint i = 0; i < marketParameters.length; i++) {
            MarketParameters memory parameters = marketParameters[i];
            if (parameters.maturity >= block.timestamp + 2 * Constants.QUARTER) {
                // it's not 3 or 6 months maturity check the next one
                continue;
            }
            uint oracleRate = parameters.oracleRate;
            if (oracleRate > highestOracleRate) {
                highestOracleRate = oracleRate;
                highestYieldMaturity = parameters.maturity;
            }
            assert(highestYieldMaturity != 0);
        }
    }

    function redeemAssetsIfMarketMatured() public {
        uint fCashPositionLength = fCashPositions.length();
        for (uint i = 0; i < fCashPositionLength; i++) {
            IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions.at(i));
            if (fCashPosition.hasMatured()) {
                uint fCashAmount = fCashPosition.balanceOf(address(this));
                fCashPositions.remove(address(fCashPosition));
                if (fCashAmount == 0) continue;
                fCashPosition.redeemToUnderlying(fCashAmount, address(this), type(uint32).max);
            }
        }
    }

    function convertToShares(uint assetBalance, IWrappedfCashComplete highestYieldWrappedFCash)
        public
        returns (uint shares)
    {
        shares = highestYieldWrappedFCash.previewDeposit(assetBalance);
        uint assets = highestYieldWrappedFCash.convertToAssets(shares);
        require(100_000 - ((assets * 100_000) / assetBalance) <= SLIPPAGE, "FRP_VAULT: PRICE_IMPACT");
    }

    function cacheFCashPosition(address highestYieldWrappedFCash) internal {
        if (fCashPositions.contains(highestYieldWrappedFCash) == false) {
            fCashPositions.add(highestYieldWrappedFCash);
            asset.approve(highestYieldWrappedFCash, type(uint).max);
        }
    }
}
