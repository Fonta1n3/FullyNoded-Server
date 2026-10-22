# Nostr Connect

**The fast way to connect Fully Noded to this node.** Instead of Tor, Fully Noded sends its RPC
calls through a nostr relay. Fully Noded Server answers them from your local Bitcoin Core. There's
no onion circuit to build, so connections take about a second, on your local network, over a VPN
like Tailscale, or anywhere through a public relay.

Your node's RPC port is never exposed: everything is end-to-end encrypted between Fully Noded and
this Mac, and the relay only passes on ciphertext.

## How it works

```
Fully Noded  ──encrypted event──▶  nostr relay  ──▶  Fully Noded Server (bridge)  ──RPC──▶  bitcoind
             ◀──encrypted event──              ◀──                                ◀──────
```

- **Keys.** The bridge has a long-lived secp256k1 key. Each paired device gets its own client key,
  handed over once in the pairing link. Only its public key is kept, so removing a pairing cuts that
  device off for good.
- **Messages.** Requests and responses are NIP-01 events of the ephemeral kind `28388`, signed
  (BIP340) and addressed with a `p` tag. Their content is NIP-44 v2 encrypted. Relays forward
  ephemeral events and don't store them.
- **Large messages.** A JSON-RPC body is DEFLATE-compressed when that makes it smaller (the first
  frame states the original size, and inflating stops there), then sent base64-encoded in numbered
  frames of 24,000 characters. Each event stays under ~40 KB, inside the 64 KB limit of many public
  relays. Bursts are paced so relays don't rate-limit them.
- **Delivery.** The bridge acks a complete request. With neither an ack nor any of the answer after
  a few seconds, Fully Noded sends the request again; the bridge ignores the duplicate, or resends
  its stored answer if it already replied. When a message stalls with frames missing, the receiver
  asks for just those, and the sender (which keeps its frames for five minutes) sends them again.
  Events a relay turns away as rate-limited are retried with backoff.
- **The bridge** subscribes to events addressed to its key on every relay it listens on: this Mac's
  relay and any public relays you add. It decrypts a request from a paired device, reassembles it,
  forwards it to the local Bitcoin Core on that pairing's network, and returns the encrypted response.
- **The built-in relay** (`Helpers/NostrRelay.swift`) is a minimal NIP-01 relay on Network.framework.
  It's ephemeral only (nothing stored), and only the bridge key and paired devices may publish.
  Anyone who can reach the port can subscribe, but every payload is encrypted.

**What a relay operator can see:** that two keys exchanged messages, and when. Never the contents.

### Encrypted connections (wss://)

Messages are end-to-end encrypted either way. With **Encrypt connections (wss://)** on (the default
for a new setup on macOS 15 and later), this Mac's relay also uses TLS, so others on the network (the
same Wi-Fi, your ISP on a port forward) can't see which keys talk, or when.

- The first time, FNS runs `Scripts/CreateRelayCert.command`, which uses macOS's `/usr/bin/openssl`
  to make an EC P-256 key and a self-signed certificate (10 years). The PKCS#12 bundle is stored
  encrypted in FNS's Keychain entry and loaded into memory only (`kSecImportToMemoryOnly`, macOS 15).
- The certificate's SHA-256 goes in the pairing link (`&cert=…`). Fully Noded accepts exactly that
  certificate for the Mac's relay, and normal CA-validated TLS for public `wss://` relays. No
  hostname is checked, so the same certificate works on the LAN IP, a Tailscale IP or a port forward.
- Turning it on or off changes the relay's addresses: pair devices again.
- ngrok: forward to the TLS relay with `ngrok http https://localhost:<port>`.

## Using it

1. Open **Nostr Connect** in the sidebar.
2. Choose where Fully Noded will reach the bridge:
   - **Run a relay on this Mac** (port 7777 by default). Its LAN address is listed, plus a
     Tailscale/VPN address when there is one. macOS may ask once to allow incoming connections.
     Leave **Encrypt connections (wss://)** on (see above).
   - **Reach this relay from outside your network:** an ngrok address (**Detect ngrok**), or a router
     port forward (`wss://<public IP>:7777`, or `ws://` with encryption off).
   - **Relays the bridge listens on:** add public relays (`wss://…`) to reach the node from anywhere
     without exposing this Mac.
3. Pick the **network** and tap **Pair Fully Noded**. Scan the QR in Fully Noded (welcome guide ›
   **Nostr Connect**, or Node Manager › **+** › **Scan QR**). The QR is shown once: anyone with it
   can use your node.
4. **Paired devices** lists each device with when it was last seen. **Remove** revokes it.

Set up relays, and choose wss:// or ws://, before pairing: the link includes the relays and the
certificate pin configured at that moment, so pair again after changing either.

The Setup Assistant (**FullyNoded-Server › Setup Assistant…**) offers Nostr Connect in its last
step.

## Pairing link

```
nostr+fullynoded://<bridge pubkey>?relay=<ws(s) url>[&relay=…]&secret=<client privkey>
                                  [&label=<name>][&chain=<main|test|testnet4|signet|regtest>]
                                  [&cert=<SHA-256 of the relay's self-signed certificate>]
```

## Code

- `Helpers/NostrConnect.swift`: keys, NIP-44 v2, events, the pairing link and RPC framing. It's
  shared with Fully Noded; keep both copies identical.
- `Helpers/NostrRelay.swift`: the built-in relay, and `RelayTLS` (its certificate: created with
  `Scripts/CreateRelayCert.command`, stored encrypted in the Keychain, loaded into memory only).
- `Scripts/CreateRelayCert.command`: makes the relay's key and self-signed certificate with
  `/usr/bin/openssl`.
- `Helpers/NostrBridge.swift`: pairings, relay subscriptions, and forwarding to bitcoind.
- `Views/NostrConnectView.swift`: the Nostr Connect page.
