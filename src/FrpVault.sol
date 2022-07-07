// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.13;

import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/introspection/ERC165CheckerUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

import "./ERC20.sol";
import "./ERC4626.sol";
import { NotionalViews, MarketParameters } from "./notional/interfaces/INotional.sol";
import "./notional/interfaces/IWrappedfCashFactory.sol";
import { IWrappedfCashComplete } from "./notional/interfaces/IWrappedfCash.sol";
import "./notional/lib/Constants.sol";
import "./interfaces/IERC4626Upgradeable.sol";

/// @title Fixed rate product vault
/// @notice Contains logic for integration with Notional
contract FrpVault is ERC4626, AccessControlUpgradeable, UUPSUpgradeable {
    using ERC165CheckerUpgradeable for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Responsible for all vault related permissions
    bytes32 internal constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");
    /// @notice Role for vault
    bytes32 internal constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");

    uint16 public immutable currencyId;
    IWrappedfCashFactory public immutable wrappedfCashFactory;
    address public immutable notionalRouter;

    EnumerableSet.AddressSet internal fCashPositions; // This takes 2 slots
    uint16 internal slippage;

    /// @dev Emitted when minting new FCash during harvest
    /// @param _fCashPosition    Address of wrappedFCash token
    /// @param _assetAmount      Amount of asset
    /// @param _fCashAmount      Amount of fCash minted
    event FCashMinted(IWrappedfCashComplete indexed _fCashPosition, uint _assetAmount, uint _fCashAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        ERC20 _asset,
        uint16 _currencyId,
        IWrappedfCashFactory _wrappedfCashFactory,
        address _notionalRouter
    ) ERC4626(_asset) initializer {
        currencyId = _currencyId;
        wrappedfCashFactory = _wrappedfCashFactory;
        notionalRouter = _notionalRouter;
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        uint16 _slippage
    ) external initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(VAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(VAULT_MANAGER_ROLE, VAULT_ADMIN_ROLE);

        __AccessControl_init();
        __ERC4626_init(_name, _symbol);
        slippage = _slippage;
    }

    /// @notice Exchanges all the available assets into the highest yielding maturity
    function harvest() external {
        redeemAssetsIfMarketMatured();

        uint assetBalance = asset.balanceOf(address(this));
        if (assetBalance == 0) {
            return;
        }
        uint highestYieldMaturity = getHighestYieldingMaturity();

        IWrappedfCashComplete highestYieldWrappedFCash = IWrappedfCashComplete(
            wrappedfCashFactory.deployWrapper(currencyId, uint40(highestYieldMaturity))
        );
        cachefCashPosition(address(highestYieldWrappedFCash));
        uint fCashAmount = convertAssetsTofCash(assetBalance, highestYieldWrappedFCash);
        highestYieldWrappedFCash.mintViaUnderlying(assetBalance, uint88(fCashAmount), address(this), 0);
        emit FCashMinted(highestYieldWrappedFCash, assetBalance, fCashAmount);
    }

    /// @notice Sets slippage
    /// @param _slippage slippage
    function setSlippage(uint16 _slippage) external {
        require(hasRole(VAULT_MANAGER_ROLE, msg.sender), "FrpVault: FORBIDDEN");
        slippage = _slippage;
    }

    function totalAssets() public view override returns (uint) {
        uint assetBalance = asset.balanceOf(address(this));
        uint fCashPositionLength = fCashPositions.length();
        for (uint i = 0; i < fCashPositionLength; i++) {
            IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions.at(i));
            uint fCashBalance = fCashPosition.balanceOf(address(this));
            if (fCashBalance != 0) {
                assetBalance = assetBalance + fCashPosition.convertToAssets(fCashBalance);
            }
        }
        return assetBalance;
    }

    /// @notice Converts assets to fCash amount
    /// @param _assetBalance Amount of asset
    /// @param _highestYieldWrappedfCash Address of the wrappedfCash
    /// @return fCashAmount for the asset amount
    function convertAssetsTofCash(uint _assetBalance, IWrappedfCashComplete _highestYieldWrappedfCash)
        public
        view
        returns (uint fCashAmount)
    {
        fCashAmount = _highestYieldWrappedfCash.previewDeposit(_assetBalance);
        uint assets = _highestYieldWrappedfCash.convertToAssets(fCashAmount);
        require(100_000 - ((assets * 100_000) / _assetBalance) <= slippage, "FrpVault: PRICE_IMPACT");
    }

    /// @notice Loops through fCash positions and redeems into asset if position has matured
    function redeemAssetsIfMarketMatured() internal {
        uint fCashPositionLength = fCashPositions.length();
        for (uint i = 0; i < fCashPositionLength; i++) {
            IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions.at(i));
            if (fCashPosition.hasMatured()) {
                uint fCashAmount = fCashPosition.balanceOf(address(this));
                fCashPositions.remove(address(fCashPosition));
                if (fCashAmount == 0) {
                    continue;
                }
                fCashPosition.redeemToUnderlying(fCashAmount, address(this), type(uint32).max);
            }
        }
    }

    /// @notice Caches fCash position
    /// @param _highestYieldWrappedFCash Address of the wrappedfCash
    function cachefCashPosition(address _highestYieldWrappedFCash) internal {
        if (!fCashPositions.contains(_highestYieldWrappedFCash)) {
            fCashPositions.add(_highestYieldWrappedFCash);
            asset.approve(_highestYieldWrappedFCash, type(uint).max);
        }
    }

    function beforeWithdraw(uint assets, uint shares) internal override {
        if (asset.balanceOf(address(this)) < assets) {
            // first withdraw from the matured markets
            redeemAssetsIfMarketMatured();
            uint assetBalance = asset.balanceOf(address(this));
            if (assetBalance < assets) {
                // TODO withdraw from active maturities
            }
        }
    }

    /// @notice Picks the highest yielding maturity from currently active maturities
    /// @return highestYieldMaturity the highest yielding maturity
    function getHighestYieldingMaturity() internal view returns (uint highestYieldMaturity) {
        MarketParameters[] memory marketParameters = NotionalViews(notionalRouter).getActiveMarkets(currencyId);
        uint highestOracleRate;
        for (uint i = 0; i < marketParameters.length; i++) {
            MarketParameters memory parameters = marketParameters[i];
            if (parameters.maturity >= block.timestamp + 2 * Constants.QUARTER) {
                // it's not 3 or 6 months maturity check the next one
                continue;
            }
            uint oracleRate = parameters.oracleRate;
            if (oracleRate > highestOracleRate) {
                highestOracleRate = oracleRate;
                highestYieldMaturity = parameters.maturity;
            }
            assert(highestYieldMaturity != 0);
        }
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address _newImpl) internal view virtual override {
        require(hasRole(VAULT_ADMIN_ROLE, msg.sender), "FrpVault: FORBIDDEN");
    }

    uint256[47] private __gap;
}
