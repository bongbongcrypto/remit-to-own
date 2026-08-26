# Remit-to-Own

Pay-as-you-go device financing where a relative abroad pays on Ethereum and the
device on Creditcoin stays unlocked. Submission for BUIDL CTC 2026 Fall.

## The one idea

Payment buys service time. It is never a loan, so there is nothing to collect and
nobody to chase. The only thing the contract needs to know is whether a payment
really happened on another chain, which is exactly what the Attestcoin Protocol
proves.

## Layout

- `contracts/` Foundry. `RemitToOwn.sol` inherits the vendored official `USCBase`.
  Two suites: product behaviour and an audit regression suite.
- `relay/` Python. Watches a plan's collection address, fetches proofs, submits.
- `detector/` not used in this project; scanning lives in `relay/watch_plan.py`.
- `web/` dependency-free status page and the primary surface. Discovers plans
  from the chain, reads state with hand-encoded `eth_call`, takes payment
  history from the Blockscout log API and the live tail from the node. Korean,
  Japanese, Chinese, English.
- `bot/` optional Telegram interface to the same state. The web page needs no
  token and no backend, so nothing depends on it.
- `docs/` technical documentation, security review, deck.

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
- **Run `python scripts/check-copy.py` after touching any wording.** Behaviour had
  thirty-eight tests and the words had none, so copy written while the
  implementation was still in mind kept shipping: source vocabulary on a buyer's
  screen, a string that read out an internal clamp, and sentences arguing with
  designs nobody proposed. The strings live in `web/strings.reference.json`; the
  page is regenerated from it, never edited string by string.
- The page layout follows the off-grid financing industry's own disclosure rules
  (GOGLA, CGAP, 60 Decibels). The reasoning is in `docs/TECHNICAL.md` 2.4. Do not
  restyle balance, lock, or switched-off states without reading it: switched off
  is amber and never red, and that is a finding, not a taste.
