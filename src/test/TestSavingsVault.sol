// SPDX-License-Identifier: Apache-2.0
pragma solidity =0.8.13;

import "../../src/SavingsVault.sol";

contract TestSavingsVault is SavingsVault {
    function harvestTo(uint _maxDepositedAmount, bool toLowestYieldMaturity) external {
        _redeemAssetsIfMarketMatured();

        (NotionalMarket memory lowestYieldMarket, NotionalMarket memory highestYieldMarket) = sortMarketsByOracleRate();

        address lowestYieldfCash = wrappedfCashFactory.deployWrapper(currencyId, uint40(lowestYieldMarket.maturity));
        address highestYieldfCash = wrappedfCashFactory.deployWrapper(currencyId, uint40(highestYieldMarket.maturity));
        _sortfCashPositions(lowestYieldfCash, highestYieldfCash);
        address fCashToMint = toLowestYieldMaturity ? lowestYieldfCash : highestYieldfCash;
        uint oracleRate = toLowestYieldMaturity ? lowestYieldMarket.oracleRate : highestYieldMarket.oracleRate;

        IERC20Upgradeable(asset()).approve(fCashToMint, _maxDepositedAmount);
        IWrappedfCashComplete(fCashToMint).mintViaUnderlying(
            _maxDepositedAmount,
            TypeConversionLibrary._safeUint88(IWrappedfCashComplete(fCashToMint).previewDeposit(_maxDepositedAmount)),
            address(this),
            TypeConversionLibrary._safeUint32((oracleRate * maxLoss) / BP)
        );
    }
}
