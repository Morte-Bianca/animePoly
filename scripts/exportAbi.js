const fs = require('fs');
const hre = require('hardhat');

async function main() {
  await hre.run('compile');
  const artifact = await hre.artifacts.readArtifact('AnimeMonopoly');
  fs.writeFileSync('abi.json', JSON.stringify(artifact.abi, null, 2));
  console.log('ABI written to abi.json');
}

main().catch(err => { console.error(err); process.exit(1); });
