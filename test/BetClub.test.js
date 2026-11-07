const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("BetClub", function () {
  let factory, club, usdc;
  let owner, alice, bob, judge, carol;
  const STAKE = ethers.parseUnits("10", 6);
  const ONE_DAY = 24 * 60 * 60;

  beforeEach(async function () {
    [owner, alice, bob, judge, carol] = await ethers.getSigners();
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    usdc = await MockERC20.deploy("USD Coin", "USDC", 6);
    for (const addr of [alice, bob, judge])
      await usdc.mint(addr.address, ethers.parseUnits("1000", 6));
    const Factory = await ethers.getContractFactory("BetClubFactory");
    factory = await Factory.deploy(await usdc.getAddress());
    const tx = await factory.connect(alice).createClub("Test Club");
    const receipt = await tx.wait();
    const event = receipt.logs.find(l => l.fragment?.name === "ClubCreated");
    club = await ethers.getContractAt("BetClub", event.args[0]);
    await club.connect(alice).addMember(bob.address);
    await club.connect(alice).addMember(judge.address);
    for (const addr of [alice, bob, judge])
      await usdc.connect(addr).approve(await club.getAddress(), ethers.MaxUint256);
  });

  it("creates a club with correct name", async function () {
    expect(await club.name()).to.equal("Test Club");
    expect(await club.creator()).to.equal(alice.address);
  });

  it("allows creator to add members", async function () {
    expect(await club.isMember(bob.address)).to.be.true;
    expect(await club.isMember(carol.address)).to.be.false;
  });

  it("allows a member to propose a bet", async function () {
    const resTime = (await time.latest()) + ONE_DAY + 3600;
    await expect(club.connect(alice).proposeBet("Will it rain?", judge.address, STAKE, resTime, 1))
      .to.emit(club, "BetProposed");
    expect(await club.betCount()).to.equal(1);
  });

  it("allows another member to join a bet", async function () {
    const resTime = (await time.latest()) + ONE_DAY + 3600;
    await club.connect(alice).proposeBet("Will it rain?", judge.address, STAKE, resTime, 1);
    await expect(club.connect(bob).joinBet(0, 2)).to.emit(club, "BetJoined");
  });

  it("judge can resolve and winner can claim", async function () {
    const resTime = (await time.latest()) + ONE_DAY + 3600;
    await club.connect(alice).proposeBet("Will it rain?", judge.address, STAKE, resTime, 1);
    await club.connect(bob).joinBet(0, 2);
    await time.increaseTo(resTime);
    await club.connect(judge).resolveBet(0, true);
    await time.increase(49 * 3600);
    const before = await usdc.balanceOf(alice.address);
    await club.connect(alice).claimWinnings(0);
    expect(await usdc.balanceOf(alice.address)).to.be.gt(before);
  });

  it("prevents double claiming", async function () {
    const resTime = (await time.latest()) + ONE_DAY + 3600;
    await club.connect(alice).proposeBet("Test", judge.address, STAKE, resTime, 1);
    await club.connect(bob).joinBet(0, 2);
    await time.increaseTo(resTime);
    await club.connect(judge).resolveBet(0, true);
    await time.increase(49 * 3600);
    await club.connect(alice).claimWinnings(0);
    await expect(club.connect(alice).claimWinnings(0)).to.be.revertedWith("Already claimed");
  });

  it("loser cannot claim winnings", async function () {
    const resTime = (await time.latest()) + ONE_DAY + 3600;
    await club.connect(alice).proposeBet("Test", judge.address, STAKE, resTime, 1);
    await club.connect(bob).joinBet(0, 2);
    await time.increaseTo(resTime);
    await club.connect(judge).resolveBet(0, true);
    await time.increase(49 * 3600);
    await expect(club.connect(bob).claimWinnings(0)).to.be.revertedWith("Did not win");
  });

  it("non-member cannot propose", async function () {
    const resTime = (await time.latest()) + ONE_DAY + 3600;
    await expect(club.connect(carol).proposeBet("Test", judge.address, STAKE, resTime, 1))
      .to.be.revertedWith("Not a member");
  });

  it("cancelled bet allows refund", async function () {
    const resTime = (await time.latest()) + ONE_DAY + 3600;
    await club.connect(alice).proposeBet("Test", judge.address, STAKE, resTime, 1);
    await club.connect(bob).joinBet(0, 2);
    await club.connect(alice).cancelBet(0);
    const before = await usdc.balanceOf(bob.address);
    await club.connect(bob).claimRefund(0);
    expect(await usdc.balanceOf(bob.address) - before).to.equal(STAKE);
  });
});
