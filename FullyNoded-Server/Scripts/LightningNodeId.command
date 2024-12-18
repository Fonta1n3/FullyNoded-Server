#!/bin/sh

#  LightningNodeId.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/7/24.
#  

sudo -u $(whoami) /opt/homebrew/Cellar/core-lightning/24.11/bin/lightning-cli getinfo
exit 1
