const fs = require("fs");
const path = require("path");
const parse = require("csv-parse");
const { ethers, upgrades } = require("hardhat");

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

const readCsv = async (file) => {
  records = [];
  const parser = fs.createReadStream(file).pipe(parse({ columns: true, delimiter: "," }));
  parser.on("error", function (err) {
    console.error(err.message);
  });
  for await (const record of parser) {
    records.push(record);
  }
  return records;
};

async function sendTxn(txnPromise, label) {
  const txn = await txnPromise;
  console.info(`Sending ${label}...`);
  await txn.wait(2);
  console.info(`... Sent! ${txn.hash}`);
  return txn;
}

async function callWithRetries(func, args, retriesCount = 3) {
  let i = 0;
  while (true) {
    i++;
    try {
      return await func(...args);
    } catch (ex) {
      if (i === retriesCount) {
        console.error("call failed %s times. throwing error", retriesCount);
        throw ex;
      }
      console.error("call i=%s failed. retrying....", i);
      console.error(ex.message);
    }
  }
}

async function deployContract(name, args, label, options, lib) {
  const contracts = readTmpAddresses();
  if (contracts[name]) {
    console.log(`Contract ${name} already exist.`);
    return;
  }

  let info = name;
  if (label) {
    info = name + ":" + label;
  }

  const contractFactory = !lib ? await ethers.getContractFactory(name) : await ethers.getContractFactory(name, lib);

  let contract;
  if (options) {
    contract = await contractFactory.deploy(...args, options);
  } else {
    contract = await contractFactory.deploy(...args);
  }
  const argStr = args.map((i) => `"${i}"`).join(" ");
  const address = await contract.address;
  console.info(`Deploying ${info} ${address} ${argStr}`);
  await contract.deployed();

  console.info(`Verifying ${address}`);
  await verify(address, args);

  const addresses = [];
  if (label) {
    addresses[label] = contract.address;
  } else {
    addresses[name] = contract.address;
  }
  writeTmpAddresses(addresses);

  console.info("... Completed!");
  return contract;
}

async function deployContractWithProxy(name, args, label, lib) {
  const contracts = readTmpAddresses();
  let info = name;
  if (label) {
    info = name + ":" + label;
  }

  const contractFactory = !lib ? await ethers.getContractFactory(name) : await ethers.getContractFactory(name, lib);

  let contract;
  if (contracts[name]) {
    contract = await upgrades.upgradeProxy(contracts[name], contractFactory);
  } else {
    contract = await upgrades.deployProxy(contractFactory, args);
  }

  const argStr = args.map((i) => `"${i}"`).join(" ");
  const address = await contract.address;
  console.info(`Deploy proxy ${info} ${address} ${argStr}`);
  await contract.deployed();

  // console.info(`Verifying ${address}`);
  // if (protocol[name]) {
  //   await verify(address)
  // }else{
  //   await verify(address)
  // }
  await verify(address);

  if (!contracts[name]) {
    const addresses = [];
    if (label) {
      addresses[label] = contract.address;
    } else {
      addresses[name] = contract.address;
    }
    writeTmpAddresses(addresses);
  }

  console.info("... Completed!");
  return contract;
}

async function verify(address, args) {
  await hre
    .run("verify:verify", {
      address: address,
      constructorArguments: args,
    })
    .catch((error) => {
      console.log(error);
    });
}

async function contractAt(name, address, provider, options) {
  let contractFactory = await ethers.getContractFactory(name, options);
  if (provider) {
    contractFactory = contractFactory.connect(provider);
  }
  return contractFactory.attach(address);
}

const tmpAddressesFilepath = path.join(__dirname, "..", "..", `deployments/${process.env.HARDHAT_NETWORK}.json`);

function readTmpAddresses() {
  if (fs.existsSync(tmpAddressesFilepath)) {
    return JSON.parse(fs.readFileSync(tmpAddressesFilepath));
  }
  return {};
}

function readTmpAddressesWithNetwork(network) {
  const filePath = path.join(__dirname, "..", "..", `deployments/${network}.json`);
  if (fs.existsSync(filePath)) {
    return JSON.parse(fs.readFileSync(filePath));
  }
  return {};
}

function writeTmpAddresses(json) {
  const tmpAddresses = Object.assign(readTmpAddresses(), json);
  fs.writeFileSync(tmpAddressesFilepath, JSON.stringify(tmpAddresses));
}

// batchLists is an array of lists
async function processBatch(batchLists, batchSize, handler) {
  let currentBatch = [];
  const referenceList = batchLists[0];

  for (let i = 0; i < referenceList.length; i++) {
    const item = [];

    for (let j = 0; j < batchLists.length; j++) {
      const list = batchLists[j];
      item.push(list[i]);
    }

    currentBatch.push(item);

    if (currentBatch.length === batchSize) {
      console.log("handling currentBatch", i, currentBatch.length, referenceList.length);
      await handler(currentBatch);
      currentBatch = [];
    }
  }

  if (currentBatch.length > 0) {
    console.log("handling final batch", currentBatch.length, referenceList.length);
    await handler(currentBatch);
  }
}

const FORKED_NETWORK_TO_TESTNET = {
  forked_base_sepolia: "baseSepolia",
  forked_op_sepolia: "opSepolia",
  forked_arbitrum_sepolia: "arbitrumSepolia",
  forked_sepolia: "sepolia",
};
const SPOKE_NAME_LIST = ["opSepolia", "arbitrumSepolia", "sepolia"];
module.exports = {
  readCsv,
  sendTxn,
  deployContract,
  deployContractWithProxy,
  verify,
  contractAt,
  writeTmpAddresses,
  readTmpAddresses,
  readTmpAddressesWithNetwork,
  callWithRetries,
  processBatch,
  sleep,
  FORKED_NETWORK_TO_TESTNET,
  SPOKE_NAME_LIST,
};
