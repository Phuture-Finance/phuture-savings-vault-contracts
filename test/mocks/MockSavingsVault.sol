// SPDX-License-Identifier: Apache-2.0
pragma solidity =0.8.13;

import "../../src/SavingsVault.sol";

contract MockSavingsVault is SavingsVault {
    function _lastTransferTime() external view returns (uint96) {
        return lastTransferTime;
    }

    function _feeRecipient() external view returns (address) {
        return feeRecipient;
    }

    function _VAULT_ADMIN_ROLE() external pure returns (bytes32) {
        return VAULT_ADMIN_ROLE;
    }

    function _VAULT_MANAGER_ROLE() external pure returns (bytes32) {
        return VAULT_MANAGER_ROLE;
    }

    function __getThreeAndSixMonthMarkets() external view returns (NotionalMarket[] memory) {
        return _getThreeAndSixMonthMarkets();
    }

    function getAUMFee(uint _lastTransfer) external view returns (uint) {
        uint timePassed = _lastTransfer - lastTransferTime;
        if (timePassed != 0) {
            return
                ((totalSupply() - balanceOf(feeRecipient)) *
                    (AUMCalculationLibrary.rpow(
                        AUM_SCALED_PER_SECONDS_RATE,
                        timePassed,
                        AUMCalculationLibrary.RATE_SCALE_BASE
                    ) - AUMCalculationLibrary.RATE_SCALE_BASE)) / AUMCalculationLibrary.RATE_SCALE_BASE;
        }
        return 0;
    }
}
