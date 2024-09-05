#!/bin/sh

#  IsLightningOn.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 9/5/24.
#  
#sudo -u $(whoami) ~/lightning/cli/lightning-cli getinfo
if pgrep "lightningd"; then
    echo 'Running';
else
    echo "Stopped";
fi
exit 1
