# Fully Noded Server (FNS) beta

## Requirements
- Python 3.10 to 3.12 for Join Market, should be located at `/Library/Frameworks/Python.framework/Versions`, if not a good guide can be found [here](https://www.codingforentrepreneurs.com/guides/install-python-on-macos).

## Installation
FNS can be downloaded via github releases [here](https://github.com/Fonta1n3/FullyNoded-Server/releases) and via [fullynoded.app](https://fullynoded.app) on the Home page.

Download the latest release files, verify the signatures and hash match, then open the dmg.
`gpg --import D3AC0FCA.asc` (my public key)
`gpg --verify FullyNoded-Server.dmg.asc FullyNoded-Server.dmg`
`gpg --verify SHA256SUMS.asc SHA256SUMS`
`shasum -a 256 FullyNoded-Server.dmg` (this should output the same hash found in the SHA256SUMS file, if not ALL STOP.)

## What does it do?
- Install any version of Bitcoin Core, Join Market and Tor, allowing you to very easily manage and connect to your servers remotely 
or locally to power Bitcoin wallets.
- GPG verifies the Bitcoin Core download files and verifies hashes of the binary during the installation process (it automates a 
secure installation).
- Tor is embedded in the app and automatically configures hidden services you can connect to remotely with wallets such as Fully 
Noded and Sparrow.
- Join Market is downloaded via the Github API, it runs its own installation script.
- Configures Bitcoin Core and Join Market for you so that you may use it in a "one click" manner, spoiler alert it is more than 
one click.
- Exposes useful utility functions such as opening debug logs, raw config files, reindexing, refresh rpc credentials and open data 
directories.
- Easily switch between networks and run multiple chains simultaneously, great for a dev environment on Mac.
- Easily connect local and remote wallets with the Quick Connect button. If Fully Noded, Unify, FN-Join Market (the wallets) are 
installed locally you can connect to them with one click, or scan the QR code to connect remotely.
- In the help section there are links for installing all Fully Noded apps/wallets which can be used with FNS.


## How?
A data directory for FNS will be created at `~/.fullynoded` which holds the binaries for Bitcoin Core and Join Market, users may 
edit the location of the Bitcoin Core data directory otherwise FNS sticks to the defaults whichj means any Bitcoin Core or Join 
Market installation should work seamlessly with an existing instance without interfering with it.

Bitcoin Core is downloaded from bitcoincore.org/bin. FNS then runs a script to verify the sha256sums match and allows the user to 
GPG verify the download with a Verify button which launches a bash script.

Join Market is downloaded via the Github API "tagged releases" from https://api.github.com/repos/JoinMarket-Org/joinmarket-clientserver/releases 
OR direct from the master branch via https://api.github.com/repos/JoinMarket-Org/joinmarket-clientserver/tarball/master.

For Bitcoin Core a wallet named "jm_wallet" will automatically be created when installing Join Market if it doesn't already exist. 

When installing Join Market it will automatically run the `wallet-tool.py` script to create a default config.

If the user clicks "Configure JM" Join Market and Bitcoin Core will be configured by creating new RPC credentials for Join Market, 
saving them to a hidden cookie file and converting them to and rpc auth string which is then saved to your bitcoin.conf. The port, 
network, chain and Tor host are all added to the Join Market config automatically. This configures Join Market to run the wallet 
daemon `jmwalletd.py` in conjunction with whatever chain Bitcoin Core is currently set to. As a side not changing the local Join 
Market RPC creds will not effect the remote connection as that is not reliant on RPC credentails, you can read about how Join Market 
remote connections work [here](https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/master/docs/JSON-RPC-API-using-jmwalletd.md).

FNS utilizes various scripts and Swift code to interact with files locally. FNS is meant to be minimal, all the heavy lifting is done 
by the services you are installing. Once services are installed FNS checks their "heartbeat" every 30 seconds or so if the app window 
is left open, once the app window is closed FNS turns into a "menu bar app" offering minimal functionality and a minimal incognito UI 
and does not do anything at all unless you click one of the menu bar app options (start/stop/get info/quit).

- Bitcoin Core
    - [Downloading the tarball](https://github.com/Fonta1n3/FullyNoded-Server/blob/master/FullyNoded-Server/Views/TaggedReleasesView.swift).
    - [Script for verifying sha256 hashes and unpacking the tarball](https://github.com/Fonta1n3/FullyNoded-Server/blob/master/FullyNoded-Server/Scripts/InstallBitcoin.command).
    - [Script for verifying gpg signatures](https://github.com/Fonta1n3/FullyNoded-Server/blob/master/FullyNoded-Server/Scripts/Verify.command).
    
- Join Market
    - [Downloading and configuring](https://github.com/Fonta1n3/FullyNoded-Server/blob/master/FullyNoded-Server/Views/JoinMarketTaggedReleases.swift)
    - [GPG verify and install](https://github.com/Fonta1n3/FullyNoded-Server/blob/master/FullyNoded-Server/Scripts/InstallJoinMarket.command)
    
## Security
The idea is to automate the right way to do things for newbs and devs alike.

Initially a random string is created which we use as a namespace for a dedicated random encryption key which is stored on your 
Mac's secure enclave/keychain. The random encryption key is created with the devices Cryptographically Secure random Number Generator.
When running FNS the first time you will be prompted to store this item on your keychain, the random letters you see are not the 
encryption key itself but its namespace. FNS uses the randomly created namespace to fetch the encryption key from your secure enclave 
to encrypt your RPC credentials which are stored encrypted on your device via "core data". Each time FNS fetches your own RPC credentials 
we first must decrypt them using this key.

FNS does not make any remote calls using RPC credentials, they are striclty used locally.

Join Market RPC credentials are stored as a cookie in the FNS data directory, this is only done if you click "Configure JM", if you have 
an existing config do not use this button.

If you do use the "Configure JM" button a new RPC redentials are created and saved, any existing plain text RPC credentials in the JM 
config will be commented out, of course this can easily be overridden by opening the config and editing it.
    
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
    - Reindex
    
- Join Market
    - Installation.
    - Automatic configuration (auto creates jm_wallet.dat for example).
    - Start/Stop.
    - Open config.
    - Quick Connect for Fully Noded - Join Market.
    - Increase gap limit.
    - Launch the Order Book.
    
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
    

    




