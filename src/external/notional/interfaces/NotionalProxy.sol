// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.8;

interface NotionalProxy {
    /** Initialize Markets Action */
    function initializeMarkets(uint16 currencyId, bool isFirstInit) external;
}
