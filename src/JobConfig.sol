// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.13;

import "openzeppelin-contracts/contracts/access/Ownable.sol";

import "./interfaces/ISavingsVaultViews.sol";
import "./interfaces/IJobConfig.sol";
import "./external/notional/interfaces/INotionalV2.sol";

/// @title JobConfig functions
/// @notice Contains function for configuring phuture jobs
contract JobConfig is IJobConfig, Ownable {
    /// @inheritdoc IJobConfig
    uint public constant SCALING_STEPS = 3;
    /// @inheritdoc IJobConfig
    uint public constant SCALING_PERCENTAGE = 3000;
    /// @inheritdoc IJobConfig
    uint public constant SCALING_STEPS_BINARY_SEARCH = 11;
    /// @inheritdoc IJobConfig
    HarvestingSpecification public harvestingSpecification;
    /// @inheritdoc IJobConfig
    ISavingsVaultViews public savingsVaultViews;

    constructor(ISavingsVaultViews _savingsVaultViews) {
        savingsVaultViews = _savingsVaultViews;
        harvestingSpecification = HarvestingSpecification.BINARY_SEARCH_SCALED_AMOUNT;
    }

    /// @inheritdoc IJobConfig
    function setSavingsVaultViews(ISavingsVaultViews _savingsVaultViews) external onlyOwner {
        savingsVaultViews = _savingsVaultViews;
    }

    /// @inheritdoc IJobConfig
    function setHarvestingAmountSpecification(HarvestingSpecification _harvestingSpecification) external onlyOwner {
        harvestingSpecification = _harvestingSpecification;
    }

    /// @inheritdoc IJobConfig
    function getDepositedAmount(address _savingsVault) external view returns (uint) {
        if (harvestingSpecification == HarvestingSpecification.MAX_AMOUNT) {
            return type(uint).max;
        } else if (harvestingSpecification == HarvestingSpecification.MAX_DEPOSITED_AMOUNT) {
            return savingsVaultViews.getMaxDepositedAmount(_savingsVault);
        } else {
            uint amount = savingsVaultViews.getMaxDepositedAmount(_savingsVault);
            if (amount == 0) {
                return amount;
            }
            if (harvestingSpecification == HarvestingSpecification.BINARY_SEARCH_SCALED_AMOUNT) {
                return savingsVaultViews.scaleWithBinarySearch(_savingsVault, amount, SCALING_STEPS_BINARY_SEARCH);
            } else if (harvestingSpecification == HarvestingSpecification.SCALED_AMOUNT) {
                return savingsVaultViews.scaleAmount(_savingsVault, amount, SCALING_PERCENTAGE, SCALING_STEPS);
            }
        }
        return 0;
    }
}
