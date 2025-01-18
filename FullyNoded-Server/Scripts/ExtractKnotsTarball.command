#!/bin/sh

#  ExtractKnotsTarball.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 1/15/25.
#  

function unpackTarball() {
  if [ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]; then
    echo "Hashes match"
    echo "Unpacking $BINARY_NAME"
    tar -zxvf $BINARY_NAME
    
    echo "Codesigning binaries..."
    for i in ~/.fullynoded/BitcoinKnots/bitcoin-$VERSION/bin/* ; do codesign -s - $i; done
        
    echo "Installation complete, you can close this terminal."
    exit 1
  else
    echo "Hashes do not match! Terminating..."
    exit 1
  fi
}

cd /Users/fontaine/.fullynoded/BitcoinKnots

