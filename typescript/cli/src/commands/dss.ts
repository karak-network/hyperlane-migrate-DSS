import { ethers } from 'ethers';
import { CommandModule, Options } from 'yargs';

import { ChainName } from '@hyperlane-xyz/sdk';
import { Address, ProtocolType } from '@hyperlane-xyz/utils';

import { CommandModuleWithWriteContext } from '../context/types.js';
import { checkValidatorDSSSetup } from '../dss/check.js';
import {
  completeUnenrollmentFromChallengers,
  deregisterOperator,
  enrollIntoChallengers,
  registerOperator,
  startUnenrollmentFromChallengers,
  updateOperatorSigningKey,
} from '../dss/hyperlaneDSS.js';
import { errorRed, log, logGray } from '../logger.js';

import {
  demandOption,
  dssChainCommandOption,
  operatorKeyPathCommandOption,
} from './options.js';

/**
 * Parent command
 */
export const dssCommand: CommandModule = {
  command: 'dss',
  describe: 'Interact with the Hyperlane DSS',
  builder: (yargs) =>
    yargs
      .command(registerCommand)
      .command(deregisterCommand)
      .command(checkCommand)
      .command(updateOperatorSigningKeyCommand)
      .command(enrollIntoChallengersCommand)
      .command(startUnenrollmentFromChallengersCommand)
      .command(completeUnenrollmentFromChallengersCommand)
      .version(false)
      .demandCommand(),
  handler: () => log('Command required'),
};

/**
 * Registration command
 */
export const registrationOptions: { [k: string]: Options } = {
  chain: dssChainCommandOption,
  operatorKeyPath: demandOption(operatorKeyPathCommandOption),
  signingKeyAddress: {
    type: 'string',
    description: 'Address of the operators signing key',
    demandOption: true,
  },
};

/**
 * Challengers command
 */
export const challengerOptions: { [k: string]: Options } = {
  chain: dssChainCommandOption,
  operatorKeyPath: demandOption(operatorKeyPathCommandOption),
  challengers: {
    type: 'array',
    string: true,
    description: 'Addresses of the challengers',
    demandOption: true,
    coerce: (challengers) => {
      return challengers.map((address: string) => {
        log(address);
        if (!ethers.utils.isAddress(address)) {
          throw new Error(`Invalid Ethereum address: ${address}`);
        }
        return ethers.utils.getAddress(address);
      });
    },
  },
};

const registerCommand: CommandModuleWithWriteContext<{
  chain: ChainName;
  operatorKeyPath: string;
  signingKeyAddress: Address;
}> = {
  command: 'register',
  describe: 'Register operator with the DSS',
  builder: registrationOptions,
  handler: async ({ context, chain, operatorKeyPath, signingKeyAddress }) => {
    await registerOperator({
      context,
      chain,
      operatorKeyPath,
      signingKeyAddress,
    });
    process.exit(0);
  },
};

const deregisterCommand: CommandModuleWithWriteContext<{
  chain: ChainName;
  operatorKeyPath: string;
}> = {
  command: 'deregister',
  describe: 'Deregister yourself with the DSS',
  builder: registrationOptions,
  handler: async ({ context, chain, operatorKeyPath }) => {
    await deregisterOperator({
      context,
      chain,
      operatorKeyPath,
    });
    process.exit(0);
  },
};

const checkCommand: CommandModuleWithWriteContext<{
  chain: ChainName;
  operatorKeyPath?: string;
  operatorAddress?: string;
}> = {
  command: 'check',
  describe: 'Check operator registration status',
  builder: {
    chain: dssChainCommandOption,
    operatorKeyPath: operatorKeyPathCommandOption,
    operatorAddress: {
      type: 'string',
      description: 'Address of the operator to check',
    },
  },
  handler: async ({ context, chain, operatorKeyPath, operatorAddress }) => {
    const { multiProvider } = context;

    // validate chain
    if (!multiProvider.hasChain(chain)) {
      errorRed(
        `❌ No metadata found for ${chain}. Ensure it is included in your configured registry.`,
      );
      process.exit(1);
    }

    const chainMetadata = multiProvider.getChainMetadata(chain);

    if (chainMetadata.protocol !== ProtocolType.Ethereum) {
      errorRed(`\n❌ Validator DSS check only supports EVM chains. Exiting.`);
      process.exit(1);
    }
    logGray(multiProvider.getRpcUrl(chain));

    await checkValidatorDSSSetup(
      chain,
      context,
      operatorKeyPath,
      operatorAddress,
    );

    process.exit(0);
  },
};

const updateOperatorSigningKeyCommand: CommandModuleWithWriteContext<{
  chain: ChainName;
  operatorKeyPath: string;
  signingKeyAddress: Address;
}> = {
  command: 'updateSigningkey',
  describe: "Update Operator's signing key",
  builder: registrationOptions,
  handler: async ({ context, chain, operatorKeyPath, signingKeyAddress }) => {
    await updateOperatorSigningKey({
      context,
      chain,
      operatorKeyPath,
      newSigningKeyAddress: signingKeyAddress,
    });
    process.exit(0);
  },
};

const enrollIntoChallengersCommand: CommandModuleWithWriteContext<{
  chain: ChainName;
  operatorKeyPath: string;
  challengers: Address[];
}> = {
  command: 'enrollIntoChallengers',
  describe: 'Enroll operators into challengers',
  builder: challengerOptions,
  handler: async ({ context, chain, operatorKeyPath, challengers }) => {
    await enrollIntoChallengers({
      context,
      chain,
      operatorKeyPath,
      challengers,
    });
    process.exit(0);
  },
};

const startUnenrollmentFromChallengersCommand: CommandModuleWithWriteContext<{
  chain: ChainName;
  operatorKeyPath: string;
  challengers: Address[];
}> = {
  command: 'startUnenrollment',
  describe: 'Start enrollment of operator into challengers',
  builder: challengerOptions,
  handler: async ({ context, chain, operatorKeyPath, challengers }) => {
    await startUnenrollmentFromChallengers({
      context,
      chain,
      operatorKeyPath,
      challengers,
    });
    process.exit(0);
  },
};

const completeUnenrollmentFromChallengersCommand: CommandModuleWithWriteContext<{
  chain: ChainName;
  operatorKeyPath: string;
  challengers: Address[];
}> = {
  command: 'completeUnenrollment',
  describe: 'Complete unenrollment of operator from challengers',
  builder: challengerOptions,
  handler: async ({ context, chain, operatorKeyPath, challengers }) => {
    await completeUnenrollmentFromChallengers({
      context,
      chain,
      operatorKeyPath,
      challengers,
    });
    process.exit(0);
  },
};
