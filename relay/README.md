# relay

Watches a plan's collection address on the source chain, fetches an Attestcoin
inclusion proof for each incoming stablecoin transfer, and submits it to the
RemitToOwn contract on Creditcoin.

```bash
python watch_plan.py --plan 0x<planId> --chainkey 3 --blocks 60 --submit
```

`--chainkey 1` is Ethereum Sepolia, `3` is Ethereum mainnet.

- Reads the wallet key from `$WALLET_ENV` (default `~/.remit-to-own.env`), never prints it.
- Runs on the build server only; a key-bearing workstation does not sign.
- Retries and fails over between the two ProofBuilder hosts.
- Gas is floored at 600k: the published fallback formula under-estimates the
  precompile cost.
- Deps: `web3==7.16.0` (see `requirements.txt`).
