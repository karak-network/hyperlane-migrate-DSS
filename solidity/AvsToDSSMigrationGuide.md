# Hyperlane AVS -> DSS Migration

## Introduction

`HyperlaneDSS.sol` is designed for the Hyperlane protocol to work with Karak restaking. Unlike AVS the `HyperlaneDSS.sol` is a single contract which is responsible for operations related to operators, challengers.

## HyperlaneDSS

- #### DeployAndRegisterHyperlaneDSS
  - To deploy and register the `HyperlaneDSS.sol` with `core`:
    - set the `DEPLOYER`, `PROXY_ADMIN_OWNER` in the script `script/dss/DeployHyperlaneDSS.s.sol`
      - DEPLOYER: address of the contracts deployer.
      - PROXY_ADMIN_OWNER: address of the owner of the PROXY ADMIN.
    - Populate the `script/dss/karak_addresses.json` with the config on each network.
      - hyperlaneDSSOwner : Onwer of the hyperlaneDSS contract.
      - coreAddress : Address of the core on the network.
      - minimumWeight : Minimum weight of an operator to consider it's input.
      - maxSlahablePercentageWad : Represents the maximum slash percentage wad that can be requested by the `hyperlaneDSS` in a single request. Belongs to a set of values [1, 100e18] where 1 represents no slashing.
  - Use the `forge script script/dss/DeployHyperlaneDSS.s.sol --broadcast --sig "deploy(string)" "<network name as per the karak_addresses.json>" --rpc-url <>  --private-key <>`
- #### Quorum

  - A quorum represents a set of assets and their corresponding weight.
  - Weight of an operator is calculated as a weighted sum of the underlying assets of it's staked vaults.

- ## Challenger
  - Challengers can have a max challengeDelayBlocks of `7 days`, as this is the delay served by the operator while unstaking the vaults, else the operator can fully unstake it's vault and escape slashing from the challenger.

## Operator

- #### Registration

  - To register with the DSS the operator needs to call `registerOperatorToDSS(dss, registrationHookData)` in the `core` contract with the follwoing params.
    - dss : address of `HyperlaneDSS`
    - registrationHookData: `abi.encode(<signingAddress>)` of the operator. HyperlaneDSS expects the signing Address of the operator i.e the validator for an operator.

- #### Staking/Unstaking vaults
  - Operator can stake vaults deployed by them from the core. Please refer to [this](https://docs.karak.network/developers/vaults/overview#vaults) to deploy the vault from core.
  - Staking/unstaking vault into a DSS is a 2 step async process, with a delay of 9 days.
    1. Request the stake update of the vault.
       - The operator needs to call `requestUpdateVaultStakeInDSS(vaultStakeUpdateRequest)` in the `core` contract.
         vaultStakeUpdateRequest : `StakeUpdateRequest {
        address vault; <address of vault to stake/unstake>
        IDSS dss; <address of the hyeprlaneDSS>
        bool toStake; // true for stake, false for unstake
    }`
       - The above call will queue a stake update request and return an object of `QueuedStakeUpdate`.
       - Only a single update request can be placed per vault.
    2. Finalize the stake update of the vault.
       - The operator (not necessarily operator) needs to call `finalizeUpdateVaultStakeInDSS(queuedStakeUpdate)` in the `core` contract. `queuedStakeUpdate` is the object returned in the previous call.
       - The call will be executed sucessfully post 9 days from the call to `requestUpdateVaultStakeInDSS`.
- #### Enrollment and Unenrollment

  - `enrollIntoChallengers(IRemoteChallenger[] memory challengers)`: Enrolls an operator into a list of challengers.
  - `startUnenrollment(IRemoteChallenger[] memory challengers)`: Starts the unenrollment process for an operator from a list of challengers.
  - `completeUnenrollment(address[] memory challengers)`: Completes the unenrollment process for an operator from a list of challengers. Can only be completed post `challengeDelayBlocks` are passed.

- #### Unregistration
  - Prerequisites for unregistration:
    - Operator must unstake all the vaults from the `HyperlaneDSS`.
  - To unregister with the `HyperlaneDSS` the operator needs to call `unregisterOperatorFromDSS(dss)` in the `core` contract with the follwoing params.
    - dss : address of `HyperlaneDSS`
  - Post unregistration of the operator from `hyperlaneDSS` via core, operator is unregistered from all the challengers. As the operator has already served a `9 days` delay during unstaking of vaults.
