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
export LIGHTNING_VERSION=v24.05

function installDependencies() {
    echo "Installing lightning dependencies..."
    
    if ! [ -d $CELLAR_PATH/autoconf ]; then
        echo "Installing autoconf..."
        sudo -u $(whoami) $BREW_PATH install autoconf
    else
        echo "autoconf already installed"
    fi
    
    if ! [ -d $CELLAR_PATH/automake ]; then
        echo "Installing automake..."
        sudo -u $(whoami) $BREW_PATH install automake
    else
        echo "automake already installed"
    fi
    
    if ! [ -d $CELLAR_PATH/libtool ]; then
        echo "Installing libtool..."
        sudo -u $(whoami) $BREW_PATH install libtool
    else
        echo "libtool already installed"
    fi
    
    if ! [ -d $CELLAR_PATH/python3 ]; then
        echo "Installing python3..."
        sudo -u $(whoami) $BREW_PATH install python3
    else
        echo "python3 already installed"
    fi
    
    if ! [ -d $CELLAR_PATH/gnu-sed ]; then
        echo "Installing gnu-sed..."
        sudo -u $(whoami) $BREW_PATH install gnu-sed
    else
        echo "gnu-sed already installed"
    fi
    
    if ! [ -d $CELLAR_PATH/gettext ]; then
        echo "Installing gettext..."
        sudo -u $(whoami) $BREW_PATH install gettext
    else
        echo "gettext already installed"
    fi
    
    if ! [ -d $CELLAR_PATH/libsodium ]; then
        echo "Installing libsodium..."
        sudo -u $(whoami) $BREW_PATH install libsodium
    else
        echo "libsodium already installed"
    fi
    
    if ! [ -d $CELLAR_PATH/sqlite ]; then
        echo "Installing sqlite..."
        sudo -u $(whoami) $BREW_PATH install sqlite
    else
        echo "sqlite already installed"
    fi
    
    if ! [ -d $CELLAR_PATH/pyenv ]; then
        echo "Installing pyenv..."
        sudo -u $(whoami) $BREW_PATH reinstall pyenv
    else
        echo "pyenv already installed"
    fi
}


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
    sudo -u $(whoami) $BREW_PATH install core-lightning
    exit 1
}

#installDependencies
configureLightning
installLightning

