const hre = require('hardhat');
require('dotenv').config();

async function main() {
  const AnimeMonopoly = await hre.ethers.getContractFactory('AnimeMonopoly');
  const tokenAddress = process.env.TOKEN_ADDRESS || hre.ethers.constants.AddressZero;
  const contract = await AnimeMonopoly.deploy(tokenAddress);
  await contract.deployed();
  console.log('AnimeMonopoly deployed to:', contract.address);
  if (hre.network.name !== 'hardhat') {
    console.log('waiting confirmations...');
    await contract.deployTransaction.wait(5);
    try {
      await hre.run('verify:verify', {
        address: contract.address,
        constructorArguments: [tokenAddress],
      });
    } catch (err) {
      console.log('verify failed:', err.message);
    }
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
