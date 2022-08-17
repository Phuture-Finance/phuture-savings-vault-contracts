// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.13;

import "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import "openzeppelin-contracts/contracts/security/Pausable.sol";

import "./interfaces/IFRPVault.sol";

import "./interfaces/IPhutureJob.sol";
import "./external/interfaces/IKeep3r.sol";
import "openzeppelin-contracts/contracts/access/AccessControl.sol";

/// @title Phuture job
/// @notice Contains harvesting execution logic
contract PhutureJob is IPhutureJob, Pausable, AccessControl {
    /// @notice Responsible for all job related permissions
    bytes32 internal constant JOB_ADMIN_ROLE = keccak256("JOB_MANAGER_ROLE");
    /// @notice Role for phuture job management
    bytes32 internal constant JOB_MANAGER_ROLE = keccak256("JOB_MANAGER_ROLE");
    /// @inheritdoc IPhutureJob
    address public immutable override keep3r;

    /// @notice Checks if msg.sender has the given role's permission
    modifier onlyByRole(bytes32 role) {
        require(hasRole(role, msg.sender), "PhutureJob: FORBIDDEN");
        _;
    }

    /// @notice Pays keeper for work
    modifier payKeeper(address _keeper) {
        require(IKeep3r(keep3r).isKeeper(_keeper), "PhutureJob: !KEEP3R");
        _;
        IKeep3r(keep3r).worked(_keeper);
    }

    constructor(address _keep3r) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(JOB_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(JOB_MANAGER_ROLE, JOB_ADMIN_ROLE);

        keep3r = _keep3r;
        _pause();
    }

    /// @inheritdoc IPhutureJob
    function pause() external override onlyByRole(JOB_MANAGER_ROLE) {
        _pause();
    }

    /// @inheritdoc IPhutureJob
    function unpause() external override onlyByRole(JOB_MANAGER_ROLE) {
        _unpause();
    }

    /// @inheritdoc IPhutureJob
    function harvest(uint _maxDepositedAmount, IFRPVault _vault) external override whenNotPaused payKeeper(msg.sender) {
        _vault.harvest(_maxDepositedAmount);
    }
}
