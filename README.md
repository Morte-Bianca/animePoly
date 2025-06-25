# animePoly

AnimeMonopoly on AnimeChain. This repo contains a Hardhat project with the `AnimeMonopoly` smart contract and a minimal browser front-end.

## Setup

```bash
npm install
```

Compile contracts and export ABI:

```bash
npx hardhat run scripts/exportAbi.js
```

Deploy contract:

```bash
PRIVATE_KEY=... RPC_URL=... npx hardhat run scripts/deploy.js --network anime
```

The `frontend/` folder hosts a simple page (`index.html`) that connects with MetaMask using Ethers.js and lets a user join the game.
