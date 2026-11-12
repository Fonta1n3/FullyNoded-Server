#!/bin/sh

#  InstallLightning.command
#  FullyNoded-Server
#
#  Installs Core Lightning with Homebrew, or updates it when it's already installed. Fully Noded
#  Server writes lightningd's config itself (~/.lightning/fns-server.conf) and never touches the
#  node's data. The result goes in ~/.fullynoded/lightning-install.status for the app to show.

STATUS_FILE="$HOME/.fullynoded/lightning-install.status"
mkdir -p "$HOME/.fullynoded"
echo "running" > "$STATUS_FILE"

BREW=""
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then BREW="$candidate"; break; fi
done
if [ -z "$BREW" ]; then
    echo "Homebrew isn't installed. Install it from Fully Noded Server first."
    echo "failed Homebrew isn't installed." > "$STATUS_FILE"
    exit 1
fi

if "$BREW" list --versions core-lightning >/dev/null 2>&1; then
    echo "Updating Core Lightning with Homebrew. This can take a few minutes..."
    "$BREW" upgrade core-lightning
else
    echo "Installing Core Lightning with Homebrew. This can take a few minutes..."
    "$BREW" install core-lightning
fi
RESULT=$?

PREFIX="$("$BREW" --prefix core-lightning 2>/dev/null)"
if [ -x "$PREFIX/bin/lightningd" ]; then
    echo ""
    echo "Core Lightning $("$PREFIX/bin/lightningd" --version) is ready."
    echo "You can close this window and go back to Fully Noded Server."
    echo "ok" > "$STATUS_FILE"
else
    echo ""
    echo "Homebrew didn't finish (exit code $RESULT). Scroll up for the reason."
    echo "failed Homebrew exited with code $RESULT. Its Terminal window shows why." > "$STATUS_FILE"
fi
