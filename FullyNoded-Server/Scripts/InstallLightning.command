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

echo "RPC_USERx: $RPC_USER"
echo "RPC_PASSWORDx: $RPC_PASSWORD"
echo "DATA_DIRx: $DATA_DIR"
echo "PREFIXx: $PREFIX"

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
    
#    if ! [ -d $CELLAR_PATH/mako ]; then
#        echo "Installing mako..."
#        sudo -u $(whoami) $BREW_PATH install mako
#    else
#        echo "mako already installed"
#    fi
    
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
plugin-dir=/usr/local/libexec/c-lightning/plugins\n\
subdaemon=channeld:/usr/local/libexec/c-lightning/lightning_channeld\n\
subdaemon=closingd:/usr/local/libexec/c-lightning/lightning_closingd\n\
subdaemon=connectd:/usr/local/libexec/c-lightning/lightning_connectd\n\
subdaemon=gossipd:/usr/local/libexec/c-lightning/lightning_gossipd\n\
subdaemon=hsmd:/usr/local/libexec/c-lightning/lightning_hsmd\n\
subdaemon=onchaind:/usr/local/libexec/c-lightning/lightning_onchaind\n\
subdaemon=openingd:/usr/local/libexec/c-lightning/lightning_openingd\n\
bitcoin-rpcpassword="$RPC_PASSWORD"\n\
bitcoin-rpcuser="$RPC_USER"\n\
bitcoin-cli=/Users/$(whoami)/.fullynoded/BitcoinCore/"$PREFIX"/bin/bitcoin-cli\n\
bitcoin-datadir="$DATA_DIR"\n\
network=bitcoin\n\
proxy=127.0.0.1:9050\n\
bind-addr=127.0.0.1:9735\n\
log-file=/Users/$(whoami)/.lightning/lightning.log\n\
log-level=debug:plugin"
    
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
    #sudo -u $(whoami) /usr/local/bin/brew install core-lightning
    #sudo -u $(whoami) /opt/homebrew/bin/brew install core-lightning
    ln -s /opt/homebrew/Cellar/gettext/0.20.1/bin/xgettext /usr/local/opt
    export PATH="/usr/local/opt:$PATH"
    
    export LDFLAGS="-L/usr/local/opt/sqlite/lib"
    export CPPFLAGS="-I/usr/local/opt/sqlite/include"
    
    # If Apple Silicon (for now we are only Apple Silicon)
    export CPATH=/opt/homebrew/include
    export LIBRARY_PATH=/opt/homebrew/lib
    
    # If you need Python 3.x for mako (or get a mako build error):
    #got an error for the below so asked chatgpt
    #echo -e 'if command -v pyenv 1>/dev/null 2>&1; then\n  eval "$(pyenv init -)"\nfi' >> ~/.bash_profile
    #she came up with this
    printf 'if command -v pyenv 1>/dev/null 2>&1; then\n  eval "$(pyenv init -)"\nfi\n' >> ~/.bash_profile

    source ~/.bash_profile
    pyenv install 3.8.10
    pip install --upgrade pip
    pip install poetry
    python3 -m pip install mako
    
    git clone https://github.com/ElementsProject/lightning.git
    cd lightning
    
    git checkout $LIGHTNING_VERSION
    
    poetry install
    # Need to pass an arg here to ensure experimental features (bolt12) works.
    ./configure
    poetry run make
    
    # maybe need this for silicon? not clear.. testing.
    #sudo PATH="/usr/local/opt:$PATH"  LIBRARY_PATH=/opt/homebrew/lib CPATH=/opt/homebrew/include make install
    make install
    
#    sudo -u $(whoami) ~/.standup/lightning/configure
#    /usr/bin/make
    
    exit 1
}

installDependencies
configureLightning
installLightning

