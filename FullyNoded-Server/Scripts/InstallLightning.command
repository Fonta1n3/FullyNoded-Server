#!/bin/sh

#  InstallLightning.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 9/5/24.
#

RPC_USER=$1
RPC_PASSWORD=$2
DATA_DIR="$3"
PREFIX=$4
NETWORK=$5


export BREW_PATH=/opt/homebrew/bin/brew
export CELLAR_PATH=/opt/homebrew/Cellar


function configureLightning () {
CONFIG="alias=FullyNoded-Server\n\
plugin-dir=/opt/homebrew/Cellar/core-lightning/24.08.1/libexec/c-lightning/plugins\n\
subdaemon=channeld:/opt/homebrew/Cellar/core-lightning/24.08.1/libexec/c-lightning/lightning_channeld\n\
subdaemon=closingd:/opt/homebrew/Cellar/core-lightning/24.08.1/libexec/c-lightning/lightning_closingd\n\
subdaemon=connectd:/opt/homebrew/Cellar/core-lightning/24.08.1/libexec/c-lightning/lightning_connectd\n\
subdaemon=gossipd:/opt/homebrew/Cellar/core-lightning/24.08.1/libexec/c-lightning/lightning_gossipd\n\
subdaemon=hsmd:/opt/homebrew/Cellar/core-lightning/24.08.1/libexec/c-lightning/lightning_hsmd\n\
subdaemon=onchaind:/opt/homebrew/Cellar/core-lightning/24.08.1/libexec/c-lightning/lightning_onchaind\n\
subdaemon=openingd:/opt/homebrew/Cellar/core-lightning/24.08.1/libexec/c-lightning/lightning_openingd\n\
bitcoin-rpcpassword="$RPC_PASSWORD"\n\
bitcoin-rpcuser="$RPC_USER"\n\
bitcoin-cli=/Users/$(whoami)/.fullynoded/BitcoinCore/"$PREFIX"/bin/bitcoin-cli\n\
bitcoin-datadir="$DATA_DIR"\n\
network="$NETWORK"\n\
log-file=/Users/$(whoami)/.lightning/lightning.log\n\
log-level=debug:plugin\n\
experimental-offers\n\
fetchinvoice-noconnect\n\
disable-plugin=clnrest\n\
plugin=/opt/homebrew/Cellar/core-lightning/24.08.1/libexec/c-lightning/plugins/clnrest-rs/clnrest-rs\n\
clnrest-port=18765\n\
clnrest-protocol=HTTP\n\
daemon"

    
    if ! [ -d ~/.lightning ]; then
        echo "Creating ~/.lightning directory..."
        mkdir ~/.lightning
    else
        echo "~/.lightning directory already exists"
    fi
    
    
    if ! test -f ~/.lightning/config; then
        echo "Create ~/.lightning/config"
        touch ~/.lightning/config
        echo "$CONFIG" > ~/.lightning/config
    else
        echo "~/.lightning config already exists..."
    fi
    
    if ! test -f ~/.lightning/lightning.log; then
        echo "Create ~/.lightning/lightning.log"
        touch ~/.lightning/lightning.log
    else
        echo "~/.lightning/lightning.log already exists..."
    fi
    
    echo "Core Lightning configuration complete, next step installation."
}

function installLightning () {
    sudo -u $(whoami) $BREW_PATH reinstall core-lightning
    cd /opt/homebrew/Cellar/core-lightning/24.08.1/libexec/c-lightning/plugins
    git clone https://github.com/daywalker90/clnrest-rs.git
    cd clnrest-rs
    $BREW_PATH install rust
    cargo build --release
    mv target/release/clnrest-rs /opt/homebrew/Cellar/core-lightning/24.08.1/libexec/c-lightning/plugins/clnrest-rs
    chmod +x /opt/homebrew/Cellar/core-lightning/24.08.1/libexec/c-lightning/plugins/clnrest-rs/clnrest-rs
    exit 1
}

configureLightning
installLightning

