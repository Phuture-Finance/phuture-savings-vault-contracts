// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.13;

import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
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
    using SafeERC20Upgradeable for IERC20Upgradeable;
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

    struct NotionalMarket {
        uint maturity;
        uint oracleRate;
    }

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

        NotionalMarket[] memory threeAndSixMonthMarkets = _getThreeAndSixMonthMarkets();
        (uint lowestYieldMaturity, uint highestYieldMaturity) = _sortMarketsByOracleRate(threeAndSixMonthMarkets);

        address lowestYieldFCash = _wrappedfCashFactory.deployWrapper(_currencyId, uint40(lowestYieldMaturity));
        address highestYieldFCash = _wrappedfCashFactory.deployWrapper(_currencyId, uint40(highestYieldMaturity));
        fCashPositions.add(lowestYieldFCash);
        fCashPositions.add(highestYieldFCash);
        IERC20Upgradeable(_asset).approve(highestYieldFCash, type(uint).max);
        IERC20Upgradeable(_asset).approve(lowestYieldFCash, type(uint).max);
    }

    /// @notice Exchanges all the available assets into the highest yielding maturity
    function harvest() external {
        bool marketHasMatured = _redeemAssetsIfMarketMatured();
        // either maxAsset or asset whichever is higher
        address _asset = asset();
        uint assetBalance = IERC20Upgradeable(_asset).balanceOf(address(this));
        if (assetBalance == 0) {
            return;
        }
        NotionalMarket[] memory threeAndSixMonthMarkets = _getThreeAndSixMonthMarkets();
        (uint lowestYieldMaturity, uint highestYieldMaturity) = _sortMarketsByOracleRate(threeAndSixMonthMarkets);

        IWrappedfCashFactory _wrappedfCashFactory = wrappedfCashFactory;
        uint16 _currencyId = currencyId;
        address lowestYieldFCash = _wrappedfCashFactory.deployWrapper(_currencyId, uint40(lowestYieldMaturity));
        address highestYieldFCash = _wrappedfCashFactory.deployWrapper(_currencyId, uint40(highestYieldMaturity));
        _sortMaturities(lowestYieldFCash, highestYieldFCash, marketHasMatured);

        uint fCashAmount = _convertAssetsTofCash(assetBalance, IWrappedfCashComplete(highestYieldFCash));
        _safeApprove(_asset, highestYieldFCash, fCashAmount);

        IWrappedfCashComplete(highestYieldFCash).mintViaUnderlying(assetBalance, uint88(fCashAmount), address(this), 0);
        emit FCashMinted(IWrappedfCashComplete(highestYieldFCash), assetBalance, fCashAmount);
    }

    /// @notice Sets slippage
    /// @param _slippage slippage
    function setSlippage(uint16 _slippage) external {
        require(hasRole(VAULT_MANAGER_ROLE, msg.sender), "FrpVault: FORBIDDEN");
        slippage = _slippage;
    }

    /// @notice Sets slippage
    function withdraw(
        uint assets,
        address receiver,
        address owner,
        uint maxSlippage
    ) external returns (uint) {
        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

        uint256 shares = previewWithdraw(assets);
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }
        address asset = asset();
        _beforeWithdraw(asset, assets, maxSlippage);
        _burn(owner, shares);
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(asset), receiver, assets);

        emit Withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint maxSlippage
    ) external returns (uint) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        uint256 assets = previewRedeem(shares);
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }
        address asset = asset();
        _beforeWithdraw(asset, assets, maxSlippage);
        _burn(owner, shares);
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(asset), receiver, assets);

        emit Withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
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
        uint assets,
        uint shares
    ) internal override {
        // put super._withdraw()
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        address asset = asset();
        _beforeWithdraw(asset, assets, slippage);
        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transfered, which is a valid state.
        _burn(owner, shares);
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(asset), receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @notice Loops through fCash positions and redeems into asset if position has matured
    function _redeemAssetsIfMarketMatured() internal returns (bool) {
        // if market has matured returns true which means we need to cache the markets again.
        bool marketHasMatured;
        uint fCashPositionLength = fCashPositions.length();
        for (uint i = 0; i < fCashPositionLength; i++) {
            IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions.at(i));
            if (fCashPosition.hasMatured()) {
                marketHasMatured = true;
                uint fCashAmount = fCashPosition.balanceOf(address(this));
                if (fCashAmount != 0) {
                    fCashPosition.redeemToUnderlying(fCashAmount, address(this), type(uint32).max);
                }
            }
        }
        return marketHasMatured;
    }

    /// @notice Withdraws asset from maturities
    /// @param _assets Amount of assets for withdrawal
    function _beforeWithdraw(
        address _asset,
        uint _assets,
        uint _maxSlippage
    ) internal virtual {
        if (IERC20Upgradeable(_asset).balanceOf(address(this)) < _assets) {
            // first withdraw from the matured markets.
            _redeemAssetsIfMarketMatured();
            uint assetBalance = IERC20Upgradeable(_asset).balanceOf(address(this));
            if (assetBalance < _assets) {
                uint amountNeeded = _assets + 1_000 - assetBalance;
                uint fCashPositionLength = fCashPositions.length();
                for (uint i = 0; i < fCashPositionLength; i++) {
                    IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions.at(i));

                    uint fCashAmountNeeded = fCashPosition.previewWithdraw(amountNeeded);
                    uint fCashAmountAvailable = fCashPosition.balanceOf(address(this));

                    if (fCashAmountAvailable == 0) {
                        continue;
                    }

                    if (fCashAmountNeeded > fCashAmountAvailable) {
                        // there isn't enough assets in this position, withdraw all and move to the next maturity
                        _checkPriceImpactDuringRedemption(
                            fCashPosition.previewRedeem(fCashAmountAvailable),
                            fCashAmountAvailable,
                            fCashPosition,
                            _maxSlippage
                        );
                        fCashPosition.redeemToUnderlying(fCashAmountAvailable, address(this), type(uint32).max);
                        amountNeeded = amountNeeded - IERC20Upgradeable(_asset).balanceOf(address(this));
                    } else {
                        _checkPriceImpactDuringRedemption(amountNeeded, fCashAmountNeeded, fCashPosition, _maxSlippage);
                        fCashPosition.redeemToUnderlying(fCashAmountNeeded, address(this), type(uint32).max);
                        break;
                    }
                }
            }
        }
    }

    /// @notice Checks for price impact during redemption.
    /// @param _assetAmount Amount of asset
    /// @param _fCashAmount Spot amount of fCash
    /// @param _fCashPosition Address of the wrappedfCash
    function _checkPriceImpactDuringRedemption(
        uint _assetAmount,
        uint _fCashAmount,
        IWrappedfCashComplete _fCashPosition,
        uint maxSlippage
    ) internal view {
        uint fCashAmountOracle = _fCashPosition.convertToShares(_assetAmount);
        require(100_000 - ((_fCashAmount * 100_000) / fCashAmountOracle) <= maxSlippage, "FrpVault: PRICE_IMPACT");
    }

    function _getThreeAndSixMonthMarkets() internal returns (NotionalMarket[] memory) {
        NotionalMarket[] memory markets = new NotionalMarket[](2);
        MarketParameters[] memory marketParameters = NotionalViews(notionalRouter).getActiveMarkets(currencyId);
        uint marketCount;
        for (uint i = 0; i < marketParameters.length; i++) {
            MarketParameters memory parameters = marketParameters[i];
            if (parameters.maturity >= block.timestamp + 2 * Constants.QUARTER) {
                // it's not 3 or 6 months maturity check the next one
                continue;
            }
            markets[marketCount] = (
                NotionalMarket({ maturity: parameters.maturity, oracleRate: parameters.oracleRate })
            );
            marketCount++;
        }
        return markets;
    }

    function _sortMarketsByOracleRate(NotionalMarket[] memory notionalMarkets)
        internal
        returns (uint lowestYieldMaturity, uint highestYieldMaturity)
    {
        uint market0OracleRate = notionalMarkets[0].oracleRate;
        uint market1OracleRate = notionalMarkets[1].oracleRate;
        if (market0OracleRate < market1OracleRate) {
            lowestYieldMaturity = notionalMarkets[0].maturity;
            highestYieldMaturity = notionalMarkets[1].maturity;
        } else {
            lowestYieldMaturity = notionalMarkets[1].maturity;
            highestYieldMaturity = notionalMarkets[0].maturity;
        }
    }

    function _sortMaturities(
        address lowestYieldFCash,
        address highestYieldFCash,
        bool _marketHasMatured
    ) internal {
        address first = fCashPositions.at(0);
        if (_marketHasMatured || first != lowestYieldFCash) {
            address second = fCashPositions.at(1);
            fCashPositions.remove(first);
            fCashPositions.remove(second);
            fCashPositions.add(lowestYieldFCash);
            fCashPositions.add(highestYieldFCash);
        }
    }

    /// @notice Approves the `_spender` to spend `_requiredAllowance` of `_token`
    /// @param _token Token address
    /// @param _spender Spender address
    /// @param _requiredAllowance Required allowance
    function _safeApprove(
        address _token,
        address _spender,
        uint _requiredAllowance
    ) internal {
        uint allowance = IERC20Upgradeable(_token).allowance(address(this), _spender);
        if (allowance < _requiredAllowance) {
            IERC20Upgradeable(_token).safeIncreaseAllowance(_spender, type(uint256).max - allowance);
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
        uint fCashAmountOracle = _highestYieldWrappedfCash.convertToShares(_assetBalance);
        require(100_000 - ((fCashAmount * 100_000) / fCashAmountOracle) <= slippage, "FrpVault: PRICE_IMPACT");
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address _newImpl) internal view virtual override {
        require(hasRole(VAULT_ADMIN_ROLE, msg.sender), "FrpVault: FORBIDDEN");
    }

    uint256[44] private __gap;
}
