#!/bin/sh

#  CloneJMMaster.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 2/25/25.
#  

mkdir /Users/$(whoami)/.fullynoded/JoinMarket
cd /Users/$(whoami)/.fullynoded/JoinMarket
git clone https://github.com/JoinMarket-Org/joinmarket-clientserver.git
cd joinmarket-clientserver
./install.sh --without-qt
# Only run wallet-tool.py if no joinmarket.cfg exists.
if [ ! -f "/Users/$(whoami)/Library/Application Support/joinmarket/joinmarket.cfg" ]; then
    source jmvenv/bin/activate
    cd scripts
    python3 wallet-tool.py generate
    deactivate
fi
echo "Join Market Install complete. This is master branch, bugs may be present!"
exit 1
