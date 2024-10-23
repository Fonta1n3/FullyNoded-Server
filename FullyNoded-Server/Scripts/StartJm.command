#!/bin/sh

#  StartJm.command
#  FullyNoded-Server
#
#  Created by Peter Denton on 10/18/24.
#
TAG_NAME=$1
SSL_DIR="/Users/$(whoami)/Library/Application Support/joinmarket/ssl"

# check if ssl directory and cert exist first, if not create them
if [ ! -d "$SSL_DIR" ]; then
  echo "$SSL_DIR does not exist, creating it."
  mkdir "$SSL_DIR"
  echo "Creating SSL self signed cert."
  cd "$SSL_DIR"
  openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -sha256 -days 3650 -nodes -subj "/C=/ST=/L=/O=/OU=/CN=joinmarket"
fi

echo "cd /Users/$(whoami)/.fullynoded/JoinMarket/joinmarket-$TAG_NAME"
cd /Users/$(whoami)/.fullynoded/JoinMarket/joinmarket-$TAG_NAME
echo "source jmvenv/bin/activate"
source jmvenv/bin/activate
echo "cd scripts"
cd scripts
echo "python jmwalletd.py"
python jmwalletd.py

