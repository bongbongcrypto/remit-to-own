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
device stays unlocked for the days that payment bought.

**Pay more, it works longer. Stop paying, it locks. Cover the price, you own it outright.**

---

## It already works (CC3 testnet, snapshot 2026-08-27)

Nine plans, sixteen proven payments, across **both source chains Attestcoin
attests**. The page reads all of it from the contract, so this table is a
snapshot and the chain is the record.

| Plan | Source | Payments proven | State |
|---|---|---|---|
| Solar lantern, 12 USDC | Sepolia | 3.00 | Running until 23 Sept |
| Solar lantern, 12 USDC | Sepolia | 3.00 | Running until 25 Sept |
| Solar lantern, 12 USDC | Sepolia | 3.00 | Running until 25 Sept |
| Delivery truck, 80,000 USDC | mainnet | 342.59, 1,500.00, 599.68 | Running until 28 Sept |
| Delivery truck, 50,000 USDC | mainnet | 23.48, 1,490.71, 97.47, 107.41, 1,946.58 | Running until 16 Oct |
| Cargo tricycle, 5,000 USDC | mainnet | 326.19, then the balance | Owned outright |
| Motorcycle, 1,800 USDC | mainnet | 89.42, then the balance | Owned outright |
| Solar home system, 800 USDC | mainnet | one transfer, capped at the balance | Owned outright |
| Motorcycle second hand, 1,200 USDC | mainnet | none yet | Not started |

The two chains do different jobs. The **Sepolia** lanterns are ours from the
collection address to the payment, so the whole sequence can be run on demand;
the third lantern was paid and proven live on camera for the demo video.
The **mainnet** plans point at busy addresses nobody here controls, which runs
the proof path against live traffic at no cost. That is where the multi-token
bug in `docs/TECHNICAL.md` section 5 came from.

Contract: [`0x59FEF8771Da4248b89F7D6052b9d10fDfb13D223`](https://creditcoin-testnet.blockscout.com/address/0x59FEF8771Da4248b89F7D6052b9d10fDfb13D223)

### When this was built

The chain is the record, and block timestamps are not something anyone can set
by hand:

| | |
|---|---|
| Contract deployed | 2026-08-21 15:54 UTC ([tx](https://creditcoin-testnet.blockscout.com/tx/0xb861aa022450528523eb3059a6edde43a0aa7dc7f7db889b2341f99ded3282f7)) |
| First payment proven | 2026-08-21 15:56 UTC |
| Fourteenth payment proven | 2026-08-24 11:51 UTC |
| Sixteenth payment proven | 2026-08-26 18:22 UTC |

Submissions for BUIDL CTC 2026 Fall opened on 13 August and close on 13
September (extended from 6 September), so every one of those falls inside the
window. The full event log is
on the [contract's page](https://creditcoin-testnet.blockscout.com/address/0x59FEF8771Da4248b89F7D6052b9d10fDfb13D223?tab=logs).

Check a device yourself:

```bash
cast call 0x59FEF8771Da4248b89F7D6052b9d10fDfb13D223 \
  "isActive(bytes32)(bool)" \
  0x2e73d5949dee6d8ea8588ec7a4e61731e7619dbc0d52552b27463ca108666ac6 \
  --rpc-url https://rpc.cc3-testnet.creditcoin.network
```

Or serve `web/` and open it in a browser:

```bash
python -m http.server 8000 --directory web
# then open http://localhost:8000
```

The page finds every plan on the
contract by itself, shows what is left to pay, how many installments remain, and
where to send money, and it announces a payment the moment one is proven. Korean,
Japanese, Chinese and English.

---

## How this reaches a real machine

Pay-as-you-go financing already ships with remote lockout hardware. A solar
home kit carries a controller chip that gates power output, and a financed
motorcycle carries a GSM immobiliser that gates the ignition. Today those
controllers obey one signal from the lender's server: paid or not paid.

This contract replaces the server, not the hardware. A controller reads
`isActive` over any public RPC, the same one-line call shown above. It is a
read, so the device needs no wallet, no key, and no gas. The status page in
`web/` runs exactly that loop in software, which is what the demo video shows:
poll the chain, flip the state, announce the payment.

Building or flashing that controller is a job for the manufacturers who
already make them, and it is out of scope here. What this submission proves is
that the signal those devices obey can come from a verified chain instead of a
company's word.

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
        └──▶ web/   status, plus a live alert the moment a payment lands
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
- **`web/`**: dependency-free device page, no build step and no backend. Reads
  state with a hand-encoded `eth_call` and watches the contract's own events, so
  a payment proven abroad shows up here with no server in between. What it puts
  on screen follows the disclosure rules the off-grid financing industry wrote
  for itself, which is why the balance owed is the headline and a switched-off
  device is never styled as a delinquency. Reasoning in `docs/TECHNICAL.md` 2.4.
- **`bot/`**: optional Telegram interface to the same state.
- **`docs/`**: technical documentation, security review, deck, demo script.

## Quickstart

```bash
# contracts
cd contracts && yarn install && forge install foundry-rs/forge-std && forge test
WALLET_ENV=~/.remit-to-own.env bash scripts/deploy.sh

# accept a stablecoin, then open a plan
cast send <contract> "setTrustedToken(uint64,address,bool)" 3 <usdc> true ...
cast send <contract> "openPlan(bytes32,address,uint64,address,address,uint128,uint128,uint32)" ...

# prove every payment that has landed on the plan's collection address
cd ../relay && python watch_plan.py --plan 0x<planId> --chainkey 3 --blocks 60 --submit
```

`--chainkey 1` is Ethereum Sepolia, `3` is Ethereum mainnet. Both are attested on
CC3 testnet, so live mainnet transfers are provable at no cost.

---

## Honest scope

- Deployed on CC3 **testnet**, per hackathon rules.
- The device lock is expressed as on-chain state (`isActive`). The lockout
  hardware already exists in this industry; flashing it to read the chain is an
  integration for the manufacturers who make it, not part of this submission.
  See "How this reaches a real machine" above.
- For the demo, plans are opened against **live mainnet addresses that already
  receive USDC**, so that genuine, independently generated transfers drive the
  system. The proofs and the state changes are real; the payers are strangers
  moving money through DeFi rather than customers buying a truck. Running the
  pipeline against live traffic is where the multi-token bug in section 5 of
  `docs/TECHNICAL.md` came from. A merchant in production generates a fresh
  collection address per plan.
- **Plans are opened by the operator.** A proof shows that a transfer happened;
  nothing on chain shows who an address belongs to. That restriction is
  deliberate, and it is the fix for the critical audit finding: left open, the
  same gap lets anyone register a busy address as their collector and bank a
  stranger's deposit. The roadmap closes it with Attestcoin itself, by having an
  address prove control through a marked transfer that is verified exactly the
  way a payment is.
- Attestation lags the source chain by roughly nine minutes by design, so a
  payment is credited shortly after it lands, not instantly. For monthly
  financing that gap does not matter.
- The page polls the chain directly, so there is no backend to run and nothing
  to trust between the contract and the screen. The Telegram interface is
  optional and needs a bot token; the web page needs nothing.

## License

MIT.
