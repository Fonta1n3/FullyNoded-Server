#!/bin/sh

#  IncreaseGapLimit.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 11/11/24.
#
TAG_NAME=$1
GAP_AMOUNT=$2
WALLET_NAME=$3

cd /Users/$(whoami)/.fullynoded/JoinMarket/joinmarket-$TAG_NAME
echo "source jmvenv/bin/activate"
source jmvenv/bin/activate
echo "cd scripts"
cd scripts
echo "python3 wallet-tool.py -g $GAP_AMOUNT $WALLET_NAME"
python3 wallet-tool.py -g $GAP_AMOUNT $WALLET_NAME

