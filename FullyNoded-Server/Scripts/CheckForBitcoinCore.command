#!/bin/sh

#  CheckForBitcoinCore.command
#  StandUp
#
#  Created by Peter on 19/11/19.
#  Copyright © 2019 Blockchain Commons, LLC
if [ -d ~/.gordian/BitcoinCore ]; then
      sudo -u $(whoami) ~/.gordian/BitcoinCore/$PREFIX/bin/bitcoind -version
else
  echo "Bitcoin not installed"
fi

exit 1
