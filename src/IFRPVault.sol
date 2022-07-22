// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.13;

import "./notional/interfaces/IWrappedfCashFactory.sol";
import { IWrappedfCashComplete } from "./notional/interfaces/IWrappedfCash.sol";

/// @title Fixed rate product vault interface
/// @notice Describes functions for integration with Notional
interface IFRPVault {
    struct NotionalMarket {
        uint maturity;
        uint oracleRate;
    }

    /// @dev Emitted when minting new FCash during harvest
    /// @param _fCashPosition    Address of wrappedFCash token
    /// @param _assetAmount      Amount of asset
    /// @param _fCashAmount      Amount of fCash minted
    event FCashMinted(IWrappedfCashComplete indexed _fCashPosition, uint _assetAmount, uint _fCashAmount);

    /// @notice Initializes FrpVault
    /// @param _name Name of the vault
    /// @param _symbol Symbol of the vault
    /// @param _asset Underlying asset which the vault holds
    /// @param _currencyId Currency id of the asset at Notional
    /// @param _wrappedfCashFactory Address of the deployed fCashFactory
    /// @param _notionalRouter Address of the deployed notional router
    /// @param _maxLoss Maximum loss allowed
    /// @param _feeRecipient Address of the feeRecipient
    function initialize(
        string memory _name,
        string memory _symbol,
        address _asset,
        uint16 _currencyId,
        IWrappedfCashFactory _wrappedfCashFactory,
        address _notionalRouter,
        uint16 _maxLoss,
        address _feeRecipient
    ) external;

    /// @notice Exchanges all the available assets into the highest yielding maturity
    /// @param _maxDepositedAmount Max amount of asset to deposit to Notional
    function harvest(uint _maxDepositedAmount) external;

    /// @notice Sets maxLoss
    /// @dev Max loss range is [0 - 10_000]
    /// @param _maxLoss Maximum loss allowed
    function setMaxLoss(uint16 _maxLoss) external;

    /// @notice AUM scaled per seconds rate
    /// @return Returns AUM scaled per seconds rate
    function AUM_SCALED_PER_SECONDS_RATE() external view returns (uint);

    /// @notice Minting fee in basis point format [0 - 10_000]
    /// @return Returns minting fee in base point (BP) format
    function MINTING_FEE_IN_BP() external view returns (uint);

    /// @notice Burning fee in base point format [0 - 10_000]
    /// @return Returns burning fee in base point (BP) format
    function BURNING_FEE_IN_BP() external view returns (uint);

    /// @notice Currency id of asset on Notional
    /// @return Returns currency id of the asset in the vault
    function currencyId() external view returns (uint16);

    /// @notice Address of Notional router
    /// @return Returns address of main Notional router contract
    function notionalRouter() external view returns (address);

    /// @notice Address of wrappedfCash factory
    /// @return Returns address of wrappedfCashFactory
    function wrappedfCashFactory() external view returns (IWrappedfCashFactory);
}
