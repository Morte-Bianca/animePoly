import { useState } from 'react';
import { Contract, ethers } from 'ethers';

interface Props {
  contract: Contract;
}

export default function DiceControls({ contract }: Props) {
  const [rolling, setRolling] = useState(false);

  const rollDice = async () => {
    if (!contract.signer) return;
    setRolling(true);
    try {
      const nonce = ethers.toBigInt(ethers.randomBytes(32));
      const address = await contract.signer.getAddress();
      const commitment = ethers.keccak256(
        ethers.solidityPacked(['address', 'uint256'], [address, nonce])
      );
      const tx = await contract.commitDice(commitment);
      await tx.wait();
      const revealTx = await contract.revealDice(nonce);
      await revealTx.wait();
    } catch (err) {
      console.error(err);
    } finally {
      setRolling(false);
    }
  };

  return (
    <button
      className="px-4 py-2 bg-green-500 text-white rounded disabled:opacity-50"
      onClick={rollDice}
      disabled={rolling}
    >
      {rolling ? 'Rolling...' : 'Roll Dice'}
    </button>
  );
}
