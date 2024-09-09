import { Wallet } from 'ethers';

import {
  HyperlaneDSS__factory,
  MerkleTreeHook__factory,
  ValidatorAnnounce__factory,
} from '@hyperlane-xyz/core';
import { ChainMap, ChainName, MultiProvider } from '@hyperlane-xyz/sdk';
import { Address, ProtocolType, isObjEmpty } from '@hyperlane-xyz/utils';

import { CommandContext } from '../context/types.js';
import {
  errorRed,
  log,
  logBlue,
  logBlueKeyValue,
  logBoldBlue,
  logGreen,
  warnYellow,
} from '../logger.js';
import { indentYamlOrJson } from '../utils/files.js';
import {
  getLatestMerkleTreeCheckpointIndex,
  getLatestValidatorCheckpointIndexAndUrl,
  getValidatorStorageLocations,
  isValidatorSigningLatestCheckpoint,
} from '../validator/utils.js';

import { dssAddresses } from './config.js';
import { readOperatorFromEncryptedJson } from './hyperlaneDSS.js';

interface ChainInfo {
  storageLocation?: string;
  latestMerkleTreeCheckpointIndex?: number;
  latestValidatorCheckpointIndex?: number;
  validatorSynced?: boolean;
  warnings?: string[];
}

interface ValidatorInfo {
  operatorAddress: Address;
  operatorName?: string;
  chains: ChainMap<ChainInfo>;
}

export const checkValidatorDSSSetup = async (
  chain: string,
  context: CommandContext,
  operatorKeyPath?: string,
  operatorAddress?: string,
) => {
  logBlue(
    `Checking DSS validator status for ${chain}, ${
      !operatorAddress ? 'this may take up to a minute to run' : ''
    }...`,
  );

  const { multiProvider } = context;

  const topLevelErrors: string[] = [];

  let operatorWallet: Wallet | undefined;
  if (operatorKeyPath) {
    operatorWallet = await readOperatorFromEncryptedJson(operatorKeyPath);
  }

  const dssOperatorRecord = await getDSSOperator(
    chain,
    multiProvider,
    topLevelErrors,
    operatorAddress ?? operatorWallet?.address,
  );

  if (!isObjEmpty(dssOperatorRecord)) {
    await setValidatorInfo(context, dssOperatorRecord, topLevelErrors);
  }

  logOutput(dssOperatorRecord, topLevelErrors);
};

const getDSSOperator = async (
  chain: string,
  multiProvider: MultiProvider,
  topLevelErrors: string[],
  operatorKey?: string,
): Promise<ChainMap<ValidatorInfo>> => {
  const dssOperator: Record<Address, ValidatorInfo> = {};

  const hyperlaneDSSAddress = getHyperlaneDSSAddress(chain, topLevelErrors);

  if (!hyperlaneDSSAddress) {
    return dssOperator;
  }

  const hyperlaneDSS = HyperlaneDSS__factory.connect(
    hyperlaneDSSAddress,
    multiProvider.getProvider(chain),
  );

  if (operatorKey) {
    // If operator key is provided, only fetch the operator's validator info
    const signingKey = await hyperlaneDSS.getLastestOperatorSigningKey(
      operatorKey,
    );
    dssOperator[signingKey] = {
      operatorAddress: operatorKey,
      chains: {},
    };
  }
  return dssOperator;
};

const setValidatorInfo = async (
  context: CommandContext,
  dssOperatorRecord: Record<Address, ValidatorInfo>,
  topLevelErrors: string[],
) => {
  const { multiProvider, registry, chainMetadata } = context;
  const failedToReadChains: string[] = [];

  const validatorAddresses = Object.keys(dssOperatorRecord);

  const chains = await registry.getChains();
  const addresses = await registry.getAddresses();

  for (const chain of chains) {
    // skip if chain is not an Ethereum chain
    if (chainMetadata[chain].protocol !== ProtocolType.Ethereum) continue;

    const chainAddresses = addresses[chain];

    // skip if no contract addresses are found for this chain
    if (chainAddresses === undefined) continue;

    if (!chainAddresses.validatorAnnounce) {
      topLevelErrors.push(`❗️ ValidatorAnnounce is not deployed on ${chain}`);
    }

    if (!chainAddresses.merkleTreeHook) {
      topLevelErrors.push(`❗️ MerkleTreeHook is not deployed on ${chain}`);
    }

    if (!chainAddresses.validatorAnnounce || !chainAddresses.merkleTreeHook) {
      continue;
    }

    const validatorAnnounce = ValidatorAnnounce__factory.connect(
      chainAddresses.validatorAnnounce,
      multiProvider.getProvider(chain),
    );

    const merkleTreeHook = MerkleTreeHook__factory.connect(
      chainAddresses.merkleTreeHook,
      multiProvider.getProvider(chain),
    );

    const latestMerkleTreeCheckpointIndex =
      await getLatestMerkleTreeCheckpointIndex(merkleTreeHook, chain);

    const validatorStorageLocations = await getValidatorStorageLocations(
      validatorAnnounce,
      validatorAddresses,
      chain,
    );

    if (!validatorStorageLocations) {
      failedToReadChains.push(chain);
      continue;
    }

    for (let i = 0; i < validatorAddresses.length; i++) {
      const validatorAddress = validatorAddresses[i];
      const storageLocation = validatorStorageLocations[i];
      const warnings: string[] = [];

      // Skip if no storage location is found, address is not validating on this chain or if storage location string doesn't not start with s3://
      if (
        storageLocation.length === 0 ||
        !storageLocation[0].startsWith('s3://')
      ) {
        continue;
      }

      const [latestValidatorCheckpointIndex, latestCheckpointUrl] =
        (await getLatestValidatorCheckpointIndexAndUrl(storageLocation[0])) ?? [
          undefined,
          undefined,
        ];

      if (!latestMerkleTreeCheckpointIndex) {
        warnings.push(
          `❗️ Failed to fetch latest checkpoint index of merkleTreeHook on ${chain}.`,
        );
      }

      if (!latestValidatorCheckpointIndex) {
        warnings.push(
          `❗️ Failed to fetch latest signed checkpoint index of validator on ${chain}, this is likely due to failing to read an S3 bucket`,
        );
      }

      let validatorSynced = undefined;
      if (latestMerkleTreeCheckpointIndex && latestValidatorCheckpointIndex) {
        validatorSynced = isValidatorSigningLatestCheckpoint(
          latestValidatorCheckpointIndex,
          latestMerkleTreeCheckpointIndex,
        );
      }

      const chainInfo: ChainInfo = {
        storageLocation: latestCheckpointUrl,
        latestMerkleTreeCheckpointIndex,
        latestValidatorCheckpointIndex,
        validatorSynced,
        warnings,
      };

      const validatorInfo = dssOperatorRecord[validatorAddress];
      if (validatorInfo) {
        validatorInfo.chains[chain as ChainName] = chainInfo;
      }
    }
  }

  if (failedToReadChains.length > 0) {
    topLevelErrors.push(
      `❗️ Failed to read storage locations onchain for ${failedToReadChains.join(
        ', ',
      )}`,
    );
  }
};

const logOutput = (
  dssKeysRecord: Record<Address, ValidatorInfo>,
  topLevelErrors: string[],
) => {
  if (topLevelErrors.length > 0) {
    for (const error of topLevelErrors) {
      errorRed(error);
    }
  }

  for (const [validatorAddress, data] of Object.entries(dssKeysRecord)) {
    log('\n\n');
    if (data.operatorName) logBlueKeyValue('Operator name', data.operatorName);
    logBlueKeyValue('Operator address', data.operatorAddress);
    logBlueKeyValue('Validator address', validatorAddress);

    if (!isObjEmpty(data.chains)) {
      logBoldBlue(indentYamlOrJson('Validating on...', 2));
      for (const [chain, chainInfo] of Object.entries(data.chains)) {
        logBoldBlue(indentYamlOrJson(chain, 2));

        if (chainInfo.storageLocation) {
          logBlueKeyValue(
            indentYamlOrJson('Storage location', 2),
            chainInfo.storageLocation,
          );
        }

        if (chainInfo.latestMerkleTreeCheckpointIndex) {
          logBlueKeyValue(
            indentYamlOrJson('Latest merkle tree checkpoint index', 2),
            String(chainInfo.latestMerkleTreeCheckpointIndex),
          );
        }

        if (chainInfo.latestValidatorCheckpointIndex) {
          logBlueKeyValue(
            indentYamlOrJson('Latest validator checkpoint index', 2),
            String(chainInfo.latestValidatorCheckpointIndex),
          );

          if (chainInfo.validatorSynced) {
            logGreen(
              indentYamlOrJson('✅ Validator is signing latest checkpoint', 2),
            );
          } else {
            errorRed(
              indentYamlOrJson(
                '❌ Validator is not signing latest checkpoint',
                2,
              ),
            );
          }
        } else {
          errorRed(
            indentYamlOrJson(
              '❌ Failed to fetch latest signed checkpoint index',
              2,
            ),
          );
        }

        if (chainInfo.warnings && chainInfo.warnings.length > 0) {
          warnYellow(
            indentYamlOrJson('The following warnings were encountered:', 2),
          );
          for (const warning of chainInfo.warnings) {
            warnYellow(indentYamlOrJson(warning, 3));
          }
        }
      }
    } else {
      logBlue('Validator is not validating on any chain');
    }
  }
};

const getHyperlaneDSSAddress = (
  chain: string,
  topLevelErrors: string[],
): Address | undefined => {
  try {
    return dssAddresses[chain]['hyperlaneDSS'];
  } catch (err) {
    topLevelErrors.push(`❗️ HyperlaneDSS address not found for ${chain}`);
    return undefined;
  }
};
