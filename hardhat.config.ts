import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-chai-matchers";
import "hardhat-dependency-compiler";
import "hardhat-abi-exporter";
import "hardhat-deploy";
const config: HardhatUserConfig = {
  solidity: "0.8.28",
  namedAccounts: {
    deployer: {
      hardhat: "0xF52E5dF676f51E410c456CC34360cA6F27959420",
      anvil: "0x6Cf8d74C7875de8C2FfB09228F4bf2A21b25e583",
      arbsepolia: "0x6Cf8d74C7875de8C2FfB09228F4bf2A21b25e583",
      default: "0xF52E5dF676f51E410c456CC34360cA6F27959420", //TODO this must be set for networks
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
    DAO: {
      default: "0x520E00225C4a43B6c55474Db44a4a44199b4c3eE",
      arbsepolia: "0xf5ea7A32aBcaFE1c7Ef79396402180B549bA4aa4",
    },
    player1: {
      default: "0xFE87428cC8C72A3a79eD1cC7e2B5892c088d0af0",
    },
  },
  defaultNetwork: "hardhat",
  networks: {
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
};

export default config;
