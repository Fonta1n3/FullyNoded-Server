#!/bin/sh

#  StartKnots.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 7/14/25.
#  

ulimit -n 188898
if [ "$CHAIN" == "main" ]; then
    sudo -u $(whoami) ~/.fullynoded/BitcoinKnots/$PREFIX/bin/bitcoind -datadir="$DATADIR" -daemon
else
    sudo -u $(whoami) ~/.fullynoded/BitcoinKnots/$PREFIX/bin/bitcoind -chain=$CHAIN -datadir="$DATADIR" -daemon
fi
exit 1
