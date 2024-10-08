#!/bin/sh

#  LightningNodeId.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/7/24.
#  

sudo -u $(whoami) /usr/local/bin/lightning-cli getinfo
exit 1
