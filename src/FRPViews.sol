// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.13;

import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC4626Upgradeable.sol";

import "./external/notional/lib/DateTime.sol";
import { IWrappedfCashComplete } from "./external/notional/interfaces/IWrappedfCash.sol";
import { NotionalViews, MarketParameters } from "./external/notional/interfaces/INotional.sol";
import "./external/notional/interfaces/INotionalV2.sol";

import "./interfaces/IFRPViewer.sol";
import "./interfaces/IFRPHarvester.sol";
import "./interfaces/IFRPVault.sol";
import "./interfaces/IFRPViews.sol";

/// @title Fixed rate product vault helper view functions
/// @notice Contains helper view functions
contract FRPViews is IFRPViews {
    /// @inheritdoc IFRPViews
    function getAPY(IFRPViewer _FRP) external view returns (uint) {
        uint16 currencyId = _FRP.currencyId();
        address[2] memory fCashPositions = _FRP.getfCashPositions();
        uint8 supportedMaturities = _FRP.SUPPORTED_MATURITIES();
        uint numerator;
        uint denominator;
        for (uint i = 0; i < supportedMaturities; i++) {
            IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions[i]);
            uint fCashBalance = fCashPosition.balanceOf(address(_FRP));
            if (!fCashPosition.hasMatured() && fCashBalance != 0) {
                // settlement date is the same for 3 and 6 month markets since they both settle at the same time.
                // 3 month market matures while 6 month market rolls to become a 3 month market.
                MarketParameters memory marketParameters = NotionalViews(_FRP.notionalRouter()).getMarket(
                    currencyId,
                    fCashPosition.getMaturity(),
                    DateTime.getReferenceTime(block.timestamp) + Constants.QUARTER
                );
                uint assets = fCashPosition.convertToAssets(fCashBalance);
                numerator += marketParameters.oracleRate * assets;
                denominator += assets;
            }
        }
        if (denominator != 0) {
            return numerator / denominator;
        } else {
            return 0;
        }
    }

    /// @inheritdoc IFRPViews
    function scaleAmount(
        address _frp,
        uint _amount,
        uint _percentage,
        uint _steps
    ) external view returns (uint) {
        (
            uint maturity,
            uint32 minImpliedRate,
            uint16 currencyId,
            INotionalV2 calculationViews
        ) = getHighestYieldMarketParameters(_frp);
        (uint fCashAmount, , ) = calculationViews.getfCashLendFromDeposit(
            currencyId,
            _amount,
            maturity,
            minImpliedRate,
            block.timestamp,
            true
        );
        uint scalingAmount = (fCashAmount * _percentage) / 100;
        for (uint i = 0; i < _steps + 1; i++) {
            try
                calculationViews.getDepositFromfCashLend(
                    currencyId,
                    fCashAmount,
                    maturity,
                    minImpliedRate,
                    block.timestamp
                )
            returns (uint amountUnderlying, uint, uint8, bytes32) {
                return amountUnderlying;
            } catch {
                // If we can scale it further we continue, else we exit the for loop.
                if (fCashAmount >= scalingAmount) {
                    fCashAmount = fCashAmount - scalingAmount;
                } else {
                    break;
                }
            }
        }
        return 0;
    }

    /// @inheritdoc IFRPViews
    function getMaxDepositedAmount(address _frp) public view returns (uint maxDepositedAmount) {
        maxDepositedAmount += IERC4626Upgradeable(IERC4626Upgradeable(_frp).asset()).balanceOf(_frp);
        address[2] memory fCashPositions = IFRPViewer(_frp).getfCashPositions();
        uint8 supportedMaturities = IFRPViewer(_frp).SUPPORTED_MATURITIES();
        for (uint i = 0; i < supportedMaturities; i++) {
            IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions[i]);
            if (fCashPosition.hasMatured()) {
                uint fCashAmount = fCashPosition.balanceOf(address(this));
                if (fCashAmount != 0) {
                    maxDepositedAmount += fCashPosition.previewRedeem(fCashAmount);
                }
            }
        }
    }

    /// @inheritdoc IFRPViews
    function getHighestYieldMarketParameters(address _frp)
        public
        view
        returns (
            uint maturity,
            uint32 minImpliedRate,
            uint16 currencyId,
            INotionalV2 calculationViews
        )
    {
        (, IFRPVault.NotionalMarket memory highestYieldMarket) = IFRPHarvester(_frp).sortMarketsByOracleRate();
        maturity = highestYieldMarket.maturity;
        minImpliedRate = uint32((highestYieldMarket.oracleRate * IFRPViewer(_frp).maxLoss()) / IFRPViewer(_frp).BP());
        currencyId = IFRPViewer(_frp).currencyId();
        calculationViews = INotionalV2(IFRPViewer(_frp).notionalRouter());
    }
}
