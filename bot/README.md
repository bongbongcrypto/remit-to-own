# bot

Telegram bot for the buyer's side: it says the moment a relative's payment is
proven on Creditcoin, and how much longer the device runs.

```bash
BOT_TOKEN=<from @BotFather> python device_bot.py
```

Use a **dedicated** bot token, never a shared or personal one.

Commands:
- `/start` subscribe this chat to device alerts
- `/device 0x…` current status of a device
- `/plans` every plan on the contract

The alert loop polls CC3 for `PaymentProven` and `PlanSettled`. Chain reads,
message formatting, and event parsing are verifiable without a token; only the
live Telegram transport needs one.
