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
import "./libraries/AUMCalculationLibrary.sol";

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
    uint16 internal constant BP = 10_000;

    /// @inheritdoc IFRPVault
    uint public constant AUM_SCALED_PER_SECONDS_RATE = 1000000000158946658547141217;
    /// @inheritdoc IFRPVault
    uint public constant MINTING_FEE_IN_BP = 20;
    /// @inheritdoc IFRPVault
    uint public constant BURNING_FEE_IN_BP = 20;

    /// @inheritdoc IFRPVault
    uint16 public currencyId;
    /// @notice Maximum loss allowed during harvesting
    uint16 internal maxLoss;
    /// @inheritdoc IFRPVault
    address public notionalRouter;
    /// @inheritdoc IFRPVault
    IWrappedfCashFactory public wrappedfCashFactory;
    /// @notice 3 and 6 months maturities
    address[] internal fCashPositions;

    /// @notice Timestamp of last AUM fee charge
    uint96 internal lastTransferTime;
    /// @notice Address of the feeRecipient
    address internal feeRecipient;

    /// @notice Checks if max loss is within an acceptable range
    modifier isValidMaxLoss(uint16 _maxLoss) {
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
        uint16 _maxLoss,
        address _feeRecipient
    ) external initializer isValidMaxLoss(_maxLoss) {
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
        feeRecipient = _feeRecipient;

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
        address lowestYieldfCash = _wrappedfCashFactory.deployWrapper(_currencyId, uint40(lowestYieldMaturity));
        address highestYieldfCash = _wrappedfCashFactory.deployWrapper(_currencyId, uint40(highestYieldMaturity));
        _sortfCashPositions(lowestYieldfCash, highestYieldfCash);

        uint fCashAmount = _convertAssetsTofCash(deposited, IWrappedfCashComplete(highestYieldfCash));
        _safeApprove(_asset, highestYieldfCash, deposited);

        IWrappedfCashComplete(highestYieldfCash).mintViaUnderlying(deposited, uint88(fCashAmount), address(this), 0);
        emit FCashMinted(IWrappedfCashComplete(highestYieldfCash), deposited, fCashAmount);
    }

    /// @inheritdoc IFRPVault
    function setMaxLoss(uint16 _maxLoss) external isValidMaxLoss(_maxLoss) {
        require(hasRole(VAULT_MANAGER_ROLE, msg.sender), "FRPVault: FORBIDDEN");
        maxLoss = _maxLoss;
    }

    /// @inheritdoc IERC4626Upgradeable
    function withdraw(
        uint256 _assets,
        address _receiver,
        address _owner
    ) public virtual override returns (uint256) {
        require(_assets <= maxWithdraw(_owner), "FRPVault: withdraw more than max");
        uint256 shares = previewWithdraw(_assets);

        uint fee = _chargeBurningFee(shares, _owner);
        // _assets - previewRedeem(fee) is needed to reduce the amount of assets for withdrawal by asset's worth in fee shares
        _withdraw(msg.sender, _receiver, _owner, _assets - previewRedeem(fee), shares - fee);

        return shares;
    }

    /// @inheritdoc IERC4626Upgradeable
    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) public virtual override returns (uint256) {
        require(_shares <= maxRedeem(_owner), "FRPVault: redeem more than max");

        uint fee = _chargeBurningFee(_shares, _owner);

        // fee shares were transferred in _chargeBurningFee.
        uint sharesMinusFee = _shares - fee;
        // Redeem only the assets for shares minus the fee.
        uint256 assetsMinusFee = previewRedeem(sharesMinusFee);
        _withdraw(msg.sender, _receiver, _owner, assetsMinusFee, sharesMinusFee);

        return assetsMinusFee;
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

    /// @inheritdoc ERC4626Upgradeable
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

    /// @inheritdoc ERC4626Upgradeable
    function _deposit(
        address _caller,
        address _receiver,
        uint256 _assets,
        uint256 _shares
    ) internal override {
        // AUM fee is charged prior to mint event with the old totalSupply
        _chargeAUMFee();
        uint fee = (_shares * MINTING_FEE_IN_BP) / BP;
        if (fee != 0) {
            _mint(feeRecipient, fee);
        }
        super._deposit(_caller, _receiver, _assets, _shares - fee);
    }

    /// @dev Overrides _transfer to include AUM fee logic
    /// @inheritdoc ERC20Upgradeable
    function _transfer(
        address _from,
        address _to,
        uint _amount
    ) internal override {
        _chargeAUMFee();
        super._transfer(_from, _to, _amount);
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
            // (10**_asset.decimals() / 10**3) is a buffer vaule to account for inaccurate estimation of fCash needed to withdraw the asset amount needed.
            // For further details refer to Notional docs: https://docs.notional.finance/developer-documentation/how-to/lend-and-borrow-fcash/wrapped-fcash
            uint amountNeeded = _assets + (10**_asset.decimals() / 10**3) - assetBalance;
            for (uint i = 0; i < SUPPORTED_MATURITIES; i++) {
                IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions[i]);
                uint fCashAmountAvailable = fCashPosition.balanceOf(address(this));
                if (fCashAmountAvailable == 0) {
                    continue;
                }
                uint fCashAmountNeeded = fCashPosition.previewWithdraw(amountNeeded);

                fCashAmountAvailable < fCashAmountNeeded
                    ? fCashPosition.redeemToUnderlying(fCashAmountAvailable, address(this), type(uint32).max)
                    : fCashPosition.redeemToUnderlying(fCashAmountNeeded, address(this), type(uint32).max);
                uint assetBalanceAfterReedem = _asset.balanceOf(address(this));
                if (amountNeeded > assetBalanceAfterReedem) {
                    amountNeeded -= assetBalanceAfterReedem;
                } else {
                    break;
                }
            }
        }
    }

    /// @notice Sorts fCash positions in case there was a change with respect to the previous state
    function _sortfCashPositions(address _lowestYieldfCash, address _highestYieldfCash) internal {
        if (
            keccak256(abi.encodePacked(fCashPositions[0], fCashPositions[1])) !=
            keccak256(abi.encodePacked(_lowestYieldfCash, _highestYieldfCash))
        ) {
            fCashPositions[0] = _lowestYieldfCash;
            fCashPositions[1] = _highestYieldfCash;
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

    /// @notice Charges the buring and AUM fees while withdrawing/redeeming
    function _chargeBurningFee(uint _shares, address _sharesOwner) internal returns (uint fee) {
        fee = (_shares * BURNING_FEE_IN_BP) / BP;
        if (fee != 0) {
            // AUM charged inside _transfer
            // Transfer the shares which account for the fee to the feeRecipient
            _transfer(_sharesOwner, feeRecipient, fee);
        } else {
            _chargeAUMFee();
        }
    }

    /// @notice Calculates and mints AUM fee to feeRecipient
    function _chargeAUMFee() internal {
        uint timePassed = uint96(block.timestamp) - lastTransferTime;
        if (timePassed != 0) {
            address _feeRecipient = feeRecipient;
            uint fee = ((totalSupply() - balanceOf(_feeRecipient)) *
                (AUMCalculationLibrary.rpow(
                    AUM_SCALED_PER_SECONDS_RATE,
                    timePassed,
                    AUMCalculationLibrary.RATE_SCALE_BASE
                ) - AUMCalculationLibrary.RATE_SCALE_BASE)) / AUMCalculationLibrary.RATE_SCALE_BASE;
            if (fee != 0) {
                _mint(_feeRecipient, fee);
                lastTransferTime = uint96(block.timestamp);
            }
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

    /// @notice Sorts the markets in ascending order by their oracle rate
    function _sortMarketsByOracleRate() internal view returns (uint lowestYieldMaturity, uint highestYieldMaturity) {
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
