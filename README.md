# Fully Noded - Server
⚠️ Currently in Alpha, 🛠 WIP! Use at your own risk.

## Requirements
- macOS 14.0 - M1/M2/M3/M? Silicon - arm64
- Python 3.10 for Join Market, should be located at `/Library/Frameworks/Python.framework/Versions`, if not a good guide can be found [here](https://www.codingforentrepreneurs.com/guides/install-python-on-macos).

## Installation
On first use you will get a prompt about Fully Noded using an item on your keychain, this is an encryption key we create and use within the app to encrypt and decrypt sensitive data like your rpc password.

Currently only a testing version has been released, if you would like to help test it can be downloaded via github [releases](https://github.com/Fonta1n3/FullyNoded-Server/releases).

Download the latest release, verify the signatures (you can find instructions in the very first testing release) and open the dmg.

## What does it do?
Turns your macmini or macbook into a Bitcoin server powerhouse all powered locally via bash scripts and swift.
Use it to power apps like Fully Noded and Sparrow, sovereignly.

Installs and configures the following services on your mac:
- Bitcoin Core
- Core Lightning (configured with clnrest-rs)
- Join Market
- Integrates Tor and configures it to allow the HTTP REST API's for the above services to be reachable remotely without any need for port forwarding or complicated setups.

Core Lightning is reachable via LNSocket with Plasma (requires a public IP or VPN for port 9735 over TCP to be added to the `addr` config item). Plasma is clearnet only for now for use with LNSocket, Tor is coming soon for use with clnrest-rs.

## How?
⚠️ Tor is only used for hosting hidden services, not for installing software, a future release will include downloading Bitcoin Core and Join Market over Tor.

Fully Noded - Server runs a number of [bash scripts](https://github.com/Fonta1n3/FullyNoded-Server/tree/master/FullyNoded-Server/Scripts) which power its core functionality as well as swift code to create directories and download tarballs for the above projects via the Github API. 

A data directory will be created at `~/.fullynoded` which holds the binaries for Bitcoin Core and Join Market, Core Lightning is installed via `brew install core-lightning` for now.

- Bitcoin Core
    - [Downloading the tarball](https://github.com/Fonta1n3/FullyNoded-Server/blob/master/FullyNoded-Server/Views/TaggedReleasesView.swift).
    - [Script for verifying sha256 hashes and unpacking the tarball](https://github.com/Fonta1n3/FullyNoded-Server/blob/master/FullyNoded-Server/Scripts/InstallBitcoin.command).
    - [Script for verifying gpg signatures](https://github.com/Fonta1n3/FullyNoded-Server/blob/master/FullyNoded-Server/Scripts/Verify.command).
    
- Core Lightning
    - [Download, configure, install](https://github.com/Fonta1n3/FullyNoded-Server/blob/master/FullyNoded-Server/Scripts/InstallLightning.command)
    
- Join Market
    - [Downloading and configuring](https://github.com/Fonta1n3/FullyNoded-Server/blob/master/FullyNoded-Server/Views/JoinMarketTaggedReleases.swift)
    - [GPG verify and install](https://github.com/Fonta1n3/FullyNoded-Server/blob/master/FullyNoded-Server/Scripts/InstallJoinMarket.command)
    
## Features
- Bitcoin Core
    - Installation.
    - GPG Verification.
    - Start/Stop.
    - Switch networks.
    - Reachable via JSON RPC HTTP REST over Tor.
    - Refresh RPC authentication.
    - Open bitcoin.conf.
    - Open debug.log.
    - QuickConnect for Fully Noded and Unify - Payjoin Wallet.
    
- Core Lightning
    - Inastallation.
    - Configures clnrest-rs.
    - Start/Stop.
    - Open config.
    - Open log.
    - Quick Connect for Plasma (via LNSocket) and clnrest-rs.
    
- Join Market
    - Installation.
    - Automatic configuration (auto creates jm_wallet.dat for example).
    - Start/Stop.
    - Open config.
    - Quick Connect for Fully Noded - Join Market
    
- Tor
    - Tor is integrated, a green check will display if its running.
    - More coming soon for the Tor UI.
    - Hidden services are automatically configured. Your torrc can be found [here](https://github.com/Fonta1n3/FullyNoded-Server/blob/master/FullyNoded-Server/Helpers/Torrc.swift).
    ```
    HiddenServiceDir .../host/joinmarket/
    HiddenServiceVersion 3
    HiddenServicePort 28183 127.0.0.1:28183

    HiddenServiceDir .../host/bitcoin/rpc/main/
    HiddenServiceVersion 3
    HiddenServicePort 8332 127.0.0.1:8332

    HiddenServiceDir .../host/bitcoin/rpc/test/
    HiddenServiceVersion 3
    HiddenServicePort 18332 127.0.0.1:18332

    HiddenServiceDir .../host/bitcoin/rpc/regtest/
    HiddenServiceVersion 3
    HiddenServicePort 18443 127.0.0.1:18443

    HiddenServiceDir .../host/bitcoin/rpc/signet/
    HiddenServiceVersion 3
    HiddenServicePort 38332 127.0.0.1:38332
    
    HiddenServiceDir .../host/cln/rpc/
    HiddenServiceVersion 3
    HiddenServicePort 18765 127.0.0.1:18765
    ```
    

    




