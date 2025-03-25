import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-chai-matchers";
import "hardhat-dependency-compiler";
import "hardhat-abi-exporter";
import "hardhat-gas-reporter";
import "hardhat-deploy";
const config: HardhatUserConfig = {
  gasReporter: {
    currency: "USD",
    enabled: true,
    L1Etherscan: process.env.ETH_MAINNET_ETHERSCAN_API_KEY,
    coinmarketcap: process.env.COINMARKETCAP_KEY,
  },
  namedAccounts: {
    deployer: {
      default: "0xF52E5dF676f51E410c456CC34360cA6F27959420",
      mainnet: "0xADdd5405fa53cC5D57569D225449C88D646f5129",
    },
    owner: {
      default: "0x520E00225C4a43B6c55474Db44a4a44199b4c3eE",
      anvil: "0x507c2d32185667156de5B4C440FEEf3800078bDb",
      arbsepolia: "0x6Cf8d74C7875de8C2FfB09228F4bf2A21b25e583",
    },
    gameMaster: {
      localhost: "0xaA63aA2D921F23f204B6Bcb43c2844Fb83c82eb9",
    },
    defaultPlayer: {
      localhost: "0xF52E5dF676f51E410c456CC34360cA6F27959420",
    },
    USDC: {
      mainnet: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
    },
    sanctionsList: {
      default: "0x40C57923924B5c5c5455c48D93317139ADDaC8fb",
    },
    DAO: {
      default: "0x520E00225C4a43B6c55474Db44a4a44199b4c3eE",
      mainnet: "0x6A8bC26c8f67c7e9939fA4e164f6F4A4c34fFE54",
    },
    player1: {
      default: "0xFE87428cC8C72A3a79eD1cC7e2B5892c088d0af0",
    },
  },
  defaultNetwork: "hardhat",
  networks: {
    mainnet: {
      url: process.env.ETH_MAINNET_RPC_URL ?? "",
      tags: ["ERC7744"],
      accounts: [process.env.ETH_MAINNET_PRIVATE_KEY ?? "0x0000000000000000000000000000000000000000000000000000000000000000"],
      verify: {
        etherscan: {
          apiKey: process.env.ETH_MAINNET_ETHERSCAN_API_KEY ?? "",
          //   apiUrl: "https://api.etherscan.io/",
        },
      },
    },
    hardhat: {
      mining: {
        mempool: {
          order: "fifo",
        },
      },
      accounts: {
        mnemonic: "casual vacant letter raw trend tool vacant opera buzz jaguar bridge myself",
      }, // ONLY LOCAL
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 2000,
          },
        },
      },
    ],
  },
  external: {
    contracts: [
      {
        artifacts: "node_modules/@peeramid-labs/eds/artifacts",
        deploy: "node_modules/@peeramid-labs/eds/deploy",
      },
    ],
  },
};

export default config;
