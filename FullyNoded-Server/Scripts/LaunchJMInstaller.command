#!/bin/sh

#  LaunchJMInstaller.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/14/24.
#  

INSTALL_SCRIPT_PATH="/Users/$(whoami)/.fullynoded/installJoinMarket.sh"
LOG="/Users/$(whoami)/.fullynoded/fullynoded.log"
touch $INSTALL_SCRIPT_PATH
echo "\"$(cd "$(dirname "$0")"; pwd)/InstallJoinMarket.command\" $TAG_NAME $AUTHOR | tee -a $LOG" > $INSTALL_SCRIPT_PATH
chmod +x $INSTALL_SCRIPT_PATH
open -a Terminal $INSTALL_SCRIPT_PATH
exit 1
