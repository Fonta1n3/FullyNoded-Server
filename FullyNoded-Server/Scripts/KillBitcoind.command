#!/bin/sh

#  KillProcess.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/2/24.
#
pid=$(ps -fe | grep 'bitcoind' | grep -v grep | awk '{print $2}')
if [[ -n $pid ]]; then
    kill $pid
    echo "Its dead"
else
    echo "Does not exist"
fi
