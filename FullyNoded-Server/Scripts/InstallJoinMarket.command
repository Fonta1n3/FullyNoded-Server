#!/bin/sh

#  InstallJoinMarket.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/14/24.
#

TAG_NAME=$1
AUTHOR=$2

function unpackTarball() {
    echo "Unpacking $TAG_NAME"
    cd /Users/$(whoami)/.fullynoded/JoinMarket
    /opt/homebrew/bin/gpg --import $AUTHOR.asc
    /opt/homebrew/bin/gpg --verify joinmarket-$TAG_NAME.tar.gz.asc joinmarket-$TAG_NAME.tar.gz
    mkdir joinmarket-$TAG_NAME && tar -zxvf joinmarket-$TAG_NAME.tar.gz -C joinmarket-$TAG_NAME --strip-components 1
    cd joinmarket-$TAG_NAME
    ./install.sh --without-qt --disable-secp-check
    source jmvenv/bin/activate
    cd scripts
    python wallet-tool.py generate
    echo "Install complete."
    exit 1
}

unpackTarball
