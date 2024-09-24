#!/bin/sh

#  CheckForLightning.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 9/5/24.
#

if command -v /usr/local/bin/lightningd &> /dev/null; then
    echo "Installed"
    exit 1
else
    echo "Not installed"
    exit 1
fi


