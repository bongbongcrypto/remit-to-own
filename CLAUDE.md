# Remit-to-Own

Pay-as-you-go device financing where a relative abroad pays on Ethereum and the
device on Creditcoin stays switched on. Submission for BUIDL CTC 2026 Fall.

## The one idea

Payment buys service time. It is never a loan, so there is nothing to collect and
nobody to chase. The only thing the contract needs to know is whether a payment
really happened on another chain, which is exactly what the Attestcoin Protocol
proves.

## Layout

- `contracts/` Foundry. `RemitToOwn.sol` derives the vendored official `USCBase`.
  Two suites: product behaviour and an audit regression suite.
- `relay/` Python. Watches a plan's collection address, fetches proofs, submits.
- `detector/` not used in this project; scanning lives in `relay/watch_plan.py`.
- `web/` dependency-free status page, hand-encoded `eth_call`.
- `bot/` Telegram device alerts.
- `docs/` technical documentation, security review, deck, demo script.

## Rules that matter here

- Contracts and relay run on the build server only. A key-bearing workstation
  never installs packages and never signs.
- The signing key lives in an external env file, is never printed, never
  committed.
- Do not mock the precompile or decoder. They are exercised live on CC3 against
  real Ethereum mainnet transactions; that is how the swap bug was found.
- Every audit finding keeps a regression test. Do not delete one to make a build
  pass.
- English for code, docs, and commits.
