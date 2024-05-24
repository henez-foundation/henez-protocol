const {
  deployContractWithProxy,
  contractAt,
  readTmpAddressesWithNetwork,
  readTmpAddresses,
  sendTxn,
} = require("../shared/helpers");
async function main() {
  const chainId = 10002;
  const wormhole = "0x4a8bc80Ed5a4067f1CCf107057b8270E0cC11A78";
  const wormholeRelayer = "0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470";
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
