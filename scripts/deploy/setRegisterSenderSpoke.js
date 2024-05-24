const { readTmpAddresses, contractAt, readTmpAddressesWithNetwork, sendTxn } = require("../shared/helpers");
async function main() {
  const { Hub } = readTmpAddresses();
  const hubContract = await contractAt("Hub", Hub);
  const networks = ["sepolia", "arbitrumSepolia", "opSepolia"];
  const chainIds = [10002, 10003, 10005];
  for (let i = 0; i < networks.length; i++) {
    const { Spoke } = readTmpAddressesWithNetwork(networks[i]);
    const spokeContract = await contractAt("Spoke", Spoke);
    const chainId = chainIds[i];
    const spokeAddress = "0x000000000000000000000000" + spokeContract.address.slice(2);
    await sendTxn(hubContract.setRegisteredSender(chainId, spokeAddress), "hubContract.setRegisteredSender");
    await sendTxn(hubContract.registerSpoke(chainId, spokeContract.address), "hubContract.registerSpoke");
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
