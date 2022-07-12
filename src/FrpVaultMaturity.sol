// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.13;

import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import "./FrpVaultLowestYieldWithdrawal.sol";

contract FrpVaultMaturity is FrpVaultLowestYieldWithdrawal {
    using EnumerableSet for EnumerableSet.AddressSet;

    function _beforeWithdraw(
        address _asset,
        uint _assets,
        uint _maxSlippage
    ) internal override {
        if (IERC20Upgradeable(_asset).balanceOf(address(this)) < _assets) {
            // first withdraw from the matured markets.
            _redeemAssetsIfMarketMatured();
            uint assetBalance = IERC20Upgradeable(_asset).balanceOf(address(this));
            if (assetBalance < _assets) {
                uint amountNeeded = _assets + 10 - assetBalance;
                uint fCashPositionLength = fCashPositions.length();
                for (uint i = 0; i < fCashPositionLength; i++) {
                    IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions.at(i));

                    uint fCashAmountNeeded = fCashPosition.previewWithdraw(amountNeeded);
                    uint fCashAmountAvailable = fCashPosition.balanceOf(address(this));
                    if (fCashAmountAvailable == 0) {
                        continue;
                    }
                    if (fCashAmountNeeded > fCashAmountAvailable) {
                        // there isn't enough assets in this position, withdraw all and move to the next maturity
                        _checkPriceImpactDuringRedemption(
                            _assets - assetBalance,
                            fCashAmountAvailable,
                            fCashPosition,
                            _maxSlippage
                        );
                        fCashPosition.redeemToUnderlying(fCashAmountAvailable, address(this), type(uint32).max);
                        amountNeeded = amountNeeded - IERC20Upgradeable(_asset).balanceOf(address(this));
                    } else {
                        _checkPriceImpactDuringRedemption(0, fCashAmountNeeded, fCashPosition, _maxSlippage);
                        fCashPosition.redeemToUnderlying(fCashAmountNeeded, address(this), type(uint32).max);
                        break;
                    }
                }
            }
        }
    }
}
