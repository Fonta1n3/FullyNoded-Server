#!/bin/sh

#  LaunchIncreaseGapLimit.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 11/11/24.
#  

SCRIPT_PATH="/Users/$(whoami)/.fullynoded/increaseGapLimit.sh"
LOG="/Users/$(whoami)/.fullynoded/fullynoded.log"
touch $SCRIPT_PATH
echo "\"$(cd "$(dirname "$0")"; pwd)/IncreaseGapLimit.command\" $TAG_NAME $GAP_AMOUNT $WALLET_NAME | tee -a $LOG" > $SCRIPT_PATH
chmod +x $SCRIPT_PATH
open -a Terminal $SCRIPT_PATH
exit 1
