# Demo video script (about 2.5 minutes)

Screen recording only. No face, no voice needed; captions carry it. Keep the
terminal clean: no absolute paths, no other windows, notifications off.

The story to land: **a relative abroad pays, and a device on the other side of
the world stays switched on, with nobody in the middle deciding whether it did.**

## Shot list

**0:00 Hook, the device page.** Serve `web/` and open the delivery truck plan.
It shows Running, 77,557.73 USDC still to pay of 80,000, paid up until 28
September, one filled block out of forty instalments, and the Ethereum address
to pay. Caption:

> This truck is running because a relative sent 342 dollars, then 1,500, then
> 599. Every one of those is a real Ethereum payment, proven on Creditcoin.

Pin the theme and language for the recording if you want them fixed:
`?theme=light` or `?theme=dark`, and the language buttons top right. The page
remembers the language you pick.

**0:20 The problem, one slide.** Deck slide 2. Caption:

> Buying on installments is normal. So is a relative abroad paying for you.
> The two do not fit, because the shop and the money are on different ledgers.

**0:35 The idea, one slide.** Deck slide 3. Let it sit for three seconds.

**0:50 Show a payment arriving (terminal).** Pick a plan with fresh payments and
run:

```
python watch_plan.py --plan 0x<planId> --chainkey 3 --blocks 25 --submit
```

Let the output play. It prints `device=OFF` before, finds real payment
transactions on Ethereum, proves each one, and prints `device=ON` after with the
days bought. Caption:

> The relay does not decide anything. It fetches a proof and hands it to the
> contract, which checks it against the Attestcoin precompile.

**1:30 Prove it is real (terminal).** Open one of the source transaction hashes
on Etherscan next to the CC3 explorer showing the `recordPayment` transaction.
Caption:

> Left: the payment on Ethereum. Right: the same payment, proven on Creditcoin.
> Nobody in between.

**1:50 Read the result independently (terminal).**

```
cast call 0x59FEF8771Da4248b89F7D6052b9d10fDfb13D223 \
  "getPlan(bytes32)(address,address,address,uint128,uint128,uint64,bool,bool)" \
  0x<planId> --rpc-url https://rpc.cc3-testnet.creditcoin.network
```

Caption: "The merchant reads one boolean. That is the whole integration."

**2:05 Paid off.** Switch the page to the motorcycle plan. The card inverts,
every one of the twelve instalment blocks is filled, and there is no longer an
address to pay to. Caption:

> When the price is covered, the device is theirs and never switches off again.

**2:20 The alert, live.** This is the shot worth setting up properly. Leave the
device page open on a plan with unproven payments waiting, run the relay in a
second window, and let the alert appear on its own: the amount arrives, the
status flips, the payment joins the list. Caption:

> Nobody pushed this. The page is watching the chain, and the payment announced
> itself.

**2:30 Close.** Deck slide 10. Contract address on screen.

## Prep checklist

- A plan with unproven payments waiting, so the off to on transition happens live
  on camera. Use the **Sepolia** plan for this, because its payments are ours and
  can be sent on demand rather than waiting for a stranger:

  ```
  # send an instalment, then wait about eight minutes for attestation
  python send_payment.py --chainkey 1     --token 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238     --to <collector> --amount 3 --submit
  ```

  Plan `0xd221e0f424111cf15571bbea04012d2c319c9fc07b628e9455b22cc950cf68d2`
  is reserved for this: a second solar lantern, 12 USDC in four instalments of
  3, with nothing paid, so it reads **Not started**. Send one instalment to
  `COLLECTOR2_ADDRESS`, wait about eight minutes for attestation, then prove it
  while the page is on screen. The first lantern plan,
  `0x51d036c6767b3e58073e30d9f3c4cbf7703bbf53de4113e4f51e212bced5c803`, is
  already running on a proven payment and shows real history. Addresses and keys
  live in `~/.rto-sepolia.env` on the build server, mode 0600.

  Do not pre-send days in advance. `watch_plan` scans a window of recent blocks,
  so a transfer left unproven for a day sits thousands of blocks back and the
  scan will not reach it without a very large and very slow range.
- Price the plan high enough that one large transfer does not settle it
  immediately, or the arc collapses into a single step.
- Faucet balance topped up. Each proof costs a fraction of a cent, so this is
  only about having a non-zero balance.
- Two windows: the device page, and a terminal for the relay. Nothing else is
  needed, and no personal account appears anywhere on screen.
- Alerts stay visible for twenty seconds, which is long enough to narrate.
- Terminal font large enough to read at 720p. Window title and paths not
  revealing.
- Deck open as a PDF in a separate window for the slide cuts.
