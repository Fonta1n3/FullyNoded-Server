#!/bin/sh

#  StartLightning.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 9/11/24.
#

sudo -u $(whoami) /opt/homebrew/Cellar/core-lightning/24.11/bin/lightningd
exit 1

