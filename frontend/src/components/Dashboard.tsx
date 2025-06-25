import { useEffect, useState } from 'react';
import { Contract } from 'ethers';

interface Props {
  contract: Contract;
  address: string;
}

export default function Dashboard({ contract, address }: Props) {
  const [tokenId, setTokenId] = useState<number>();
  const [position, setPosition] = useState<number>();
  const [score, setScore] = useState<string>();

  const joinGame = async () => {
    if (!contract.signer) return;
    const tx = await contract.joinGame();
    await tx.wait();
  };

  useEffect(() => {
    const load = async () => {
      try {
        const id = await contract.addressToTokenId(address);
        if (id > 0) {
          setTokenId(Number(id));
          const state = await contract.playerStates(id);
          setPosition(Number(state.position));
          setScore(state.score.toString());
        }
      } catch (err) {
        console.error(err);
      }
    };
    load();

    contract.on('PlayerMoved', (tid: bigint, _from: bigint, to: bigint) => {
      if (tokenId && Number(tid) === tokenId) setPosition(Number(to));
    });
    contract.on('ScoreUpdated', (tid: bigint, newScore: bigint) => {
      if (tokenId && Number(tid) === tokenId) setScore(newScore.toString());
    });

    return () => {
      contract.removeAllListeners('PlayerMoved');
      contract.removeAllListeners('ScoreUpdated');
    };
  }, [contract, address, tokenId]);

  return (
    <div className="space-y-2">
      {tokenId ? (
        <>
          <div>Token ID: {tokenId}</div>
          <div>Current Tile: {position}</div>
          <div>Score: {score}</div>
        </>
      ) : (
        <button className="px-4 py-2 bg-purple-600 text-white rounded" onClick={joinGame}>
          Join Game
        </button>
      )}
    </div>
  );
}
