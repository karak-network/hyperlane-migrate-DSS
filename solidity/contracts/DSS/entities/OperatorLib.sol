// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.22;

import {CheckpointsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/CheckpointsUpgradeable.sol";
import {Enrollment, EnrollmentStatus, EnumerableMapEnrollment} from "../../libs/EnumerableMapEnrollment.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {SignatureCheckerUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/SignatureCheckerUpgradeable.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";

import {HyperlaneDSSConstants} from "./Constants.sol";
import {HyperlaneDSSLib} from "./HyperlaneDSSLib.sol";
import {BaseDSSOperatorLib} from "karak-onchain-sdk/src/entities/BaseDssOperatorlib.sol";
import {IBaseDSS} from "karak-onchain-sdk/src/interfaces/IBaseDSS.sol";

import "../../interfaces/DSS/vendored/Events.sol";
import "../../interfaces/DSS/vendored/Errors.sol";
import {IKarakBaseVault} from "../../interfaces/DSS/vendored/IKarakBaseVault.sol";

library OperatorStateLib {
    using HyperlaneDSSLib for HyperlaneDSSLib.Storage;
    using EnumerableMapEnrollment for EnumerableMapEnrollment.AddressToEnrollmentMap;
    using CheckpointsUpgradeable for CheckpointsUpgradeable.History;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using SignatureCheckerUpgradeable for address;

    struct State {
        // Mapping of operators to challengers they are enrolled in
        EnumerableMapEnrollment.AddressToEnrollmentMap enrolledChallengers;
        /// @notice Maps an operator to their signing key history using checkpoints
        CheckpointsUpgradeable.History operatorSigningKeyHistory;
        /// @notice Maps operator addresses to their respective stake histories using checkpoints
        CheckpointsUpgradeable.History operatorWeightHistory;
    }

    function registerOperator(
        HyperlaneDSSLib.Storage storage self,
        address operator,
        bytes memory data
    ) internal {
        address signingKey = abi.decode(data, (address));
        int256 delta = updateOperatorWeight(self, operator);
        self.updateTotalWeight(delta);
        updateOperatorSigningKey(self, operator, signingKey);
    }

    function unregisterOperator(
        HyperlaneDSSLib.Storage storage self,
        address operator
    ) internal {
        int256 delta = updateOperatorWeight(self, operator);
        self.updateTotalWeight(delta);
    }

    function enrollIntoChallengers(
        HyperlaneDSSLib.Storage storage self,
        IRemoteChallenger[] memory challengers,
        address operator
    ) internal {
        State storage operatorState = self.operatorState[operator];
        for (uint256 i = 0; i < challengers.length; i++) {
            (bool exists, Enrollment memory enrollment) = operatorState
                .enrolledChallengers
                .tryGet(address(challengers[i]));
            if (
                exists &&
                enrollment.status == EnrollmentStatus.PENDING_UNENROLLMENT
            ) {
                revert PendingUnenrollment(challengers[i]);
            }
            if (enrollment.status == EnrollmentStatus.ENROLLED) break;

            bool success = operatorState.enrolledChallengers.set(
                address(challengers[i]),
                Enrollment(EnrollmentStatus.ENROLLED, 0)
            );
            if (!success) revert UnableToEnrollIntoChallenger(challengers[i]);
            emit OperatorEnrolledToChallenger(operator, challengers[i]);
        }
    }

    function startUnenrollment(
        HyperlaneDSSLib.Storage storage self,
        IRemoteChallenger[] memory challengers,
        address operator
    ) internal {
        State storage operatorState = self.operatorState[operator];
        for (uint256 i = 0; i < challengers.length; i++) {
            (bool exists, Enrollment memory enrollment) = operatorState
                .enrolledChallengers
                .tryGet(address(challengers[i]));
            if (!exists || enrollment.status == EnrollmentStatus.UNENROLLED) {
                revert OperatorNotEnrolledWithChallenger(challengers[i]);
            }
            if (enrollment.status == EnrollmentStatus.PENDING_UNENROLLMENT) {
                break;
            }

            operatorState.enrolledChallengers.set(
                address(challengers[i]),
                Enrollment(
                    EnrollmentStatus.PENDING_UNENROLLMENT,
                    uint248(block.number)
                )
            );
            emit OperatorQueuedUnenrollmentFromChallenger(
                operator,
                challengers[i],
                block.number,
                challengers[i].challengeDelayBlocks()
            );
        }
    }

    function validateUnenrollment(
        State storage self,
        IRemoteChallenger challenger
    ) internal view {
        (bool exists, Enrollment memory enrollment) = self
            .enrolledChallengers
            .tryGet(address(challenger));
        if (
            !exists ||
            enrollment.status != EnrollmentStatus.PENDING_UNENROLLMENT
        ) {
            revert ChallengerNotQueuedForUnenrollment(challenger);
        }
        if (
            block.number <
            enrollment.unenrollmentStartBlock +
                challenger.challengeDelayBlocks()
        ) {
            revert ChallengeDelayNotPassed(challenger);
        }
    }

    function completeUnenrollment(
        HyperlaneDSSLib.Storage storage self,
        address[] memory challengers,
        address operator,
        bool validate
    ) internal {
        State storage operatorState = self.operatorState[operator];
        for (uint256 i = 0; i < challengers.length; i++) {
            if (validate) {
                validateUnenrollment(
                    operatorState,
                    IRemoteChallenger(challengers[i])
                );
            }
            operatorState.enrolledChallengers.remove(address(challengers[i]));
            emit OperatorUnenrolledFromChallenger(
                operator,
                IRemoteChallenger(challengers[i]),
                block.number
            );
        }
    }

    function updateOperatorWeight(
        HyperlaneDSSLib.Storage storage self,
        address operator
    ) internal returns (int256 delta) {
        State storage operatorState = self.operatorState[operator];
        uint256 newWeight;
        uint256 oldWeight = operatorState.operatorWeightHistory.latest();
        bool isRegistered = IBaseDSS(address(this)).isOperatorRegistered(
            operator
        );
        if (!isRegistered) {
            delta -= int256(oldWeight);
            if (delta == 0) {
                return delta;
            }
            operatorState.operatorWeightHistory.push(0);
        } else {
            newWeight = getOperatorWeight(self, operator);
            delta = int256(newWeight) - int256(oldWeight);
            if (delta == 0) {
                return delta;
            }
            operatorState.operatorWeightHistory.push(newWeight);
        }
        emit OperatorWeightUpdated(operator, oldWeight, newWeight);
    }

    function updateOperatorSigningKey(
        HyperlaneDSSLib.Storage storage self,
        address operator,
        address newSigningKey
    ) internal {
        address oldSigningKey = address(
            uint160(
                self.operatorState[operator].operatorSigningKeyHistory.latest()
            )
        );
        if (newSigningKey == oldSigningKey) {
            return;
        }
        self.operatorState[operator].operatorSigningKeyHistory.push(
            uint160(newSigningKey)
        );
        emit SigningKeyUpdate(
            operator,
            block.number,
            newSigningKey,
            oldSigningKey
        );
    }

    function getOperatorChallengers(
        HyperlaneDSSLib.Storage storage self,
        address operator
    ) internal view returns (address[] memory) {
        return self.operatorState[operator].enrolledChallengers.keys();
    }

    function getEnrollmentStatus(
        HyperlaneDSSLib.Storage storage self,
        address operator,
        address challenger
    ) internal view returns (Enrollment memory enrollment) {
        (, enrollment) = self
            .operatorState[operator]
            .enrolledChallengers
            .tryGet(challenger);
    }

    function getOperatorWeight(
        HyperlaneDSSLib.Storage storage self,
        address operator
    ) internal view returns (uint256) {
        uint256 weight;
        address[] memory vaults = IBaseDSS(address(this)).getActiveVaults(
            operator
        );
        for (uint256 i; i < vaults.length; i++) {
            uint256 sharesNotQueuedForWithdrawal = IERC20(vaults[i])
                .totalSupply() - IERC20(vaults[i]).balanceOf(vaults[i]);
            uint256 assetBalance = IERC4626(vaults[i]).convertToAssets(
                sharesNotQueuedForWithdrawal
            );
            weight +=
                assetBalance *
                getAssetWeight(self, IKarakBaseVault(vaults[i]).asset());
        }
        weight = weight / HyperlaneDSSConstants.BPS;

        if (weight >= self.minimumWeight) {
            return weight;
        } else {
            return 0;
        }
    }

    function getAssetWeight(
        HyperlaneDSSLib.Storage storage self,
        address asset
    ) internal view returns (uint256 weight) {
        (, weight) = self.assetToWeightMap[self.quorumIndex].tryGet(asset);
    }

    function getOperatorSigningKeyAtBlock(
        HyperlaneDSSLib.Storage storage self,
        address operator,
        uint256 blockNumber
    ) internal view returns (address) {
        return
            address(
                uint160(
                    self
                        .operatorState[operator]
                        .operatorSigningKeyHistory
                        .getAtBlock(blockNumber)
                )
            );
    }

    function getLastestOperatorSigningKey(
        HyperlaneDSSLib.Storage storage self,
        address operator
    ) internal view returns (address) {
        return
            address(
                uint160(
                    self
                        .operatorState[operator]
                        .operatorSigningKeyHistory
                        .latest()
                )
            );
    }

    function getLastCheckpointOperatorWeight(
        HyperlaneDSSLib.Storage storage self,
        address operator
    ) internal view returns (uint256) {
        return self.operatorState[operator].operatorWeightHistory.latest();
    }

    function getOperatorWeightAtBlock(
        HyperlaneDSSLib.Storage storage self,
        address operator,
        uint32 blockNumber
    ) internal view returns (uint256) {
        return
            self.operatorState[operator].operatorWeightHistory.getAtBlock(
                blockNumber
            );
    }

    function isValidSignature(
        HyperlaneDSSLib.Storage storage self,
        address operator,
        bytes32 dataHash,
        bytes memory signature,
        uint32 blockNumber
    ) internal view {
        address signer = getOperatorSigningKeyAtBlock(
            self,
            operator,
            blockNumber
        );
        if (!signer.isValidSignatureNow(dataHash, signature)) {
            revert InvalidSignature();
        }
    }

    function getOperatorRestakedVaults(
        HyperlaneDSSLib.Storage storage self,
        address operator
    ) internal view returns (address[] memory restakedVaults) {
        address[] memory vaults = self.baseDssState.core.fetchVaultsStakedInDSS(
            operator,
            IBaseDSS(address(this))
        );

        uint256 vaultCountWithAssetsInQuorum = 0;
        for (uint256 i = 0; i < vaults.length; i++) {
            address asset = IKarakBaseVault(vaults[i]).asset();
            if (getAssetWeight(self, asset) > 0) {
                vaultCountWithAssetsInQuorum++;
            }
        }

        // Resize the array to fit only the vaults having assets in quorum
        restakedVaults = new address[](vaultCountWithAssetsInQuorum);
        uint256 index = 0;
        for (uint256 j = 0; j < vaults.length; j++) {
            address asset = IKarakBaseVault(vaults[j]).asset();
            if (getAssetWeight(self, asset) > 0) {
                restakedVaults[index] = address(vaults[j]);
                index++;
            }
        }
    }
}
