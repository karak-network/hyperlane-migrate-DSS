// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import {Quorum} from "../interfaces/avs/vendored/IECDSAStakeRegistryEventsAndErrors.sol";
import {ECDSAStakeRegistry} from "./ECDSAStakeRegistry.sol";

import {IDSS} from "../interfaces/avs/vendored/IDSS.sol";
import {ICore} from "../interfaces/avs/vendored/ICore.sol";
import {IKarakBaseVault} from "../interfaces/avs/vendored/IKarakBaseVault.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @author Layr Labs, Inc.
abstract contract ECDSAServiceManagerBase is IDSS, OwnableUpgradeable {
    // ============ Public Storage ============
    /// @notice Address of the stake registry contract, which manages registration and stake recording.
    address public immutable stakeRegistry;

    address public immutable core;

    // ============ Events ============

    /**
     * @notice Emitted when an operator is registered to the AVS
     * @param operator The address of the operator
     */
    event OperatorRegisteredToDSS(address indexed operator);

    /**
     * @notice Emitted when an operator is deregistered from the AVS
     * @param operator The address of the operator
     */
    event OperatorDeregisteredFromDSS(address indexed operator);

    // ============ Constructor ============

    /**
     * @dev Constructor for ECDSAServiceManagerBase, initializing immutable contract addresses and disabling initializers.
     * @param _stakeRegistry The address of the stake registry contract, managing registration and stake recording.
     */
    constructor(address _stakeRegistry, address _core) {
        stakeRegistry = _stakeRegistry;
        core = _core;
    }

    /**
     * @dev Initializes the base service manager by transferring ownership to the initial owner.
     * @param initialOwner The address to which the ownership of the contract will be transferred.
     */
    function __ServiceManagerBase_init(address initialOwner) internal virtual onlyInitializing {
        _transferOwnership(initialOwner);
    }

    function getRestakeableAssets() external view virtual returns (address[] memory) {
        return _getRestakeableAssets();
    }

    function getOperatorRestakedVaults(address _operator) external view virtual returns (address[] memory) {
        return _getOperatorStakedVaults(_operator);
    }

    /**
     * @notice Retrieves the addresses of all assets that are part of the current quorum.
     * @dev Fetches the quorum configuration from the ECDSAStakeRegistry and extracts the assets addresses.
     * @return assets An array of addresses representing the assets in the current quorum.
     */
    function _getRestakeableAssets() internal view virtual returns (address[] memory) {
        Quorum memory quorum = ECDSAStakeRegistry(stakeRegistry).quorum();
        address[] memory assets = new address[](quorum.assets.length);
        for (uint256 i = 0; i < quorum.assets.length; i++) {
            assets[i] = address(quorum.assets[i].asset);
        }
        return assets;
    }

    /**
     * @notice Retrieves the addresses of vaults the operator has restaked.
     * @dev This function fetches the quorum details from the ECDSAStakeRegistry, retrieves the operator's vaults staked in DSS,
     * and filters out vaults with assets not in quorum.
     * @param _operator The address of the operator whose restaked vaults are to be retrieved.
     * @return restakedVaults An array of addresses of vaults which the operator has staked.
     */
    function _getOperatorStakedVaults(address _operator) internal view virtual returns (address[] memory) {
        address[] memory vaults = ICore(core).fetchVaultsStakedInDSS(_operator, address(this));

        uint256 vaultCountWithAssetsInQuorum = 0;
        for (uint256 i; i < vaults.length; i++) {
            address asset = IKarakBaseVault(vaults[i]).asset();
            if (ECDSAStakeRegistry(stakeRegistry).getAssetWeight(asset) > 0) {
                vaultCountWithAssetsInQuorum++;
            }
        }

        // Resize the array to fit only the vaults having assets in quorum
        address[] memory restakedVaults = new address[](vaultCountWithAssetsInQuorum);
        uint256 index;
        for (uint256 j = 0; j < vaults.length; j++) {
            address asset = IKarakBaseVault(vaults[j]).asset();
            if (ECDSAStakeRegistry(stakeRegistry).getAssetWeight(asset) > 0) {
                restakedVaults[index] = address(vaults[j]);
                index++;
            }
        }

        return restakedVaults;
    }

    function _registerOperator(address operator, bytes memory extraData) internal {
        ECDSAStakeRegistry(stakeRegistry).registerOperator(operator, extraData);
    }

    function _unregisterOperator(address operator, bytes memory extraData) internal {
        ECDSAStakeRegistry(stakeRegistry).unregisterOperator(operator, extraData);
    }

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[48] private __GAP;
}
