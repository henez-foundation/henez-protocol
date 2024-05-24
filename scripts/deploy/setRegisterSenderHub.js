const {readTmpAddresses, contractAt, readTmpAddressesWithNetwork, sendTxn} = require("../shared/helpers")
async function main() {
    const {Hub} = readTmpAddressesWithNetwork("baseSepolia")
    const hubContract = await  contractAt("Hub", Hub)
    const {Spoke} = readTmpAddresses()
    const spokeContract = await  contractAt("Spoke", Spoke)
    const chainId = 10004
    const hubAddress = '0x000000000000000000000000' + hubContract.address.slice(2);
    console.log(hubAddress)
    await sendTxn(spokeContract.setRegisteredSender(chainId,hubAddress), "spokeContract.setRegisteredSender")
}
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
