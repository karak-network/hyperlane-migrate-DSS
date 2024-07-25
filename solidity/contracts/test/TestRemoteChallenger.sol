// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

import {IRemoteChallenger} from "../interfaces/DSS/IRemoteChallenger.sol";
import {HyperlaneDSS} from "../DSS/HyperlaneDSS.sol";

contract TestRemoteChallenger is IRemoteChallenger {
    HyperlaneDSS internal immutable hDSS;

    constructor(HyperlaneDSS _hDSS) {
        hDSS = _hDSS;
    }

    function challengeDelayBlocks() external pure returns (uint256) {
        return 50400; // one week of eth L1 blocks
    }

    function handleChallenge(address operator) external {
        hDSS.jailOperator(operator);
    }
}
