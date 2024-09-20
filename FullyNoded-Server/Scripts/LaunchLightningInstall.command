#!/bin/sh

#  LaunchLightningInstall.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 9/5/24.
#

INSTALL_SCRIPT_PATH="/Users/$(whoami)/.fullynoded/installLightning.sh"
LOG="/Users/$(whoami)/.fullynoded/fullynoded.log"
touch $INSTALL_SCRIPT_PATH
echo "\"$(cd "$(dirname "$0")"; pwd)/InstallLightning.command\" $RPC_USER $RPC_PASSWORD $DATA_DIR $PREFIX | tee -a $LOG" > $INSTALL_SCRIPT_PATH
chmod +x $INSTALL_SCRIPT_PATH
open -a Terminal $INSTALL_SCRIPT_PATH

echo "RPC_USER: $RPC_USER"
echo "RPC_PASSWORD: $RPC_PASSWORD"
echo "DATA_DIR: $DATA_DIR"
echo "PREFIX: $PREFIX"
exit 1

#open "$(cd "$(dirname "$0")"; pwd)"/InstallLightning.command
#exit 1
