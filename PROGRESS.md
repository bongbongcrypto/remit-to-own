# PROGRESS

Last updated 2026-08-25.

## Goal

Win BUIDL CTC 2026 Fall (Creditcoin / Credit Labs, DoraHacks) with Remit-to-Own,
solo. Submission closes 2026-09-06, results 2026-09-18.

Remit-to-Own is pay-as-you-go device financing across two chains. A relative
abroad sends USDC on Ethereum, the Attestcoin Protocol proves that payment to
Creditcoin, and the device at home stays unlocked for the days that payment bought. Cover
the price and it belongs to the buyer. Nothing is ever lent, so there is no
default to chase.

## Decisions

- **2026-08-21. Never lend.** Payment buys service time instead of credit. Three
  earlier concepts died on the question of what happens when a borrower stops
  paying. This one has no answer to give because it never asks the question.
- **2026-08-21. One collection address per plan.** A stablecoin transfer carries
  no memo, so the address is what tells the contract whose payment it is. This is
  what payment processors already do.
- **2026-08-21. Issuing collectors is an operator action.** A proof shows a
  transfer happened; nothing on chain shows who an address belongs to. Treating
  the second as following from the first was the critical audit finding.
- **2026-08-22. Skip unrecognised transfers rather than reverting.** Real payment
  transactions are often swaps carrying several tokens. Reverting killed four of
  six live payments. Only live mainnet data surfaced this.
- **2026-08-22. Telegram is optional, the web page is the surface.** The owner
  will not show a personal Telegram account on the demo video, and the page needs
  no token and no backend.
- **2026-08-23. The page follows the off-grid financing industry's own
  disclosure rules** (GOGLA, CGAP, 60 Decibels) rather than dashboard instinct.
  Balance owed is the headline, progress is counted in instalments, and a
  switched-off device is amber and never red. Reasoning in `docs/TECHNICAL.md`
  2.4; do not restyle those without reading it.
- **2026-08-23. History from the indexer, live tail from the node.** The CC3 node
  caps `eth_getLogs` at a ten second query and serialises parallel chunks, so
  scanning history over RPC cannot work. Blockscout answers it in one request.
- **2026-08-24. Submit in English, gloss it in Korean.** The announcement, rules,
  form fields and Discord are all English, and one judge who cannot read Korean
  is a loss with no matching gain. The page offering four languages is a product
  feature, not the submission language.
- **2026-08-25. A paid-off plan keeps the same card.** Inverting the surface was
  meant to mark the moment; the first person to see it read it as a different
  page. The content already says it, so only the card edge changes now.

## Progress

- ✅ Contract live on CC3 testnet, `0x59FEF8771Da4248b89F7D6052b9d10fDfb13D223`,
  linked decoder `0x21f3e26A827F2e89c0F99B46da033F4b05D57fd8`.
- ✅ 38 Foundry tests passing: 23 behaviour, 15 audit regression, one per attack.
- ✅ Adversarial audit run, ten findings closed, each with a regression test.
- ✅ End to end proven on **both source chains**. Eight plans, fourteen proven
  payments, three paid off. The Sepolia lantern is ours from the collection
  address to the payment, so the off to on sequence runs on demand; the mainnet
  plans meet live traffic, which is what surfaced the multi-token bug.
- ✅ `relay/open_plan.py` and `relay/send_payment.py`. Both estimate gas rather
  than guess it, and a receipt with a status other than one raises instead of
  printing success. The first run of open_plan reverted twice and reported both
  as fine, which is how that got found.
- ✅ Relay and plan watcher, multi endpoint failover, signing only on the build
  server.
- ✅ Device page rebuilt: self discovering plans, instalment progress, payment
  record with running balances, live alerts, Korean, Japanese, Chinese, English,
  WCAG AA verified in light and dark, every state.
- ✅ Adversarial QA on the page, relay and bot (2026-08-23). Thirteen defects
  found and closed, none of them by clicking around: a percentage that read 3.0
  where the truth was 3.1, a plan with no payment reporting that it stopped in
  1970, a saturated service term printing "Invalid Date", the record announcing
  "no payment has been proven" when it had merely failed to read, a copy button
  claiming a copy the clipboard refused, keyboard focus thrown off the card once
  a minute by a pointless repaint, amber and the toast body failing contrast, an
  unescaped link in the payment record, a missing heading level, Korean breaking
  "30일" after the digits, a missing favicon, and the same date defect again in
  both the relay and the Telegram bot. Verified by recomputing all six plans and
  thirteen payment rows independently from raw RPC and the indexer, eighteen
  adversarial render cases, a contrast sweep of every text node in light, dark
  and layout from 320 to 1024 pixels.
- ✅ Docs current: `README.md`, `docs/TECHNICAL.md`, `docs/SECURITY.md`,
  `docs/DEMO-SCRIPT.md`, `docs/deck.html` and a regenerated ten slide
  `docs/deck.pdf`.
- 📋 **Record the demo video.** Follow `docs/DEMO-SCRIPT.md`. Use the second
  Sepolia lantern, `0xd221e0f4…68d2`, which is open at 12 USDC with nothing paid
  and reads Not started. Send one instalment, wait about eight minutes for
  attestation, then prove it on camera. Do not send days ahead: the scan covers
  a window of recent blocks only. Completion criterion: a video of about 2.5
  minutes, no personal account visible in any frame, showing the off to on
  transition and the alert arriving on its own.
- 📋 **Korean gloss for anything submitted.** The deck is glossed in
  `contests/2026-creditcoin-hackathon/DECK-KO.md`. Do the same for the DoraHacks
  form answers before they are submitted: owner cannot put their name to text
  they cannot read.
- 📋 **Submit on DoraHacks.** Completion criterion: submission accepted before
  2026-09-06, with the repo, video and deck attached. Real name and nationality
  go to the organiser privately and never into anything public.

## Files

- `contracts/src/RemitToOwn.sol` the whole mechanism, derives vendored `USCBase`
- `contracts/test/RemitToOwnAudit.t.sol` one regression test per closed attack
- `relay/rto_relay.py`, `relay/watch_plan.py` proof fetch and submit
- `web/index.html` the device page, no build step, no backend
- `docs/TECHNICAL.md` integration, threat model, measured field notes
- `docs/DEMO-SCRIPT.md` shot list and prep checklist for the video

## Blockers

None technical. Both remaining items are the owner's to do.

Worth knowing before touching the live setup: the CC3 node rejects an
`eth_getLogs` range beyond roughly 30,000 blocks and gets worse under parallel
requests, attestation lags the source chain by about nine minutes by design, and
the signing key lives only in an external env file on the build server.
