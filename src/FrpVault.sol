// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.13;

import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

import { NotionalViews, MarketParameters } from "./notional/interfaces/INotional.sol";
import "./notional/interfaces/IWrappedfCashFactory.sol";
import { IWrappedfCashComplete } from "./notional/interfaces/IWrappedfCash.sol";
import "./notional/lib/Constants.sol";

/// @title Fixed rate product vault
/// @notice Contains logic for integration with Notional
contract FrpVault is ERC4626Upgradeable, ERC20PermitUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Responsible for all vault related permissions
    bytes32 internal constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");
    /// @notice Role for vault
    bytes32 internal constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");

    uint16 public currencyId;
    IWrappedfCashFactory public wrappedfCashFactory;
    address public notionalRouter;

    EnumerableSet.AddressSet internal fCashPositions; // This takes 2 slots
    uint16 internal slippage;

    /// @dev Emitted when minting new FCash during harvest
    /// @param _fCashPosition    Address of wrappedFCash token
    /// @param _assetAmount      Amount of asset
    /// @param _fCashAmount      Amount of fCash minted
    event FCashMinted(IWrappedfCashComplete indexed _fCashPosition, uint _assetAmount, uint _fCashAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _asset,
        uint16 _currencyId,
        IWrappedfCashFactory _wrappedfCashFactory,
        address _notionalRouter,
        uint16 _slippage
    ) external initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(VAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(VAULT_MANAGER_ROLE, VAULT_ADMIN_ROLE);

        __ERC4626_init(IERC20MetadataUpgradeable(_asset));
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __AccessControl_init();

        currencyId = _currencyId;
        wrappedfCashFactory = _wrappedfCashFactory;
        notionalRouter = _notionalRouter;
        slippage = _slippage;
    }

    /// @notice Exchanges all the available assets into the highest yielding maturity
    function harvest() external {
        _redeemAssetsIfMarketMatured();

        uint assetBalance = IERC20Upgradeable(asset()).balanceOf(address(this));
        if (assetBalance == 0) {
            return;
        }
        uint highestYieldMaturity = _getHighestYieldingMaturity();

        IWrappedfCashComplete highestYieldWrappedFCash = IWrappedfCashComplete(
            wrappedfCashFactory.deployWrapper(currencyId, uint40(highestYieldMaturity))
        );
        _cachefCashPosition(address(highestYieldWrappedFCash));
        uint fCashAmount = _convertAssetsTofCash(assetBalance, highestYieldWrappedFCash);
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
        uint assetBalance = IERC20Upgradeable(asset()).balanceOf(address(this));
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

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _beforeWithdraw(assets);
        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transfered, which is a valid state.
        _burn(owner, shares);
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(asset()), receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @notice Loops through fCash positions and redeems into asset if position has matured
    function _redeemAssetsIfMarketMatured() internal {
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
    function _cachefCashPosition(address _highestYieldWrappedFCash) internal {
        if (!fCashPositions.contains(_highestYieldWrappedFCash)) {
            fCashPositions.add(_highestYieldWrappedFCash);
            IERC20Upgradeable(asset()).approve(_highestYieldWrappedFCash, type(uint).max);
        }
    }

    /// @notice Withdraws asset from maturities
    /// @param _assets Amount of assets for withdrawal
    function _beforeWithdraw(uint _assets) internal {
        if (IERC20Upgradeable(asset()).balanceOf(address(this)) < _assets) {
            // first withdraw from the matured markets.
            _redeemAssetsIfMarketMatured();
            uint fCashPositionLength = fCashPositions.length();
            for (uint i = 0; i < fCashPositionLength; i++) {
                // fetch the asset balance, if it is higher or equal than assets break.
                // otherwise fetch from the available maturity.
                uint assetBalance = IERC20Upgradeable(asset()).balanceOf(address(this));
                if (assetBalance >= _assets) {
                    break;
                }
                IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions.at(i));
                // For the assets needed to withdraw this is the amount of shares.
                // 10 is the buffer to avoid reverts since previewWithdraw and actual redeem differ slightly.
                uint fCashAmountNeeded = fCashPosition.previewWithdraw(_assets + 10 - assetBalance);
                uint fCashAmountAvailable = fCashPosition.balanceOf(address(this));
                if (fCashAmountNeeded > fCashAmountAvailable) {
                    // there isn't enough assets in this position, withdraw all and move to the next maturity
                    _checkPriceImpactDuringRedemption(_assets - assetBalance, fCashAmountAvailable, fCashPosition);
                    fCashPosition.redeemToUnderlying(fCashAmountAvailable, address(this), type(uint32).max);
                    fCashPositions.remove(address(fCashPosition));
                } else {
                    _checkPriceImpactDuringRedemption(0, fCashAmountNeeded, fCashPosition);
                    fCashPosition.redeemToUnderlying(fCashAmountNeeded, address(this), type(uint32).max);
                    break;
                }
            }
        }
    }

    /// @notice Checks for price impact during redemption.
    /// @dev Passing 0 as _assetAmount acts as function overload to estimate the _assetAmount for _fCashAmount
    /// @param _assetAmount Amount of asset
    /// @param _fCashAmount Amount of fCash
    /// @param _fCashPosition Address of the wrappedfCash
    function _checkPriceImpactDuringRedemption(
        uint _assetAmount,
        uint _fCashAmount,
        IWrappedfCashComplete _fCashPosition
    ) internal view {
        uint shares = _fCashPosition.convertToShares(
            _assetAmount == 0 ? _fCashPosition.previewRedeem(_fCashAmount) : _assetAmount
        );
        require(100_000 - ((shares * 100_000) / _fCashAmount) <= slippage, "FrpVault: PRICE_IMPACT");
    }

    /// @notice Picks the highest yielding maturity from currently active maturities
    /// @return highestYieldMaturity the highest yielding maturity
    function _getHighestYieldingMaturity() internal view returns (uint highestYieldMaturity) {
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

    /// @notice Converts assets to fCash amount
    /// @param _assetBalance Amount of asset
    /// @param _highestYieldWrappedfCash Address of the wrappedfCash
    /// @return fCashAmount for the asset amount
    function _convertAssetsTofCash(uint _assetBalance, IWrappedfCashComplete _highestYieldWrappedfCash)
        internal
        view
        returns (uint fCashAmount)
    {
        fCashAmount = _highestYieldWrappedfCash.previewDeposit(_assetBalance);
        uint assets = _highestYieldWrappedfCash.convertToAssets(fCashAmount);
        require(100_000 - ((assets * 100_000) / _assetBalance) <= slippage, "FrpVault: PRICE_IMPACT");
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address _newImpl) internal view virtual override {
        require(hasRole(VAULT_ADMIN_ROLE, msg.sender), "FrpVault: FORBIDDEN");
    }

    uint256[44] private __gap;
}
