#!/bin/sh

#  UpdateLightning.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 12/2/24.
#
export BREW_PATH=/opt/homebrew/bin/brew
sudo -u $(whoami) $BREW_PATH upgrade core-lightning
