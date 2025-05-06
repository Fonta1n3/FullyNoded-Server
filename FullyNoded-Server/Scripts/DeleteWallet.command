#!/bin/sh

#  DeleteWallet.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 5/5/25.
#  

# Check if WALLET_NAME environment variable is set
#if [ -z "$WALLET_NAME" ]; then
#    echo "Error: WALLET_NAME environment variable is not set"
#    exit 1
#fi

# Check if WALLET_PATH environment variable is set
if [ -z "$WALLET_PATH" ]; then
    echo "Error: WALLET_PATH environment variable is not set"
    exit 1
fi

# Check if the directory exists
if [ -d "$WALLET_PATH" ]; then
    # Confirm deletion
    echo "Found directory at: $WALLET_PATH"
    read -p "Are you sure you want to delete the wallet directory? This action cannot be undone! (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$WALLET_PATH"
        if [ $? -eq 0 ]; then
            echo "Wallet directory deleted successfully"
        else
            echo "Error: Failed to delete wallet directory"
            exit 1
        fi
    else
        echo "Deletion cancelled"
        exit 0
    fi
else
    echo "Error: Wallet directory not found at $WALLET_PATH"
    exit 1
fi
