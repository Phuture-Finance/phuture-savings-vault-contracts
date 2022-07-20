// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.13;

import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { NotionalViews, MarketParameters } from "./notional/interfaces/INotional.sol";
import "./notional/interfaces/IWrappedfCashFactory.sol";
import { IWrappedfCashComplete } from "./notional/interfaces/IWrappedfCash.sol";
import "./notional/lib/Constants.sol";
import "./IFRPVault.sol";

/// @title Fixed rate product vault
/// @notice Contains logic for integration with Notional
contract FRPVault is IFRPVault, ERC4626Upgradeable, ERC20PermitUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Responsible for all vault related permissions
    bytes32 internal constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");
    /// @notice Role for vault
    bytes32 internal constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
    /// @notice Number of supported maturities
    uint8 internal constant SUPPORTED_MATURITIES = 2;
    /// @notice Base point number
    uint16 constant BP = 10_000;

    uint16 public currencyId;
    IWrappedfCashFactory public wrappedfCashFactory;
    address public notionalRouter;

    address[] internal fCashPositions;
    uint16 internal maxLoss;

    modifier isVaildMaxLoss(uint16 _maxLoss) {
        require(maxLoss <= BP, "FRPVault: MAX_LOSS");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IFRPVault
    function initialize(
        string memory _name,
        string memory _symbol,
        address _asset,
        uint16 _currencyId,
        IWrappedfCashFactory _wrappedfCashFactory,
        address _notionalRouter,
        uint16 _maxLoss
    ) external initializer isVaildMaxLoss(_maxLoss) {
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
        maxLoss = _maxLoss;

        (uint lowestYieldMaturity, uint highestYieldMaturity) = _sortMarketsByOracleRate();

        address lowestYieldFCash = _wrappedfCashFactory.deployWrapper(_currencyId, uint40(lowestYieldMaturity));
        address highestYieldFCash = _wrappedfCashFactory.deployWrapper(_currencyId, uint40(highestYieldMaturity));
        fCashPositions = new address[](SUPPORTED_MATURITIES);
        fCashPositions[0] = lowestYieldFCash;
        fCashPositions[1] = highestYieldFCash;
        IERC20Upgradeable(_asset).safeApprove(highestYieldFCash, type(uint).max);
        IERC20Upgradeable(_asset).safeApprove(lowestYieldFCash, type(uint).max);
    }

    /// @inheritdoc IFRPVault
    function harvest(uint _maxDepositedAmount) external {
        _redeemAssetsIfMarketMatured();

        address _asset = asset();
        uint assetBalance = IERC20Upgradeable(_asset).balanceOf(address(this));
        if (assetBalance == 0) {
            return;
        }
        uint deposited = Math.min(assetBalance, _maxDepositedAmount);

        (uint lowestYieldMaturity, uint highestYieldMaturity) = _sortMarketsByOracleRate();

        IWrappedfCashFactory _wrappedfCashFactory = wrappedfCashFactory;
        uint16 _currencyId = currencyId;
        address lowestYieldFCash = _wrappedfCashFactory.deployWrapper(_currencyId, uint40(lowestYieldMaturity));
        address highestYieldFCash = _wrappedfCashFactory.deployWrapper(_currencyId, uint40(highestYieldMaturity));
        _sortfCashPositions(lowestYieldFCash, highestYieldFCash);

        uint fCashAmount = _convertAssetsTofCash(deposited, IWrappedfCashComplete(highestYieldFCash));
        _safeApprove(_asset, highestYieldFCash, deposited);

        IWrappedfCashComplete(highestYieldFCash).mintViaUnderlying(deposited, uint88(fCashAmount), address(this), 0);
        emit FCashMinted(IWrappedfCashComplete(highestYieldFCash), deposited, fCashAmount);
    }

    /// @inheritdoc IFRPVault
    function setMaxLoss(uint16 _maxLoss) external isVaildMaxLoss(_maxLoss) {
        require(hasRole(VAULT_MANAGER_ROLE, msg.sender), "FRPVault: FORBIDDEN");
        maxLoss = _maxLoss;
    }

    /// @inheritdoc IERC4626Upgradeable
    function totalAssets() public view override returns (uint) {
        uint assetBalance = IERC20Upgradeable(asset()).balanceOf(address(this));
        for (uint i = 0; i < SUPPORTED_MATURITIES; i++) {
            IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions[i]);
            uint fCashBalance = fCashPosition.balanceOf(address(this));
            if (fCashBalance != 0) {
                assetBalance += fCashPosition.convertToAssets(fCashBalance);
            }
        }
        return assetBalance;
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address _caller,
        address _receiver,
        address _owner,
        uint _assets,
        uint _shares
    ) internal override {
        _beforeWithdraw(_assets);
        super._withdraw(_caller, _receiver, _owner, _assets, _shares);
    }

    /// @notice Loops through fCash positions and redeems into asset if position has matured
    function _redeemAssetsIfMarketMatured() internal {
        uint fCashPositionLength = fCashPositions.length;
        for (uint i = 0; i < fCashPositionLength; i++) {
            IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions[i]);
            if (fCashPosition.hasMatured()) {
                uint fCashAmount = fCashPosition.balanceOf(address(this));
                if (fCashAmount != 0) {
                    fCashPosition.redeemToUnderlying(fCashAmount, address(this), type(uint32).max);
                }
            }
        }
    }

    /// @notice Withdraws asset from maturities
    /// @param _assets Amount of assets for withdrawal
    function _beforeWithdraw(uint _assets) internal virtual {
        IERC20MetadataUpgradeable _asset = IERC20MetadataUpgradeable(asset());
        uint assetBalance = _asset.balanceOf(address(this));
        if (assetBalance < _assets) {
            uint amountNeeded = _assets + (10**_asset.decimals() / 10**3) - assetBalance;
            uint fCashPositionLength = fCashPositions.length;
            for (uint i = 0; i < fCashPositionLength; i++) {
                IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions[i]);
                uint fCashAmountAvailable = fCashPosition.balanceOf(address(this));
                if (fCashAmountAvailable == 0) {
                    continue;
                }
                uint fCashAmountNeeded = fCashPosition.previewWithdraw(amountNeeded);

                if (fCashAmountNeeded > fCashAmountAvailable) {
                    // there isn't enough assets in this position, withdraw all and move to the next maturity
                    fCashPosition.redeemToUnderlying(fCashAmountAvailable, address(this), type(uint32).max);
                    amountNeeded -= _asset.balanceOf(address(this));
                } else {
                    fCashPosition.redeemToUnderlying(fCashAmountNeeded, address(this), type(uint32).max);
                    break;
                }
            }
        }
    }

    /// @notice Sorts the markets in ascending order by their oracle rate
    function _sortMarketsByOracleRate() internal returns (uint lowestYieldMaturity, uint highestYieldMaturity) {
        NotionalMarket[] memory notionalMarkets = _getThreeAndSixMonthMarkets();
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

    /// @notice Sorts fCash positions in case there was a change with respect to the previous state
    function _sortfCashPositions(address _lowestYieldFCash, address _highestYieldFCash) internal {
        if (
            keccak256(abi.encodePacked(fCashPositions[0], fCashPositions[1])) !=
            keccak256(abi.encodePacked(_lowestYieldFCash, _highestYieldFCash))
        ) {
            fCashPositions[0] = _lowestYieldFCash;
            fCashPositions[1] = _highestYieldFCash;
        }
    }

    /// @notice Approves the `_spender` to spend `_requiredAllowance` of `_token`
    /// @param _token Token address_msg
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

    /// @notice Gets the three and six months markets from Notional
    function _getThreeAndSixMonthMarkets() internal view returns (NotionalMarket[] memory) {
        NotionalMarket[] memory markets = new NotionalMarket[](SUPPORTED_MATURITIES);
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
        require(marketCount == SUPPORTED_MATURITIES, "FRPVault: NOTIONAL_MARKETS");
        return markets;
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
        require(fCashAmount >= (fCashAmountOracle * maxLoss) / BP, "FRPVault: PRICE_IMPACT");
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address _newImpl) internal view virtual override {
        require(hasRole(VAULT_ADMIN_ROLE, msg.sender), "FRPVault: FORBIDDEN");
    }

    uint256[45] private __gap;
}
