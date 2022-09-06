// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.13;

import "../interfaces/ISavingsVaultHarvester.sol";

/// @title Harvester interface
/// @notice Contains harvesting and pausing logic
interface IHarvestingJob {
    /// @notice Pause harvesting job
    function pause() external;

    /// @notice Unpause harvesting job
    function unpause() external;

    /// @notice Harvests from vault
    /// @param _vault Address of the SavingsVault
    function harvest(ISavingsVaultHarvester _vault) external;
}
