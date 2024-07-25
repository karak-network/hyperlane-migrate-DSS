// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import {Enrollment} from "../../../libs/EnumerableMapEnrollment.sol";
import {IRemoteChallenger} from "../IRemoteChallenger.sol";
import {IDSS} from "./IDSS.sol";

interface IHyperlaneDSS is IDSS {
    /* ========== MUTATIVE FUNCTIONS ========== */
    function initialize(address _owner, address _core, uint256 _minWeight) external;
    function enrollIntoChallengers(IRemoteChallenger[] memory _challengers) external;
    function startUnenrollment(IRemoteChallenger[] memory _challengers) external;
    function completeUnenrollment(address[] memory _challengers) external;
    function jailOperator(address operator) external;
    /* ======================================== */

    /* ============ VIEW FUNCTIONS ============ */
    function getChallengerEnrollment(address _operator, IRemoteChallenger _challenger)
        external
        returns (Enrollment memory enrollment);
    function getOperatorChallengers(address _operator) external returns (address[] memory);
    function getRestakeableAssets() external view returns (address[] memory);
    function getOperatorRestakedVaults(address _operator) external view returns (address[] memory);
}
