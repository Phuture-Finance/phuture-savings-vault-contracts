// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.13;

import "openzeppelin-contracts/contracts/access/Ownable.sol";

import "./interfaces/IFRPViews.sol";
import "./interfaces/IJobConfig.sol";

/// @title JobConfig functions
/// @notice Contains function for configuring phuture jobs
contract JobConfig is IJobConfig, Ownable {
    /// @notice Harvesting amount specification
    HarvestingSpecification internal harvestingSpecification;
    /// @notice Address of frpViews
    address internal frpViews;

    constructor(address _frpViews) {
        frpViews = _frpViews;
        harvestingSpecification = HarvestingSpecification.MAX_AMOUNT;
    }

    /// @inheritdoc IJobConfig
    function setHarvestingAmountSpecification(HarvestingSpecification _harvestingSpecification) external onlyOwner {
        harvestingSpecification = _harvestingSpecification;
    }

    /// @inheritdoc IJobConfig
    function setFrpViews(address _frpViews) external onlyOwner {
        frpViews = _frpViews;
    }

    /// @inheritdoc IJobConfig
    function getDepositedAmount(address _frp) external view returns (uint amount) {
        if (harvestingSpecification == HarvestingSpecification.MAX_AMOUNT) {
            amount = type(uint).max;
        } else if (harvestingSpecification == HarvestingSpecification.MAX_DEPOSITED_AMOUNT) {
            amount = IFRPViews(frpViews).getMaxDepositedAmount(_frp);
        } else {
            amount = IFRPViews(frpViews).getMaxDepositedAmount(_frp);
            address _frpViews = frpViews;
            IWrappedfCashComplete highestYieldFCash = IWrappedfCashComplete(
                IFRPViews(frpViews).getHighestYieldfCash(_frp)
            );
            if (harvestingSpecification == HarvestingSpecification.LINEAR_SCALED_AMOUNT) {
                for (uint i = 0; i < 10; i++) {
                    if (IFRPViews(_frpViews).canHarvestAmount(amount, _frp, highestYieldFCash)) {
                        break;
                    } else {
                        amount = (amount * 90) / 100;
                    }
                }
            } else if (harvestingSpecification == HarvestingSpecification.SLIPPAGE_SCALED_AMOUNT) {
                bool canHarvest;
                while (!canHarvest) {
                    (canHarvest, amount) = IFRPViews(_frpViews).canHarvestScaledAmount(amount, _frp, highestYieldFCash);
                }
            } else {
                revert("PHUTURE_JOB_CONFIG: UNDEFINED");
            }
        }
    }
}
