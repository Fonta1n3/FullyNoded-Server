#!/bin/sh

#  InstallJoinMarket.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/14/24.
#

TAG_NAME=$1
AUTHOR=$2

echo "Unpacking $TAG_NAME"
cd /Users/$(whoami)/.fullynoded/JoinMarket
/opt/homebrew/bin/gpg --import $AUTHOR.asc
/opt/homebrew/bin/gpg --verify joinmarket-$TAG_NAME.tar.gz.asc joinmarket-$TAG_NAME.tar.gz
mkdir joinmarket-$TAG_NAME && tar -zxvf joinmarket-$TAG_NAME.tar.gz -C joinmarket-$TAG_NAME --strip-components 1
cd joinmarket-$TAG_NAME
./install.sh --without-qt
# Only run wallet-tool.py if no joinmarket.cfg exists.
if [ ! -f "/Users/$(whoami)/Library/Application Support/joinmarket/joinmarket.cfg" ]; then
    source jmvenv/bin/activate
    cd scripts
    python3 wallet-tool.py generate
    deactivate
fi
echo "Join Market Install complete."
exit 1
