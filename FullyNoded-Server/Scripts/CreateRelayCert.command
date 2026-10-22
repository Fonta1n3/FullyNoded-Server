#!/bin/sh

#  CreateRelayCert.command
#  FullyNoded-Server
#
#  Creates the TLS identity of the Nostr Connect relay: an EC P-256 key and a self-signed
#  certificate (10 years), bundled as PKCS#12 for the app to import and store. Fully Noded pins
#  the certificate's SHA-256 from the pairing link, so no CA or hostname is involved.
#
#  Env: OUT_DIR (a new private folder), P12_PASSWORD.

set -e
cd "$OUT_DIR"
/usr/bin/openssl ecparam -name prime256v1 -genkey -noout -out key.pem
/usr/bin/openssl req -new -x509 -key key.pem -out cert.pem -days 3650 -sha256 -subj "/CN=Fully Noded Server Nostr Connect"
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -out identity.p12 -passout env:P12_PASSWORD -name "Fully Noded Server Nostr Connect"
/bin/rm -f key.pem cert.pem
echo "created"
