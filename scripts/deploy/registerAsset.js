const {readTmpAddresses, contractAt, readTmpAddressesWithNetwork, sendTxn} = require("../shared/helpers")
async function main() {
    const {Hub} = readTmpAddresses()
    const hubContract = await  contractAt("Hub", Hub)

    // TODO: make it a list of asset configs
    const assetAddress = "0x4200000000000000000000000000000000000006" // WETH
    const kinks = [0, 1000000]
    const rates = [0, 0]
    const collateralizationRatioDeposit = 1000000
    const collateralizationRatioBorrow = 1100000
    const ratePrecision = 1000000
    const reserveFactor = 0
    const reservePrecision = 1000000

    const pythId = "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace"

    await sendTxn(hubContract.registerAsset(
        assetAddress,
        collateralizationRatioDeposit,
        collateralizationRatioBorrow,
        ratePrecision,
        kinks,
        rates,
        reserveFactor,
        reservePrecision,
        pythId
    ),"hubContract.registerAsset")
}
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
