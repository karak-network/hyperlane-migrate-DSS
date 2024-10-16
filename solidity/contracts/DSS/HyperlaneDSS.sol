// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

/*@@@@@@@       @@@@@@@@@
 @@@@@@@@@       @@@@@@@@@
  @@@@@@@@@       @@@@@@@@@
   @@@@@@@@@       @@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@
     @@@@@  HYPERLANE  @@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@
   @@@@@@@@@       @@@@@@@@@
  @@@@@@@@@       @@@@@@@@@
 @@@@@@@@@       @@@@@@@@@
@@@@@@@@@       @@@@@@@@*/

// ============ Internal Imports ============
import {IERC1271Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC1271Upgradeable.sol";
import {BaseDSSLib} from "karak-onchain-sdk/src/entities/BaseDSSLib.sol";
import {BaseDSS} from "karak-onchain-sdk/src/BaseDSS.sol";

import {Enrollment, EnrollmentStatus} from "../libs/EnumerableMapEnrollment.sol";
import {HyperlaneDSSLib} from "./entities/HyperlaneDSSLib.sol";
import {OperatorStateLib} from "./entities/OperatorLib.sol";

import {IHyperlaneDSS, IBaseDSS} from "../interfaces/DSS/vendored/IHyperlaneDSS.sol";
import {IRemoteChallenger} from "../interfaces/DSS/IRemoteChallenger.sol";
import {ICore} from "../interfaces/DSS/vendored/ICore.sol";
import "../interfaces/DSS/vendored/Events.sol";
import "../interfaces/DSS/vendored/Errors.sol";
import "./entities/Constants.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract HyperlaneDSS is IHyperlaneDSS, OwnableUpgradeable, BaseDSS {
    // ============ Libraries ============

    using HyperlaneDSSLib for HyperlaneDSSLib.Storage;
    using OperatorStateLib for HyperlaneDSSLib.Storage;
    using BaseDSSLib for BaseDSSLib.State;

    // keccak256(abi.encode(uint256(keccak256("hyperlanedss.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant STORAGE_SLOT =
        0x97a737615475bcee79cdac5f4bd6f79c0343e9fd71e6afea38865e795c47e800;

    string public constant VERSION = "v1.0.0";

    constructor() {
        _disableInitializers();
    }

    // ============ Mutative Functions ============
    /**
     * @notice Initializes the HyperlaneDSS contract with the owner address, minimum weight
     * @notice Registers the HyperlaneDSS with core with given `_maxSlashablePerecentageWad`.
     */
    function initialize(
        address _owner,
        address _core,
        uint256 _minWeight,
        uint256 _maxSlashablePerecentageWad,
        HyperlaneDSSLib.Quorum memory _quorum
    ) external initializer {
        _transferOwnership(_owner);
        _self().init(_minWeight, _quorum);
        _init(_core, _maxSlashablePerecentageWad);
    }

    /**
     * @notice Enrolls as an operator into a list of challengers
     * @param challengers The list of challengers to enroll into
     */
    function enrollIntoChallengers(
        IRemoteChallenger[] memory challengers
    ) external onlyRegisteredOperator(msg.sender) {
        _self().enrollIntoChallengers(challengers, msg.sender);
    }

    /**
     * @notice starts an operator for unenrollment from a list of challengers
     * @param challengers The list of challengers to unenroll from
     */
    function startUnenrollment(
        IRemoteChallenger[] memory challengers
    ) external onlyRegisteredOperator(msg.sender) {
        _self().startUnenrollment(challengers, msg.sender);
    }

    /**
     * @notice Completes the unenrollment of an operator from a list of challengers
     * @param challengers The list of challengers to unenroll from
     */
    function completeUnenrollment(
        address[] memory challengers
    ) external onlyRegisteredOperator(msg.sender) {
        _self().completeUnenrollment(challengers, msg.sender, true);
    }

    /**
     * @notice freeze the operator.
     * @param operator The address of the operator to freeze.
     * @dev only the enrolled challengers can call this function
     */
    function jailOperator(
        address operator
    ) external virtual onlyEnrolledChallenger(operator) {
        _jailOperator(operator);
    }

    /**
     * @notice operator registers through the `core` and the hook is called by the `core`
     * @param operator address of the operator
     * @param extraData data passed specific to this DSS
     */
    function registrationHook(
        address operator,
        bytes memory extraData
    ) public override(BaseDSS, IHyperlaneDSS) onlyCore {
        _self().registerOperator(operator, extraData);
        super.registrationHook(operator, "");
    }

    /**
     * @notice unregistration happens form the protocol and `unregistrationHook` is called from the karak protocol.
     * Delays are already introduced in the protcol for staking/unstaking vaults. To unregister operator needs to fully unstake.
     * @dev Operator is unenrolled from all the challengers as `Challenger` had enough time to slash any operator during unstaking delay.
     * @param operator address of the operator.
     */
    function unregistrationHook(
        address operator
    ) public override(BaseDSS, IHyperlaneDSS) onlyCore {
        HyperlaneDSSLib.Storage storage self = _self();
        address[] memory challengers = self.getOperatorChallengers(operator);
        self.completeUnenrollment(challengers, operator, false);
        self.unregisterOperator(operator);
        super.unregistrationHook(operator);
    }

    /**
     * @notice Updates the signing key for an operator
     * @dev Only callable by the operator themselves
     * @param newSigningKey The new signing key to set for the operator
     */
    function updateOperatorSigningKey(
        address newSigningKey
    ) external onlyRegisteredOperator(msg.sender) {
        _self().updateOperatorSigningKey(msg.sender, newSigningKey);
    }

    /**
     * @notice Updates the StakeRegistry's view of one or more operators' stakes adding a new entry in their history of stake checkpoints,
     * @dev Queries stakes from the `Core` contract
     * @param operators A list of operator addresses to update
     */
    function updateOperators(address[] memory operators) public {
        HyperlaneDSSLib.Storage storage self = _self();
        int256 delta = 0;
        for (uint256 i = 0; i < operators.length; i++) {
            if (!isOperatorRegistered(operators[i])) {
                revert OperatorNotRegistered();
            }
            delta += self.updateOperatorWeight(operators[i]);
        }
        self.updateTotalWeight(delta);
    }

    /**
     * @notice Updates the quorum configuration and the set of operators
     * @dev Only callable by the contract owner.
     * @param quorum The new quorum configuration, including assets and their new weights
     * @param operators The list of operator addresses to update stakes for
     */
    function updateQuorumConfig(
        HyperlaneDSSLib.Quorum memory quorum,
        address[] memory operators
    ) external onlyOwner {
        _self().updateQuorumConfig(quorum);
        updateOperators(operators);
    }

    /**
     * @notice Updates the weight an operator must have to join the operator set
     * @dev Access controlled to the contract owner
     * @param newMinimumWeight The new weight an operator must have to join the operator set
     */
    function updateMinimumWeight(
        uint256 newMinimumWeight,
        address[] memory operators
    ) external onlyOwner {
        _self().updateMinimumWeight(newMinimumWeight);
        updateOperators(operators);
    }

    /**
     * @notice Sets a new cumulative threshold weight for message validation by operator set signatures.
     * @dev This function can only be invoked by the owner of the contract.
     * @param thresholdWeight The updated threshold weight required to validate a message. This is the
     * cumulative weight that must be met or exceeded by the sum of the stakes of the signatories for
     * a message to be deemed valid.
     */
    function updateStakeThreshold(uint256 thresholdWeight) external onlyOwner {
        _self().updateStakeThreshold(thresholdWeight);
    }

    // ============ VIEW Functions ============ //

    /**
     * @notice Verifies if the provided signature data is valid for the given data hash.
     * @param dataHash The hash of the data that was signed.
     * @param signatureData Encoded signature data consisting of an array of operators, an array of signatures, and a reference block number.
     * @return The function selector that indicates the signature is valid according to ERC1271 standard.
     */
    function isValidSignature(
        bytes32 dataHash,
        bytes memory signatureData
    ) external view returns (bytes4) {
        (
            address[] memory operators,
            bytes[] memory signatures,
            uint32 referenceBlock
        ) = abi.decode(signatureData, (address[], bytes[], uint32));

        if (operators.length != signatures.length) revert LengthMismatch();
        if (operators.length == 0) revert InvalidLength();
        _self().checkSignatures(
            dataHash,
            operators,
            signatures,
            referenceBlock
        );
        return IERC1271Upgradeable.isValidSignature.selector;
    }

    /// @notice Retrieves the current stake quorum details.
    /// @return quorum - The current quorum of assets and weights
    function quorum() public view returns (HyperlaneDSSLib.Quorum memory) {
        return _self().getQuorum();
    }

    /**
     * @notice Retrieves the latest signing key for a given operator.
     * @param operator The address of the operator.
     * @return The latest signing key of the operator.
     */
    function getLastestOperatorSigningKey(
        address operator
    ) external view returns (address) {
        return _self().getLastestOperatorSigningKey(operator);
    }

    /**
     * @notice Retrieves the latest signing key for a given operator at a specific block number.
     * @param operator The address of the operator.
     * @param blockNumber The block number to get the operator's signing key.
     * @return The signing key of the operator at the given block.
     */
    function getOperatorSigningKeyAtBlock(
        address operator,
        uint256 blockNumber
    ) external view returns (address) {
        return _self().getOperatorSigningKeyAtBlock(operator, blockNumber);
    }

    /// @notice Retrieves the last recorded weight for a given operator.
    /// @param operator The address of the operator.
    /// @return uint256 - The latest weight of the operator.
    function getLastCheckpointOperatorWeight(
        address operator
    ) external view returns (uint256) {
        return _self().getLastCheckpointOperatorWeight(operator);
    }

    /// @notice Retrieves the last recorded total weight across all operators.
    /// @return uint256 - The latest total weight.
    function getLastCheckpointTotalWeight() external view returns (uint256) {
        return _self().getLastCheckpointTotalWeight();
    }

    /// @notice Retrieves the last recorded threshold weight
    /// @return uint256 - The latest threshold weight.
    function getLastCheckpointThresholdWeight()
        external
        view
        returns (uint256)
    {
        return _self().getLastCheckpointThresholdWeight();
    }

    /// @notice Retrieves the operator's weight at a specific block number.
    /// @param operator The address of the operator.
    /// @param blockNumber The block number to get the operator weight for the quorum
    /// @return uint256 - The weight of the operator at the given block.
    function getOperatorWeightAtBlock(
        address operator,
        uint32 blockNumber
    ) external view returns (uint256) {
        return _self().getOperatorWeightAtBlock(operator, blockNumber);
    }

    /// @notice Retrieves the total weight at a specific block number.
    /// @param blockNumber The block number to get the total weight for the quorum
    /// @return uint256 - The total weight at the given block.
    function getLastCheckpointTotalWeightAtBlock(
        uint32 blockNumber
    ) external view returns (uint256) {
        return _self().getLastCheckpointTotalWeightAtBlock(blockNumber);
    }

    /// @notice Retrieves the threshold weight at a specific block number.
    /// @param blockNumber The block number to get the threshold weight for the quorum
    /// @return uint256 - The threshold weight the given block.
    function getLastCheckpointThresholdWeightAtBlock(
        uint32 blockNumber
    ) external view returns (uint256) {
        return _self().getLastCheckpointThresholdWeightAtBlock(blockNumber);
    }

    /**
     * @notice returns the status of a challenger an operator is enrolled in
     * @param operator The address of the operator
     * @param _challenger specified IRemoteChallenger contract
     */
    function getChallengerEnrollment(
        address operator,
        IRemoteChallenger _challenger
    ) external view returns (Enrollment memory enrollment) {
        return _self().getEnrollmentStatus(operator, address(_challenger));
    }

    /**
     * @notice returns the list of challengers an operator is enrolled in
     * @param operator The address of the operator
     */
    function getOperatorChallengers(
        address operator
    ) public view returns (address[] memory) {
        return _self().getOperatorChallengers(operator);
    }

    function getRestakeableAssets()
        external
        view
        virtual
        returns (address[] memory)
    {
        return _self().getRestakeableAssets();
    }

    function getOperatorRestakedVaults(
        address operator
    ) external view virtual returns (address[] memory) {
        return _self().getOperatorRestakedVaults(operator);
    }

    // ============ Internal Functions ============

    /**
     * @return $ pointer to `HyperlaneDSSLib` Storage
     */
    function _self() internal pure returns (HyperlaneDSSLib.Storage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }

    /**
     * @return pointer to `BaseDSSLib` State
     */
    function baseDssStatePtr()
        internal
        view
        override
        returns (BaseDSSLib.State storage)
    {
        return _self().baseDssState;
    }

    // ============ Modifiers ============

    // Only allows the challenger the operator is enrolled in to call the function
    modifier onlyEnrolledChallenger(address operator) {
        if (
            _self().getEnrollmentStatus(operator, msg.sender).status ==
            EnrollmentStatus.UNENROLLED
        ) {
            revert OperatorNotEnrolledWithChallenger(
                IRemoteChallenger(msg.sender)
            );
        }
        _;
    }

    modifier onlyRegisteredOperator(address operator) {
        if (!isOperatorRegistered(operator)) {
            revert OperatorNotRegistered();
        }
        _;
    }
}
