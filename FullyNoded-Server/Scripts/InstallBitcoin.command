#!/bin/sh


BINARY_NAME=$1
VERSION=$2

function installBitcoin() {
  cd ~/.fullynoded/BitcoinCore
  echo "Checking sha256 checksums $BINARY_NAME against provided SHA256SUMS"
  ACTUAL_SHA=$(shasum -a 256 $BINARY_NAME | awk '{print $1}')
  EXPECTED_SHA=$(grep $BINARY_NAME SHA256SUMS | awk '{print $1}')

  echo "See two hashes (they should match):"
  echo $ACTUAL_SHA
  echo $EXPECTED_SHA
  
  if [ "$ACTUAL_SHA" != "" ]; then
    export ACTUAL_SHA
    export EXPECTED_SHA
    unpackTarball
  else
    echo "No hash exists, Bitcoin Core download failed..."
    exit 1
  fi
}

function unpackTarball() {
  if [ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]; then
    echo "Hashes match"
    echo "Unpacking $BINARY_NAME"
    tar -zxvf $BINARY_NAME
    
    echo "Codesigning binaries..."
    for i in ~/.fullynoded/BitcoinCore/bitcoin-$VERSION/bin/* ; do codesign -s - $i; done
        
    echo "Installation complete, you can close this terminal."
    exit 1
  else
    echo "Hashes do not match! Terminating..."
    exit 1
  fi
}

installBitcoin
