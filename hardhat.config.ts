import { task, subtask } from "hardhat/config";
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-chai-matchers";
import "hardhat-dependency-compiler";
import "hardhat-abi-exporter";
import "hardhat-gas-reporter";
import "hardhat-deploy";
import fs from "fs";
import path from "path";
import { ethers, Fragment } from "ethers";

const getSuperInterface = (outputPath?: string) => {
  let mergedArray: Fragment[] = [];
  function readDirectory(directory: string) {
    const files = fs.readdirSync(directory);

    files.forEach((file) => {
      const fullPath = path.join(directory, file);
      if (fs.statSync(fullPath).isDirectory()) {
        readDirectory(fullPath); // Recurse into subdirectories
      } else if (path.extname(file) === ".json") {
        const fileContents = require("./" + fullPath); // Load the JSON file
        if (Array.isArray(fileContents)) {
          mergedArray = mergedArray.concat(fileContents); // Merge the array from the JSON file
        }
      }
    });
  }
  const originalConsoleLog = console.log;
  readDirectory("./abi");
  readDirectory("./node_modules/@peeramid-labs/eds/abi");
  console.log = () => {}; // avoid noisy output
  const result = new ethers.Interface(mergedArray);
  if (outputPath) {
    fs.writeFileSync(outputPath, JSON.stringify(result.format(true), null, 2));
  }
  console.log = originalConsoleLog;
  return result;
};

task("getSuperInterface", "Prints the super interface of a contract")
  .setAction(async (taskArgs: { outputPath: string }, hre) => {
    const originalConsoleLog = console.log;
    console.log = () => {};
    const su = getSuperInterface(taskArgs.outputPath + "/super-interface.json");
    let return_value: Record<string, string> = {};
    Object.values(su.fragments.filter((x) => x.type === "function")).forEach((x) => {
      return_value[x.format("sighash")] = x.format("minimal");
    });
    Object.values(su.fragments.filter((x) => x.type === "event")).forEach((x) => {
      return_value[x.format("sighash")] = x.format("minimal");
    });
    Object.values(su.fragments.filter((x) => x.type === "error")).forEach((x) => {
      return_value[x.format("sighash")] = x.format("minimal");
    });
    fs.writeFileSync(taskArgs.outputPath + "/signatures.json", JSON.stringify(return_value, null, 2));
    console.log = originalConsoleLog;
  })
  .addParam("outputPath", "The path to the abi file");

const config: HardhatUserConfig = {
  gasReporter: {
    currency: "USD",
    enabled: false,
    L1Etherscan: process.env.ETH_MAINNET_ETHERSCAN_API_KEY,
    coinmarketcap: process.env.COINMARKETCAP_KEY,
  },
  namedAccounts: {
    deployer: {
      default: "0xF52E5dF676f51E410c456CC34360cA6F27959420",
      mainnet: "0xADdd5405fa53cC5D57569D225449C88D646f5129",
      sepolia: "0x6A8bC26c8f67c7e9939fA4e164f6F4A4c34fFE54",
    },
    owner: {
      default: "0x520E00225C4a43B6c55474Db44a4a44199b4c3eE",
      anvil: "0x507c2d32185667156de5B4C440FEEf3800078bDb",
      sepolia: "0x6Cf8d74C7875de8C2FfB09228F4bf2A21b25e583",
      mainnet: "0x6A8bC26c8f67c7e9939fA4e164f6F4A4c34fFE54",
    },
    USDC: {
      mainnet: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
    },
    sanctionsList: {
      default: "0x40C57923924B5c5c5455c48D93317139ADDaC8fb",
      sepolia: "0x0000000000000000000000000000000000000000",
    },
    DAO: {
      default: "0xF52E5dF676f51E410c456CC34360cA6F27959420",
      mainnet: "0x0b00b3227a5f3df3484f03990a87e02ebad2f888", //Safe DAO treasury
      sepolia: "0x6A8bC26c8f67c7e9939fA4e164f6F4A4c34fFE54",
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
  abiExporter: {
    path: "./abi",
    runOnCompile: true,
    clear: true,
    format: "json",
    // flat: true,
    // only: [":ERC20$"],
    spacing: 2,
    pretty: false,
  },
};

export default config;
