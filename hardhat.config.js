require('@nomiclabs/hardhat-ethers');
require('@nomiclabs/hardhat-etherscan');
require('dotenv').config();

const { PRIVATE_KEY, RPC_URL, ETHERSCAN_API_KEY } = process.env;

const networks = {};
if (RPC_URL) {
  const accounts = [];
  if (PRIVATE_KEY && /^0x[0-9a-fA-F]{64}$/.test(PRIVATE_KEY)) {
    accounts.push(PRIVATE_KEY);
  }
  networks.anime = {
    url: RPC_URL,
    accounts,
  };
}

module.exports = {
  solidity: '0.8.20',
  networks,
  etherscan: {
    apiKey: ETHERSCAN_API_KEY || '',
  },
};
