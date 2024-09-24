#!/bin/sh

#  StopLightning.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 9/11/24.
#  
sudo -u $(whoami) /usr/local/bin/lightning-cli stop
