# Fully Noded Server (FNS) beta

## Requirements
- Python 3.10 to 3.12 for Join Market, should be located at `/Library/Frameworks/Python.framework/Versions`, if not a good guide can 
be found [here](https://www.codingforentrepreneurs.com/guides/install-python-on-macos).

## Installation
FNS can be downloaded via github releases [here](https://github.com/Fonta1n3/FullyNoded-Server/releases) and via [fullynoded.app](https://fullynoded.app) 
on the Home page.

Download the latest release files, verify the signatures and hash match, then open the dmg.
```
gpg --import 147538F5.asc
gpg --verify FullyNoded-Server.dmg.asc FullyNoded-Server.dmg
gpg --verify SHA256SUMS.asc SHA256SUMS
shasum -a 256 FullyNoded-Server.dmg
``` 
`shasum -a 256 FullyNoded-Server.dmg` should output the same hash found in the SHA256SUMS file, if not ALL STOP!

## What does it do?
- It first checks for xcode command line tools and brew, if either do not exist you will be prompted to install them.
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
- 🧪 Scans your node for **silent payments** (BIP352) sent to you and imports them, watch-only, into your Fully Noded 
wallet so Fully Noded can see and spend them (experimental, see [Silent Payments](#silent-payments-bip352)).


## How?
A data directory for FNS will be created at `~/.fullynoded` which holds the binaries for Bitcoin Core and Join Market, users may 
edit the location of the Bitcoin Core data directory otherwise FNS sticks to the defaults which means any Bitcoin Core or Join 
Market installation should work seamlessly with an existing instance without interfering with it.

Bitcoin Core is downloaded from bitcoincore.org/bin. FNS then runs a script to verify the sha256sums match and allows the user to 
GPG verify the download with a Verify button which launches a bash script.

Join Market is downloaded via the Github API "tagged releases" from https://api.github.com/repos/JoinMarket-Org/joinmarket-clientserver/releases 
OR direct from the master branch via https://api.github.com/repos/JoinMarket-Org/joinmarket-clientserver/tarball/master.

For Bitcoin Core a wallet named "jm_wallet" will automatically be created when installing Join Market if it doesn't already exist. 

When installing Join Market it will automatically run the `wallet-tool.py` script to create a default config.

If the user clicks "Configure JM" Join Market and Bitcoin Core will be configured by creating new RPC credentials for Join Market, 
saving them to a hidden cookie file and converting them to a rpc auth string which is saved to your bitcoin.conf. The port, 
network, chain and Tor host are all added to the Join Market config automatically. This configures Join Market to run the wallet 
daemon `jmwalletd.py` in conjunction with whatever chain Bitcoin Core is currently set to. As a side note changing the local Join 
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
    
## Silent Payments (BIP352)
> 🧪 Experimental, in development on the `Silent-Payments` branch. Test with small amounts.

A silent payment address (`sp1…`) is one static address you can share anywhere, yet every payment to it lands on a new, 
unlinkable Taproot output. Finding those payments means checking every transaction with your *scan key*. FNS does that 
with your own node, so no third party ever learns which payments are yours.

1. In **Fully Noded** open the wallet you'll spend from, go to its *Silent payments* section and tap **FN-SERVER LINK** 
(authentication required). It's one QR / `fnsp://` link with your silent payment address, your scan private key and the 
wallet's name on your node. (From a signer: *SP Scan Private Key* → *Fully Noded Server QR*.)
2. In **FNS** open **Silent Payments** (sidebar, or Bitcoin Core → Utilities):
    - *Import from Fully Noded*: *Paste link* (Copy Text in Fully Noded; Universal Clipboard brings it to your Mac), 
    *QR image…* or *Scan QR*. That fills the address, scan key and wallet. You can also enter them one by one (camera QR, 
    QR image or paste); the spend public key is read from the address and the scan key is checked against it;
    - check the network, choose a start height (the first block that could contain a payment to you, or *Earliest 
    available*) and click *Start scanning*.
3. FNS follows the chain in the background (one block fetched ahead, each block's transactions checked in parallel), 
imports every payment to you as a watch-only `rawtr()` descriptor, shows a card for each one and rescans the wallet once 
caught up. It resumes automatically when FNS launches. The icon on the sidebar's Silent Payments row shows the scanner's 
state; *History* lists every payment imported, *Rescan* scans again, and *Check a transaction* explains whether a given 
transaction pays you.
4. To spend, use that wallet in **Fully Noded** as usual: its transaction verifier recognises the silent payment inputs and 
signs them with your spend key, which never leaves Fully Noded.

What FNS holds: the scan private key, your address, the wallet and network, encrypted in the Keychain (*Forget keys* 
deletes them), and scan progress (block heights) in its settings. It never stores which outputs it found and never has 
your spend key, so it can see payments but can't spend them. Requires Bitcoin Core 25+ and the blocks from your start 
height onward (a pruned node works if it still has them). The camera is only used to scan QR codes and macOS asks for 
permission the first time.

Full technical details: [SilentPayments.md](./SilentPayments.md).

## Security
If connecting to a remote wallet usage of Tor is recommended, Fully Noded apps allow you to generate Tor authentication keys which
make your remote connection more secure.

#### RPC Credentials
Initially a random string is created which is used as a namespace for a dedicated random encryption key stored on the device 
secure enclave/keychain which stores it data encrypted. The random encryption key is created with the devices Cryptographically Secure Random Number Generator.
When running FNS the first time you will be prompted to store this item on your keychain, the random letters you see are not the 
encryption key itself but its namespace. FNS uses the randomly created namespace to fetch the encryption key from your secure enclave 
to encrypt your RPC credentials which are stored encrypted locally using Apples Core Data API. FNS fetches your RPC credentials 
and decrypts/encrypts them using this key.

FNS does not make any remote calls using RPC credentials, they are used locally.

Join Market RPC credentials are stored as a cookie in the FNS data directory, this is only done if you click "Configure JM", if you have 
an existing config do not use this button.

If you do use the "Configure JM" button new RPC credentials are created and saved, any existing plain text RPC credentials in the JM 
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
    - Quick Connect for Fully Noded and Unify - Payjoin Wallet.
    - Reindex.
    - Silent payments scanner (experimental): import keys, background scanning, status.
    
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
    
    ## License
    GNU General Public License v3.0

    If you would like to relicense this code to distribute it on the App Store,
    please contact me at [dentondevelopment@protonmail.com](mailto:dentondevelopment@protonmail.com).   




