#!/bin/sh


if pgrep "bitcoind"; then
    echo 'Running';
else
    echo "Stopped";
fi
exit 1
