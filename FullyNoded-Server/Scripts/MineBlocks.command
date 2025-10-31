#!/bin/sh

#  MineBlocks.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/31/25.
#  
# ------------------------------------------------------------
# Mines 101 regtest blocks, each to a *different* new address.
# Usage:
#   RPCWALLET=mywallet ./MineBlocks.command
# ------------------------------------------------------------

set -euo pipefail

# ---- 1. Check input -------------------------------------------------
if [[ -z "${RPCWALLET:-}" ]]; then
  echo "Error: RPCWALLET environment variable is not set."
  echo "Usage: RPCWALLET=mywallet $0"
  exit 1
fi

# ---- 2. Helper: get a fresh bech32 address -------------------------
get_new_address() {
  sudo -u $(whoami) ~/.fullynoded/BitcoinCore/$PREFIX/bin/bitcoin-cli -regtest -datadir="$DATADIR" -rpcwallet="$RPCWALLET" getnewaddress "" "bech32"
}

# ---- 3. Start timing ------------------------------------------------
START=$(date +%s.%N)
#echo "Mining 100 blocks (one per new address) using wallet '$RPCWALLET'..."

# ---- 4. Mine 101 blocks --------------------------------------------
for i in $(seq 1 100); do
  ADDR=$(get_new_address)
  # generatetoaddress returns an array with the single block hash
  #$(bitcoin-cli -regtest -rpcwallet="$RPCWALLET" generatetoaddress 1 "$ADDR")
$(sudo -u $(whoami) ~/.fullynoded/BitcoinCore/$PREFIX/bin/bitcoin-cli -regtest -datadir="$DATADIR" -rpcwallet="$RPCWALLET" generatetoaddress 1 "$ADDR")
  #printf "Block %3d → %s  (hash: %s)\n" "$i" "$ADDR"
done

# ---- 5. Finish ------------------------------------------------------
END=$(date +%s.%N)
ELAPSED=$(echo "$END - $START" | bc)
echo "Done! 100 blocks mined in $ELAPSED seconds."
