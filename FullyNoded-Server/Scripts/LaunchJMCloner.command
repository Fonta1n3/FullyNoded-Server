#!/bin/sh

#  LaunchJMCloner.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 2/25/25.
#  

INSTALL_SCRIPT_PATH="/Users/$(whoami)/.fullynoded/cloneJMMaster.sh"
LOG="/Users/$(whoami)/.fullynoded/fullynoded.log"
touch $INSTALL_SCRIPT_PATH
echo "\"$(cd "$(dirname "$0")"; pwd)/CloneJMMaster.command\" | tee -a $LOG" > $INSTALL_SCRIPT_PATH
chmod +x $INSTALL_SCRIPT_PATH
open -a Terminal $INSTALL_SCRIPT_PATH
exit 1
