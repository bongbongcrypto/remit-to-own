#!/usr/bin/env python3
"""Remit-to-Own Telegram bot.

The buyer's side of the product. It tells you the moment a relative's payment is
proven on Creditcoin, how much longer the device runs, and when it becomes yours.

    BOT_TOKEN=<from @BotFather> python device_bot.py

Commands:
    /start              subscribe this chat to device alerts
    /device <planId>    current status of a device
    /plans              every plan on the contract

Use a DEDICATED bot token, never a shared or personal one.
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "relay"))
import rto_relay as R  # noqa: E402
from web3 import Web3  # noqa: E402

TOKEN = os.environ.get("BOT_TOKEN", "")
API = f"https://api.telegram.org/bot{TOKEN}"
SUBS_FILE = Path(os.environ.get("SUBS_FILE", str(Path(__file__).resolve().parent / "subscribers.json")))
STATE_FILE = Path(os.environ.get("BOT_STATE", str(Path(__file__).resolve().parent / ".bot_state.json")))
EXPLORER = "https://creditcoin-testnet.blockscout.com"

w3 = R.make_web3()
rto = R.get_contract(w3)

PAYMENT_TOPIC = w3.keccak(text="PaymentProven(bytes32,address,uint128,uint128,uint64)").hex()
SETTLED_TOPIC = w3.keccak(text="PlanSettled(bytes32,address,uint128)").hex()


def tg(method, **params):
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(f"{API}/{method}", data=data)
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.loads(r.read().decode())


def _load(path, default):
    try:
        return json.loads(path.read_text())
    except Exception:  # noqa: BLE001
        return default


def _save(path, obj):
    path.write_text(json.dumps(obj))


def usdc(v) -> str:
    return f"{v / 1e6:,.2f}"


def fmt_device(plan_hex: str) -> str:
    plan_id = Web3.to_bytes(hexstr=plan_hex)
    buyer, merchant, collector, price, paid, active_until, active, settled = rto.functions.getPlan(plan_id).call()
    if price == 0:
        return "No device found for that plan."

    pct = paid * 100 / price
    if settled:
        head = "🎉 <b>Paid off. The device is yours.</b>"
        line = "It never switches off again."
    elif active:
        left = rto.functions.timeRemaining(plan_id).call()
        until = R.fmt_until(active_until, "%d %b %Y")
        head = "🟢 <b>Device running</b>"
        line = (f"Runs {R.fmt_days(left)} more (until {until})." if until
                else f"Runs {R.fmt_days(left)} more.")
    elif active_until == 0:
        head = "⚪ <b>Not started yet</b>"
        line = "It runs as soon as the first payment is proven."
    else:
        head = "🔴 <b>Device switched off</b>"
        line = "A payment switches it straight back on."

    return (f"{head}\n{line}\n\n"
            f"Paid: <b>{usdc(paid)}</b> of {usdc(price)} USDC ({pct:.1f}%)\n"
            f"Still owed: {usdc(price - paid)} USDC\n\n"
            f"Pay from Ethereum to:\n<code>{collector}</code>\n"
            f"<a href=\"{EXPLORER}/address/{rto.address}\">contract</a>")


def cmd_device(chat_id, arg):
    arg = (arg or "").strip()
    if not (arg.startswith("0x") and len(arg) == 66):
        tg("sendMessage", chat_id=chat_id, text="Usage: /device 0x&lt;planId&gt;", parse_mode="HTML")
        return
    try:
        tg("sendMessage", chat_id=chat_id, text=fmt_device(arg), parse_mode="HTML",
           disable_web_page_preview="true")
    except Exception as e:  # noqa: BLE001
        tg("sendMessage", chat_id=chat_id, text=f"Lookup failed: {e}")


def cmd_plans(chat_id):
    n = rto.functions.planCount().call()
    if n == 0:
        tg("sendMessage", chat_id=chat_id, text="No plans yet.")
        return
    lines = ["<b>Devices on this contract</b>"]
    for i in range(min(n, 10)):
        pid = rto.functions.planIds(i).call()
        _b, _m, _c, price, paid, _au, active, settled = rto.functions.getPlan(pid).call()
        icon = "🎉" if settled else ("🟢" if active else "🔴")
        lines.append(f"{icon} {usdc(paid)}/{usdc(price)} USDC · <code>0x{pid.hex()[:16]}…</code>")
    tg("sendMessage", chat_id=chat_id, text="\n".join(lines), parse_mode="HTML")


def handle_update(u):
    msg = u.get("message") or u.get("channel_post")
    if not msg:
        return
    chat_id = msg["chat"]["id"]
    text = (msg.get("text") or "").strip()
    if text.startswith("/start"):
        subs = _load(SUBS_FILE, [])
        if chat_id not in subs:
            subs.append(chat_id)
            _save(SUBS_FILE, subs)
        tg("sendMessage", chat_id=chat_id, parse_mode="HTML",
           text=("🛵 <b>Remit-to-Own</b>\nYou will hear the moment a payment from abroad is proven.\n\n"
                 "/device 0x… status of a device\n/plans every device"))
    elif text.startswith("/device"):
        cmd_device(chat_id, text[len("/device"):])
    elif text.startswith("/plans"):
        cmd_plans(chat_id)


def poll_alerts(state):
    """Tell subscribers when a payment lands or a device is paid off."""
    latest = w3.eth.block_number
    frm = state.get("lastBlock", latest - 500) + 1
    if frm > latest:
        return
    try:
        logs = w3.eth.get_logs({"address": rto.address, "fromBlock": frm, "toBlock": latest})
    except Exception:  # noqa: BLE001
        return

    subs = _load(SUBS_FILE, [])
    for lg in logs:
        topic0 = lg["topics"][0].hex() if lg["topics"] else ""
        text = None
        if topic0 in (PAYMENT_TOPIC, PAYMENT_TOPIC.replace("0x", "")):
            ev = rto.events.PaymentProven().process_log(lg)
            a = ev["args"]
            until = R.fmt_until(a["activeUntil"], "%d %b %Y")
            runs = f"Device runs until {until}." if until else "Device is running."
            text = (f"💸 <b>Payment proven</b>\n"
                    f"{usdc(a['amount'])} USDC arrived from Ethereum.\n"
                    f"{runs}\n"
                    f"Paid so far: {usdc(a['paidTotal'])} USDC")
        elif topic0 in (SETTLED_TOPIC, SETTLED_TOPIC.replace("0x", "")):
            ev = rto.events.PlanSettled().process_log(lg)
            a = ev["args"]
            text = (f"🎉 <b>Paid off</b>\n"
                    f"{usdc(a['paidTotal'])} USDC covered in full.\n"
                    f"The device belongs to <code>{a['buyer']}</code> now.")
        if not text:
            continue
        for chat_id in subs:
            try:
                tg("sendMessage", chat_id=chat_id, text=text, parse_mode="HTML")
            except Exception:  # noqa: BLE001
                pass

    state["lastBlock"] = latest
    _save(STATE_FILE, state)


def main():
    if not TOKEN:
        raise SystemExit("BOT_TOKEN not set (create a dedicated bot via @BotFather)")
    print("device_bot up; contract", rto.address)
    state = _load(STATE_FILE, {})
    offset = 0
    while True:
        try:
            resp = tg("getUpdates", offset=offset, timeout=20)
            for u in resp.get("result", []):
                offset = u["update_id"] + 1
                handle_update(u)
        except Exception as e:  # noqa: BLE001
            print("poll error:", e)
            time.sleep(3)
        poll_alerts(state)


if __name__ == "__main__":
    main()
