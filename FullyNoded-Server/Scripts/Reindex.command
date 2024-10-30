#!/bin/sh

#  Reindex.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/28/24.
#  
ulimit -n 188898
if [ "$CHAIN" == "main" ]; then
    sudo -u $(whoami) ~/.fullynoded/BitcoinCore/$PREFIX/bin/bitcoind -datadir="$DATADIR" -daemon -reindex
else
    sudo -u $(whoami) ~/.fullynoded/BitcoinCore/$PREFIX/bin/bitcoind -chain=$CHAIN -datadir="$DATADIR" -daemon -reindex
fi
exit 1
