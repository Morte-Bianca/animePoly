import abi from '../abi.json' assert { type: 'json' };
const { useState, useEffect } = React;

function App() {
  const [contract, setContract] = useState();
  const [address, setAddress] = useState();

  const connect = async () => {
    if (!window.ethereum) return alert('MetaMask required');
    await window.ethereum.request({ method: 'eth_requestAccounts' });
    const provider = new ethers.BrowserProvider(window.ethereum);
    const signer = await provider.getSigner();
    const contractAddr = localStorage.getItem('contractAddress') || '';
    if (contractAddr) setContract(new ethers.Contract(contractAddr, abi, signer));
    setAddress(await signer.getAddress());
  };

  const joinGame = async () => {
    if (!contract) return alert('contract not set');
    const tx = await contract.joinGame();
    await tx.wait();
    alert('Joined game');
  };

  return React.createElement('div', {}, [
    React.createElement('button', { onClick: connect }, address ? 'Connected' : 'Connect Wallet'),
    React.createElement('button', { onClick: joinGame }, 'Join Game')
  ]);
}

ReactDOM.createRoot(document.getElementById('root')).render(React.createElement(App));
