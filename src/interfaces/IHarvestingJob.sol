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
    function harvest(address _vault) external;

    /// @notice Sets timeout for harvesting
    /// @param _timeout Time between two harvests
    /// @param _savingsVault Vault to set timeout for
    function setTimeout(uint32 _timeout, address _savingsVault) external;

    /// @notice Check if can harvest based on time passed
    /// @param _vault Address of the SavingsVault
    /// @return Returns true if can harvest
    function canHarvest(address _vault) external view returns (bool);

    /// @notice Timestamp of last harvest
    /// @param _vault Address of the SavingsVault
    /// @return Returns timestamp of last harvest
    function lastHarvest(address _vault) external view returns (uint96);

    /// @notice Timout for a specific vault
    /// @param _vault Address of the SavingsVault
    /// @return Returns timeout for a specific vault
    function timeout(address _vault) external view returns (uint32);
}
