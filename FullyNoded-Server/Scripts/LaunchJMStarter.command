#!/bin/sh

#  LaunchJMStarter.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/18/24.
#  
SCRIPT_PATH="/Users/$(whoami)/.fullynoded/startJoinMarket.sh"
LOG="/Users/$(whoami)/.fullynoded/fullynoded.log"
touch $SCRIPT_PATH
echo "\"$(cd "$(dirname "$0")"; pwd)/StartJm.command\" $TAG_NAME | tee -a $LOG" > $SCRIPT_PATH
chmod +x $SCRIPT_PATH
open -a Terminal $SCRIPT_PATH
exit 1
