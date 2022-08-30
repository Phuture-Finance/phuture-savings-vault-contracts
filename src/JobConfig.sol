// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.13;

import "openzeppelin-contracts/contracts/access/Ownable.sol";

import "./interfaces/IFRPViews.sol";
import "./interfaces/IJobConfig.sol";

/// @title JobConfig functions
/// @notice Contains function for configuring phuture jobs
contract JobConfig is IJobConfig, Ownable {
    /// @notice Harvesting amount specification
    HarvestingAmount internal depositedAmount;
    /// @notice Address of frpViews
    address internal frpViews;

    constructor(address _frpViews) {
        frpViews = _frpViews;
        depositedAmount = HarvestingAmount.MAX_AMOUNT;
    }

    /// @inheritdoc IJobConfig
    function setHarvestingAmountSpecification(HarvestingAmount _harvestingAmount) external onlyOwner {
        depositedAmount = _harvestingAmount;
    }

    /// @inheritdoc IJobConfig
    function setFrpViews(address _frpViews) external onlyOwner {
        frpViews = _frpViews;
    }

    /// @inheritdoc IJobConfig
    function getDepositedAmount(address _frp) external view returns (uint amount) {
        if (depositedAmount == HarvestingAmount.MAX_AMOUNT) {
            return type(uint).max;
        } else if (depositedAmount == HarvestingAmount.MAX_DEPOSITED_AMOUNT) {
            return IFRPViews(frpViews).getMaxDepositedAmount(_frp);
        } else if (depositedAmount == HarvestingAmount.SCALED_AMOUNT) {
            amount = IFRPViews(frpViews).getMaxDepositedAmount(_frp);
            // TODO establish a more appropriate scaling logic
            // scaling amount = 10%
            for (uint i = 0; i < 10; i++) {
                if (IFRPViews(frpViews).canHarvestAmount(amount, _frp)) {
                    break;
                } else {
                    amount = (amount * 90) / 100;
                }
            }
        } else {
            revert("PHUTURE_JOB_CONFIG: UNDEFINED");
        }
    }
}
