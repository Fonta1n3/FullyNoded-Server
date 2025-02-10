#!/bin/sh

#  RefreshJMConfig.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 2/7/25.
#
JM_DATADIR=$1
rm -f JM_DATADIR/joinmarket.cfg
cd /Users/$(whoami)/.fullynoded/
    source jmvenv/bin/activate
    cd scripts
    python3 wallet-tool.py generate
    deactivate
exit 1
