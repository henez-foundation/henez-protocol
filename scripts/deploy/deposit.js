const {readTmpAddresses, contractAt, sendTxn} = require("../shared/helpers")
const {expandDecimals} = require("../shared/utilities");
async function main() {
    const {Spoke} = readTmpAddresses()
    const spokeContract = await  contractAt("Spoke", Spoke)
    const tokenAddress = "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"
    const tokenContract= await contractAt("MyERC20", tokenAddress)
    const amount = expandDecimals(1, 17)
    await sendTxn(tokenContract.approve(spokeContract.address,amount), "tokenContract.approve")
    await sendTxn(spokeContract.depositCollateral(tokenAddress, amount),"spokeContract.depositCollateral")
}
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
