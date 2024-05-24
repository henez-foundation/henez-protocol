require("@nomiclabs/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-contract-sizer");
require("@nomicfoundation/hardhat-foundry");
require("dotenv").config();

module.exports = {
  networks: {
    localhost: {
      timeout: 120000,
    },
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    baseSepolia: {
      url: "https://sepolia.base.org",
      chainId: 84532,
      accounts: [process.env.BASE_TESTNET_DEPLOYER_KEY],
    },
    sepolia: {
      url: "https://rpc.sepolia.org",
      chainId: 11155111,
      accounts: [process.env.ETH_SEPOLIA_DEPLOYER_KEY],
    },
    arbitrumSepolia: {
      url: "https://sepolia-rollup.arbitrum.io/rpc",
      chainId: 421614,
      accounts: [process.env.ARB_SEPOLIA_DEPLOYER_KEY],
    },
    opSepolia: {
      url: "https://sepolia.optimism.io",
      chainId: 11155420,
      accounts: [process.env.OP_SEPOLIA_DEPLOYER_KEY],
    },
    // `anvil --fork-url https://sepolia.base.org --port 8545` for more stable forked network
    forked_base_sepolia: {
      url: "http://127.0.0.1:8545",
      chainId: 84532,
      accounts: [process.env.BASE_TESTNET_DEPLOYER_KEY],
    },
    // `anvil --fork-url https://1rpc.io/sepolia  --port 8546` for more stable forked network
    forked_sepolia: {
      url: "http://127.0.0.1:8546",
      chainId: 11155111,
      accounts: [process.env.ETH_SEPOLIA_DEPLOYER_KEY],
    },
    // `anvil --fork-url https://sepolia-rollup.arbitrum.io/rpc  --port 8547` for more stable forked network
    forked_arbitrum_sepolia: {
      url: "http://127.0.0.1:8547",
      chainId: 421614,
      accounts: [process.env.ARB_SEPOLIA_DEPLOYER_KEY],
    },
    // `anvil --fork-url https://sepolia.optimism.io  --port 8548` for more stable forked network
    forked_op_sepolia: {
      url: "http://127.0.0.1:8548",
      chainId: 11155420,
      accounts: [process.env.OP_SEPOLIA_DEPLOYER_KEY],
    },
  },
  etherscan: {
    apiKey: {
      sepolia: process.env.ETH_API_KEY,
      baseSepolia: process.env.BASE_API_KEY,
      opSepolia: process.env.OP_API_KEY,
      arbitrumSepolia: process.env.ARB_API_KEY,
    },
    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org/",
        },
      },
      {
        network: "opSepolia",
        chainId: 11155420,
        urls: {
          apiURL: "https://api-sepolia-optimistic.etherscan.io/api",
          browserURL: "https://sepolia-optimistic.etherscan.io",
        },
      },
      {
        network: "arbitrumSepolia",
        chainId: 421614,
        urls: {
          apiURL: "https://api-sepolia.arbiscan.io/api",
          browserURL: "https://sepolia.arbiscan.io",
        },
      },
    ],
  },
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 10,
      },
    },
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
  paths: {
    dependencies: "./lib",
  },
};
