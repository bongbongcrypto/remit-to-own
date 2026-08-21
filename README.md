# Remit-to-Own

**Pay-as-you-go device financing, paid for by a relative on another chain.**
BUIDL CTC 2026 Fall.

Buying a motorcycle or a solar home system on installments is ordinary across
much of the world. So is having a relative abroad cover the payments. Those two
facts do not compose today: the seller is at home, the money is abroad, and
neither side can see the other's ledger. The gap gets filled by remittance
operators and local agents who each take a cut and each have to be trusted.

Remit-to-Own closes it with proof. Each plan gets a dedicated collection address
on Ethereum. A relative anywhere sends stablecoins there. The Attestcoin
Protocol proves that transfer to Creditcoin, the plan credits itself, and the
device stays switched on for the days that payment bought.

**Pay more, it runs longer. Stop paying, it stops. Cover the price, it is yours.**

---

## It already works (CC3 testnet, 2026-08-22)

Every plan below was driven by **real Ethereum mainnet USDC transfers**, each
proven on Creditcoin through the BlockProver precompile.

| Plan | What happened | State |
|---|---|---|
| Delivery truck, 50,000 USDC | 23.48, then 1,490.71, then 97.47, then 107.41 USDC proven | **Running, 25 days bought so far** |
| Motorcycle, 1,800 USDC | 89.42 USDC, then the balance | **Off, then running, then owned outright** |
| Solar home system, 800 USDC | real payments proven | **Paid off, owned outright** |

Contract: [`0x59FEF8771Da4248b89F7D6052b9d10fDfb13D223`](https://creditcoin-testnet.blockscout.com/address/0x59FEF8771Da4248b89F7D6052b9d10fDfb13D223)

Check a device yourself:

```bash
cast call 0x59FEF8771Da4248b89F7D6052b9d10fDfb13D223 \
  "isActive(bytes32)(bool)" \
  0x2e73d5949dee6d8ea8588ec7a4e61731e7619dbc0d52552b27463ca108666ac6 \
  --rpc-url https://rpc.cc3-testnet.creditcoin.network
```

Or open `web/index.html`, which reads the same state straight from the chain.

---

## Why this needs Attestcoin, and why it does not break

Two design problems had to be solved, and the second is the one that sinks most
cross-chain credit ideas.

**Attributing a payment.** A stablecoin transfer carries no memo, so a payment
cannot say which plan it belongs to. Each plan is therefore issued its own
collection address, exactly as payment processors do with per-invoice deposit
addresses. Money arriving there belongs to that plan and no other.

**Never extending credit.** The contract does not lend, score, or trust anyone.
Payment buys service time and nothing else, so there is nothing to collect later
and nobody to chase. A borrower who stops paying simply stops having a working
device, which is how pay-as-you-go financing already works in the field. This is
why the design has no default risk, no liquidation logic, and no reputation to
game.

What remains is a single question: *did this payment really happen on Ethereum?*
That is precisely what Attestcoin answers, and there is no other way for a
Creditcoin contract to know it.

---

## How the proof path works

```
 relative abroad
   sends USDC on Ethereum to the plan's collection address
        │
        ▼
 relay/    fetch inclusion proof (ProofBuilder API)
        │  submit recordPayment(...)
        ▼
 RemitToOwn.execute()  →  verifyAndEmit @ precompile 0x…0FD2
        │                 invalid proof reverts the whole call
        ▼
 decode receipt → ERC-20 Transfer logs → match collector → credit the plan
        │
        ├──▶ web/   device status page
        └──▶ bot/   "a payment just arrived, your device runs 30 more days"
```

Each proven transfer must clear every rule in `_creditTransferLog` to count as a
payment. The three that carry the most weight:

1. The Attestcoin proof must verify, or `execute` reverts and nothing is written.
2. The log's emitter must be an **accepted token** on that chain. A contract
   emitting its own worthless token's `Transfer` cannot buy a device.
3. The recipient must be a **registered collection address**, which is what binds
   the payment to one plan.

A per-query replay guard (inherited from `USCBase`) means the same payment can
never be counted twice. This is verified live: resubmitting a proven payment is
rejected on-chain.

---

## Layout

- **`contracts/`**: Foundry. `RemitToOwn.sol` derives the official `USCBase`;
  38 passing tests including an audit regression suite; deploy script.
- **`relay/`**: Python. Watches a plan's collection address, fetches proofs, and
  submits them. Signs only on the build server, never on a developer machine.
- **`web/`**: dependency-free device status page (hand-encoded `eth_call`).
- **`bot/`**: Telegram bot: device status, and an alert the moment a relative's
  payment is proven.
- **`docs/`**: technical documentation, security review, deck, demo script.

## Quickstart

```bash
# contracts
cd contracts && yarn install && forge install foundry-rs/forge-std && forge test
WALLET_ENV=~/.ato-wallet.env bash scripts/deploy.sh

# accept a stablecoin, then open a plan
cast send <contract> "setTrustedToken(uint64,address,bool)" 3 <usdc> true ...
cast send <contract> "openPlan(bytes32,address,uint64,address,address,uint128,uint128,uint32)" ...

# prove every payment that has landed on the plan's collection address
cd ../relay && python watch_plan.py --plan 0x<planId> --chainkey 3 --blocks 60 --submit
```

`--chainkey 1` is Ethereum Sepolia, `3` is Ethereum mainnet. Both are attested on
CC3 testnet, so real mainnet payments are provable at no cost.

---

## Honest scope

- Deployed on CC3 **testnet**, per hackathon rules.
- The device lock is expressed as on-chain state (`isActive`). Wiring that to a
  real device controller is a hardware integration, not part of this submission.
- For the demo, plans are opened against **live mainnet addresses that already
  receive USDC**, so that genuine, independently generated payments drive the
  system. A merchant in production generates a fresh collection address per plan.
- Attestation lags the source chain by roughly nine minutes by design, so a
  payment is credited shortly after it lands, not instantly. For monthly
  financing that gap does not matter.
- The Telegram bot needs a dedicated token to run live; its chain reads, message
  formatting, and event parsing are verified without one.

## License

MIT.
