import { defaultAbiCoder } from '@ethersproject/abi';
import { password } from '@inquirer/prompts';
import { BigNumberish, Wallet, utils } from 'ethers';

import { ICore__factory, IHyperlaneDSS__factory } from '@hyperlane-xyz/core';
import { ChainName } from '@hyperlane-xyz/sdk';
import { Address } from '@hyperlane-xyz/utils';

import { WriteCommandContext } from '../context/types.js';
import { log, logBlue, logRed } from '../logger.js';
import { readFileAtPath, resolvePath } from '../utils/files.js';

import { dssAddresses } from './config.js';

export type SignatureWithSaltAndExpiryStruct = {
  signature: utils.BytesLike;
  salt: utils.BytesLike;
  expiry: BigNumberish;
};

export async function registerOperator({
  context,
  chain,
  operatorKeyPath,
  signingKeyAddress,
}: {
  context: WriteCommandContext;
  chain: ChainName;
  operatorKeyPath: string;
  signingKeyAddress: Address;
}) {
  const { multiProvider } = context;

  const operatorAsSigner = await readOperatorFromEncryptedJson(operatorKeyPath);

  const provider = multiProvider.getProvider(chain);
  const connectedSigner = operatorAsSigner.connect(provider);

  const coreAddress = dssAddresses[chain].core;

  const core = ICore__factory.connect(coreAddress, connectedSigner);

  const hyperlaneDSSAddress = dssAddresses[chain].hyperlaneDSS;

  const resgistrationData = defaultAbiCoder.encode(
    ['address'],
    [signingKeyAddress],
  );
  // check if the operator is already registered
  const operatorStatus = await core.isOperatorRegisteredToDSS(
    operatorAsSigner.address,
    hyperlaneDSSAddress,
  );
  if (operatorStatus) {
    logBlue(
      `Operator ${operatorAsSigner.address} already registered with Hyperlane DSS`,
    );
    return;
  }

  log(
    `Registering operator ${operatorAsSigner.address} attesting ${signingKeyAddress} on ${chain}...`,
  );
  await multiProvider.handleTx(
    chain,
    core.registerOperatorToDSS(hyperlaneDSSAddress, resgistrationData),
  );
  logBlue(`Operator ${operatorAsSigner.address} registered with Hyperlane DSS`);
}

export async function deregisterOperator({
  context,
  chain,
  operatorKeyPath,
}: {
  context: WriteCommandContext;
  chain: ChainName;
  operatorKeyPath: string;
}) {
  const { multiProvider } = context;

  const operatorAsSigner = await readOperatorFromEncryptedJson(operatorKeyPath);

  const provider = multiProvider.getProvider(chain);
  const connectedSigner = operatorAsSigner.connect(provider);

  const coreAddress = dssAddresses[chain].core;
  const hyperlaneDSSAddress = dssAddresses[chain].hyperlaneDSS;

  const core = ICore__factory.connect(coreAddress, connectedSigner);

  const operatorStakedVaults = await core.fetchVaultsStakedInDSS(
    operatorAsSigner.address,
    hyperlaneDSSAddress,
  );
  if (operatorStakedVaults.length > 0) {
    logRed(`Unstake these vaults to unregister: ${operatorStakedVaults}`);
    return;
  }
  log(`Deregistering operator ${operatorAsSigner.address} on ${chain}...`);
  await multiProvider.handleTx(
    chain,
    core.unregisterOperatorFromDSS(hyperlaneDSSAddress),
  );
  logBlue(
    `Operator ${operatorAsSigner.address} unregistered from Hyperlane DSS`,
  );
}

export async function readOperatorFromEncryptedJson(
  operatorKeyPath: string,
): Promise<Wallet> {
  const encryptedJson = readFileAtPath(resolvePath(operatorKeyPath));

  const keyFilePassword = await password({
    mask: '*',
    message: 'Enter the password for the operator key file: ',
  });

  return Wallet.fromEncryptedJson(encryptedJson, keyFilePassword);
}

export async function updateOperatorSigningKey({
  context,
  chain,
  operatorKeyPath,
  newSigningKeyAddress,
}: {
  context: WriteCommandContext;
  chain: ChainName;
  operatorKeyPath: string;
  newSigningKeyAddress: Address;
}) {
  const { multiProvider } = context;

  const operatorAsSigner = await readOperatorFromEncryptedJson(operatorKeyPath);

  const provider = multiProvider.getProvider(chain);
  const connectedSigner = operatorAsSigner.connect(provider);

  const coreAddress = dssAddresses[chain].core;

  const core = ICore__factory.connect(coreAddress, connectedSigner);

  const hyperlaneDSSAddress = dssAddresses[chain].hyperlaneDSS;
  const hyperlaneDSS = IHyperlaneDSS__factory.connect(
    hyperlaneDSSAddress,
    connectedSigner,
  );

  // check if the operator is already registered
  const operatorStatus = await core.isOperatorRegisteredToDSS(
    operatorAsSigner.address,
    hyperlaneDSSAddress,
  );
  if (!operatorStatus) {
    logRed(
      `Operator ${operatorAsSigner.address} not registered with Hyperlane DSS`,
    );
    return;
  }

  log(
    `Updating operator ${operatorAsSigner.address} singinig key to ${newSigningKeyAddress} on ${chain}...`,
  );
  await multiProvider.handleTx(
    chain,
    hyperlaneDSS.updateOperatorSigningKey(newSigningKeyAddress),
  );
  logBlue(
    `Updated Operator ${operatorAsSigner.address} signing key to ${newSigningKeyAddress}`,
  );
}

export async function enrollIntoChallengers({
  context,
  chain,
  operatorKeyPath,
  challengers,
}: {
  context: WriteCommandContext;
  chain: ChainName;
  operatorKeyPath: string;
  challengers: Address[];
}) {
  const { multiProvider } = context;

  const operatorAsSigner = await readOperatorFromEncryptedJson(operatorKeyPath);

  const provider = multiProvider.getProvider(chain);
  const connectedSigner = operatorAsSigner.connect(provider);

  const coreAddress = dssAddresses[chain].core;

  const core = ICore__factory.connect(coreAddress, connectedSigner);

  const hyperlaneDSSAddress = dssAddresses[chain].hyperlaneDSS;
  const hyperlaneDSS = IHyperlaneDSS__factory.connect(
    hyperlaneDSSAddress,
    connectedSigner,
  );

  // check if the operator is already registered
  const operatorStatus = await core.isOperatorRegisteredToDSS(
    operatorAsSigner.address,
    hyperlaneDSSAddress,
  );
  if (!operatorStatus) {
    logRed(
      `Operator ${operatorAsSigner.address} not registered with Hyperlane DSS`,
    );
    return;
  }

  log(
    `Enrolling operator ${operatorAsSigner.address} into challengers: ${challengers} on ${chain}...`,
  );
  await multiProvider.handleTx(
    chain,
    hyperlaneDSS.enrollIntoChallengers(challengers),
  );
  logBlue(
    `Enrolled Operator ${operatorAsSigner.address} into challengers: ${challengers}`,
  );
}

export async function startUnenrollmentFromChallengers({
  context,
  chain,
  operatorKeyPath,
  challengers,
}: {
  context: WriteCommandContext;
  chain: ChainName;
  operatorKeyPath: string;
  challengers: Address[];
}) {
  const { multiProvider } = context;

  const operatorAsSigner = await readOperatorFromEncryptedJson(operatorKeyPath);

  const provider = multiProvider.getProvider(chain);
  const connectedSigner = operatorAsSigner.connect(provider);

  const coreAddress = dssAddresses[chain].core;

  const core = ICore__factory.connect(coreAddress, connectedSigner);

  const hyperlaneDSSAddress = dssAddresses[chain].hyperlaneDSS;
  const hyperlaneDSS = IHyperlaneDSS__factory.connect(
    hyperlaneDSSAddress,
    connectedSigner,
  );

  // check if the operator is already registered
  const operatorStatus = await core.isOperatorRegisteredToDSS(
    operatorAsSigner.address,
    hyperlaneDSSAddress,
  );
  if (!operatorStatus) {
    logRed(
      `Operator ${operatorAsSigner.address} not registered with Hyperlane DSS`,
    );
    return;
  }

  log(
    `Starting unenrolling of operator ${operatorAsSigner.address} from challengers: ${challengers} on ${chain}...`,
  );
  await multiProvider.handleTx(
    chain,
    hyperlaneDSS.startUnenrollment(challengers),
  );
  logBlue(
    `Started unenrollment of Operator ${operatorAsSigner.address} from challengers: ${challengers}`,
  );
}

export async function completeUnenrollmentFromChallengers({
  context,
  chain,
  operatorKeyPath,
  challengers,
}: {
  context: WriteCommandContext;
  chain: ChainName;
  operatorKeyPath: string;
  challengers: Address[];
}) {
  const { multiProvider } = context;

  const operatorAsSigner = await readOperatorFromEncryptedJson(operatorKeyPath);

  const provider = multiProvider.getProvider(chain);
  const connectedSigner = operatorAsSigner.connect(provider);

  const coreAddress = dssAddresses[chain].core;

  const core = ICore__factory.connect(coreAddress, connectedSigner);

  const hyperlaneDSSAddress = dssAddresses[chain].hyperlaneDSS;
  const hyperlaneDSS = IHyperlaneDSS__factory.connect(
    hyperlaneDSSAddress,
    connectedSigner,
  );

  // check if the operator is already registered
  const operatorStatus = await core.isOperatorRegisteredToDSS(
    operatorAsSigner.address,
    hyperlaneDSSAddress,
  );
  if (!operatorStatus) {
    logRed(
      `Operator ${operatorAsSigner.address} not registered with Hyperlane DSS`,
    );
    return;
  }

  log(
    `Completing unenrollment of operator ${operatorAsSigner.address} from challengers: ${challengers} on ${chain}...`,
  );
  await multiProvider.handleTx(
    chain,
    hyperlaneDSS.completeUnenrollment(challengers),
  );
  logBlue(
    `Completed unenrollment of Operator ${operatorAsSigner.address} from challengers: ${challengers}`,
  );
}
