#!/bin/sh

#  StopJm.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/18/24.
#
osascript -e 'tell application "Terminal" to close (every window whose name contains "startJoinMarket.sh")' & exit
