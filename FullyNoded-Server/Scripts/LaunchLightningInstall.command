#!/bin/sh

#  LaunchLightningInstall.command
#  FullyNoded-Server
#
#  Runs InstallLightning.command in a Terminal window, so Homebrew's progress (and any password
#  prompt) is visible.

SCRIPT_PATH="$HOME/.fullynoded/installLightning.sh"
mkdir -p "$HOME/.fullynoded"
echo "\"$(cd "$(dirname "$0")"; pwd)/InstallLightning.command\"" > "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"
open -a Terminal "$SCRIPT_PATH"
exit 0
