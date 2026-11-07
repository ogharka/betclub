// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BetClub.sol";

contract BetClubFactory is Ownable {
    address public immutable usdc;
    address[] public allClubs;
    mapping(address => address[]) public clubsByCreator;
    event ClubCreated(address indexed club, address indexed creator, string name);

    constructor(address _usdc) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC");
        usdc = _usdc;
    }

    function createClub(string calldata name) external returns (address) {
        require(bytes(name).length > 0 && bytes(name).length <= 50, "Invalid name");
        BetClub club = new BetClub(name, msg.sender, usdc, address(this));
        allClubs.push(address(club));
        clubsByCreator[msg.sender].push(address(club));
        emit ClubCreated(address(club), msg.sender, name);
        return address(club);
    }

    function totalClubs() external view returns (uint256) { return allClubs.length; }
    function getClubsByCreator(address creator) external view returns (address[] memory) {
        return clubsByCreator[creator];
    }
}
