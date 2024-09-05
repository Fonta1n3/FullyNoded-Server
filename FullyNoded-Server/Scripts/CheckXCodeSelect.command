#!/bin/sh


if [[ $(command -v xcode-select) == "" ]]; then
    echo "XCode select not installed"
else
    echo "XCode select installed"
fi

exit 1
