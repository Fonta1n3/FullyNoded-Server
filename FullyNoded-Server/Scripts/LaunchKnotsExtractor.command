#!/bin/sh

#  LaunchKnotsExtractor.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 1/21/25.
#  
INSTALL_SCRIPT_PATH="/Users/$(whoami)/.fullynoded/installKnots.sh"
LOG="/Users/$(whoami)/.fullynoded/fullynoded.log"
touch $INSTALL_SCRIPT_PATH
echo "\"$(cd "$(dirname "$0")"; pwd)/ExtractKnotsTarball.command\" $BINARY_NAME $VERSION | tee -a $LOG" > $INSTALL_SCRIPT_PATH
chmod +x $INSTALL_SCRIPT_PATH
open -a Terminal $INSTALL_SCRIPT_PATH
exit 1
