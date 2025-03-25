import { time, loadFixture, mine } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre, { deployments, ethers, network } from "hardhat";
import { MockERC20, Smaug, SmaugDistribution } from "../typechain-types";
import { parseEther } from "ethers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("SmaugDistribution", function () {
  let owner: SignerWithAddress;
  let distributionContract: SmaugDistribution;
  let mockUSDC: MockERC20;
  let mockSmaug: Smaug;
  let mockSanctionsList: any;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;

  beforeEach(async function () {
    // Get signers
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy mock USDC with initial supply
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    mockUSDC = await MockERC20.deploy("USD Coin", "USDC", parseEther("1000")); // Deploy with 1000 USDC initial supply
    await mockUSDC.waitForDeployment();

    // Deploy mock Smaug
    const Smaug = await ethers.getContractFactory("Smaug");
    mockSmaug = await Smaug.deploy();
    await mockSmaug.waitForDeployment();

    // Deploy mock SanctionsList
    const MockSanctionsList = await ethers.getContractFactory("MockSanctionsList");
    mockSanctionsList = await MockSanctionsList.deploy();
    await mockSanctionsList.waitForDeployment();

    // Deploy SmaugDistribution
    const SmaugDistribution = await ethers.getContractFactory("SmaugDistribution");
    distributionContract = await SmaugDistribution.deploy(
      await mockSmaug.getAddress(),
      ethers.keccak256(ethers.toUtf8Bytes("Smaug")), // Convert string to bytes32
      1,
      await mockUSDC.getAddress(),
      owner.address,
      user1.address, // beneficiary
      await mockSanctionsList.getAddress()
    );
    await distributionContract.waitForDeployment();

    // Transfer USDC to user2 for testing
    await mockUSDC.transfer(user2.address, parseEther("1000")); // Transfer 1000 USDC to user2
  });

  describe("Instantiation", function () {
    it("should instantiate Smaug with correct parameters", async function () {
      const assets = [await mockUSDC.getAddress()];
      const policies = [
        {
          inDay: 100000, // 100 USDC
          inBlock: 50000, // 50 USDC
          inTX: 10000, // 10 USDC
          inTotal: 1000000, // 1000 USDC
        },
      ];

      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["(address,uint256,address,address[],(uint256,uint256,uint256,uint256)[])"],
        [
          [
            user2.address, // admin
            86400, // ttl (1 day)
            user2.address, // safe
            assets,
            policies.map((p) => [p.inDay, p.inBlock, p.inTX, p.inTotal]),
          ],
        ]
      );

      await distributionContract.instantiate(data);

      // Verify the instantiated Smaug contract
      const tx = await distributionContract.instantiate(data);
      const receipt = await tx.wait();
      if (!receipt) {
        throw new Error("Transaction failed");
      }
      // now parse logs
      const filter = distributionContract.filters.SmaugInstantiated();
      const smaugInstantiatedEvt = await distributionContract.queryFilter(filter);
      const smaugAddress = smaugInstantiatedEvt[0].args.smaug;
      const smaug = await ethers.getContractAt("Smaug", smaugAddress);
      expect(await smaug.getTTL()).to.equal(86400);
      const policy = await smaug.getAssetPolicy(await mockUSDC.getAddress());
      expect(policy.inDay).to.equal(100000);
      expect(policy.inBlock).to.equal(50000);
      expect(policy.inTX).to.equal(10000);
      expect(policy.inTotal).to.equal(1000000);
    });

    it("should require gratitude payment from non-owner", async function () {
      const assets = [await mockUSDC.getAddress()];
      const policies = [
        {
          inDay: 100000, // 100 USDC
          inBlock: 50000, // 50 USDC
          inTX: 10000, // 10 USDC
          inTotal: 1000000, // 1000 USDC
        },
      ];

      const data = ethers.AbiCoder.defaultAbiCoder().encode(["(address,uint256,address,address[],(uint256,uint256,uint256,uint256)[])"], [[user2.address, 86400, user2.address, assets, policies.map((p) => [p.inDay, p.inBlock, p.inTX, p.inTotal])]]);

      //   await mockUSDC.connect(owner).transfer(user2.address, parseEther("100"));
      // Approve USDC spending
      await mockUSDC.connect(user2).approve(await distributionContract.getAddress(), parseEther("0"));

      // Should fail without gratitude payment
      await expect(distributionContract.connect(user2).instantiate(data)).to.be.reverted;

      await mockUSDC.connect(user2).approve(await distributionContract.getAddress(), parseEther("1000"));
      const u1balance = await mockUSDC.balanceOf(user1.address);
      // Should succeed with gratitude payment
      await expect(distributionContract.connect(user2).instantiate(data)).to.not.be.reverted;
      const u1balance2 = await mockUSDC.balanceOf(user1.address);
      expect(u1balance2).to.equal(u1balance + 200000000n);
    });
  });

  describe("Admin Functions", function () {
    it("should allow owner to set gratitude amount", async function () {
      const newGratitude = 300000; // 300 USDC
      await distributionContract.setGratitude(newGratitude);
      expect(await distributionContract.gratitude()).to.equal(newGratitude);
    });

    it("should allow owner to set beneficiary", async function () {
      await distributionContract.setBeneficiary(user2.address);
      // Note: We can't directly check the private _dao variable
      // but we can verify it through the instantiate function behavior
    });

    it("should not allow non-owner to set gratitude", async function () {
      await expect(distributionContract.connect(user2).setGratitude(300000)).to.be.revertedWithCustomError(distributionContract, "OwnableUnauthorizedAccount");
    });

    it("should not allow non-owner to set beneficiary", async function () {
      await expect(distributionContract.connect(user2).setBeneficiary(user2.address)).to.be.revertedWithCustomError(distributionContract, "OwnableUnauthorizedAccount");
    });
  });

  describe("Sanctions Check", function () {
    it("should prevent instantiation by sanctioned address", async function () {
      const assets = [await mockUSDC.getAddress()];
      const policies = [
        {
          inDay: 100000, // 100 USDC
          inBlock: 50000, // 50 USDC
          inTX: 10000, // 10 USDC
          inTotal: 1000000, // 1000 USDC
        },
      ];

      const data = ethers.AbiCoder.defaultAbiCoder().encode(["(address,uint256,address,address[],(uint256,uint256,uint256,uint256)[])"], [[user2.address, 86400, user2.address, assets, policies.map((p) => [p.inDay, p.inBlock, p.inTX, p.inTotal])]]);

      // Set user2 as sanctioned
      await mockSanctionsList.setSanctioned(user1.address, true);
      await mockUSDC.connect(user1).approve(await distributionContract.getAddress(), parseEther("1000"));
      await expect(distributionContract.connect(user1).instantiate(data)).to.be.revertedWith("Sender is sanctioned");
    });
  });
});
