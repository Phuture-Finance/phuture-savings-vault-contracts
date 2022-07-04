// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >0.8.8;

interface ICToken {
    function mint(uint256 assets) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function getCash() external view returns (uint256);
}
