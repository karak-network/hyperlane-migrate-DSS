import { ChainMap } from '@hyperlane-xyz/sdk';
import { Address } from '@hyperlane-xyz/utils';

interface DSSContracts {
  hyperlaneDSS: Address;
  core: Address;
}

export const dssAddresses: ChainMap<DSSContracts> = {
  holesky: {
    hyperlaneDSS: '0xe8E59c6C8B56F2c178f63BCFC4ce5e5e2359c8fc',
    core: '0xe8E59c6C8B56F2c178f63BCFC4ce5e5e2359c8fc',
  },
  ethereum: {
    hyperlaneDSS: '0x48eB57918c60dcC03Fc25Cf6cdfbec710FCC66Dd',
    core: '0x3dFfaBD3459e5D95b5C7BBF6e7Bc333Ea5EB860D',
  },
};
