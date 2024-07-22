// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/interfaces/IERC165.sol";

interface IDSS is IERC165 {
    struct StakeUpdateRequest {
        address vault;
        IDSS dss;
        bool toStake; // true for stake, false for unstake
    }

    struct QueuedStakeUpdate {
        uint48 nonce;
        uint48 startTimestamp;
        address operator;
        StakeUpdateRequest updateRequest;
    }

    // HOOKS

    function registrationHook(address operator, bytes memory extraData) external;
    function unregistrationHook(address operator, bytes memory extraData) external;

    error CallerNotCore();
}
