import { ethers } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
const func = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer, USDC, DAO } = await getNamedAccounts();

  const result = await deploy("Smaug", {
    from: deployer,
    skipIfAlreadyDeployed: true,
  });
  let usdcAddress = USDC;
  console.log("Smaug deployed at", result.address);
  if (hre.network.name == "hardhat") {
    // deploy mock usdc
    const mockUsdc = await deploy("MockERC20", {
      from: deployer,
      skipIfAlreadyDeployed: true,
      args: ["Mock USDC", "mUSDC", 1000000000000n],
    });
    console.log("Mock USDC deployed at", mockUsdc.address);
    usdcAddress = mockUsdc.address;
  }

  const result2 = await deploy("SmaugDistribution", {
    from: deployer,
    skipIfAlreadyDeployed: true,
    args: [result.address, ethers.encodeBytes32String("SmaugDistribution"), 1, USDC, DAO, DAO],
  });

  console.log("SmaugDistribution deployed at", result2.address);
};

export default func;
func.tags = ["SmaugDistribution"];
