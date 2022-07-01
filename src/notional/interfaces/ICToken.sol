// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >0.8.8;

interface ICToken {
    function mint(uint assets) external returns (uint);

    function redeem(uint redeemTokens) external returns (uint);

    function getCash() external view returns (uint);
}
