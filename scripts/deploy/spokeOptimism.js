const {
  deployContractWithProxy,
  contractAt,
  readTmpAddressesWithNetwork,
  readTmpAddresses,
  sendTxn,
} = require("../shared/helpers");
async function main() {
  const chainId = 10005;
  const wormhole = "0x31377888146f3253211EFEf5c676D41ECe7D58Fe";
  const wormholeRelayer = "0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE";
  const hubChainId = 10004;
  const { ZUSD, USDC } = readTmpAddresses();
  const zusdContract = await contractAt("ZUSD", ZUSD);
  const usdcContract = await contractAt("ZUSD", USDC);
  const { Hub } = readTmpAddressesWithNetwork("baseSepolia");
  const hubContract = await contractAt("Hub", Hub);

  const spoke = await deployContractWithProxy("Spoke", [
    wormholeRelayer,
    wormhole,
    hubChainId,
    hubContract.address,
    zusdContract.address,
    usdcContract.address,
    chainId,
  ]);

  await sendTxn(zusdContract.setMintvault(spoke.address), "zusdContract.setMintvault");
  await sendTxn(usdcContract.setMintvault(spoke.address), "usdcContract.setMintvault");
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
