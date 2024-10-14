#!/bin/sh

#  StopLightning.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 9/11/24.
#  
sudo -u $(whoami) /opt/homebrew/Cellar/core-lightning/24.08.1/bin/lightning-cli stop
exit 1
