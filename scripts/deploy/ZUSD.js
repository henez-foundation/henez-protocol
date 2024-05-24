const { deployContract } = require("../shared/helpers");
async function main() {
  await deployContract("ZUSD", [], "USDC");
  await deployContract("ZUSD", []);
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
