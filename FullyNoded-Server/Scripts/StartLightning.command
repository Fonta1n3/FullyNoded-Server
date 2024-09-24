#!/bin/sh

#  StartLightning.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 9/11/24.
#

sudo -u $(whoami) /usr/local/bin/lightningd
exit 1

