#!/usr/bin/env python3
"""Watch a plan's collection address and prove every payment that lands there.

    python watch_plan.py --plan 0x<planId> --chainkey 3 --blocks 60 [--submit]

Reads the plan's collector straight from the contract, scans the source chain
for stablecoin transfers into it, and (with --submit) proves each one so the
device on Creditcoin stays switched on.
"""
import argparse
import json
import os
import time
import urllib.request
from datetime import datetime, timezone

import rto_relay as R
from web3 import Web3

TRANSFER_SIG = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
# Public endpoints rate-limit hard and each has its own quirks, so every chunk
# is tried against the whole list before it is given up on.
SOURCE_RPCS = {
    1: [os.environ.get("SEPOLIA_RPC", "https://sepolia.drpc.org"),
        "https://ethereum-sepolia-rpc.publicnode.com"],
    3: [os.environ.get("MAINNET_RPC", "https://eth.drpc.org"),
        "https://ethereum-rpc.publicnode.com",
        "https://rpc.ankr.com/eth"],
}


def _rpc(url, method, params, timeout=45):
    req = urllib.request.Request(
        url,
        data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(),
        headers={"Content-Type": "application/json", "User-Agent": "remit-to-own/1"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        d = json.loads(r.read().decode())
    if "error" in d:
        raise RuntimeError(f"{method}: {d['error']}")
    return d["result"]


def _addr_topic(addr: str) -> str:
    return "0x" + addr.lower().replace("0x", "").rjust(64, "0")


def scan_incoming(chainkey: int, token: str, collector: str, frm: int, to: int, window: int = 6):
    """Stablecoin transfers into the collector, chunked for public-RPC limits."""
    urls = SOURCE_RPCS[chainkey]
    flt_topics = [TRANSFER_SIG, None, _addr_topic(collector)]
    out, skipped = [], 0
    start = frm
    while start <= to:
        end = min(start + window - 1, to)
        got, last = None, None
        for url in urls:
            try:
                got = _rpc(url, "eth_getLogs", [{
                    "address": token, "fromBlock": hex(start), "toBlock": hex(end),
                    "topics": flt_topics,
                }])
                break
            except Exception as e:  # noqa: BLE001
                last = e
                time.sleep(0.4)
        if got is None:
            skipped += 1
            print(f"  [scan] blocks {start}..{end} skipped: {str(last)[:60]}")
        else:
            out.extend(got)
        start = end + 1
        time.sleep(0.3)
    if skipped:
        print(f"  [scan] {skipped} chunk(s) skipped, coverage is partial")
    return out


def show(rto, plan_id: bytes):
    buyer, merchant, collector, price, paid, active_until, active, settled = rto.functions.getPlan(plan_id).call()
    left = rto.functions.timeRemaining(plan_id).call()
    due = rto.functions.amountRemaining(plan_id).call()
    if settled:
        print(f"  device=OWNED  paid={paid/1e6:,.2f}/{price/1e6:,.2f} USDC  "
              f"owned outright, never switches off")
        return
    state = "ON" if active else "OFF"
    until = datetime.fromtimestamp(active_until, timezone.utc).strftime("%Y-%m-%d") if active else "-"
    print(f"  device={state}  paid={paid/1e6:,.2f}/{price/1e6:,.2f} USDC  "
          f"due={due/1e6:,.2f}  runs {left//86400}d (until {until})")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True, help="planId (0x…32 bytes)")
    ap.add_argument("--chainkey", type=int, default=3)
    ap.add_argument("--blocks", type=int, default=60)
    ap.add_argument("--submit", action="store_true")
    ap.add_argument("--max-submit", type=int, default=6)
    args = ap.parse_args()

    w3 = R.make_web3()
    rto = R.get_contract(w3)
    plan_id = Web3.to_bytes(hexstr=args.plan)

    p = rto.functions.plans(plan_id).call()
    buyer, merchant, chainkey, token, collector = p[0], p[1], p[2], p[3], p[4]
    if not p[10]:
        raise SystemExit("no such plan")
    print(f"plan      : {args.plan}")
    print(f"collector : {collector} (chainkey {chainkey})")
    print(f"token     : {token}")
    print("before    :")
    show(rto, plan_id)

    tip = R.attested_height(args.chainkey)
    frm = tip - args.blocks + 1
    print(f"[scan] blocks {frm}..{tip} (attested)")
    logs = scan_incoming(args.chainkey, token, collector, frm, tip)
    txs = []
    for lg in logs:
        h = lg["transactionHash"]
        if h not in txs:
            txs.append(h)
    print(f"[scan] {len(txs)} incoming payment tx(s)")
    for i, tx in enumerate(txs):
        print(f"  payment[{i}] {tx}")

    if not args.submit:
        print("[dry run] pass --submit to prove these on Creditcoin")
        return

    acct = R.load_wallet()
    print(f"[prove] relayer {acct.address}")
    for tx in txs[:args.max_submit]:
        # Once the price is covered the contract stops accepting payments, so
        # there is nothing left to prove and no fee worth spending.
        if rto.functions.getPlan(plan_id).call()[7]:
            print("  = plan is paid off, nothing further to prove")
            break
        try:
            res = R.submit_payment(w3, rto, acct, args.chainkey, tx)
            if res["status"] == 1 and "amount" in res:
                tag = "  -> PAID OFF, device is now owned" if res.get("settled") else ""
                print(f"  + {tx[:14]}.. {res['amount']:,.2f} USDC  total {res['paidTotal']:,.2f}{tag}")
            else:
                print(f"  ! {tx[:14]}.. status={res['status']}")
        except Exception as e:  # noqa: BLE001
            print(f"  ! {tx[:14]}.. {str(e)[:110]}")

    print("after     :")
    show(rto, plan_id)


if __name__ == "__main__":
    main()
