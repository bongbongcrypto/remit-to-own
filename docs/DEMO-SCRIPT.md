# Demo video script (about 2.5 minutes)

Screen recording only. No face, no voice needed; captions carry it. Keep the
terminal clean: no absolute paths, no other windows, notifications off.

The story to land: **a relative abroad pays, and a device on the other side of
the world stays switched on, with nobody in the middle deciding whether it did.**

## Shot list

**0:00 Hook, the device page.** Open `web/index.html` on the delivery truck plan.
It shows RUNNING, 1,719.07 of 50,000 USDC paid, 25 days left, and the Ethereum
address to pay. Caption:

> This truck is running because a relative sent 23 dollars, then 1,490, then 97,
> then 107. Every one of those is a real Ethereum payment, proven on Creditcoin.

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

**2:05 Paid off.** Switch the page to the motorcycle plan: OWNED, 100 percent,
"yours, permanently". Caption:

> When the price is covered, the device is theirs and never switches off again.

**2:20 The alert (Telegram).** Show the bot pushing a payment alert, then
`/device 0x…`. Caption: "The family hears the moment it lands."

**2:30 Close.** Deck slide 10. Contract address on screen.

## Prep checklist

- A plan with unproven payments waiting, so the OFF to ON transition happens live
  on camera. Open a fresh plan shortly before recording and do not prove it yet.
- Price the plan high enough that one large transfer does not settle it
  immediately, or the arc collapses into a single step.
- Faucet balance topped up. Each proof costs a fraction of a cent, so this is
  only about having a non-zero balance.
- Telegram bot running with a dedicated token, demo chat subscribed via `/start`.
- Terminal font large enough to read at 720p. Window title and paths not
  revealing.
- Deck open as a PDF in a separate window for the slide cuts.
