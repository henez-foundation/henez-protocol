const { deployContractWithProxy, readTmpAddresses, contractAt, sendTxn, deployContract } = require("../../shared/helpers");
//    npx hardhat run --network arbitrumSepolia scripts/deploy/disperse/disperse.js

async function main() {
  const disperse = await deployContract("Disperse",[]);
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
