import { useState } from 'react';
import { BrowserProvider, Signer } from 'ethers';

declare global {
  interface Window {
    ethereum?: any;
  }
}

export function useWallet() {
  const [provider, setProvider] = useState<BrowserProvider>();
  const [signer, setSigner] = useState<Signer>();
  const [address, setAddress] = useState<string>();

  const connect = async () => {
    if (!window.ethereum) {
      alert('MetaMask required');
      return;
    }
    const p = new BrowserProvider(window.ethereum);
    await p.send('eth_requestAccounts', []);
    const s = await p.getSigner();
    setProvider(p);
    setSigner(s);
    setAddress(await s.getAddress());
  };

  return { provider, signer, address, connect };
}
