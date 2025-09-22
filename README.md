# AtomicSwapPool

AtomicSwapPool is a cross-chain Automated Market Maker (AMM) liquidity pool that enables atomic swaps between Bitcoin (BTC) and STX tokens on the Stacks blockchain. The protocol combines traditional AMM functionality with atomic swap mechanisms to provide decentralized, trustless cross-chain trading.

## Features

- **Cross-chain AMM**: Automated market maker for BTC/STX trading pairs
- **Atomic Swaps**: Trustless cross-chain swaps using hash time-locked contracts (HTLCs)
- **Liquidity Provision**: Users can provide liquidity and earn fees from trading activity
- **Pool Tokens**: LP tokens representing proportional ownership in the liquidity pool
- **Fee Collection**: 0.3% trading fee distributed proportionally to liquidity providers
- **Slippage Protection**: Built-in slippage checks for all trading operations
- **Time-locked Swaps**: Configurable timeouts for atomic swap operations
- **Refund Mechanism**: Automatic refunds for expired or cancelled swaps

## Technical Specifications

- **Blockchain**: Stacks
- **Language**: Clarity 2.0
- **Epoch**: 2.5
- **Fee Rate**: 30 basis points (0.3%)
- **Hash Function**: SHA256 for atomic swap locks
- **Token Standard**: SIP-010 compatible fungible tokens

## Architecture

The contract consists of several key components:

### Core AMM Functions
- Constant product formula (x * y = k) for price discovery
- Dynamic fee calculation based on trade size
- Liquidity token minting and burning

### Atomic Swap System
- Hash time-locked contracts (HTLCs) for cross-chain operations
- Secret revelation mechanism for swap completion
- Timeout-based refund system for failed swaps

### Data Structures
- Pool reserves tracking (STX and BTC)
- Liquidity provider mappings
- Atomic swap state management
- Secret storage for completed swaps

## Installation

### Prerequisites

- Node.js (v16 or higher)
- Clarinet CLI
- Stacks wallet

### Setup

1. Clone the repository:
```bash
git clone https://github.com/your-username/AtomicSwapPool.git
cd AtomicSwapPool
```

2. Navigate to the contract directory:
```bash
cd AtomicSwapPool_contract
```

3. Install dependencies:
```bash
npm install
```

4. Run tests:
```bash
npm test
```

## Usage Examples

### Initialize Pool (Contract Owner Only)

```clarity
(contract-call? .AtomicSwapPool initialize-pool u1000000 u100000000)
;; Initialize with 1 STX and 1 BTC (in satoshis)
```

### Add Liquidity

```clarity
(contract-call? .AtomicSwapPool add-liquidity u500000 u50000000 u1000)
;; Add 0.5 STX and 0.5 BTC with minimum 1000 liquidity tokens
```

### Remove Liquidity

```clarity
(contract-call? .AtomicSwapPool remove-liquidity u1000 u400000 u40000000)
;; Remove 1000 liquidity tokens with minimum returns
```

### Initiate Atomic Swap

```clarity
(contract-call? .AtomicSwapPool initiate-swap
  u1000000                           ;; 1 STX to swap
  u95000000                          ;; Expected BTC amount
  "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh" ;; BTC address
  0x1234567890abcdef...              ;; Hash lock (32 bytes)
  u1000)                             ;; Timeout block height
```

### Complete Atomic Swap

```clarity
(contract-call? .AtomicSwapPool complete-swap
  u1                                 ;; Swap ID
  0xsecret123...)                    ;; Secret that hashes to the lock
```

## Contract Functions Documentation

### Read-Only Functions

#### `get-btc-amount (stx-amount uint)`
Returns the amount of BTC that would be received for a given STX amount, accounting for fees and current pool ratios.

#### `get-stx-amount (btc-amount uint)`
Returns the amount of STX that would be received for a given BTC amount, accounting for fees and current pool ratios.

#### `get-reserves ()`
Returns current pool reserves and total liquidity:
```clarity
{
  stx-reserve: uint,
  btc-reserve: uint,
  total-liquidity: uint
}
```

#### `get-user-liquidity (user principal)`
Returns the amount of liquidity tokens owned by a specific user.

#### `get-swap-details (swap-id uint)`
Returns complete details of an atomic swap by ID.

#### `get-swap-secret (swap-id uint)`
Returns the revealed secret for a completed swap (if available).

#### `is-swap-active (swap-id uint)`
Checks if a swap is active (not completed, cancelled, or expired).

### Public Functions

#### `initialize-pool (initial-stx uint) (initial-btc uint)`
Initializes the liquidity pool with initial reserves. Only callable by contract owner.

#### `add-liquidity (stx-amount uint) (btc-amount uint) (min-liquidity uint)`
Adds liquidity to the pool and mints LP tokens proportionally.

#### `remove-liquidity (liquidity-amount uint) (min-stx uint) (min-btc uint)`
Removes liquidity from the pool and burns LP tokens.

#### `initiate-swap (stx-amount uint) (btc-amount uint) (btc-address string) (hash-lock buff) (timeout uint)`
Initiates a new atomic swap with specified parameters.

#### `complete-swap (swap-id uint) (secret buff)`
Completes an atomic swap by revealing the secret that matches the hash lock.

#### `cancel-swap (swap-id uint)`
Cancels an expired atomic swap or allows initiator to cancel before expiry.

## Deployment Guide

### Testnet Deployment

1. Configure Clarinet for testnet:
```bash
clarinet integrate --testnet
```

2. Deploy the contract:
```bash
clarinet deploy --network testnet
```

### Mainnet Deployment

1. Update configuration in `settings/Mainnet.toml`
2. Deploy with sufficient STX for transaction fees:
```bash
clarinet deploy --network mainnet
```

### Post-Deployment Steps

1. Initialize the pool with initial liquidity
2. Verify all functions work correctly
3. Set up monitoring for pool operations
4. Document the deployed contract address

## Security Notes

### Atomic Swap Security

- **Hash Lock Validation**: All swaps require cryptographic proof via SHA256 hash locks
- **Timeout Protection**: Swaps automatically expire after specified block height
- **Double Spending Prevention**: Completed swaps cannot be replayed or modified
- **Secret Management**: Secrets are only stored after successful completion

### AMM Security

- **Slippage Protection**: All operations include minimum return parameters
- **Balance Checks**: Insufficient balance errors prevent overdraws
- **Integer Overflow**: Clarity's built-in overflow protection prevents arithmetic errors
- **Authorization**: Owner-only functions properly restricted

### Best Practices

- Always set appropriate timeout values for atomic swaps
- Use secure random number generation for hash lock secrets
- Implement client-side slippage calculations
- Monitor pool ratios to detect unusual activity
- Keep private keys secure for Bitcoin operations

### Known Limitations

- BTC operations require off-chain coordination
- Pool initialization is irreversible
- No emergency pause mechanism
- Fee rates are fixed at contract deployment

## Testing

The project includes comprehensive unit tests covering:

- Pool initialization and liquidity operations
- Atomic swap lifecycle (initiate, complete, cancel)
- Error conditions and edge cases
- Fee calculations and slippage protection

Run the test suite:
```bash
npm test
```

For coverage reports:
```bash
npm run test:report
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

This project is licensed under the ISC License - see the LICENSE file for details.

## Disclaimer

This software is provided as-is without warranties. Users should conduct thorough testing and security audits before deploying to mainnet. Cross-chain operations involve additional risks and complexities.