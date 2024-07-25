// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.22;

import {IRemoteChallenger} from "../IRemoteChallenger.sol";
import {HyperlaneDSSLib} from "../../../DSS/entities/HyperlaneDSSLib.sol";

event OperatorEnrolledToChallenger(address operator, IRemoteChallenger challenger);

event OperatorQueuedUnenrollmentFromChallenger(
    address operator, IRemoteChallenger challenger, uint256 unenrollmentStartBlock, uint256 challengeDelayBlocks
);

event OperatorUnenrolledFromChallenger(address operator, IRemoteChallenger challenger, uint256 unenrollmentEndBlock);

event OperatorWeightUpdated(address operator, uint256 oldWeight, uint256 newWeight);

event TotalWeightUpdated(uint256 oldTotalWeight, uint256 newTotalWeight);

event SigningKeyUpdate(address operator, uint256 blockNumber, address newSigningKey, address oldSigningKey);

event QuorumUpdated(HyperlaneDSSLib.Quorum oldQuorum, HyperlaneDSSLib.Quorum newQuorum);

event ThresholdWeightUpdated(uint256 thresholdWeight);

event MinimumWeightUpdated(uint256 oldMinimumWeight, uint256 newMinimumWeight);
