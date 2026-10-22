#!/bin/sh

#  StopJm.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/18/24.
#
# Stop the wallet daemon itself (closing its Terminal window alone can leave it running, or
# stop at Terminal's "terminate running processes?" prompt), then close that window.
pkill -INT -u "$(id -u)" -f "jmwalletd.py" 2>/dev/null
sleep 2
pkill -TERM -u "$(id -u)" -f "jmwalletd.py" 2>/dev/null
osascript -e 'tell application "Terminal" to close (every window whose name contains "startJoinMarket.sh")' >/dev/null 2>&1 &
exit 0
