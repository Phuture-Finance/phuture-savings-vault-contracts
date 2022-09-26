// SPDX-License-Identifier: Apache-2.0
pragma solidity =0.8.13;

import "../../src/external/interfaces/IKeep3r.sol";

contract Keepr3rMock is IKeep3r {
    function isKeeper(address _keeper) external returns (bool _isKeeper) {
        return true;
    }

    function worked(address _keeper) external {}
}
