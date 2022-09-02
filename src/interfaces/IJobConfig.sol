// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.13;

/// @title JobConfig interface
/// @notice Describes function for configuring phuture jobs
interface IJobConfig {
    enum HarvestingSpecification {
        MAX_AMOUNT,
        MAX_DEPOSITED_AMOUNT,
        SCALED_AMOUNT
    }

    /// @notice Sets harvesting amount specification
    /// @param _harvestingSpecification Enum which specifies the harvesting amount calculation method
    function setHarvestingAmountSpecification(HarvestingSpecification _harvestingSpecification) external;

    /// @notice Gets harvesting amount specification
    /// @param _index Index of the harvesting specification
    /// @return returns harvesting specification
    function getHarvestingSpecification(uint _index) external returns (HarvestingSpecification);

    /// @notice Sets FRPViews contract
    /// @param _frpViews Address of the FRPViews
    function setFrpViews(address _frpViews) external;

    /// @notice Calculates the deposited amount based on the specification
    /// @param _frp Address of the FRP
    /// @return amount Amount possible to harvest
    function getDepositedAmount(address _frp) external view returns (uint amount);

    /// @notice Address of the FRPViews contract
    /// @return Returns address of the FRPViews contract
    function frpViews() external view returns (address);
}
