"""RemitToOwn relay.

Watches a plan's collection address on the source chain, proves each incoming
stablecoin transfer with the Attestcoin Protocol, and credits the plan on
Creditcoin so the device stays switched on.

    python watch_plan.py --plan 0x<planId> --chainkey 3 --blocks 60 --submit

The private key is read from an external env file, never printed, and only used
on the build server.
"""
import json
import os
import time
import urllib.request
from pathlib import Path

from eth_account import Account
from web3 import Web3

CC3_RPC = os.environ.get("CREDITCOIN_RPC_URL", "https://rpc.cc3-testnet.creditcoin.network")
CC3_CHAIN_ID = 102031
PROOF_HOSTS = [
    "https://prover.cc3-testnet.creditcoin.network",
    "https://proof-gen-api.cc3-testnet.creditcoin.network",
]

ROOT = Path(__file__).resolve().parent.parent
ABI_PATH = ROOT / "contracts" / "out" / "RemitToOwn.sol" / "RemitToOwn.json"
DEPLOY_PATH = ROOT / "contracts" / "deployments" / "cc3-testnet.json"


def http_get_json(url: str, timeout: int = 30, retries: int = 4):
    """GET with retry and backoff. The testnet prover is intermittently flaky."""
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "remit-to-own-relay/1"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode())
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(2 * (i + 1))
    raise RuntimeError(f"GET failed after {retries} tries: {url}\n{last}")


def attested_height(chainkey: int) -> int:
    for host in PROOF_HOSTS:
        try:
            return int(http_get_json(f"{host}/api/v1/attested-height/{chainkey}")["attestedHeight"])
        except Exception:  # noqa: BLE001
            continue
    raise RuntimeError("could not read attested height from any proof host")


def fetch_proof(chainkey: int, tx_hash: str) -> dict:
    errs = []
    for host in PROOF_HOSTS:
        try:
            return http_get_json(f"{host}/api/v1/proof-by-tx/{chainkey}/{tx_hash}")
        except Exception as e:  # noqa: BLE001
            errs.append(str(e))
    raise RuntimeError("all proof hosts failed: " + " | ".join(errs))


def load_wallet():
    wallet_env = Path(os.environ.get("WALLET_ENV", str(Path.home() / ".ato-wallet.env")))
    key = None
    for line in wallet_env.read_text().splitlines():
        line = line.strip()
        if line.startswith("DEV_WALLET_KEY="):
            key = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not key:
        raise RuntimeError(f"DEV_WALLET_KEY not found in {wallet_env}")
    if not key.startswith("0x"):
        key = "0x" + key
    return Account.from_key(key)


def make_web3() -> Web3:
    return Web3(Web3.HTTPProvider(CC3_RPC, request_kwargs={"timeout": 60}))


def get_contract(w3: Web3, address: str | None = None):
    if not address:
        address = json.loads(DEPLOY_PATH.read_text())["remitToOwn"]
    abi = json.loads(ABI_PATH.read_text())["abi"]
    return w3.eth.contract(address=Web3.to_checksum_address(address), abi=abi)


def submit_payment(w3: Web3, rto, acct, chainkey: int, tx_hash: str) -> dict:
    """Prove one source-chain stablecoin transfer and credit its plan."""
    tip = attested_height(chainkey)
    proof = fetch_proof(chainkey, tx_hash)
    height = int(proof["headerNumber"])
    if height > tip:
        raise RuntimeError(f"block {height} not yet attested (tip {tip})")

    siblings = [(Web3.to_bytes(hexstr=s["hash"]), bool(s["isLeft"])) for s in proof["merkleProof"]["siblings"]]
    fn = rto.functions.recordPayment(
        chainkey,
        height,
        Web3.to_bytes(hexstr=proof["txBytes"]),
        Web3.to_bytes(hexstr=proof["merkleProof"]["root"]),
        siblings,
        Web3.to_bytes(hexstr=proof["continuityProof"]["lowerEndpointDigest"]),
        [Web3.to_bytes(hexstr=r) for r in proof["continuityProof"]["roots"]],
    )

    # Gas: estimate, then floor at 600k. The published fallback formula
    # under-estimates the precompile cost by roughly 60 percent.
    try:
        gas = max(int(fn.estimate_gas({"from": acct.address}) * 1.35), 600_000)
    except Exception:  # noqa: BLE001
        gas = 900_000

    base = w3.eth.get_block("latest").get("baseFeePerGas", w3.to_wei(0.5, "gwei"))
    tip_fee = w3.to_wei(1, "gwei")
    tx = fn.build_transaction({
        "from": acct.address,
        "nonce": w3.eth.get_transaction_count(acct.address, "pending"),
        "chainId": CC3_CHAIN_ID,
        "gas": gas,
        "maxFeePerGas": base * 2 + tip_fee,
        "maxPriorityFeePerGas": tip_fee,
    })
    signed = acct.sign_transaction(tx)
    raw = getattr(signed, "raw_transaction", None) or signed.rawTransaction
    cc3_hash = w3.eth.send_raw_transaction(raw)
    rcpt = w3.eth.wait_for_transaction_receipt(cc3_hash, timeout=300)

    out = {"cc3Tx": cc3_hash.hex(), "status": rcpt.status, "gasUsed": rcpt.gasUsed}
    if rcpt.status == 1:
        for ev in rto.events.PaymentProven().process_receipt(rcpt):
            a = ev["args"]
            out.update({
                "planId": a["planId"].hex(), "payer": a["payer"],
                "amount": a["amount"] / 1e6, "paidTotal": a["paidTotal"] / 1e6,
                "activeUntil": a["activeUntil"],
            })
        out["settled"] = len(rto.events.PlanSettled().process_receipt(rcpt)) > 0
    return out
