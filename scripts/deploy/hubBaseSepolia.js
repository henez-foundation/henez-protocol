const { deployContractWithProxy, readTmpAddresses, contractAt, sendTxn } = require("../shared/helpers");
async function main() {
  const { ZUSD, USDC } = readTmpAddresses();
  const chainId = 10004;
  const zusdContract = await contractAt("ZUSD", ZUSD);
  const usdcContract = await contractAt("ZUSD", USDC);
  const wormhole = "0x79A1027a6A159502049F10906D333EC57E95F083";
  const wormholeRelayer = "0x93bad53ddfb6132b0ac8e37f6029163e63372cee";
  const baseSepoliaPythContractAddress = "0xA2aa501b19aff244D90cc15a4Cf739D2725B5729";
  const oracleMode = 0;
  const ethUSDPriceFeedPythId = "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace";
  const hub = await deployContractWithProxy("Hub", [
    zusdContract.address,
    usdcContract.address,
    wormholeRelayer,
    wormhole,
    chainId,
    baseSepoliaPythContractAddress,
    oracleMode,
    ethUSDPriceFeedPythId,
  ]);

  await sendTxn(zusdContract.setMintvault(hub.address), "zusdContract.setMintvault");
  await sendTxn(usdcContract.setMintvault(hub.address), "usdcContract.setMintvault");
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
