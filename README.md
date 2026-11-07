# 🎯 BetClub

**Friend-group prediction markets on Base L2**

BetClub lets friend groups create private clubs, propose bets on anything,
stake USDC, and settle outcomes transparently onchain.

## How It Works
1. Create a club → invite friends
2. Propose a bet with a question, judge, and USDC stake
3. Friends join Yes or No side
4. Judge resolves after the deadline
5. Winners claim USDC instantly — 2% protocol fee

## Setup
```bash
npm install
cp .env.example .env
npx hardhat compile
npx hardhat test
```

## Deploy to Base Sepolia
```bash
npx hardhat run scripts/deploy.js --network base-sepolia
```

## Built With
- Solidity 0.8.24 + OpenZeppelin 5.x
- Hardhat
- Base L2 (Coinbase)

## License
MIT
