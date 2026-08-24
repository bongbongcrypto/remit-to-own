#!/usr/bin/env python3
"""Send a stablecoin payment to a plan's collection address, on a testnet.

    python send_payment.py --chainkey 1 --token 0x1c7D... \
        --to 0xAF2b... --amount 6 [--submit]

This stands in for the relative abroad. In production nobody runs this: the
family sends from whatever wallet or exchange they already use, and the
contract never learns how the transfer was made, only that it happened.

Testnet only. It signs with the dev wallet, which is the same key the relay
uses, and refuses to run against a chain that is not a testnet.
"""
import argparse
import json
import os
import time
import urllib.request

import rto_relay as R
from web3 import Web3

DECIMALS = 6
TRANSFER = "0xa9059cbb"   # transfer(address,uint256)

SOURCE_RPCS = {
    1: [os.environ.get("SEPOLIA_RPC", "https://ethereum-sepolia-rpc.publicnode.com"),
        "https://sepolia.drpc.org"],
}
CHAIN_IDS = {1: 11155111}


def rpc(chainkey: int, method: str, params, timeout: int = 40):
    last = None
    for url in SOURCE_RPCS[chainkey]:
        try:
            req = urllib.request.Request(
                url,
                data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(),
                headers={"Content-Type": "application/json", "User-Agent": "remit-to-own/1"},
            )
            with urllib.request.urlopen(req, timeout=timeout) as r:
                d = json.loads(r.read().decode())
            if "error" in d:
                last = d["error"]
                continue
            return d["result"]
        except Exception as e:  # noqa: BLE001
            last = e
    raise RuntimeError(f"{method} failed: {str(last)[:90]}")


def balance_of(chainkey, token, who) -> int:
    data = "0x70a08231" + who[2:].lower().rjust(64, "0")
    return int(rpc(chainkey, "eth_call", [{"to": token, "data": data}, "latest"]), 16)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--chainkey", type=int, default=1, help="1 Sepolia. Testnets only")
    ap.add_argument("--token", required=True)
    ap.add_argument("--to", required=True, help="the plan's collection address")
    ap.add_argument("--amount", type=float, required=True, help="whole units, e.g. 6 for 6 USDC")
    ap.add_argument("--submit", action="store_true")
    args = ap.parse_args()

    if args.chainkey not in SOURCE_RPCS:
        raise SystemExit("this tool only sends on testnets; mainnet payments are made by real people")

    token = Web3.to_checksum_address(args.token)
    to = Web3.to_checksum_address(args.to)
    acct = R.load_wallet()
    amount = int(round(args.amount * 10 ** DECIMALS))

    gas_bal = int(rpc(args.chainkey, "eth_getBalance", [acct.address, "latest"]), 16)
    tok_bal = balance_of(args.chainkey, token, acct.address)
    print(f"sender    : {acct.address}")
    print(f"gas       : {gas_bal / 1e18:,.6f} ETH")
    print(f"token     : {tok_bal / 10 ** DECIMALS:,.2f}  sending {args.amount:,.2f}")
    print(f"to        : {to}")

    if tok_bal < amount:
        raise SystemExit("not enough of that token; top up from the faucet first")
    if gas_bal == 0:
        raise SystemExit("no gas on the source chain; top up from the faucet first")
    if not args.submit:
        print("[dry run] pass --submit to send it")
        return

    data = TRANSFER + to[2:].lower().rjust(64, "0") + f"{amount:064x}"
    nonce = int(rpc(args.chainkey, "eth_getTransactionCount", [acct.address, "pending"]), 16)
    latest = rpc(args.chainkey, "eth_getBlockByNumber", ["latest", False])
    base = int(latest.get("baseFeePerGas", "0x3b9aca00"), 16)
    tip = 1_500_000_000

    tx = {
        "type": 2, "chainId": CHAIN_IDS[args.chainkey], "nonce": nonce,
        "to": token, "value": 0, "data": data, "gas": 90_000,
        "maxFeePerGas": base * 2 + tip, "maxPriorityFeePerGas": tip,
    }
    signed = acct.sign_transaction(tx)
    raw = getattr(signed, "raw_transaction", None) or signed.rawTransaction
    h = rpc(args.chainkey, "eth_sendRawTransaction", ["0x" + raw.hex().replace("0x", "")])
    print(f"  sent {h}")

    for _ in range(60):
        time.sleep(5)
        r = rpc(args.chainkey, "eth_getTransactionReceipt", [h])
        if r:
            blk = int(r["blockNumber"], 16)
            if int(r["status"], 16) != 1:
                raise SystemExit(f"  transfer REVERTED in block {blk:,}, tx {h}")
            print(f"  mined in block {blk:,}")
            print(f"\n  attestation lags the source chain by about forty blocks, so wait a few")
            print(f"  minutes, then prove it with:")
            print(f"    python watch_plan.py --plan 0x<planId> --chainkey {args.chainkey} "
                  f"--blocks 200 --submit")
            return
    print("  still pending; check the explorer")


if __name__ == "__main__":
    main()
