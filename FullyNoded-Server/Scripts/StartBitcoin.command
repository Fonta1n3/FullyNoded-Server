#!/bin/sh

ulimit -n 188898
if [ "$CHAIN" == "main" ]; then
    sudo -u $(whoami) ~/.fullynoded/BitcoinCore/$PREFIX/bin/bitcoind -datadir="$DATADIR" -daemon
else
    sudo -u $(whoami) ~/.fullynoded/BitcoinCore/$PREFIX/bin/bitcoind -chain=$CHAIN -datadir="$DATADIR" -daemon
fi
exit 1
