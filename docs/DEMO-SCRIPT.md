# Demo video script (about 2.5 minutes)

Screen recording only. No face, no voice needed; captions carry it. Keep the
terminal clean: no absolute paths, no other windows, notifications off.

The story to land: **a relative abroad pays, and a device on the other side of
the world keeps working, with nobody in the middle deciding whether it did.**

## Before you press record

Everything below runs on the build server. Nothing is signed on a workstation.

**1. Send the payment that will go live on camera.** The second Sepolia lantern
is reserved for this. It is open at 12 USDC in four installments of 3, with
nothing paid, so the page reads **Not started**.

```bash
cd ~/hackathon-ctc/remit-to-own/relay && set -a && . ~/.rto-sepolia.env && set +a && WALLET_ENV=~/.ato-wallet.env venv/bin/python send_payment.py --chainkey 1 --token 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 --to "$COLLECTOR2_ADDRESS" --amount 3 --submit
```

**2. Wait about eight minutes.** Attestation trails Sepolia by roughly forty
blocks. Do not send this days ahead: `watch_plan` scans a window of recent
blocks, so a transfer left unproven overnight sits thousands of blocks back and
the scan will not reach it.

**3. Serve the page and open the reserved plan.**

```bash
python -m http.server 5330 --directory ~/hackathon-ctc/remit-to-own/web
```

Then open `http://localhost:5330/?theme=light&lang=en#0xd221e0f424111cf15571bbea04012d2c319c9fc07b628e9455b22cc950cf68d2`

`?theme=light` or `?theme=dark` pins the theme so it cannot change mid take, and
`?lang=` pins the language. English is the default.

## Shot list

**0:00 Hook.** Open the delivery truck plan. It shows Working, 77,557.73 USDC
still to pay of 80,000, paid up until 28 September, and the Ethereum address to
pay into. Caption:

> This truck is still on the road because a relative sent 342 dollars, then
> 1,500, then 599. Every one of those is a real Ethereum payment, proven on
> Creditcoin.

**0:20 The problem.** Deck slide 2. Caption:

> Buying on installments is normal. So is a relative abroad paying for you.
> The two do not fit, because the shop and the money are on different ledgers.

**0:35 The idea.** Deck slide 3. Let it sit for three seconds.

**0:50 The live moment.** This is the shot the whole video exists for. Have the
reserved lantern on screen reading **Not started**, then run the relay in a
second window:

```bash
cd ~/hackathon-ctc/remit-to-own/relay && WALLET_ENV=~/.ato-wallet.env venv/bin/python watch_plan.py --plan 0xd221e0f424111cf15571bbea04012d2c319c9fc07b628e9455b22cc950cf68d2 --chainkey 1 --blocks 200 --submit
```

It prints `device=LOCKED ... not started, no payment proven yet`, finds the
transfer on Sepolia, proves it, and prints `device=WORKING ... 30d left`.
Within twelve seconds the page finds it too: an alert slides in, the state
flips to Working, and the payment joins the record. Nobody touched the page.
Caption:

> Nobody pushed this. The page is watching the chain, and the payment announced
> itself.

**1:30 Prove it is real.** Put the Sepolia transaction on Sepolia Etherscan next
to the CC3 explorer showing the `recordPayment` transaction. Caption:

> Left: the payment on Ethereum. Right: the same payment, proven on Creditcoin.
> Nobody in between.

**1:50 Read the result independently.**

```bash
cast call 0x59FEF8771Da4248b89F7D6052b9d10fDfb13D223 "isActive(bytes32)(bool)" 0xd221e0f424111cf15571bbea04012d2c319c9fc07b628e9455b22cc950cf68d2 --rpc-url https://rpc.cc3-testnet.creditcoin.network
```

Caption: "The merchant reads one boolean. That is the whole integration."

**2:05 Paid off.** Switch to the motorcycle plan. Every one of the twelve
installment blocks is filled, the balance is zero, and the address to pay into is
gone because there is nothing left to pay. Caption:

> When the price is covered, the buyer owns it outright and it never locks again.

**2:20 Both chains.** Deck slide 6, or the plan row on the page. Caption:

> Sepolia for a payment we can make on demand. Ethereum mainnet for real
> traffic, which is what found the bug that killed four proofs in six.

**2:30 Close.** Deck slide 10. Contract address on screen.

## Checklist

- The reserved plan `0xd221e0f4…68d2` still reads **Not started**. If it does
  not, a payment has already been proven into it and there is no off to on shot
  left. Open a fresh one with `open_plan.py`.
- The first lantern `0x51d036c6…c803` is already working on a proven payment, so
  it carries real history if you want a second example.
- Addresses and keys live in `~/.rto-sepolia.env` on the build server, mode 0600.
  Never show that file.
- Faucet balance non zero on both chains. A proof costs a fraction of a cent, so
  this is only about not hitting zero.
- Two windows: the page, and one terminal. Nothing else, and no personal account
  anywhere on screen.
- Alerts stay up for twenty seconds, long enough to narrate.
- Terminal font readable at 720p. Window title and paths not revealing.
- Deck open as a PDF in its own window for the slide cuts.
