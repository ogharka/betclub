// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
interface IBetClub {
    enum BetState { Open, Locked, Resolved, Disputed, Cancelled }
    enum Side { None, Yes, No }
    event BetProposed(uint256 indexed betId, address indexed proposer, string question, uint256 stakePerSide);
    event BetJoined(uint256 indexed betId, address indexed member, Side side);
    event BetResolved(uint256 indexed betId, bool outcome, address indexed judge);
    event BetDisputed(uint256 indexed betId, address indexed disputer);
    event WinningsClaimed(uint256 indexed betId, address indexed winner, uint256 amount);
    event BetCancelled(uint256 indexed betId);
}
