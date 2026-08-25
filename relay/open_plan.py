#!/usr/bin/env python3
"""Open a financing plan on the RemitToOwn contract.

    python open_plan.py --label "solar-lantern-1" --chainkey 1 \
        --token 0x1c7D... --collector 0xAF2b... --buyer 0x... \
        --price 24 --installment 6 --days 30 [--trust] [--submit]

This is the merchant's action. It is restricted to the contract admin on
purpose: a proof shows that a transfer happened and nothing on chain shows who
an address belongs to, so an open registration would let anyone claim a busy
address as their collector. See docs/TECHNICAL.md section 4.
"""
import argparse

import rto_relay as R
from web3 import Web3

DECIMALS = 6


def plan_id(label: str) -> bytes:
    """A readable label makes a plan easy to find again; the chain keeps the hash."""
    return Web3.keccak(text="remit-to-own/plan/" + label)


def send(w3, acct, fn, label):
    """Estimate, send, and refuse to call a reverted receipt a success.

    A guessed gas limit is how the first attempt at this failed: setTrustedToken
    wants about 161k on CC3 and a hardcoded 120k ran out, which then cascaded
    into openPlan reverting on an untrusted token. Both printed success.
    """
    gas = int(fn.estimate_gas({"from": acct.address}) * 1.4)
    base = w3.eth.get_block("latest").get("baseFeePerGas", w3.to_wei(0.5, "gwei"))
    tip = w3.to_wei(1, "gwei")
    tx = fn.build_transaction({
        "from": acct.address,
        "nonce": w3.eth.get_transaction_count(acct.address, "pending"),
        "chainId": R.CC3_CHAIN_ID,
        "gas": gas,
        "maxFeePerGas": base * 2 + tip,
        "maxPriorityFeePerGas": tip,
    })
    signed = acct.sign_transaction(tx)
    raw = getattr(signed, "raw_transaction", None) or signed.rawTransaction
    h = w3.eth.send_raw_transaction(raw)
    r = w3.eth.wait_for_transaction_receipt(h, timeout=300)
    if r.status != 1:
        raise SystemExit(f"  {label} REVERTED, tx {h.hex()}, gas used {r.gasUsed:,} of {gas:,}")
    print(f"  {label} ok, gas {r.gasUsed:,}, tx {h.hex()}")
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", required=True, help="readable plan label, hashed to the planId")
    ap.add_argument("--chainkey", type=int, required=True, help="1 Sepolia, 3 Ethereum mainnet")
    ap.add_argument("--token", required=True, help="stablecoin accepted for this plan")
    ap.add_argument("--collector", required=True, help="this plan's own collection address")
    ap.add_argument("--buyer", required=True, help="the household that owns it once paid off")
    ap.add_argument("--price", type=float, required=True, help="full price, whole units")
    ap.add_argument("--installment", type=float, required=True, help="one installment, whole units")
    ap.add_argument("--days", type=int, default=30, help="days of service one installment buys")
    ap.add_argument("--trust", action="store_true", help="also accept this token on this chain")
    ap.add_argument("--submit", action="store_true", help="send, rather than print the plan")
    args = ap.parse_args()

    pid = plan_id(args.label)
    price = int(round(args.price * 10 ** DECIMALS))
    inst = int(round(args.installment * 10 ** DECIMALS))
    if inst <= 0 or price <= 0:
        raise SystemExit("price and installment must be positive")
    if inst > price:
        raise SystemExit("an installment cannot be larger than the price")

    w3 = R.make_web3()
    rto = R.get_contract(w3)
    token = Web3.to_checksum_address(args.token)
    collector = Web3.to_checksum_address(args.collector)
    buyer = Web3.to_checksum_address(args.buyer)

    print(f"label      : {args.label}")
    print(f"planId     : 0x{pid.hex()}")
    print(f"chainKey   : {args.chainkey}")
    print(f"token      : {token}")
    print(f"collector  : {collector}")
    print(f"buyer      : {buyer}")
    print(f"price      : {args.price:,.2f}  installment {args.installment:,.2f} buys {args.days} days"
          f"  ({price // inst} installments)")

    if rto.functions.plans(pid).call()[10]:
        raise SystemExit("that plan already exists")
    taken = rto.functions.collectorPlan(args.chainkey, collector).call()
    if int.from_bytes(taken, "big"):
        raise SystemExit(f"that collector is already bound to plan 0x{taken.hex()}")

    trusted = rto.functions.trustedToken(args.chainkey, token).call()
    print(f"token accepted on chainKey {args.chainkey}: {trusted}")
    if not trusted and not args.trust:
        raise SystemExit("token is not accepted yet; pass --trust to accept it")

    if not args.submit:
        print("[dry run] pass --submit to open it")
        return

    acct = R.load_wallet()
    admin = rto.functions.admin().call()
    if admin.lower() != acct.address.lower():
        raise SystemExit(f"only the admin can open a plan (admin is {admin})")

    if not trusted:
        send(w3, acct, rto.functions.setTrustedToken(args.chainkey, token, True),
             "accept token")

    send(w3, acct, rto.functions.openPlan(
        pid, buyer, args.chainkey, token, collector, price, inst, args.days), "open plan")
    print(f"\nwatch it with:\n  python watch_plan.py --plan 0x{pid.hex()} "
          f"--chainkey {args.chainkey} --blocks 200 --submit")


if __name__ == "__main__":
    main()
