#!/bin/sh

#  InstallLightning.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 9/5/24.
#  


function installLightning () {
    #sudo -u $(whoami) /usr/local/bin/brew install core-lightning
        sudo -u $(whoami) /opt/homebrew/bin/brew install core-lightning
}

function configureLightning () {

CONFIG="alias=FullyNoded\n\
bitcoin-rpcpassword="$RPC_PASSWORD"\n\
bitcoin-rpcuser="$RPC_USER"\n\
bitcoin-cli=/Users/$USER/.fullynoded/BitcoinCore/"$PREFIX"/bin/bitcoin-cli\n\
bitcoin-datadir="$DATA_DIR"\n\
network=bitcoin\n\
proxy=127.0.0.1:9050\n\
bind-addr=127.0.0.1:9735\n\
log-file=/Users/$USER/.lightning/lightning.log\n\
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
    
    echo "Core Lightning installation complete!"
    exit 1

}


installLightning
configureLightning
