#!/bin/sh

#  CheckForLightning.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 9/5/24.
#  
#if ! command -v ~/.fullynoded/lightning/lightningd/lightningd &> /dev/null; then
#    echo "lightning not installed"
#    exit 1
#else
#    echo "lightning installed"
#    exit 1
#fi
sudo -u $(whoami) /opt/homebrew/bin/brew list
exit
