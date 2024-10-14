#!/bin/sh

#  LightningAddress.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/7/24.
#

/opt/homebrew/bin/ngrok config add-authtoken xx
touch ~/.fullynoded/ngrok.log
/opt/homebrew/bin/ngrok tcp 9735 --log ~/.fullynoded/ngrok.log --log-format json
exit 1
