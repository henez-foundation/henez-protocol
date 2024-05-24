const {
  deployContractWithProxy,
  contractAt,
  readTmpAddressesWithNetwork,
  readTmpAddresses,
  sendTxn,
} = require("../shared/helpers");
async function main() {
  const chainId = 10003;
  const wormhole = "0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35";
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
