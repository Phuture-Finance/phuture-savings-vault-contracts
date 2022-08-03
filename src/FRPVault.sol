// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.13;

import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { NotionalViews, MarketParameters } from "./external/notional/interfaces/INotional.sol";
import "./external/notional/interfaces/IWrappedfCashFactory.sol";
import { IWrappedfCashComplete } from "./external/notional/interfaces/IWrappedfCash.sol";
import "./external/notional/lib/Constants.sol";
import "./external/notional/lib/DateTime.sol";
import "./interfaces/IFRPVault.sol";
import "./libraries/AUMCalculationLibrary.sol";

/// @title Fixed rate product vault
/// @notice Contains logic for integration with Notional protocol
contract FRPVault is
    IFRPVault,
    ERC4626Upgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

    /// @notice Responsible for all vault related permissions
    bytes32 internal constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");
    /// @notice Role for vault management
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
    address[2] internal fCashPositions;

    /// @notice Timestamp of last AUM fee charge
    uint96 internal lastTransferTime;
    /// @notice Address of the feeRecipient
    address internal feeRecipient;

    /// @notice Checks if max loss is within an acceptable range
    modifier isValidMaxLoss(uint16 _maxLoss) {
        require(_maxLoss <= BP, "FRPVault: MAX_LOSS");
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
        __UUPSUpgradeable_init();

        currencyId = _currencyId;
        wrappedfCashFactory = _wrappedfCashFactory;
        notionalRouter = _notionalRouter;
        maxLoss = _maxLoss;
        feeRecipient = _feeRecipient;
        lastTransferTime = uint96(block.timestamp);

        (uint lowestYieldMaturity, uint highestYieldMaturity) = _sortMarketsByOracleRate();

        address lowestYieldFCash = _wrappedfCashFactory.deployWrapper(_currencyId, uint40(lowestYieldMaturity));
        address highestYieldFCash = _wrappedfCashFactory.deployWrapper(_currencyId, uint40(highestYieldMaturity));

        fCashPositions[0] = lowestYieldFCash;
        fCashPositions[1] = highestYieldFCash;
        IERC20Upgradeable(_asset).safeApprove(highestYieldFCash, type(uint).max);
        IERC20Upgradeable(_asset).safeApprove(lowestYieldFCash, type(uint).max);
    }

    /// @inheritdoc IFRPVault
    function harvest(uint _maxDepositedAmount) external nonReentrant {
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
    ) public override returns (uint256) {
        require(_assets <= maxWithdraw(_owner), "FRPVault: withdraw more than max");
        // determine the amount of shares for the assets without the fees
        uint shares = _convertToShares(_assets, MathUpgradeable.Rounding.Up);
        // determine the burning fee on top of the estimated shares for withdrawing the exact asset output
        // cannot use the previewWithdraw since it already accounts for the burning fee
        uint fee = _chargeBurningFee(shares, _owner);
        // shares accounting for the fees are not burned since they are transferred to the feeRecipient
        _withdraw(msg.sender, _receiver, _owner, _assets, shares);
        // returns the shares plus fee
        return shares + fee;
    }

    /// @inheritdoc IERC4626Upgradeable
    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) public override returns (uint256) {
        require(_shares <= maxRedeem(_owner), "FRPVault: redeem more than max");
        // previewReedem is fine to use here since we are dealing with exact input of shares so we calculate burning fee on that
        uint256 assetsMinusFee = previewRedeem(_shares);
        uint fee = _chargeBurningFee(_shares, _owner);
        // burns _shares - fee since fee is transferred to the feeRecipient
        _withdraw(msg.sender, _receiver, _owner, assetsMinusFee, _shares - fee);

        return assetsMinusFee;
    }

    /// @inheritdoc ERC4626Upgradeable
    function mint(uint256 _shares, address receiver) public override returns (uint256) {
        require(_shares <= maxMint(receiver), "FRPVault: mint more than max");

        uint256 assets = _convertToAssets(_shares, MathUpgradeable.Rounding.Up);

        uint fee = (_shares * MINTING_FEE_IN_BP) / BP;
        uint feeInAssets = convertToAssets(fee);
        if (fee != 0) {
            _mint(feeRecipient, fee);
        }
        _chargeAUMFee();
        // we need to mint exact number of shares
        _deposit(msg.sender, receiver, assets + feeInAssets, _shares);

        return assets + feeInAssets;
    }

    /// @inheritdoc ERC4626Upgradeable
    function deposit(uint256 _assets, address _receiver) public override returns (uint256) {
        require(_assets <= maxDeposit(_receiver), "FRPVault: deposit more than max");
        // calculate the shares to mint
        uint shares = convertToShares(_assets);
        // charge the actual fees
        _chargeAUMFee();
        uint fee = (shares * MINTING_FEE_IN_BP) / BP;
        if (fee != 0) {
            _mint(feeRecipient, fee);
        }
        _deposit(msg.sender, _receiver, _assets, shares - fee);
        return shares - fee;
    }

    /// @inheritdoc IERC4626Upgradeable
    function previewWithdraw(uint256 _assets) public view override returns (uint256) {
        uint shares = super.previewWithdraw(_assets);
        uint burningFee = (shares * BURNING_FEE_IN_BP) / BP;
        // To withdraw asset amount on top of needed shares burning fee is added
        return shares + burningFee;
    }

    /// @inheritdoc IERC4626Upgradeable
    function previewRedeem(uint256 _shares) public view override returns (uint256) {
        // amount of assets received is reduced by the shares amount
        return convertToAssets(_shares - (_shares * BURNING_FEE_IN_BP) / BP);
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewMint(uint256 _shares) public view override returns (uint256) {
        // While minting exact amount of shares user needs to transfer asset plus fees on top of those assets
        return super.previewMint(_shares + (_shares * MINTING_FEE_IN_BP) / BP);
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewDeposit(uint256 _assets) public view override returns (uint256) {
        uint shares = super.previewDeposit(_assets);
        uint fee = (shares * MINTING_FEE_IN_BP) / BP;
        // While depositing exact amount of assets user receives shares minus fee payed on that amount
        return shares - fee;
    }

    /// @inheritdoc IERC4626Upgradeable
    function maxWithdraw(address _owner) public view virtual override returns (uint256) {
        // max withdraw asset amount is equal to shares / 1 + burning_fee
        return convertToAssets((balanceOf(_owner) * BP) / (BP + BURNING_FEE_IN_BP));
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
    ) internal override nonReentrant {
        _beforeWithdraw(_assets);
        super._withdraw(_caller, _receiver, _owner, _assets, _shares);
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
        for (uint i = 0; i < SUPPORTED_MATURITIES; i++) {
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
    function _beforeWithdraw(uint _assets) internal {
        IERC20MetadataUpgradeable _asset = IERC20MetadataUpgradeable(asset());
        if (_asset.balanceOf(address(this)) < _assets) {
            // (10**_asset.decimals() / 10**3) is a buffer value to account for inaccurate estimation of fCash needed to withdraw the asset amount needed.
            // For further details refer to Notional docs: https://docs.notional.finance/developer-documentation/how-to/lend-and-borrow-fcash/wrapped-fcash
            uint bufferAmount = 10**_asset.decimals() / 10**3;
            for (uint i = 0; i < SUPPORTED_MATURITIES; i++) {
                IWrappedfCashComplete fCashPosition = IWrappedfCashComplete(fCashPositions[i]);
                uint fCashAmountAvailable = fCashPosition.balanceOf(address(this));
                if (fCashAmountAvailable == 0) {
                    continue;
                }
                uint assetBalanceBeforeRedeem = _asset.balanceOf(address(this));
                uint amountNeeded = _assets + bufferAmount - assetBalanceBeforeRedeem;

                uint fCashAmountNeeded = fCashPosition.previewWithdraw(amountNeeded);
                uint fCashAmountBurned = _redeemToUnderlying(fCashAmountAvailable, fCashAmountNeeded, fCashPosition);

                uint assetBalanceAfterRedeem = _asset.balanceOf(address(this));
                emit FCashRedeemed(
                    fCashPosition,
                    assetBalanceAfterRedeem - assetBalanceBeforeRedeem,
                    fCashAmountBurned
                );
                if (assetBalanceAfterRedeem >= _assets) {
                    break;
                }
            }
        }
    }

    /// @notice Redeems fCash for underlying asset
    function _redeemToUnderlying(
        uint fCashAmountAvailable,
        uint fCashAmountNeeded,
        IWrappedfCashComplete fCashPosition
    ) internal returns (uint fCashAmountBurned) {
        if (fCashAmountAvailable < fCashAmountNeeded) {
            fCashAmountBurned = fCashAmountAvailable;
            fCashPosition.redeemToUnderlying(fCashAmountAvailable, address(this), type(uint32).max);
        } else {
            fCashAmountBurned = fCashAmountNeeded;
            fCashPosition.redeemToUnderlying(fCashAmountNeeded, address(this), type(uint32).max);
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
        require(hasRole(VAULT_MANAGER_ROLE, msg.sender), "FRPVault: FORBIDDEN");
    }

    uint256[45] private __gap;
}
