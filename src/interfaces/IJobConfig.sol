// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.13;

/// @title JobConfig interface
/// @notice Describes function for configuring phuture jobs
interface IJobConfig {
    enum HarvestingSpecification {
        MAX_AMOUNT,
        MAX_DEPOSITED_AMOUNT,
        LINEAR_SCALED_AMOUNT,
        SLIPPAGE_SCALED_AMOUNT
    }

    /// @notice Sets harvesting amount specification
    /// @param _harvestingSpecification Enum which specifies the harvesting amount calculation method
    function setHarvestingAmountSpecification(HarvestingSpecification _harvestingSpecification) external;

    function getHarvestingSpecification(uint index) external returns (HarvestingSpecification);

    /// @notice FRPViews contract address
    /// @param _frpViews Address of the FRPViews
    function setFrpViews(address _frpViews) external;

    /// @notice Calculates the deposited amount based on the specification
    /// @param _frp Address of the FRP
    /// @return amount Amount possible to harvest
    function getDepositedAmount(address _frp) external view returns (uint amount);
}
