# Security

Two things were reviewed: the dependencies this project pulls in, and the
contract itself under adversarial attack.

## 1. Dependencies

Installs and builds are isolated to a dedicated build server. The development
workstation holds first-party source only, with no `node_modules` and no package
installs.

**Verdict: clean.**

| Check | Result |
|---|---|
| Dependency tree | `@gluwa/usc-contracts` 0.1.2 and `@openzeppelin/contracts` 5.4.0. Two packages, zero transitive runtime dependencies |
| Install lifecycle hooks | None. OpenZeppelin's `prepack` runs on publish, not on install |
| Provenance | Published by `gluwa-bot@gluwa.com` and the OpenZeppelin team, resolved from the public registry with integrity hashes |
| Contents | `@gluwa/usc-contracts` ships nine `.sol` files plus metadata. No JavaScript, no binaries |
| Dangerous patterns | No `child_process`, `eval`, `exec`, filesystem writes, or network exfiltration |
| Version pinning | Exact versions, matching what is installed |

`web3`, `eth-account`, `forge-std` and Foundry v1.2.3 are mainstream, widely
used, and pinned.

## 2. Contract audit

An adversarial review was run against `RemitToOwn.sol`, with a working exploit
written for each finding before any fix. Every one is now closed and held closed
by a regression test in `test/RemitToOwnAudit.t.sol`.

### Critical

**Collection addresses had no proof of ownership.** `openPlan` was open to
anyone, so an attacker could name an address they did not control, a busy
exchange wallet for instance, as their plan's collection address. The next
unrelated deposit to that address would be proven, credited, and the attacker
would own a device having sent nothing.

The root cause is worth stating plainly, because it shapes the design: **an
Attestcoin proof shows that a transfer happened, and cannot show whose address
received it.** The contract treated the second as though it followed from the
first. The fix is a restriction rather than a cleverer proof: issuing collection
addresses is an operator action. The roadmap replaces this with escrow addresses
the protocol deploys itself, which is the only way to make ownership provable
rather than asserted.

**Any accepted token could pay any plan.** `Plan.token` and `Plan.chainKey` were
written at creation and never read again on the payment path, so the contract
checked only that a token was accepted somewhere, not that it was *this plan's*
currency on *this plan's* chain. With two accepted tokens of different decimals,
a plan priced in 6-decimal USDC could be settled by a rounding error's worth of
an 18-decimal token. Both fields are now compared on every credit.

### Medium

- **Chain key bypass.** `execute()` is external on the inherited base, so calling
  it directly left no chain key in flight and payments could be attributed to
  chain zero. Direct calls are now refused; payments must enter through
  `recordPayment`.
- **Silent `uint128` truncation.** A transfer value above `uint128` wrapped: a
  value of `2^128 + price` truncated to exactly the price and settled a plan for
  free, and `2^128` truncated to zero while still passing the non-zero guard.
  Oversized values are now rejected rather than truncated.
- **Self-transfers counted as payments.** A log where sender and recipient are
  the same address moves no money, but bought service time. Now refused.

### Low

- Service term could overflow the timestamp and switch a device off; the term is
  now capped and the arithmetic saturates.
- Payments smaller than one day's service were recorded as money but bought zero
  time. Service now accrues in seconds, which matters because small sums are the
  norm in this market.
- A plan opened with a zero id left its collection address indistinguishable from
  an unregistered one, breaking uniqueness. Rejected.
- Payments arriving after a plan was paid off reported success and vanished.
  Settled plans now stop accepting payments.
- Admin could be transferred to the zero address, freezing the contract. Rejected.

### Found only by running against live data

The first version rejected an entire transaction if it carried a token it did not
recognise. That looked defensive and was in fact a denial of service against
genuine payments: real payment transactions are frequently swaps routing several
assets to the same address, and **four of the first six real payments failed
because of it.** Unrecognised transfers are now skipped instead, which is safe
because they can never credit a plan. Eight of eight succeeded afterwards.

No unit test would have caught this. It surfaced because the precompile and
decoder are never mocked; they are exercised on CC3 against real Ethereum
mainnet transactions.

### Verified sound

- **Payment accounting.** `paid` never exceeds the price, never decreases, and
  the settlement latch is irreversible. Held by a fuzz invariant over payment
  sequences.
- **Replay protection.** The `queryId` binds a proof to (chain, block,
  transaction index). Resubmitting a proven payment is rejected, confirmed on
  chain, not only in tests.
- **Griefing via direct `execute()`.** A revert rolls back the processed-query
  write, so an attacker cannot burn a query id to block a legitimate payment.

## 3. Key handling

The signing key lives only in an external environment file on the build server,
is never printed, and never touches a workstation that holds other keys. The
repository contains no key material and no `.env`.
