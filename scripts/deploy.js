const hre = require("hardhat");
async function main() {
  const USDC = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";
  console.log("Deploying BetClubFactory to Base Sepolia...");
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deployer:", deployer.address);
  const Factory = await hre.ethers.getContractFactory("BetClubFactory");
  const factory = await Factory.deploy(USDC);
  await factory.waitForDeployment();
  const address = await factory.getAddress();
  console.log("\n✅ BetClubFactory deployed to:", address);
  console.log("🔗 BaseScan:", `https://sepolia.basescan.org/address/${address}`);
  console.log("\nVerify with:");
  console.log(`npx hardhat verify --network base-sepolia ${address} "${USDC}"`);
}
main().catch((e) => { console.error(e); process.exit(1); });
