#!/bin/sh

sudo -u $(whoami) ~/.fullynoded/BitcoinCore/$PREFIX/bin/bitcoin-cli -chain=$CHAIN -datadir="$DATADIR" stop
exit 1
