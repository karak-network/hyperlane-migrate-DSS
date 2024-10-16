// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8;
import {Enrollment} from "../../../libs/EnumerableMapEnrollment.sol";
import {IRemoteChallenger} from "../IRemoteChallenger.sol";
import {HyperlaneDSSLib} from "../../../DSS/entities/HyperlaneDSSLib.sol";
import {IBaseDSS} from "karak-onchain-sdk/src/interfaces/IBaseDSS.sol";

interface IHyperlaneDSS is IBaseDSS {
    // ============ Mutative Functions ============

    function initialize(
        address _owner,
        address _core,
        uint256 _minWeight,
        uint256 _maxSlashablePerecentageWad,
        HyperlaneDSSLib.Quorum memory _quorum
    ) external;

    function enrollIntoChallengers(
        IRemoteChallenger[] memory challengers
    ) external;

    function startUnenrollment(IRemoteChallenger[] memory challengers) external;

    function completeUnenrollment(address[] memory challengers) external;

    function jailOperator(address operator) external;

    function registrationHook(
        address operator,
        bytes memory extraData
    ) external override;

    function unregistrationHook(address operator) external override;

    function updateOperatorSigningKey(address newSigningKey) external;

    function updateOperators(address[] memory operators) external;

    function updateQuorumConfig(
        HyperlaneDSSLib.Quorum memory quorum,
        address[] memory operators
    ) external;

    function updateMinimumWeight(
        uint256 newMinimumWeight,
        address[] memory operators
    ) external;

    function updateStakeThreshold(uint256 thresholdWeight) external;

    // ============ VIEW Functions ============

    function isValidSignature(
        bytes32 dataHash,
        bytes memory signatureData
    ) external view returns (bytes4);

    function quorum() external view returns (HyperlaneDSSLib.Quorum memory);

    function getLastestOperatorSigningKey(
        address operator
    ) external view returns (address);

    function getOperatorSigningKeyAtBlock(
        address operator,
        uint256 blockNumber
    ) external view returns (address);

    function getLastCheckpointOperatorWeight(
        address operator
    ) external view returns (uint256);

    function getLastCheckpointTotalWeight() external view returns (uint256);

    function getLastCheckpointThresholdWeight() external view returns (uint256);

    function getOperatorWeightAtBlock(
        address operator,
        uint32 blockNumber
    ) external view returns (uint256);

    function getLastCheckpointTotalWeightAtBlock(
        uint32 blockNumber
    ) external view returns (uint256);

    function getLastCheckpointThresholdWeightAtBlock(
        uint32 blockNumber
    ) external view returns (uint256);

    function getChallengerEnrollment(
        address operator,
        IRemoteChallenger _challenger
    ) external view returns (Enrollment memory);

    function getOperatorChallengers(
        address operator
    ) external view returns (address[] memory);

    function getRestakeableAssets() external view returns (address[] memory);

    function getOperatorRestakedVaults(
        address operator
    ) external view returns (address[] memory);
}
