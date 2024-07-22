// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {ECDSAStakeRegistryStorage, Quorum, AssetParams} from "./ECDSAStakeRegistryStorage.sol";
import {IKarakBaseVault} from "../interfaces/avs/vendored/IKarakBaseVault.sol";
import {ICore} from "../interfaces/avs/vendored/ICore.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {CheckpointsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/CheckpointsUpgradeable.sol";
import {SignatureCheckerUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/cryptography/SignatureCheckerUpgradeable.sol";
import {IERC1271Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC1271Upgradeable.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

/// @title ECDSA Stake Registry
/// @author Layr Labs, Inc.
/// @dev THIS CONTRACT IS NOT AUDITED
/// @notice registers and updates the stake of an operator.
contract ECDSAStakeRegistry is IERC1271Upgradeable, OwnableUpgradeable, ECDSAStakeRegistryStorage {
    using SignatureCheckerUpgradeable for address;
    using CheckpointsUpgradeable for CheckpointsUpgradeable.History;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /// @dev Constructor to create ECDSAStakeRegistry.
    /// @param _core Address of the Core contract that this registry interacts with.
    constructor(ICore _core) ECDSAStakeRegistryStorage(_core) {
        // _disableInitializers();
    }

    /// @notice Initializes the contract with the given parameters.
    /// @param _serviceManager The address of the service manager.
    /// @param _thresholdWeight The threshold weight in basis points.
    /// @param _quorum The quorum struct containing the details of the quorum thresholds.
    function initialize(address _serviceManager, uint256 _thresholdWeight, Quorum memory _quorum)
        external
        initializer
    {
        __ECDSAStakeRegistry_init(_serviceManager, _thresholdWeight, _quorum);
    }

    /// @notice Registers a new operator using a provided signature and signing key
    /// @param data Contains the address of the siging key for operator
    function registerOperator(address operator, bytes memory data) external onlyServiceManager {
        address signingKey = abi.decode(data, (address));
        _registerOperator(operator, signingKey);
    }

    /// @notice Deregisters an existing operator
    function unregisterOperator(address operator, bytes memory) external onlyServiceManager {
        _unregisterOperator(operator);
    }

    /**
     * @notice Updates the signing key for an operator
     * @dev Only callable by the operator themselves
     * @param _newSigningKey The new signing key to set for the operator
     */
    function updateOperatorSigningKey(address _newSigningKey) external {
        if (!_operatorRegistered[msg.sender]) {
            revert OperatorNotRegistered();
        }
        _updateOperatorSigningKey(msg.sender, _newSigningKey);
    }

    /**
     * @notice Updates the StakeRegistry's view of one or more operators' stakes adding a new entry in their history of stake checkpoints,
     * @dev Queries stakes from the `Core` contract
     * @param _operators A list of operator addresses to update
     */
    function updateOperators(address[] memory _operators) external {
        _updateOperators(_operators);
    }

    /**
     * @notice Updates the quorum configuration and the set of operators
     * @dev Only callable by the contract owner.
     * It first updates the quorum configuration and then updates the list of operators.
     * @param _quorum The new quorum configuration, including assets and their new weights
     * @param _operators The list of operator addresses to update stakes for
     */
    function updateQuorumConfig(
        Quorum memory _quorum,
        address[] memory _operators
    ) external onlyOwner {
        _updateQuorumConfig(_quorum);
        _updateOperators(_operators);
    }

    /// @notice Updates the weight an operator must have to join the operator set
    /// @dev Access controlled to the contract owner
    /// @param _newMinimumWeight The new weight an operator must have to join the operator set
    function updateMinimumWeight(
        uint256 _newMinimumWeight,
        address[] memory _operators
    ) external onlyOwner {
        _updateMinimumWeight(_newMinimumWeight);
        _updateOperators(_operators);
    }

    /**
     * @notice Sets a new cumulative threshold weight for message validation by operator set signatures.
     * @dev This function can only be invoked by the owner of the contract. It delegates the update to
     * an internal function `_updateStakeThreshold`.
     * @param _thresholdWeight The updated threshold weight required to validate a message. This is the
     * cumulative weight that must be met or exceeded by the sum of the stakes of the signatories for
     * a message to be deemed valid.
     */
    function updateStakeThreshold(uint256 _thresholdWeight) external onlyOwner {
        _updateStakeThreshold(_thresholdWeight);
    }

    /// @notice Verifies if the provided signature data is valid for the given data hash.
    /// @param _dataHash The hash of the data that was signed.
    /// @param _signatureData Encoded signature data consisting of an array of operators, an array of signatures, and a reference block number.
    /// @return The function selector that indicates the signature is valid according to ERC1271 standard.
    function isValidSignature(
        bytes32 _dataHash,
        bytes memory _signatureData
    ) external view returns (bytes4) {
        (
            address[] memory operators,
            bytes[] memory signatures,
            uint32 referenceBlock
        ) = abi.decode(_signatureData, (address[], bytes[], uint32));
        _checkSignatures(_dataHash, operators, signatures, referenceBlock);
        return IERC1271Upgradeable.isValidSignature.selector;
    }

    /// @notice Retrieves the current stake quorum details.
    /// @return quorum - The current quorum of assets and weights
    function quorum() public view returns (Quorum memory quorum) {
        quorum.assets = new AssetParams[](_assetToWeightMap[_quorumIndex].length());
        for (uint256 i = 0; i < quorum.assets.length; i++) {
            uint256 weight;
            (quorum.assets[i].asset, weight) = _assetToWeightMap[_quorumIndex].at(i);
            quorum.assets[i].weight = uint96(weight);
        }
        return quorum;
    }

    /**
     * @notice Retrieves the latest signing key for a given operator.
     * @param _operator The address of the operator.
     * @return The latest signing key of the operator.
     */
    function getLastestOperatorSigningKey(
        address _operator
    ) external view returns (address) {
        return address(uint160(_operatorSigningKeyHistory[_operator].latest()));
    }

    /**
     * @notice Retrieves the latest signing key for a given operator at a specific block number.
     * @param _operator The address of the operator.
     * @param _blockNumber The block number to get the operator's signing key.
     * @return The signing key of the operator at the given block.
     */
    function getOperatorSigningKeyAtBlock(
        address _operator,
        uint256 _blockNumber
    ) external view returns (address) {
        return
            address(
                uint160(
                    _operatorSigningKeyHistory[_operator].getAtBlock(
                        _blockNumber
                    )
                )
            );
    }

    /// @notice Retrieves the last recorded weight for a given operator.
    /// @param _operator The address of the operator.
    /// @return uint256 - The latest weight of the operator.
    function getLastCheckpointOperatorWeight(
        address _operator
    ) external view returns (uint256) {
        return _operatorWeightHistory[_operator].latest();
    }

    /// @notice Retrieves the last recorded total weight across all operators.
    /// @return uint256 - The latest total weight.
    function getLastCheckpointTotalWeight() external view returns (uint256) {
        return _totalWeightHistory.latest();
    }

    /// @notice Retrieves the last recorded threshold weight
    /// @return uint256 - The latest threshold weight.
    function getLastCheckpointThresholdWeight()
        external
        view
        returns (uint256)
    {
        return _thresholdWeightHistory.latest();
    }

    /// @notice Retrieves the operator's weight at a specific block number.
    /// @param _operator The address of the operator.
    /// @param _blockNumber The block number to get the operator weight for the quorum
    /// @return uint256 - The weight of the operator at the given block.
    function getOperatorWeightAtBlock(
        address _operator,
        uint32 _blockNumber
    ) external view returns (uint256) {
        return _operatorWeightHistory[_operator].getAtBlock(_blockNumber);
    }

    /// @notice Retrieves the total weight at a specific block number.
    /// @param _blockNumber The block number to get the total weight for the quorum
    /// @return uint256 - The total weight at the given block.
    function getLastCheckpointTotalWeightAtBlock(
        uint32 _blockNumber
    ) external view returns (uint256) {
        return _totalWeightHistory.getAtBlock(_blockNumber);
    }

    /// @notice Retrieves the threshold weight at a specific block number.
    /// @param _blockNumber The block number to get the threshold weight for the quorum
    /// @return uint256 - The threshold weight the given block.
    function getLastCheckpointThresholdWeightAtBlock(uint32 _blockNumber) external view returns (uint256) {
        return _thresholdWeightHistory.getAtBlock(_blockNumber);
    }

    function operatorRegistered(address _operator) external view returns (bool) {
        return _operatorRegistered[_operator];
    }

    /// @notice Returns the weight an operator must have to contribute to validating an DSS
    function minimumWeight() external view returns (uint256) {
        return _minimumWeight;
    }

    /// @notice Calculates the current weight of an operator based on their delegated stake in the vaults having assets considered in the quorum
    /// @param _operator The address of the operator.
    /// @return uint256 - The current weight of the operator; returns 0 if below the threshold.
    function getOperatorWeight(address _operator) public view returns (uint256) {
        uint256 weight;
        // Includes vaults queued for exit too. Need to removed vaults queued for unstaking
        address[] memory vaults = CORE.fetchVaultsStakedInDSS(_operator, _serviceManager);
        for (uint256 i; i < vaults.length; i++) {
            //instead of `totalAssets()` need to fetch assets not queued for withdrawals
            weight += IKarakBaseVault(vaults[i]).totalAssets() * getAssetWeight(IKarakBaseVault(vaults[i]).asset());
        }
        weight = weight / BPS;

        if (weight >= _minimumWeight) {
            return weight;
        } else {
            return 0;
        }
    }

    function getAssetWeight(address asset) public view returns (uint256 weight) {
        (, weight) = _assetToWeightMap[_quorumIndex].tryGet(asset);
    }

    /// @notice Initializes state for the StakeRegistry
    /// @param _serviceManagerAddr The DSS' ServiceManager contract's address
    function __ECDSAStakeRegistry_init(address _serviceManagerAddr, uint256 _thresholdWeight, Quorum memory _quorum)
        internal
        onlyInitializing
    {
        _serviceManager = _serviceManagerAddr;
        _updateStakeThreshold(_thresholdWeight);
        _updateQuorumConfig(_quorum);
        __Ownable_init();
    }

    /// @dev Updates the weights for a given list of operator addresses.
    /// When passing an operator that isn't registered, then 0 is added to their history
    /// @param _operators An array of addresses for which to update the weights.
    function _updateOperators(address[] memory _operators) internal {
        int256 delta = 0;
        for (uint256 i; i < _operators.length; i++) {
            delta += _updateOperatorWeight(_operators[i]);
        }
        _updateTotalWeight(delta);
    }

    /// @dev Updates the stake threshold weight and records the history.
    /// @param _thresholdWeight The new threshold weight to set and record in the history.
    function _updateStakeThreshold(uint256 _thresholdWeight) internal {
        _thresholdWeightHistory.push(_thresholdWeight);
        emit ThresholdWeightUpdated(_thresholdWeight);
    }

    /// @dev Updates the weight an operator must have to join the operator set
    /// @param _newMinimumWeight The new weight an operator must have to join the operator set
    function _updateMinimumWeight(uint256 _newMinimumWeight) internal {
        uint256 oldMinimumWeight = _minimumWeight;
        _minimumWeight = _newMinimumWeight;
        emit MinimumWeightUpdated(oldMinimumWeight, _newMinimumWeight);
    }

    /// @notice Updates the quorum configuration
    /// @dev Replaces the current quorum configuration with `_newQuorum` if valid.
    /// Reverts with `InvalidQuorum` if the new quorum configuration is not valid.
    /// Emits `QuorumUpdated` event with the old and new quorum configurations.
    /// @param _newQuorum The new quorum configuration to set.
    function _updateQuorumConfig(Quorum memory _newQuorum) internal {
        if (!_isValidQuorum(_newQuorum)) {
            revert InvalidQuorum();
        }
        Quorum memory oldQuorum = quorum();

        for (uint256 i; i < _newQuorum.assets.length; i++) {
            _assetToWeightMap[_quorumIndex].set(_newQuorum.assets[i].asset, _newQuorum.assets[i].weight);
        }
        _quorumIndex++;
        emit QuorumUpdated(oldQuorum, _newQuorum);
    }

    /// @dev Internal function to deregister an operator
    /// @param _operator The operator's address to deregister
    function _unregisterOperator(address _operator) internal {
        if (!_operatorRegistered[_operator]) {
            revert OperatorNotRegistered();
        }
        _totalOperators--;
        delete _operatorRegistered[_operator];
        int256 delta = _updateOperatorWeight(_operator);
        _updateTotalWeight(delta);
        emit OperatorDeregistered(_operator, address(_serviceManager));
    }

    /// @dev registers an operator through a provided signature
    /// @param _signingKey The signing key to add to the operator's history
    function _registerOperator(address _operator, address _signingKey) internal virtual {
        if (_operatorRegistered[_operator]) {
            revert OperatorAlreadyRegistered();
        }
        _totalOperators++;
        _operatorRegistered[_operator] = true;
        int256 delta = _updateOperatorWeight(_operator);
        _updateTotalWeight(delta);
        _updateOperatorSigningKey(_operator, _signingKey);
        emit OperatorRegistered(_operator, _serviceManager);
    }

    /// @dev Internal function to update an operator's signing key
    /// @param _operator The address of the operator to update the signing key for
    /// @param _newSigningKey The new signing key to set for the operator
    function _updateOperatorSigningKey(
        address _operator,
        address _newSigningKey
    ) internal {
        address oldSigningKey = address(
            uint160(_operatorSigningKeyHistory[_operator].latest())
        );
        if (_newSigningKey == oldSigningKey) {
            return;
        }
        _operatorSigningKeyHistory[_operator].push(uint160(_newSigningKey));
        emit SigningKeyUpdate(
            _operator,
            block.number,
            _newSigningKey,
            oldSigningKey
        );
    }

    /// @notice Updates the weight of an operator and returns the previous and current weights.
    /// @param _operator The address of the operator to update the weight of.
    function _updateOperatorWeight(
        address _operator
    ) internal virtual returns (int256) {
        int256 delta;
        uint256 newWeight;
        uint256 oldWeight = _operatorWeightHistory[_operator].latest();
        if (!_operatorRegistered[_operator]) {
            delta -= int256(oldWeight);
            if (delta == 0) {
                return delta;
            }
            _operatorWeightHistory[_operator].push(0);
        } else {
            newWeight = getOperatorWeight(_operator);
            delta = int256(newWeight) - int256(oldWeight);
            if (delta == 0) {
                return delta;
            }
            _operatorWeightHistory[_operator].push(newWeight);
        }
        emit OperatorWeightUpdated(_operator, oldWeight, newWeight);
        return delta;
    }

    /// @dev Internal function to update the total weight of the stake
    /// @param delta The change in stake applied last total weight
    /// @return oldTotalWeight The weight before the update
    /// @return newTotalWeight The updated weight after applying the delta
    function _updateTotalWeight(
        int256 delta
    ) internal returns (uint256 oldTotalWeight, uint256 newTotalWeight) {
        oldTotalWeight = _totalWeightHistory.latest();
        int256 newWeight = int256(oldTotalWeight) + delta;
        newTotalWeight = uint256(newWeight);
        _totalWeightHistory.push(newTotalWeight);
        emit TotalWeightUpdated(oldTotalWeight, newTotalWeight);
    }

    /**
     * @dev Verifies that a specified quorum configuration is valid. A valid quorum has:
     *      1. Weights that sum to exactly 10,000 basis points, ensuring proportional representation.
     *      2. Unique strategies without duplicates to maintain quorum integrity.
     * @param _quorum The quorum configuration to be validated.
     * @return bool True if the quorum configuration is valid, otherwise false.
     */
    function _isValidQuorum(Quorum memory _quorum) internal pure returns (bool) {
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
        if (totalWeight != BPS) {
            return false;
        } else {
            return true;
        }
    }

    /**
     * @notice Common logic to verify a batch of ECDSA signatures against a hash, using either last stake weight or at a specific block.
     * @param _dataHash The hash of the data the signers endorsed.
     * @param _operators A collection of addresses that endorsed the data hash.
     * @param _signatures A collection of signatures matching the signers.
     * @param _referenceBlock The block number for evaluating stake weight; use max uint32 for latest weight.
     */
    function _checkSignatures(
        bytes32 _dataHash,
        address[] memory _operators,
        bytes[] memory _signatures,
        uint32 _referenceBlock
    ) internal view {
        uint256 signersLength = _operators.length;
        address currentOperator;
        address lastOperator;
        address signer;
        uint256 signedWeight;

        _validateSignaturesLength(signersLength, _signatures.length);
        for (uint256 i; i < signersLength; i++) {
            currentOperator = _operators[i];
            signer = _getOperatorSigningKey(currentOperator, _referenceBlock);

            _validateSortedSigners(lastOperator, currentOperator);
            _validateSignature(signer, _dataHash, _signatures[i]);

            lastOperator = currentOperator;
            uint256 operatorWeight = _getOperatorWeight(
                currentOperator,
                _referenceBlock
            );
            signedWeight += operatorWeight;
        }

        _validateThresholdStake(signedWeight, _referenceBlock);
    }

    /// @notice Validates that the number of signers equals the number of signatures, and neither is zero.
    /// @param _signersLength The number of signers.
    /// @param _signaturesLength The number of signatures.
    function _validateSignaturesLength(
        uint256 _signersLength,
        uint256 _signaturesLength
    ) internal pure {
        if (_signersLength != _signaturesLength) {
            revert LengthMismatch();
        }
        if (_signersLength == 0) {
            revert InvalidLength();
        }
    }

    /// @notice Ensures that signers are sorted in ascending order by address.
    /// @param _lastSigner The address of the last signer.
    /// @param _currentSigner The address of the current signer.
    function _validateSortedSigners(
        address _lastSigner,
        address _currentSigner
    ) internal pure {
        if (_lastSigner >= _currentSigner) {
            revert NotSorted();
        }
    }

    /// @notice Validates a given signature against the signer's address and data hash.
    /// @param _signer The address of the signer to validate.
    /// @param _dataHash The hash of the data that is signed.
    /// @param _signature The signature to validate.
    function _validateSignature(
        address _signer,
        bytes32 _dataHash,
        bytes memory _signature
    ) internal view {
        if (!_signer.isValidSignatureNow(_dataHash, _signature)) {
            revert InvalidSignature();
        }
    }

    /// @notice Retrieves the operator weight for a signer, either at the last checkpoint or a specified block.
    /// @param _operator The operator to query their signing key history for
    /// @param _referenceBlock The block number to query the operator's weight at, or the maximum uint32 value for the last checkpoint.
    /// @return The weight of the operator.
    function _getOperatorSigningKey(
        address _operator,
        uint32 _referenceBlock
    ) internal view returns (address) {
        if (_referenceBlock >= block.number) {
            revert InvalidReferenceBlock();
        }
        return
            address(
                uint160(
                    _operatorSigningKeyHistory[_operator].getAtBlock(
                        _referenceBlock
                    )
                )
            );
    }

    /// @notice Retrieves the operator weight for a signer, either at the last checkpoint or a specified block.
    /// @param _signer The address of the signer whose weight is returned.
    /// @param _referenceBlock The block number to query the operator's weight at, or the maximum uint32 value for the last checkpoint.
    /// @return The weight of the operator.
    function _getOperatorWeight(
        address _signer,
        uint32 _referenceBlock
    ) internal view returns (uint256) {
        if (_referenceBlock >= block.number) {
            revert InvalidReferenceBlock();
        }
        return _operatorWeightHistory[_signer].getAtBlock(_referenceBlock);
    }

    /// @notice Retrieve the total stake weight at a specific block or the latest if not specified.
    /// @dev If the `_referenceBlock` is the maximum value for uint32, the latest total weight is returned.
    /// @param _referenceBlock The block number to retrieve the total stake weight from.
    /// @return The total stake weight at the given block or the latest if the given block is the max uint32 value.
    function _getTotalWeight(
        uint32 _referenceBlock
    ) internal view returns (uint256) {
        if (_referenceBlock >= block.number) {
            revert InvalidReferenceBlock();
        }
        return _totalWeightHistory.getAtBlock(_referenceBlock);
    }

    /// @notice Retrieves the threshold stake for a given reference block.
    /// @param _referenceBlock The block number to query the threshold stake for.
    /// If set to the maximum uint32 value, it retrieves the latest threshold stake.
    /// @return The threshold stake in basis points for the reference block.
    function _getThresholdStake(
        uint32 _referenceBlock
    ) internal view returns (uint256) {
        if (_referenceBlock >= block.number) {
            revert InvalidReferenceBlock();
        }
        return _thresholdWeightHistory.getAtBlock(_referenceBlock);
    }

    /// @notice Validates that the cumulative stake of signed messages meets or exceeds the required threshold.
    /// @param _signedWeight The cumulative weight of the signers that have signed the message.
    /// @param _referenceBlock The block number to verify the stake threshold for
    function _validateThresholdStake(
        uint256 _signedWeight,
        uint32 _referenceBlock
    ) internal view {
        uint256 totalWeight = _getTotalWeight(_referenceBlock);
        if (_signedWeight > totalWeight) {
            revert InvalidSignedWeight();
        }
        uint256 thresholdStake = _getThresholdStake(_referenceBlock);
        if (thresholdStake > _signedWeight) {
            revert InsufficientSignedStake();
        }
    }

    /**
     * =========MODIFIER=========
     */
    modifier onlyServiceManager() {
        if (msg.sender != _serviceManager) revert CallerNotServiceManager();
        _;
    }
}
