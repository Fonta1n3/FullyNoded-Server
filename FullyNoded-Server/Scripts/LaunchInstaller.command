#!/bin/sh


INSTALL_SCRIPT_PATH="/Users/$(whoami)/.fullynoded/installBitcoin.sh"
LOG="/Users/$(whoami)/.fullynoded/fullynoded.log"
touch $INSTALL_SCRIPT_PATH
echo "\"$(cd "$(dirname "$0")"; pwd)/InstallBitcoin.command\" $BINARY_NAME $VERSION | tee -a $LOG" > $INSTALL_SCRIPT_PATH
chmod +x $INSTALL_SCRIPT_PATH
open -a Terminal $INSTALL_SCRIPT_PATH
exit 1
