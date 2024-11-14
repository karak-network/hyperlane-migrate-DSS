// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.22;

import {IRemoteChallenger} from "../IRemoteChallenger.sol";

// Operator
error OperatorAlreadyRegistered();
error OperatorNotRegistered();
error PendingUnenrollment(IRemoteChallenger challenger);
error UnableToEnrollIntoChallenger(IRemoteChallenger challenger);
error OperatorNotEnrolledWithChallenger(IRemoteChallenger challenger);
error ChallengerNotQueuedForUnenrollment(IRemoteChallenger challenger);
error ChallengeDelayNotPassed(IRemoteChallenger challenger);

// DSS
error InvalidQuorum();
error InvalidSignedWeight();
error InsufficientSignedStake();

// Genric
error NotSorted();
error LengthMismatch();
error InvalidLength();
error InvalidSignature();
error InvalidReferenceBlock();
