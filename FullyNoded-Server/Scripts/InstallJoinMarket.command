#!/bin/sh

#  InstallJoinMarket.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/14/24.
#  
function unpackTarball() {
#  if [ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]; then
#    echo "Hashes match"
#    echo "Unpacking $BINARY_NAME"
#    tar -zxvf $BINARY_NAME
#    
#    echo "Codesigning binaries..."
#    for i in ~/.fullynoded/BitcoinCore/bitcoin-$VERSION/bin/* ; do codesign -s - $i; done
#        
#    echo "Installation complete, you can close this terminal."
#    exit 1
#  else
#    echo "Hashes do not match! Terminating..."
#    exit 1
#  fi

# MARK TODO: Handle signature verification before unpacking!
    echo "Unpacking $BINARY_NAME"
    cd /Users/$(whoami)/.fullynoded/JoinMarket
    #gpg --verify joinmarket-v0.9.11.tar.gz.asc joinmarket-v0.9.11.tar.gz
    #tar -zxvf joinmarket-v0.9.11.tar.gz
    mkdir joinmarket-v0.9.11 && tar -zxvf joinmarket-v0.9.11.tar.gz -C joinmarket-v0.9.11 --strip-components 1
    echo "Tarball Unpacked"
    rm -rf joinmarket-v0.9.11.tar.gz
    rm -rf joinmarket-v0.9.11.tar.gz.asc
    cd joinmarket-v0.9.11
    ./install.sh --without-qt
    exit 1
}

unpackTarball
