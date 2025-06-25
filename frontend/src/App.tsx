import { useWallet } from './hooks/useWallet';
import { useAnimeMonopolyContract } from './hooks/useAnimeMonopolyContract';
import Dashboard from './components/Dashboard';
import DiceControls from './components/DiceControls';
import Board from './components/Board';

function App() {
  const wallet = useWallet();
  const contract = useAnimeMonopolyContract(wallet.signer);

  return (
    <div className="p-4 space-y-4">
      <button
        className="px-4 py-2 bg-blue-600 text-white rounded"
        onClick={wallet.connect}
      >
        {wallet.address ? 'Wallet Connected' : 'Connect Wallet'}
      </button>

      {wallet.address && contract && (
        <>
          <Dashboard contract={contract} address={wallet.address} />
          <DiceControls contract={contract} />
          <Board />
        </>
      )}
    </div>
  );
}

export default App;
