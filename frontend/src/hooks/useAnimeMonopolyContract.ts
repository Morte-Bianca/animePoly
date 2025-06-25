import { useMemo } from 'react';
import { Contract, Signer, Provider } from 'ethers';
import abi from '../contracts/abi.json';

export function useAnimeMonopolyContract(signerOrProvider?: Signer | Provider) {
  const address = import.meta.env.VITE_CONTRACT_ADDRESS;

  return useMemo(() => {
    if (!address || !signerOrProvider) return undefined;
    return new Contract(address, abi, signerOrProvider);
  }, [address, signerOrProvider]);
}
