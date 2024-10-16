// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.22;

import {IBaseDSS} from "karak-onchain-sdk/src/interfaces/IBaseDSS.sol";

interface ICore {
    function registerDSS(uint256 maxSlashablePercentageWad) external;
    function registerOperatorToDSS(
        IBaseDSS dss,
        bytes memory registrationHookData
    ) external;
    function unregisterOperatorFromDSS(IBaseDSS dss) external;

    function requestUpdateVaultStakeInDSS(
        IBaseDSS.StakeUpdateRequest memory newStake
    ) external returns (IBaseDSS.QueuedStakeUpdate memory);
    function finalizeUpdateVaultStakeInDSS(
        IBaseDSS.QueuedStakeUpdate memory newQueuedStake
    ) external;

    /* ============ VIEW FUNCTIONS ============ */
    function getOperatorVaults(
        address operator
    ) external view returns (address[] memory vaults);
    function fetchVaultsStakedInDSS(
        address operator,
        address dss
    ) external view returns (address[] memory vaults);
    function extSloads(
        bytes32[] calldata slots
    ) external view returns (bytes32[] memory res);
    function isOperatorRegisteredToDSS(
        address operator,
        IBaseDSS dss
    ) external view returns (bool);
    /* ======================================== */
}
