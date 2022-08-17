// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.13;

import "../interfaces/IFRPVault.sol";

/// @title Phuture job interface
/// @notice Contains signature verification and order execution logic
interface IPhutureJob {
    /// @notice Pause order execution
    function pause() external;

    /// @notice Unpause order execution
    function unpause() external;

    /// @notice Harvests from vault
    /// @param _maxDepositedAmount Max amount of asset to deposit to Notional
    /// @param _vault Address of the FRPVault
    function harvest(uint _maxDepositedAmount, IFRPVault _vault) external;

    /// @notice Keep3r address
    /// @return Returns address of keep3r network
    function keep3r() external view returns (address);
}
