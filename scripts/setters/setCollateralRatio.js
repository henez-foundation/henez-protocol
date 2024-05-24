const { expandDecimals, getUserKeys, delay, randomIntFromInterval } = require("../shared/utilities");
const {
  deployContractWithProxy,
  contractAt,
  readTmpAddressesWithNetwork,
  readTmpAddresses,
  sendTxn,
  SPOKE_NAME_LIST,
  FORKED_NETWORK_TO_TESTNET,
} = require("../shared/helpers");
const { ethers, network } = require("hardhat");
const { parseEther } = require("ethers/lib/utils");
const { Wallet, BigNumber } = require("ethers");
async function main() {
  //@note setCollateralRatio on Hub
  // `yarn hardhat run scripts/setters/setCollateralRatio.js --network baseSepolia`

    // catch the arg --network
    let networkName = network.name;

    // get admin key
    const signers = await ethers.getSigners();
    const signer = signers[0];

    const { Hub, ZUSD, USDC } = readTmpAddressesWithNetwork(networkName);
    if(!Hub || !ZUSD || !USDC){
        throw new Error(`Failed to find contract on ${networkName} chain`)
    }
    const hubContract = await contractAt("Hub", Hub);
    // const zusdContract = await contractAt("ZUSD", ZUSD);
    // const usdcContract = await contractAt("ZUSD", USDC);
    const tx = await hubContract.connect(signer).setSafeCollateralRatio(parseEther('125')); // 125%
    console.info(`Deployer ${signer.address} hubContract.setSafeCollateralRatio ${tx.hash}`)
    await tx.wait()
    console.info(`Tx completed`)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
