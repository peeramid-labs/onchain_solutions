# Smaug - Safe Guard Contract Review

## Overview
Smaug is a guard contract for [Safe](https://safe.global/) multi-signature wallets that implements budget controls and transaction approval mechanisms. It's designed to protect assets by enforcing spending limits based on various timeframes:

- Daily limits
- Block limits
- Per-transaction limits
- Total (lifetime) limits

## Key Features
- Budget enforcement for multiple assets
- Transaction pre-approval mechanism
- Time-locked policy updates
- Support for ERC20 tokens and native ETH

## Testing Summary
Tests were conducted to verify the core functionality of the Smaug contract. Key findings:

1. ✅ **Budget Enforcement**: Successfully restricts transactions exceeding configured limits
2. ✅ **Pre-approval Bypass**: Correctly allows pre-approved transactions to bypass budget checks
3. ✅ **Pre-approval Expiration**: Pre-approved transactions correctly expire after the TTL period
4. ✅ **Asset Protection**: Multiple assets can be protected with independent budgets

## Usage

### Protecting Assets
To protect an asset with budget controls:

```solidity
// Add protection for an ERC20 token
smaug.addProtectedAsset(
  tokenAddress, // Zero address for ETH
  {
    inDay: 1000 ether,    // 1000 tokens per day
    inBlock: 100 ether,   // 100 tokens per block
    inTX: 50 ether,       // 50 tokens per transaction
    inTotal: 10000 ether  // 10000 tokens total lifetime limit
  }
);
```

### Pre-approving Transactions
To bypass budget controls for specific transactions:

```solidity
// Pre-approve a transaction hash
bytes32 txHash = keccak256("Your transaction hash here");
smaug.preApproveTx(txHash);
```

### Scheduling Policy Updates
To update budget controls with a time-lock:

```solidity
// Schedule a policy update
smaug.schedulePolicyUpdate(
  tokenAddress,
  {
    inDay: 2000 ether,    // Updated limits
    inBlock: 200 ether,
    inTX: 150 ether,
    inTotal: 20000 ether
  }
);
```

