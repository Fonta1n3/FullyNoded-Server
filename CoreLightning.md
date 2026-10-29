# Core Lightning

**A Lightning node next to your Bitcoin node, made for [Plasma](https://github.com/Fonta1n3/Plasma).**
Fully Noded Server installs [Core Lightning](https://github.com/ElementsProject/lightning) with
Homebrew, configures it for this Mac's bitcoind, starts and stops it, and pairs it with Plasma (the
Core Lightning wallet for iPhone) with a QR code. Other Lightning wallets can connect over Tor.

It's optional: add it from the Setup Assistant's **Lightning** step, or later from **Core Lightning**
in the sidebar.

## Set up

1. **Homebrew.** Core Lightning comes from Homebrew's `core-lightning` formula. If Homebrew isn't
   installed, the page offers to install it.
2. **Install.** Tap **Install Core Lightning**. Homebrew runs in a Terminal window (a few minutes),
   and the page continues by itself when it's done.
3. **Start.** Your Bitcoin node must be running. Core Lightning uses the same network as the node
   (Mainnet, Testnet3, Testnet4, Signet or Regtest) and waits for the node to finish syncing before
   it's fully usable.
4. **Back up `~/.lightning/<network>/hsm_secret`.** It holds the keys to the node's on-chain funds.
   To recover channel funds you also need the node's database, or `emergency.recover`.
5. **Pair Plasma** (below).

Updates: when Homebrew has a newer version, the page shows **Update**. Stop the node first, because
Homebrew replaces the files a running node uses. The node's database is upgraded on its next start,
and an older version can't open it afterwards.

## Pair Plasma

Plasma connects through **Nostr Connect**, the same way Fully Noded does: no open port, no VPN, any
network.

```
Plasma ──NIP-44 encrypted events──▶ wss:// relay ──▶ FN-Server bridge ──HTTP + Rune──▶ clnrest ──▶ lightningd
       ◀───────────────────────────               ◀──                  ◀─────────────
```

Plasma sends each Core Lightning command as an end-to-end encrypted nostr event, using the same
protocol as [Nostr Connect](./NostrConnect.md) (NIP-44 v2, BIP340-signed ephemeral events, framing,
acks and retransmission). The bridge decrypts it and calls Core Lightning's REST API (clnrest, on
127.0.0.1) with the pairing's rune in the `Rune` header. clnrest checks the rune and runs the
command. The bridge returns the result as `{"result": …}` or `{"error": …}`.

- **Relays:** wss:// only. Use this Mac's relay with **Encrypt connections (wss://)** on (its
  self-signed certificate is pinned in the pairing link), which covers the local network and VPNs.
  Add a wss:// public relay on the Nostr Connect page to reach the node from anywhere. A relay only
  ever sees ciphertext.
- **clnrest is required:** the compiled plugin that ships with current Core Lightning. If it isn't
  running, the card says why and pairing is disabled.
- **Pairing:** **Pair Plasma** (full access) or **Read-only** creates a pairing key for that phone
  and a rune for it. The QR code is a `nostr+plasma://` link, shown once. In Plasma: Node Manager
  → + → scan it, or paste the link.
- **Permissions:** the rune stays on this Mac, and clnrest enforces it, so a read-only pairing
  can't pay or open channels. Refused commands come back with Core Lightning's own error.
- **Removing:** each Plasma pairing is listed on the card (and on the Nostr Connect page) with
  **Remove**. Removing it cuts that phone off at once.
- **Network:** a pairing is for the network the node was on when it was made, and its commands go
  to that network's Core Lightning.
- Fully Noded refuses `nostr+plasma://` links, and Plasma pairings never reach Bitcoin Core.

### Runes

- **Full access:** `createrune` with no restrictions.
- **Read-only:** `createrune` with `[["method^list","method^get","method=summary"],["method/listdatastore"]]`
  (any `list…` or `get…` method, or `summary`, but never `listdatastore`).
- **Revoke all runes** blacklists every rune issued so far, Plasma pairings' included. Every paired
  wallet then needs a new one, and Plasma needs pairing again.

## Other wallets: CLNRest over Tor

For wallets that speak CLNRest (Zeus, for example). Core Lightning's `clnrest` plugin serves its REST
API on `127.0.0.1:18765`, and FN-Server's Tor publishes it as an onion service (it's on the Tor page
as **Core Lightning REST**). **Full access** or **Read-only** shows the onion host, the port and a new
rune, plus a QR code of `clnrest://<onion>:18765?rune=<rune>`.

The REST API needs the compiled `clnrest` plugin that ships with newer Core Lightning. Older
versions have a Python plugin that switches itself off without its Python packages. FN-Server then
starts the node without REST and says so; update Core Lightning to use it.

## Ports

Each network gets its own ports (Core Lightning's defaults for the peer port), so nodes for different
networks can run at the same time:

| Network  | Peers | REST (clnrest) | gRPC  |
|----------|-------|----------------|-------|
| Mainnet  | 9735  | 18765          | 9736  |
| Testnet3 | 19735 | 18766          | 19736 |
| Testnet4 | 49735 | 18767          | 49736 |
| Signet   | 39735 | 18768          | 39736 |
| Regtest  | 19846 | 18769          | 19847 |

REST and gRPC listen on 127.0.0.1 only. The Tor onion for Core Lightning forwards all five REST ports.
If a port is taken, the page shows lightningd's own reason (for example "Failed to bind … Address
already in use").

## What FN-Server configures

FN-Server writes `~/.lightning/fns-server.conf` each time it starts the node, and runs:

```
lightningd --conf=~/.lightning/fns-server.conf --lightning-dir=~/.lightning \
           --network=<network> --log-file=~/.lightning/<network>/fns-lightningd.log --daemon
```

```
alias=FullyNoded-Server                 # or the alias from an older ~/.lightning/config
bitcoin-cli=~/.fullynoded/BitcoinCore/<version>/bin/bitcoin-cli
bitcoin-datadir=<your Bitcoin data folder>
bind-addr=127.0.0.1:9735                # the network's peer port; 0.0.0.0 with "Accept incoming peer connections" on
proxy=127.0.0.1:19850                   # FN-Server's Tor
always-use-proxy=true                   # with "Connect to peers only through Tor" on
grpc-port=9736                          # the network's gRPC port, when cln-grpc is installed
clnrest-port=18765                      # the network's REST port, when the compiled clnrest plugin is installed
clnrest-protocol=http
clnrest-host=127.0.0.1
```

- **`--conf`** makes lightningd skip `~/.lightning/config`, which is left as it is (the old setup's
  file pointed at a versioned Homebrew folder and broke on every upgrade). Put your own options in
  `~/.lightning/<network>/config` (**My options** on the page), which lightningd still reads.
- **bitcoind:** through FN-Server's own `bitcoin-cli` with your node's data folder, so it signs in
  with bitcoind's cookie. No RPC password is written to any file.
- **Binaries** come from Homebrew's `opt/core-lightning` link, which survives upgrades.
- **Incoming peers** (off by default): **Accept incoming peer connections** listens on all of this
  Mac's addresses. Plasma doesn't need it. With the macOS firewall on, the page shows the command
  that allows `lightning_connectd` (Homebrew's binaries are never allowed automatically, and every
  update needs a new rule).
- **Peers over Tor** (on by default) hides this Mac's IP address from Lightning peers. Turn it off
  to reach peers that are only on clearnet.
- **An existing node** in `~/.lightning/<network>/` is used as it is. FN-Server never writes or
  deletes anything in that folder.

## Start a new node

**Settings → Start a new node…** (also offered when the node fails to start) replaces the current
network's node with a new one, with a new node ID and keys. Choose:

- **Keep the old node:** its folder is renamed to `<network>.old-<date>`. Moving it back restores
  it. Kept folders are listed under Settings, each with **Delete**.
- **Delete the old node:** its folder (hsm_secret, database) is erased for good.

A running node is stopped first, and force-stopped if it doesn't stop. Use this when a node can't
be used any more, for example when it can't catch up because a pruned Bitcoin node no longer has
the blocks it needs.

If lightningd crashes but doesn't exit (it can hang after `FATAL SIGNAL`), the page says so,
shows the error that caused it, and offers **Force stop**.

## Status and controls

The page reads lightningd's state straight from its RPC socket
(`~/.lightning/<network>/lightning-rpc`), the way `lightning-cli` does, and checks the process
itself (the pid file, confirmed to be a `lightningd`), so a node that's still starting isn't shown
as off. It shows:

- the node's alias, node ID, peers and channels (active, pending, inactive)
- funds in channels and on-chain, and a **New deposit address** button for funding channels
- sync warnings from lightningd
- whether the REST server is listening
- the end of the log, with buttons for your options file, the node folder and the full log

The sidebar shows a check while Core Lightning runs on the current network.

## Code

- `Helpers/LightningNode.swift`: install and update, config, start and stop, polling, runes, Plasma
  pairing.
- `Helpers/NostrBridge.swift` (`forwardLightning`): Plasma's commands to clnrest.
- `Helpers/LightningRPC.swift`: JSON-RPC over the unix socket.
- `Views/CoreLightning.swift`: the page, and the sidebar's status icon.
- `Scripts/LaunchLightningInstall.command`, `Scripts/InstallLightning.command`: the Homebrew install
  and update in Terminal (the result goes to `~/.fullynoded/lightning-install.status`).
