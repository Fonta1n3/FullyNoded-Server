#!/bin/sh

#  LaunchUpdateLightning.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 12/2/24.
#  
INSTALL_SCRIPT_PATH="/Users/$(whoami)/.fullynoded/updateLightning.sh"
LOG="/Users/$(whoami)/.fullynoded/fullynoded.log"
touch $INSTALL_SCRIPT_PATH
echo "\"$(cd "$(dirname "$0")"; pwd)/UpdateLightning.command\" $RPC_USER $RPC_PASSWORD $DATA_DIR $PREFIX $NETWORK | tee -a $LOG" > $INSTALL_SCRIPT_PATH
chmod +x $INSTALL_SCRIPT_PATH
open -a Terminal $INSTALL_SCRIPT_PATH
exit 1
