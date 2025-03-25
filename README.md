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

## Time-To-Live (TTL) Mechanism

Smaug uses a Time-To-Live (TTL) mechanism that affects several aspects of the contract's behavior:

### How TTL Works

- **Definition**: TTL is a time period (in seconds) that determines how long various approvals and scheduled changes remain valid
- **Default**: The TTL is set during contract initialization (typically 86400 seconds or 1 day)
- **Scope**: The TTL value applies globally to all assets protected by the contract

### TTL Effects

- **Pre-approved transactions**: The TTL acts as a maturity period for pre-approved transactions. When a transaction is pre-approved, it is still subject to budget checks until the TTL period has passed. Only after this waiting period does it bypass budget checks. The exact check is: `if (block.timestamp - preApprovalTimestamp < TTL)`, then budget checks apply.
- **Policy updates**: Changes to asset policies (budget limits) are scheduled and only applied after the TTL period has passed from the time of scheduling.
- **TTL updates**: Changes to the TTL value itself are also time-locked and only take effect after waiting for the current TTL period from when the update was scheduled.

### Changing TTL

To schedule a TTL update:

```solidity
// Schedule a change to the TTL value (will take effect after the current TTL period)
smaug.scheduleTTLUpdate(43200); // Change TTL to 12 hours (43200 seconds)
```

### Important Notes

- **Pre-approved transactions require maturity**: Pre-approved transactions bypass budget checks only after they have matured for the full TTL period.
- **Pre-approvals mature after TTL period**: After the TTL period passes from when a transaction was pre-approved, that transaction becomes exempt from standard budget checks and limits.
- **TTL is a mandatory waiting period**: For pre-approved transactions, TTL defines the minimum waiting period before the pre-approval takes effect and can bypass budget checks.
- **All updates respect TTL**: Policy changes, TTL changes, and pre-approval maturity all follow the same time-based TTL mechanism.

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

### Revoking Pre-approved Transactions
If a pre-approved transaction needs to be canceled or revoked:

```solidity
// Revoke a previously pre-approved transaction
bytes32 txHash = keccak256("Your transaction hash here");
smaug.revokePreApprovedTx(txHash);
```

This will **immediately** invalidate the pre-approval, causing any subsequent executions of the transaction to be subject to normal budget checks, even if the TTL period has passed.

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

### Code Security Review

The code was reviewed internally for security issues and best practices. No critical issues were found.




