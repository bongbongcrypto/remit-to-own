# Technical Documentation

How Remit-to-Own is built and deployed, and how it integrates the Attestcoin
Protocol. Companion to the top-level `README.md`.

## 1. System overview

```
relative abroad (Ethereum)        relay (Python)              RemitToOwn (Solidity, CC3)
  USDC -> plan collection    →   fetch proof, submit      →   recordPayment():
  address                        recordPayment(...)             verifyAndEmit @ 0x…0FD2
                                                                decode Transfer logs
                                                                match collector -> plan
                                                                credit + extend service
                                                        ↘  web/ + bot/ read the result
```

Source chains are Ethereum **Sepolia** (chainKey 1) and **mainnet** (chainKey 3),
both attested on CC3 testnet. Mainnet's attested range starts at genesis, so any
historical payment is provable.

## 2. Attestcoin integration

### 2.1 The on-chain contract

`contracts/src/RemitToOwn.sol` derives the official `USCBase` (vendored from
`@gluwa/usc-contracts`). `recordPayment` wraps `USCBase.execute` so the origin
check knows which chain the proof came from, then:

1. `USCBase` computes a `queryId`, rejects replays, and calls the **BlockProver
   precompile** at `0x0000000000000000000000000000000000000FD2` via
   `verifyAndEmit`. An invalid proof reverts everything.
2. `_processAndEmitEvent` decodes the proven transaction with `EvmV1Decoder`,
   requires `receiptStatus == 1`, and pulls every ERC-20 `Transfer` log
   (topic0 `0xddf252ad…3b3ef`).
3. Each log goes through `_creditTransferLog`, which holds every rule a transfer
   must satisfy to count as a payment, in one readable place:
   - the recipient is a registered collection address (`collectorPlan`)
   - the plan's own `chainKey` matches the proof in flight
   - the emitter is exactly the plan's `token`, not merely some accepted token
   - the emitter is accepted money (`trustedToken`)
   - the plan is not already paid off
   - sender and recipient differ, since an address paying itself moves nothing
   - the amount is non-zero and fits in `uint128` without truncation

   A transfer failing any of these is skipped rather than rejecting the whole
   transaction, because one payment transaction routinely carries several tokens
   to the same address.
4. At least one credited transfer is required, or the call reverts.

### 2.2 Turning payment into service

```solidity
uint256 secondsBought = (uint256(amount) * uint256(p.daysPerInstallment) * 1 days) / p.installment;
uint256 base = p.activeUntil > block.timestamp ? p.activeUntil : block.timestamp;
uint256 until = base + secondsBought;
p.activeUntil = until > type(uint64).max ? type(uint64).max : uint64(until);
```

Time scales with the amount, so a relative can send a third of an installment or
four at once. It accrues in **seconds, not whole days**: people in this market
send small sums, and rounding a payment down to zero days would quietly eat it.
Paying early stacks time onto what is left rather than wasting it; paying after a
lapse restarts from now with no penalty. The addition saturates instead of
wrapping. When `paid` reaches `priceTotal` the plan settles and `activeUntil`
becomes `type(uint64).max`, so an owned device never switches off again.

### 2.3 The relay

`relay/rto_relay.py` and `relay/watch_plan.py`:

- `attested_height(chainKey)`: `GET /api/v1/attested-height/{chainKey}`
- `fetch_proof(chainKey, txHash)`: `GET /api/v1/proof-by-tx/{chainKey}/{txHash}`
  returning `{chainKey, headerNumber, txIndex, txBytes, merkleProof{root,
  siblings[]}, continuityProof{lowerEndpointDigest, roots[]}, cached}`
- `submit_payment(...)` maps those fields onto `recordPayment(...)`, estimates
  gas with a 600k floor, signs EIP-1559, and waits for the receipt
- `watch_plan.py` reads the plan's collector from the contract, scans the source
  chain for transfers into it, and proves each one

Both ProofBuilder hosts are used with failover:
`prover.cc3-testnet.creditcoin.network` and
`proof-gen-api.cc3-testnet.creditcoin.network`.

## 3. Deployment

`EvmV1Decoder` is a linked library, deployed first and linked into the contract
(`contracts/scripts/deploy.sh`):

```bash
cd contracts
yarn install                       # @gluwa/usc-contracts, @openzeppelin/contracts (pinned)
forge install foundry-rs/forge-std
forge build                        # solc 0.8.30, shanghai
WALLET_ENV=~/.ato-wallet.env bash scripts/deploy.sh
```

Live deployment (`contracts/deployments/cc3-testnet.json`):

| Contract | Address |
|---|---|
| RemitToOwn | `0x59FEF8771Da4248b89F7D6052b9d10fDfb13D223` |
| EvmV1Decoder (linked) | `0x21f3e26A827F2e89c0F99B46da033F4b05D57fd8` |

CC3 testnet: chainId `102031`, RPC `https://rpc.cc3-testnet.creditcoin.network`,
explorer `https://creditcoin-testnet.blockscout.com`.

## 4. Threat model

An adversarial audit was run against this contract. Every attack below was a
working exploit at some point during development and is now closed, each with a
regression test in `test/RemitToOwnAudit.t.sol`.

| Attack | Defence |
|---|---|
| Forge a payment that never happened | Attestcoin proof; an invalid proof reverts the call |
| Replay a real payment to double-credit | `queryId` guard in `USCBase`, verified live on chain |
| **Name a busy address you do not control as your collector, then claim a stranger's deposit as your payment** | Issuing collectors is an operator action. A proof shows a transfer happened; nothing on chain can show who an address belongs to |
| Squat a collection address to lock a merchant out of it permanently | Same restriction |
| Emit a fake `Transfer` from an attacker's own token | Emitter must be accepted money |
| **Pay a USDC plan with a different accepted token**, so 18 decimals settle a 6-decimal plan for a rounding error | The emitter must equal the plan's own `token` |
| **Submit a proof verified for one chain and credit a plan on another** | The plan's `chainKey` must match the proof in flight |
| Call the inherited `execute()` directly, with no chain key set | Refused; payments must enter through `recordPayment` |
| Send a value above `uint128` so it truncates to something small, or to zero | Rejected rather than truncated |
| Credit a transfer where sender and recipient are the same address | Refused; no money moved |
| Keep paying a settled plan and have the money silently vanish | Settled plans stop accepting payments |
| Open a plan with `planId` zero, breaking collector uniqueness | Rejected |
| Overflow the service term so the device switches off | Service term capped, arithmetic saturates |
| Anyone setting accepted tokens, or burning admin | `onlyAdmin`, and admin cannot be set to the zero address |

Deliberately **not** defended, because the design does not need it: default,
delinquency, collateral, liquidation, credit scoring. Nothing is lent, so nothing
must be recovered.

## 5. Field notes (measured)

- **Fee**: a `recordPayment` submit costs a fraction of a cent in tCTC, far below
  the older published figures.
- **Gas estimation** works against the precompile-backed call, but the published
  fallback formula under-estimates by roughly 60 percent; the relay floors gas at
  600k.
- **Attestation lag**: about 44 source blocks (~9 minutes). The protocol stays
  behind the tip on purpose to survive re-orgs.
- **Live-data bug, found and fixed**: rejecting a whole transaction because it
  carried an unrecognised token killed four of six real payments, since payment
  transactions are often swaps routing several assets to one address. Skipping
  unrecognised transfers instead is both correct and safe: they can never credit
  a plan. After the fix, eight of eight succeeded. Only running against live
  mainnet data surfaced this.
- **Public RPC limits**: `eth_getLogs` needs an address filter on some endpoints
  and chunked ranges with a delay, and still rate-limits. The scanner tries each
  chunk against several endpoints before giving up, and reports partial coverage
  rather than a silent zero.
- **Private-key handling**: the key lives only in an external env file on the
  build server, is never printed, and never touches a key-bearing workstation.

## 6. Testing

**38 Foundry tests, all passing.** 23 cover product behaviour: setup guards,
service extension, early and late payment, dust and oversized payments,
settlement, plan independence, operator restrictions. 15 are the audit
regression suite in `test/RemitToOwnAudit.t.sol`, one per attack in section 4,
plus a fuzz invariant over payment sequences.

The precompile and decoder are deliberately not mocked. They are exercised live
on CC3 against real Ethereum mainnet transactions, which is how the swap bug in
section 5 surfaced and why unit tests alone could not have caught it.

## 7. Roadmap

- Device-side integration: a controller that gates power on `isActive`.
- Batch proofs (`verifyAndEmit` accepts several transactions from one continuity
  proof) to cut per-payment cost for merchants with many plans.
- Merchant console for issuing collection addresses and tracking a portfolio.
- Additional source chains as Attestcoin adds them.
