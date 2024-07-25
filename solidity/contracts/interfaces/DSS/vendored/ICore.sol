// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.22;

interface ICore {
    /* ============ VIEW FUNCTIONS ============ */
    function getOperatorVaults(address operator) external view returns (address[] memory vaults);
    function fetchVaultsStakedInDSS(address operator, address dss) external view returns (address[] memory vaults);
    function extSloads(bytes32[] calldata slots) external view returns (bytes32[] memory res);
    /* ======================================== */
}
