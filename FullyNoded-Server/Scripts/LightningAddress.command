#!/bin/sh

#  LightningAddress.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/7/24.
#
/opt/homebrew/bin/ngrok config add-authtoken xxx
/opt/homebrew/bin/ngrok tcp 9735
exit 1
