// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.22;

interface IKarakBaseVault {
    struct Config {
        // Required fields
        address asset;
        uint8 decimals;
        address operator;
        string name;
        string symbol;
        bytes extraData;
    }

    /* ============ VIEW FUNCTIONS ============ */
    function totalAssets() external view returns (uint256);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function vaultConfig() external pure returns (Config memory);

    function asset() external view returns (address);
    /* ======================================== */
}
