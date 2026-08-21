#!/usr/bin/env bash
# Deploy EvmV1Decoder + RemitToOwn to Creditcoin CC3 testnet.
# The private key is read from an external file (never committed, never printed).
#   Usage: WALLET_ENV=~/.ato-wallet.env bash scripts/deploy.sh
set -euo pipefail

WALLET_ENV="${WALLET_ENV:-$HOME/.ato-wallet.env}"
RPC="${CREDITCOIN_RPC_URL:-https://rpc.cc3-testnet.creditcoin.network}"
DECODER_PATH="node_modules/@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol:EvmV1Decoder"
OUT_DIR="deployments"
OUT_FILE="$OUT_DIR/cc3-testnet.json"

command -v forge >/dev/null || { echo "forge not on PATH"; exit 1; }
[ -f "$WALLET_ENV" ] || { echo "wallet env not found: $WALLET_ENV"; exit 1; }

# Load key from the external file only.
set -a; . "$WALLET_ENV"; set +a
KEY="${DEV_WALLET_KEY:?DEV_WALLET_KEY missing}"
case "$KEY" in 0x*) ;; *) KEY="0x$KEY" ;; esac
ADDR="${DEV_WALLET_ADDRESS:-unknown}"

echo "Deployer: $ADDR"
echo "RPC:      $RPC"

deployed_to() { python3 -c 'import json,sys; print(json.load(sys.stdin)["deployedTo"])'; }
tx_hash()     { python3 -c 'import json,sys; print(json.load(sys.stdin)["transactionHash"])'; }

echo "==> Deploying EvmV1Decoder library ..."
DEC_JSON=$(forge create --broadcast --rpc-url "$RPC" --private-key "$KEY" "$DECODER_PATH" --json)
DEC_ADDR=$(printf '%s' "$DEC_JSON" | deployed_to)
echo "    EvmV1Decoder: $DEC_ADDR"

echo "==> Deploying RemitToOwn (linked) ..."
CP_JSON=$(forge create --broadcast --rpc-url "$RPC" --private-key "$KEY" \
  --libraries "$DECODER_PATH:$DEC_ADDR" \
  src/RemitToOwn.sol:RemitToOwn --json)
CP_ADDR=$(printf '%s' "$CP_JSON" | deployed_to)
CP_TX=$(printf '%s' "$CP_JSON" | tx_hash)
echo "    RemitToOwn: $CP_ADDR"

mkdir -p "$OUT_DIR"
cat > "$OUT_FILE" <<EOF
{
  "network": "cc3-testnet",
  "chainId": 102031,
  "rpc": "$RPC",
  "deployer": "$ADDR",
  "evmV1Decoder": "$DEC_ADDR",
  "remitToOwn": "$CP_ADDR",
  "remitToOwnDeployTx": "$CP_TX",
  "explorer": "https://creditcoin-testnet.blockscout.com/address/$CP_ADDR"
}
EOF
echo "==> Wrote $OUT_FILE"
cat "$OUT_FILE"
