// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.22;

import {IDSS} from "./IDSS.sol";

interface ICore {
    function registerDSS(uint256 maxSlashablePercentageWad) external;
    function registerOperatorToDSS(
        IDSS dss,
        bytes memory registrationHookData
    ) external;
    function unregisterOperatorFromDSS(IDSS dss) external;

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
        IDSS dss
    ) external view returns (bool);
    /* ======================================== */
}
