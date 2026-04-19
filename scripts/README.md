# Haven Scripts

Automated setup and utility scripts for Haven mesh nodes.

> For the full setup walkthrough, see **[docs/setup-guide.md](../docs/setup-guide.md)**.
>
> For finding node IPs and accessing LuCI, see **[docs/finding-nodes.md](../docs/finding-nodes.md)**.
>
> For troubleshooting, see **[docs/troubleshooting.md](../docs/troubleshooting.md)**.

## Scripts Overview

| Script | Purpose | Run On |
|--------|---------|--------|
| `setup-haven-gate.sh` | Configure gateway node (internet uplink) | First node |
| `setup-haven-point.sh` | Configure extender node | Additional nodes |
| `setup-reticulum.sh` | Install encrypted mesh overlay | Any node (optional) |
| `configure-heltec.sh` | Configure Heltec HaLow node for BATMAN-adv mesh | Heltec v2 nodes |
| `haven-bridge-check.sh` | Boot-time health check — auto-repairs BATMAN bridge | All mesh nodes |
| `setup-cot-bridge.sh` | Install ATAK/CivTAK bridge | Any node (optional) |
| `rns_status.py` | Live Reticulum + HaLow network dashboard | Any node |
| `rns_send.py` | Send a message over Reticulum | Sender node |
| `rns_receive.py` | Receive messages over Reticulum | Receiver node |

---

## Reticulum Demo Scripts

These scripts demonstrate and monitor Reticulum data transfer over the Haven mesh. Requires Reticulum to be installed (see [setup guide → Step 3](../docs/setup-guide.md#step-3-install-reticulum-optional)).

### rns_status.py — Live Network Dashboard

A live-refreshing dashboard showing Reticulum network status, HaLow radio details, configured interfaces, and real-time data exchange with PING/PONG between nodes. Refreshes every 3 seconds.

**Deploy to a node:**
```bash
scp scripts/rns_status.py root@<node_ip>:/root/rns_status.py
```

**Usage:**
```bash
# Standalone mode (listen only, no outbound link)
python3 /root/rns_status.py

# Peered mode (connect to another node running rns_status.py)
python3 /root/rns_status.py <peer_destination_hash>
```

**Two-node setup:**
1. Start on the first node (BLUE) with no arguments — note the destination hash it prints
2. Start on the second node (GREEN) with BLUE's hash — it connects and begins exchanging PING/PONG

```bash
# On BLUE (listener)
python3 /root/rns_status.py

# On GREEN (initiator) — use BLUE's hash from step 1
python3 /root/rns_status.py b9b2bef4bf0510882bcd394469c20928
```

**Example output — standalone (before peering):**
```
  Reticulum Network Status — green
  ======================================================
  Version         : RNS 0.9.3
  Node hash       : ca6fafa5fe557c2f1a86807ee129671c
  Status          : Waiting for peers...

  Radio Transport Layer
  ------------------------------------------------------
    Hardware      : Morse Micro MM6108 802.11ah (HaLow)
    Mode          : Mesh Point
    Mesh ID       : haven
    Frequency     : 916.0 MHz
    Channel       : 28
    Bit Rate      : 32.5 MBit/s
    Signal        : -6 dBm
    Encryption    : WPA3 SAE (CCMP)

  Reticulum Interfaces
  ------------------------------------------------------
    [HaLow Mesh Bridge]
      Type        : AutoInterface
      Device      : br-ahwlan
    [UDP Broadcast]
      Type        : UDPInterface
      Listen      : 10.41.0.1:4242
      Forward     : 10.41.255.255:4242

  Data Exchange
  ------------------------------------------------------
    Packets TX    : 0
    Packets RX    : 0
    Peers         : Discovering...

  ──────────────────────────────────────────────────────
  Refreshing every 3s — Ctrl+C to exit
```

**Example output — linked (active data exchange):**
```
  Reticulum Network Status — green
  ======================================================
  Version         : RNS 0.9.3
  Node hash       : ca6fafa5fe557c2f1a86807ee129671c
  Status          : Linked with blue

  Radio Transport Layer
  ------------------------------------------------------
    Hardware      : Morse Micro MM6108 802.11ah (HaLow)
    Mode          : Mesh Point
    Mesh ID       : haven
    Frequency     : 916.0 MHz
    Channel       : 28
    Bit Rate      : 32.5 MBit/s
    Signal        : -6 dBm
    Encryption    : WPA3 SAE (CCMP)

  Reticulum Interfaces
  ------------------------------------------------------
    [HaLow Mesh Bridge]
      Type        : AutoInterface
      Device      : br-ahwlan
    [UDP Broadcast]
      Type        : UDPInterface
      Listen      : 10.41.0.1:4242
      Forward     : 10.41.255.255:4242

  Data Exchange
  ------------------------------------------------------
    Packets TX    : 42
    Packets RX    : 43
    Peer [blue]   : RTT 23.4ms  (alive)

  ──────────────────────────────────────────────────────
  Refreshing every 3s — Ctrl+C to exit
```

### rns_send.py / rns_receive.py — Message Transfer Demo

Simple sender/receiver pair for demonstrating Reticulum message delivery across the mesh.

**Deploy to nodes:**
```bash
scp scripts/rns_receive.py root@<receiver_ip>:/root/rns_receive.py
scp scripts/rns_send.py root@<sender_ip>:/root/rns_send.py
```

**Usage:**
```bash
# On the receiver node — note the destination hash
python3 /root/rns_receive.py

# On the sender node — use the receiver's hash
python3 /root/rns_send.py <dest_hash> Hello from GREEN over Reticulum and HaLow
```

**Example — receiver:**
```
Listening...
Destination hash: a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6
Link established!

>>> Hello from GREEN over Reticulum and HaLow
```

**Example — sender:**
```
Resolving path...
Connecting...
Sending: Hello from GREEN over Reticulum and HaLow
Sent!
```
