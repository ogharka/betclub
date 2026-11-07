// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IBetClub.sol";

contract BetClub is IBetClub, ReentrancyGuard {
    using SafeERC20 for IERC20;
    uint256 public constant FEE_BPS = 200;
    uint256 public constant DISPUTE_WINDOW = 48 hours;
    uint256 public constant MIN_STAKE = 1e6;
    uint256 public constant MAX_STAKE = 1000e6;

    string public name;
    address public creator;
    address public immutable usdc;
    address public immutable factory;
    address[] private _members;
    mapping(address => bool) public isMember;
    uint256 public betCount;

    struct Bet {
        uint256 id; string question; address proposer; address judge;
        uint256 stakePerSide; uint256 resolutionTime; uint256 yesPool; uint256 noPool;
        BetState state; bool outcome; uint256 disputeDeadline; uint256 disputeCount;
    }

    mapping(uint256 => Bet) public bets;
    mapping(uint256 => mapping(address => Side)) public positions;
    mapping(uint256 => mapping(address => bool)) public claimed;
    mapping(uint256 => mapping(address => bool)) public disputed;

    modifier onlyMember() { require(isMember[msg.sender], "Not a member"); _; }
    modifier onlyCreator() { require(msg.sender == creator, "Not creator"); _; }
    modifier betExists(uint256 betId) { require(betId < betCount, "Bet not found"); _; }

    constructor(string memory _name, address _creator, address _usdc, address _factory) {
        require(bytes(_name).length > 0, "Empty name");
        require(_creator != address(0) && _usdc != address(0) && _factory != address(0), "Invalid address");
        name = _name; creator = _creator; usdc = _usdc; factory = _factory;
        _addMember(_creator);
    }

    function addMember(address member) external onlyCreator {
        require(member != address(0), "Invalid address");
        require(!isMember[member], "Already a member");
        require(_members.length < 50, "Club full");
        _addMember(member);
    }

    function _addMember(address member) internal { isMember[member] = true; _members.push(member); }
    function getMembers() external view returns (address[] memory) { return _members; }

    function proposeBet(string calldata question, address judge, uint256 stakePerSide, uint256 resolutionTime, Side side)
        external onlyMember nonReentrant returns (uint256) {
        require(bytes(question).length > 0 && bytes(question).length <= 200, "Invalid question");
        require(isMember[judge], "Judge must be member");
        require(judge != msg.sender, "Cannot judge own bet");
        require(stakePerSide >= MIN_STAKE && stakePerSide <= MAX_STAKE, "Invalid stake");
        require(resolutionTime > block.timestamp + 1 hours, "Resolution too soon");
        require(side == Side.Yes || side == Side.No, "Pick Yes or No");
        uint256 betId = betCount++;
        Bet storage b = bets[betId];
        b.id = betId; b.question = question; b.proposer = msg.sender; b.judge = judge;
        b.stakePerSide = stakePerSide; b.resolutionTime = resolutionTime; b.state = BetState.Open;
        positions[betId][msg.sender] = side;
        if (side == Side.Yes) b.yesPool += stakePerSide;
        else b.noPool += stakePerSide;
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), stakePerSide);
        emit BetProposed(betId, msg.sender, question, stakePerSide);
        return betId;
    }

    function joinBet(uint256 betId, Side side) external onlyMember betExists(betId) nonReentrant {
        Bet storage b = bets[betId];
        require(b.state == BetState.Open, "Bet not open");
        require(block.timestamp < b.resolutionTime, "Past resolution time");
        require(positions[betId][msg.sender] == Side.None, "Already joined");
        require(b.judge != msg.sender, "Judge cannot bet");
        require(side == Side.Yes || side == Side.No, "Pick Yes or No");
        positions[betId][msg.sender] = side;
        if (side == Side.Yes) b.yesPool += b.stakePerSide;
        else b.noPool += b.stakePerSide;
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), b.stakePerSide);
        emit BetJoined(betId, msg.sender, side);
    }

    function resolveBet(uint256 betId, bool outcome) external betExists(betId) {
        Bet storage b = bets[betId];
        require(msg.sender == b.judge, "Only judge");
        require(b.state == BetState.Open, "Bet not open");
        require(block.timestamp >= b.resolutionTime, "Too early");
        require(b.yesPool > 0 && b.noPool > 0, "Need both sides");
        b.state = BetState.Resolved; b.outcome = outcome;
        b.disputeDeadline = block.timestamp + DISPUTE_WINDOW;
        emit BetResolved(betId, outcome, msg.sender);
    }

    function disputeResolution(uint256 betId) external onlyMember betExists(betId) {
        Bet storage b = bets[betId];
        require(b.state == BetState.Resolved, "Not resolved");
        require(block.timestamp <= b.disputeDeadline, "Dispute window closed");
        require(positions[betId][msg.sender] != Side.None, "Not a participant");
        require(!disputed[betId][msg.sender], "Already disputed");
        disputed[betId][msg.sender] = true;
        b.disputeCount++;
        if (b.disputeCount * 2 > _members.length) b.state = BetState.Disputed;
        emit BetDisputed(betId, msg.sender);
    }

    function claimWinnings(uint256 betId) external onlyMember betExists(betId) nonReentrant {
        Bet storage b = bets[betId];
        require(b.state == BetState.Resolved, "Not claimable");
        require(block.timestamp > b.disputeDeadline, "Dispute window open");
        require(!claimed[betId][msg.sender], "Already claimed");
        Side side = positions[betId][msg.sender];
        require(side != Side.None, "Not a participant");
        bool won = (b.outcome && side == Side.Yes) || (!b.outcome && side == Side.No);
        require(won, "Did not win");
        claimed[betId][msg.sender] = true;
        uint256 totalPot = b.yesPool + b.noPool;
        uint256 fee = (totalPot * FEE_BPS) / 10_000;
        uint256 payoutPool = totalPot - fee;
        uint256 winnerPool = b.outcome ? b.yesPool : b.noPool;
        uint256 payout = (b.stakePerSide * payoutPool) / winnerPool;
        IERC20(usdc).safeTransfer(msg.sender, payout);
        IERC20(usdc).safeTransfer(factory, fee);
        emit WinningsClaimed(betId, msg.sender, payout);
    }

    function cancelBet(uint256 betId) external betExists(betId) nonReentrant {
        Bet storage b = bets[betId];
        require(b.state == BetState.Open, "Not open");
        require(msg.sender == b.proposer || msg.sender == creator, "Not authorized");
        b.state = BetState.Cancelled;
        emit BetCancelled(betId);
    }

    function claimRefund(uint256 betId) external betExists(betId) nonReentrant {
        Bet storage b = bets[betId];
        require(b.state == BetState.Cancelled, "Not cancelled");
        require(!claimed[betId][msg.sender], "Already refunded");
        require(positions[betId][msg.sender] != Side.None, "Not a participant");
        claimed[betId][msg.sender] = true;
        IERC20(usdc).safeTransfer(msg.sender, b.stakePerSide);
    }

    function getBet(uint256 betId) external view betExists(betId) returns (Bet memory) { return bets[betId]; }
    function getMyPosition(uint256 betId) external view returns (Side) { return positions[betId][msg.sender]; }
}
