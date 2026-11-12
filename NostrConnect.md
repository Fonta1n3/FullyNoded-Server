# Nostr Connect

**The fast way to connect Fully Noded to this node.** Instead of Tor, Fully Noded sends its RPC
calls through a nostr relay. Fully Noded Server answers them from your local Bitcoin Core. There's
no onion circuit to build, so connections take about a second, on your local network, over a VPN
like Tailscale, or anywhere through a public relay.

Your node's RPC port is never exposed: everything is end-to-end encrypted between Fully Noded and
this Mac, and the relay only passes on ciphertext.

**Plasma uses it too.** A Plasma pairing, made on the Core Lightning page, uses the same relays
and bridge (wss:// relays only), and its commands go to Core Lightning's REST API (clnrest) instead
of Bitcoin Core, with the pairing's rune. See [CoreLightning.md](./CoreLightning.md#anywhere-nostr-connect).

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
same Wi-Fi, a VPN) can't see which keys talk, or when.

- The first time, FNS runs `Scripts/CreateRelayCert.command`, which uses macOS's `/usr/bin/openssl`
  to make an EC P-256 key and a self-signed certificate (10 years). The PKCS#12 bundle is stored
  encrypted in FNS's Keychain entry and loaded into memory only (`kSecImportToMemoryOnly`, macOS 15).
- The certificate's SHA-256 goes in the pairing link (`&cert=…`). Fully Noded accepts exactly that
  certificate for the Mac's relay, and normal CA-validated TLS for public `wss://` relays. No
  hostname is checked, so the same certificate works on the LAN IP and a VPN IP.
- Turning it on or off changes the relay's addresses: pair devices again.
- Tailscale Funnel's public address uses Tailscale's own, publicly trusted certificate (see below).

## Using it

1. Open **Nostr Connect** in the sidebar.
2. Choose where Fully Noded will reach the bridge:
   - **Run a relay on this Mac** (port 7777 by default). Its LAN address is listed, plus a
     Tailscale/VPN address when there is one. macOS may ask once to allow incoming connections.
     Leave **Encrypt connections (wss://)** on (see above).
   - **Reach this relay from anywhere · Tailscale Funnel:** publish the relay at
     `wss://<mac>.<tailnet>.ts.net` (see below). Nothing to install on the phone.
   - **Relays the bridge listens on:** public relays (`wss://…`) reach the node from anywhere
     without exposing this Mac. `wss://relay.damus.io`, `wss://nos.lol` and `wss://relay.primal.net`
     are included by default (added once; remove any you don't want). The bridge only connects to
     them once something is paired.
3. Pick the **network** and tap **Pair Fully Noded**. Scan the QR in Fully Noded (welcome guide ›
   **Nostr Connect**, or Node Manager › **+** › **Scan QR**). The QR is shown once: anyone with it
   can use your node.
4. **Paired devices** lists each device with when it was last seen. **Remove** revokes it.

### Tailscale Funnel

[Funnel](https://tailscale.com/kb/1223/funnel) gives this Mac's relay a public HTTPS address,
`wss://<mac>.<tailnet>.ts.net` on port 443, with a publicly trusted certificate. Fully Noded and
Plasma reach it from any network with nothing installed on the phone: no Tailscale there, no port
forward, no ngrok. Only this Mac runs Tailscale (and Fully Noded Server).

- **Turn on Funnel** runs `tailscale funnel --bg https+insecure://localhost:<port>` (or
  `http://localhost:<port>` with encryption off). Tailscale terminates the public TLS and forwards to
  the relay. It can't check the relay's self-signed certificate, hence `+insecure`; that hop stays
  on this Mac.
- The first time, Tailscale needs HTTPS certificates and Funnel allowed for this Mac. The CLI prints
  a login.tailscale.com link and waits; FNS shows it as **Approve in Tailscale**, and Funnel turns on
  once it's approved.
- While Funnel serves the relay, new pairing links carry only its address (plus any public relays),
  not the local or VPN ones: it works on every network, and addresses that only work at home would
  just be extra connections failing away from it. Pair devices again after turning it on.
- When it's first turned on, public DNS can take a few minutes to find the new `ts.net` name.
- **Turn off** runs `tailscale funnel --https=443 off`, so other `tailscale serve` settings stay.
- Tailscale (the company) relays the traffic but only sees NIP-44 ciphertext, like any relay.
- **Reachability:** "on" doesn't prove it works. Tailscale's ingress has been seen to stop forwarding
  to this Mac (TLS dropped mid-handshake, no ingress node connected) while everything here looks
  fine, until Funnel is turned off and on. So while Funnel is on, FNS checks the public address
  every 3 minutes the way a phone away from home reaches it: public DNS (DNS-over-HTTPS to
  1.1.1.1, then dns.google, since MagicDNS would give the tailnet address), then a TLS handshake
  with each ingress address. TLS ends on this Mac, so a finished handshake means the ingress
  forwards here. The card shows **Reachable from the internet** or **Not reachable** with the
  reason, and the sidebar shows a warning while it's down.
- **Auto-repair:** two failed checks in a row turn Funnel off and on (at most every 10 minutes, and
  not in the first 3 minutes after turning it on, while public DNS catches up). **Turn off and on**
  and **Check now** do the same by hand. Keep public relays in the pairing so devices fall back to
  them meanwhile.

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
