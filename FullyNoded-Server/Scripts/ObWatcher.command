#!/bin/sh

#  ObWatcher.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 11/13/24.
#
TAG_NAME=$1
cd /Users/$(whoami)/.fullynoded/JoinMarket/joinmarket-$TAG_NAME
echo "source jmvenv/bin/activate"
source jmvenv/bin/activate
echo "cd scripts/obwatch"
cd scripts/obwatch
echo "pip3 install matplotlib"
pip3 install matplotlib
echo "python3 ob-watcher.py"
python3 ob-watcher.py
