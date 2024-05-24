const {ethers} = require("ethers");
const {readFileSync} = require("fs")
const maxUint256 = ethers.constants.MaxUint256

function newWallet() {
  return ethers.Wallet.createRandom()
}

function bigNumberify(n) {
  return ethers.BigNumber.from(n)
}

function expandDecimals(n, decimals) {
  return bigNumberify(n).mul(bigNumberify(10).pow(decimals))
}

async function send(provider, method, params = []) {
  await provider.send(method, params)
}

async function mineBlock(provider) {
  await send(provider, "evm_mine")
}

async function increaseTime(provider, seconds) {
  await send(provider, "evm_increaseTime", [seconds])
}

async function gasUsed(provider, tx) {
  return (await provider.getTransactionReceipt(tx.hash)).gasUsed
}

async function getNetworkFee(provider, tx) {
  const gas = await gasUsed(provider, tx)
  return gas.mul(tx.gasPrice)
}

async function reportGasUsed(provider, tx, label) {
  const { gasUsed } = await provider.getTransactionReceipt(tx.hash)
  console.info(label, gasUsed.toString())
  return gasUsed
}

async function getBlockTime(provider) {
  const blockNumber = await provider.getBlockNumber()
  const block = await provider.getBlock(blockNumber)
  return block.timestamp
}

async function getTxnBalances(provider, user, txn, callback) {
    const balance0 = await provider.getBalance(user.address)
    const tx = await txn()
    const fee = await getNetworkFee(provider, tx)
    const balance1 = await provider.getBalance(user.address)
    callback(balance0, balance1, fee)
}

function print(label, value, decimals) {
  if (decimals === 0) {
    console.log(label, value.toString())
    return
  }
  const valueStr = ethers.utils.formatUnits(value, decimals)
  console.log(label, valueStr)
}

const limitDecimals = (amount, maxDecimals) => {
  let amountStr = amount.toString();
  if (maxDecimals === undefined) {
    return amountStr;
  }
  if (maxDecimals === 0) {
    return amountStr.split(".")[0];
  }
  const dotIndex = amountStr.indexOf(".");
  if (dotIndex !== -1) {
    let decimals = amountStr.length - dotIndex - 1;
    if (decimals > maxDecimals) {
      amountStr = amountStr.substr(0, amountStr.length - (decimals - maxDecimals));
    }
  }
  return amountStr;
}

const padDecimals = (amount, minDecimals) => {
  let amountStr = amount.toString();
  const dotIndex = amountStr.indexOf(".");
  if (dotIndex !== -1) {
    const decimals = amountStr.length - dotIndex - 1;
    if (decimals < minDecimals) {
      amountStr = amountStr.padEnd(amountStr.length + (minDecimals - decimals), "0");
    }
  } else {
    amountStr = amountStr + ".0000";
  }
  return amountStr;
}

const parseValue = (value, tokenDecimals) => {
  const pValue = parseFloat(value);
  if (isNaN(pValue)) {
    return undefined;
  }
  value = limitDecimals(value, tokenDecimals);
  const amount = ethers.utils.parseUnits(value, tokenDecimals);
  return bigNumberify(amount);
}

function numberWithCommas(x) {
  if (!x) {
    return "...";
  }
  var parts = x.toString().split(".");
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return parts.join(".");
}

const formatAmount = (amount, tokenDecimals, displayDecimals, useCommas, defaultValue) => {
  if (!defaultValue) {
    defaultValue = "...";
  }
  if (amount === undefined || amount.toString().length === 0) {
    return defaultValue;
  }
  if (displayDecimals === undefined) {
    displayDecimals = 4;
  }
  let amountStr = ethers.utils.formatUnits(amount, tokenDecimals);
  amountStr = limitDecimals(amountStr, displayDecimals);
  if (displayDecimals !== 0) {
    amountStr = padDecimals(amountStr, displayDecimals);
  }
  if (useCommas) {
    return numberWithCommas(amountStr);
  }
  return amountStr;
};

const getUserKeys = () => {
  return JSON.parse(readFileSync('user-list.json', 'utf-8')).map((user)=> user.private_key);

}
const delay = ms => new Promise(res => setTimeout(res, ms));

function randomIntFromInterval(min, max) { // min and max included 
  return Math.floor(Math.random() * (max - min + 1) + min);
}
module.exports = {
  newWallet,
  maxUint256,
  bigNumberify,
  expandDecimals,
  mineBlock,
  increaseTime,
  gasUsed,
  getNetworkFee,
  reportGasUsed,
  getBlockTime,
  getTxnBalances,
  print,
  formatAmount,
  parseValue,
  getUserKeys,
  delay,
  randomIntFromInterval
}
