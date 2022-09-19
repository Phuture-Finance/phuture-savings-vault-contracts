// SPDX-License-Identifier: Apache-2.0
pragma solidity =0.8.13;

import "../../src/SavingsVault.sol";
import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

contract MockSavingsVault is SavingsVault {
    function _lastTransferTime() public view returns (uint96) {
        return lastTransferTime;
    }

    function _feeRecipient() public view returns (address) {
        return feeRecipient;
    }

    function _VAULT_ADMIN_ROLE() public pure returns (bytes32) {
        return VAULT_ADMIN_ROLE;
    }

    function _VAULT_MANAGER_ROLE() public pure returns (bytes32) {
        return VAULT_MANAGER_ROLE;
    }

    function _fCashPositions() public view returns (address[] memory) {
        address[] memory positions = new address[](2);
        for (uint i = 0; i < 2; i++) {
            positions[i] = fCashPositions[i];
        }
        return positions;
    }

    function __getThreeAndSixMonthMarkets() public view returns (NotionalMarket[] memory) {
        return _getThreeAndSixMonthMarkets();
    }

    function __getMaxImpliedRate(uint32 _oracleRate) public view returns (uint32) {
        return _getMaxImpliedRate(_oracleRate, maxLoss);
    }

    function getAUMFee(uint _lastTransfer) public view returns (uint) {
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
