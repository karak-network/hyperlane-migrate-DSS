// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.22;

import {CheckpointsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/CheckpointsUpgradeable.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {BaseDSSLib} from "karak-onchain-sdk/src/entities/BaseDSSLib.sol";
import {Enrollment, EnrollmentStatus, EnumerableMapEnrollment} from "../../libs/EnumerableMapEnrollment.sol";
import {OperatorStateLib} from "./OperatorLib.sol";
import {HyperlaneDSSConstants} from "./Constants.sol";

import "../../interfaces/DSS/vendored/ICore.sol";
import "../../interfaces/DSS/vendored/Events.sol";
import "../../interfaces/DSS/vendored/Errors.sol";

library HyperlaneDSSLib {
    using OperatorStateLib for OperatorStateLib.State;
    using OperatorStateLib for HyperlaneDSSLib.Storage;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using CheckpointsUpgradeable for CheckpointsUpgradeable.History;
    using BaseDSSLib for BaseDSSLib.State;

    struct AssetParams {
        address asset; // The asset contract reference
        uint96 weight; // The weight applied to the asset
    }

    struct Quorum {
        AssetParams[] assets; // An array of asset parameters to define the quorum
    }

    struct Storage {
        // Mapping of operators to challengers they are enrolled in
        mapping(address operator => OperatorStateLib.State state) operatorState;
        /// @notice Stores the latest quorum index
        uint256 quorumIndex;
        /// @notice Stores the current quorum configuration
        mapping(uint256 quorumIndex => EnumerableMap.AddressToUintMap assetToWeightMap) assetToWeightMap;
        /// @notice Tracks the total stake history over time using checkpoints
        CheckpointsUpgradeable.History totalWeightHistory;
        /// @notice Tracks the threshold bps history using checkpoints
        CheckpointsUpgradeable.History thresholdWeightHistory;
        /// @notice Specifies the weight required to become an operator
        uint256 minimumWeight;
        /// @notice Storage for BaseDSS `State`
        BaseDSSLib.State baseDssState;
    }

    function init(
        Storage storage self,
        uint256 _minWeight,
        Quorum memory _quorum
    ) internal {
        self.minimumWeight = _minWeight;
        self.quorumIndex = 0;
        updateQuorumConfig(self, _quorum);
    }

    function updateTotalWeight(
        Storage storage self,
        int256 delta
    ) internal returns (uint256 oldTotalWeight, uint256 newTotalWeight) {
        oldTotalWeight = self.totalWeightHistory.latest();
        int256 newWeight = int256(oldTotalWeight) + delta;
        newTotalWeight = uint256(newWeight);
        self.totalWeightHistory.push(newTotalWeight);
        emit TotalWeightUpdated(oldTotalWeight, newTotalWeight);
    }

    function validateQuorum(
        Quorum memory _quorum
    ) internal pure returns (bool) {
        AssetParams[] memory assets = _quorum.assets;
        address lastAsset;
        address currentAsset;
        uint256 totalWeight;
        for (uint256 i; i < assets.length; i++) {
            currentAsset = address(assets[i].asset);
            if (lastAsset >= currentAsset) revert NotSorted();
            lastAsset = currentAsset;
            totalWeight += assets[i].weight;
        }
        if (totalWeight != HyperlaneDSSConstants.BPS) {
            return false;
        } else {
            return true;
        }
    }

    function updateQuorumConfig(
        Storage storage self,
        Quorum memory newQuorum
    ) internal {
        if (!validateQuorum(newQuorum)) revert InvalidQuorum();
        Quorum memory oldQuorum = getQuorum(self);

        self.quorumIndex++;
        for (uint256 i; i < newQuorum.assets.length; i++) {
            self.assetToWeightMap[self.quorumIndex].set(
                newQuorum.assets[i].asset,
                newQuorum.assets[i].weight
            );
        }
        emit QuorumUpdated(oldQuorum, newQuorum);
    }

    function updateStakeThreshold(
        Storage storage self,
        uint256 thresholdWeight
    ) internal {
        self.thresholdWeightHistory.push(thresholdWeight);
        emit ThresholdWeightUpdated(thresholdWeight);
    }

    function updateMinimumWeight(
        Storage storage self,
        uint256 newMinimumWeight
    ) internal {
        uint256 oldMinimumWeight = self.minimumWeight;
        self.minimumWeight = newMinimumWeight;
        emit MinimumWeightUpdated(oldMinimumWeight, newMinimumWeight);
    }

    function getQuorum(
        Storage storage self
    ) internal view returns (Quorum memory quorum) {
        quorum.assets = new AssetParams[](
            self.assetToWeightMap[self.quorumIndex].length()
        );
        for (uint256 i = 0; i < quorum.assets.length; i++) {
            uint256 weight;
            (quorum.assets[i].asset, weight) = self
                .assetToWeightMap[self.quorumIndex]
                .at(i);
            quorum.assets[i].weight = uint96(weight);
        }
        return quorum;
    }

    function getLastCheckpointTotalWeight(
        Storage storage self
    ) internal view returns (uint256) {
        return self.totalWeightHistory.latest();
    }

    function getLastCheckpointThresholdWeight(
        Storage storage self
    ) internal view returns (uint256) {
        return self.thresholdWeightHistory.latest();
    }

    function getLastCheckpointTotalWeightAtBlock(
        Storage storage self,
        uint32 blockNumber
    ) internal view returns (uint256) {
        return self.totalWeightHistory.getAtBlock(blockNumber);
    }

    function getLastCheckpointThresholdWeightAtBlock(
        Storage storage self,
        uint32 blockNumber
    ) internal view returns (uint256) {
        return self.thresholdWeightHistory.getAtBlock(blockNumber);
    }

    function getRestakeableAssets(
        Storage storage self
    ) internal view returns (address[] memory) {
        return self.assetToWeightMap[self.quorumIndex].keys();
    }

    function checkSignatures(
        Storage storage self,
        bytes32 dataHash,
        address[] memory operators,
        bytes[] memory signatures,
        uint32 referenceBlock
    ) internal view {
        address lastOperator;
        uint256 signedWeight;

        for (uint256 i; i < operators.length; i++) {
            if (lastOperator >= operators[i]) revert NotSorted();
            self.isValidSignature(
                operators[i],
                dataHash,
                signatures[i],
                referenceBlock
            );

            lastOperator = operators[i];
            uint256 operatorWeight = self.getOperatorWeightAtBlock(
                operators[i],
                referenceBlock
            );
            signedWeight += operatorWeight;
        }

        validateThresholdStake(self, signedWeight, referenceBlock);
    }

    function validateThresholdStake(
        Storage storage self,
        uint256 signedWeight,
        uint32 referenceBlock
    ) internal view {
        uint256 totalWeight = getLastCheckpointTotalWeightAtBlock(
            self,
            referenceBlock
        );
        if (signedWeight > totalWeight) {
            revert InvalidSignedWeight();
        }
        uint256 thresholdStake = getLastCheckpointThresholdWeightAtBlock(
            self,
            referenceBlock
        );
        if (thresholdStake > signedWeight) {
            revert InsufficientSignedStake();
        }
    }
}
