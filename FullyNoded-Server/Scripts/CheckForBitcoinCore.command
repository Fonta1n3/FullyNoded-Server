#!/bin/sh


if [ -d ~/.fullynoded/BitcoinCore ]; then
      sudo -u $(whoami) ~/.fullynoded/BitcoinCore/$PREFIX/bin/bitcoind -version
else
  echo "Bitcoin not installed"
fi

exit 1