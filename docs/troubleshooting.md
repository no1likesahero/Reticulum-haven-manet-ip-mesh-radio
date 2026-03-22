# Haven Mesh Troubleshooting

This guide gives you a mental model of how the mesh works, then a checklist for every common failure. If something breaks, start at the top of the relevant checklist and work down.

---

## The Mental Model

Everything in Haven flows through two separate paths — get this picture in your head and most problems become obvious.

### Interface Stack (gate)

```
 INTERNET
     │
   eth0          ← upstream router gives this a DHCP IP
     │
 br-ahwlan       ← Linux bridge — everything on the mesh lives here (10.41.x.x)
  ├── bat0        ← BATMAN-adv virtual interface (handles mesh routing)
  │    └── wlan0  ← HaLow radio (802.11s mesh point, 915 MHz)
  ├── phy1-ap0    ← 5GHz WiFi AP — clients join here, land on br-ahwlan
  └── phy2-ap0    ← 2.4GHz or Panda WiFi AP — same
```

### Interface Stack (Haven Point — blue)

```
 br-ahwlan       ← same bridge concept, gets DHCP IP from gate
  ├── bat0        ← BATMAN-adv (client mode)
  │    └── wlan0  ← HaLow radio (802.11s mesh point)
  └── phy1-ap0    ← 5GHz WiFi AP — clients join here, land on br-ahwlan
```

### Interface Stack (Heltec node)

```
 br-ahwlan       ← same bridge concept, gets DHCP IP from gate
  ├── bat0        ← BATMAN-adv (client mode)
  │    └── wlan0  ← HaLow radio (802.11s mesh point)
  └── phy0-ap0    ← 2.4GHz WiFi AP — clients join here, land on br-ahwlan
```

> The Haven Point and Heltec nodes are the same concept — the only difference is the radio hardware and which `phy` interface the AP lands on. The bridge and BATMAN stack are identical.

### The One Rule

> **If it's not in `br-ahwlan`, it's not on the mesh.**

Run this on any node:
```sh
brctl show br-ahwlan
```

Every interface that carries mesh traffic must appear here — either directly (WiFi APs) or through bat0 (HaLow). If something is missing, that's your problem.

### What a working mesh looks like

```
  Your laptop                                        Your phone
  (10.41.0.x)                                       (10.41.0.x)
      │                                                   │
  gate WiFi AP                                   heltec WiFi AP
      │                                                   │
  br-ahwlan ── bat0 ── wlan0 ~~HaLow~~ wlan0 ── bat0 ── br-ahwlan
  (gate)                                                (heltec)
      │                                                   │
    DHCP                                           DHCP from gate
  10.41.0.1                                       10.41.x.x lease
```

Both devices are on the same `10.41.x.x` subnet. Ping works. Reticulum AutoInterface discovers peers via multicast.

---

## Quick Diagnostics

Run these first on any node to understand what's happening:

```sh
# Is the HaLow radio in BATMAN?
batctl if
# Expected: "wlan0: active"
# Bad: empty — wlan0 is not in bat0

# Are any mesh peers visible?
batctl o
# Expected: one or more originators with throughput > 0
# Bad: empty — no mesh peers

# Is the HaLow mesh joined?
logread | grep -i "MESH-GROUP\|joining mesh\|SAE"
# Expected: "MESH-GROUP-STARTED ssid=haven"
# Bad: "MESH-SAE-AUTH-FAILURE" or nothing

# Is the HaLow driver working?
dmesg | grep morse | grep -i "fail\|error\|timeout" | tail -5
# Expected: nothing (or only the enable_ps WARNING which is harmless)
# Bad: "morse_spi_cmd53_write failed" / "errno=-71"

# Who is on the mesh?
cat /tmp/dhcp.leases

# Can you reach a specific node?
ping -c 3 10.41.0.x
```

---

## Checklist 1 — HaLow Radio Not Coming Up

**Symptom:** `batctl if` is empty, `dmesg | grep morse` shows `cmd53_write/read failed (errno=-71)`

The Morse Micro chip is stuck and not responding over SPI.

- [ ] **Try driver reload first (no reboot needed):**
  ```sh
  rmmod morse && sleep 2 && modprobe morse && sleep 5
  batctl if   # should now show "wlan0: active"
  ```
- [ ] **If that fails, power cycle the gate** (full unplug from wall — soft reboot is not enough, the chip reset GPIO is not wired in the device tree)
- [ ] **If it keeps happening**, check the WM-WM6108 HAT physically:
  - Is it seated evenly on the RPi 40-pin GPIO header? Both sides should be level.
  - Are case standoffs pressing down on the HAT? Add height to standoffs so the case lid clears the board.
  - Check for bent pins on the SPI header (GPIO 8, 9, 10, 11).
  - The chip does NOT need to be opened — the metal RF shield is soldered on and not meant to be removed.

---

## Checklist 2 — Mesh Peers Not Showing (`batctl o` empty)

**Symptom:** `batctl if` shows `wlan0: active` but `batctl o` is empty

The HaLow radio joined the 802.11s mesh but BATMAN isn't routing.

- [ ] **Check wlan0 is actually in bat0, not in br-ahwlan:**
  ```sh
  ip link show wlan0 | grep master
  # Should say: master bat0
  # Bad:        master br-ahwlan  ← wlan0 bypassed bat0
  ```
  If it says `master br-ahwlan`, fix it:
  ```sh
  uci show wireless | grep "mesh_id\|network"
  # The mesh interface network must be 'batmesh' or 'batmesh0', NOT 'ahwlan'
  uci set wireless.<mesh_iface>.network='batmesh0'
  uci commit wireless && wifi reload
  ```

- [ ] **Check the peer node is using the same settings:**

  | Setting | Required value |
  |---------|---------------|
  | Mesh ID | `haven` |
  | Encryption | WPA3-SAE |
  | Key | `havenmesh` |
  | Channel | 27 (915.5 MHz) |
  | Width | 1 MHz |
  | Channel fwding | disabled (mesh_fwding=0) |

- [ ] **Check for SAE auth failures:**
  ```sh
  logread | grep "SAE"
  # "MESH-SAE-AUTH-FAILURE" = key mismatch or PMF incompatibility
  # "MESH-SAE-AUTH-BLOCKED" = too many failures, peer blocked for 300s
  ```
  If blocked, reload wifi to clear the block: `wifi reload`

- [ ] **If SAE keeps failing with correct keys**, check both nodes are using the same `sae_pwe` mode:
  ```sh
  grep sae_pwe /var/run/wpa_supplicant-wlan0.conf
  # Set to 0 (supports both methods) on both nodes:
  uci set wireless.<mesh_iface>.sae_pwe='0'
  uci commit wireless && wifi reload
  ```

---

## Checklist 3 — WiFi Clients Not Getting Internet

**Symptom:** Phone/laptop connects to a node's WiFi, gets an IP, but no internet.

Two different sub-problems depending on which IP the client got:

### Client got 10.41.x.x → routing issue

Client is on the mesh subnet but can't reach the internet.

- [ ] Can the client ping the gate? `ping 10.41.0.1` (or the gate's mesh IP)
- [ ] Can the gate ping the internet? SSH to gate and run `ping 8.8.8.8`
- [ ] Check the gate has internet via eth0: `ip route show default`
  - Should show a default route via eth0 to the upstream router
- [ ] Check firewall masquerade is on for the WAN zone:
  ```sh
  uci show firewall | grep masq
  # Should show masq='1' on the wan zone
  ```

### Client got 10.42.x.x (or 192.168.x.x) → bridging issue

Client landed on the wrong bridge — the WiFi AP is connected to `br-lan` instead of `br-ahwlan`.

```
  WRONG                           CORRECT
  ─────                           ───────
  phy0-ap0 → br-lan              phy0-ap0 → br-ahwlan
  (isolated, no mesh)            (on the mesh, gets 10.41.x.x)
```

Fix: move the AP interface to the `ahwlan` network:
```sh
# Find the AP interface name
uci show wireless | grep "mode='ap'"
# Set it to ahwlan
uci set wireless.<ap_iface>.network='ahwlan'
uci commit wireless && wifi reload
```

> **Warning:** This will change the node's management IP from 10.42.0.1 to a 10.41.x.x DHCP address from the gate. SSH access will need to go through the gate after this change.

After the change, find the node's new IP:
```sh
# On the gate:
cat /tmp/dhcp.leases
```

---

## Checklist 4 — Reticulum Peers Not Discovering Each Other

**Symptom:** Mesh is up, devices have 10.41.x.x IPs, but Sideband/MeshChat don't see each other.

- [ ] **Confirm both devices are on the same subnet:**
  - Device A (e.g. laptop on gate WiFi): should have 10.41.x.x
  - Device B (e.g. phone on heltec WiFi): should have 10.41.x.x
  - If Device B has 10.42.x.x → bridging issue, see Checklist 3

- [ ] **Confirm they can ping each other:**
  From laptop: `ping <phone-ip>` — if this fails, the issue is network, not Reticulum.

- [ ] **AutoInterface uses UDP multicast** — confirm BATMAN multicast mode is on:
  ```sh
  batctl multicast_mode   # should say "enabled"
  ```

- [ ] **EUDs only need AutoInterface** — no RNS config on the nodes is required. Just connect to the mesh WiFi, enable AutoInterface in Sideband/MeshChat, and they discover each other automatically. See [Reticulum/README.md](../Reticulum/README.md) for the easy setup.

- [ ] **If multicast doesn't work**, fall back to UDPInterface pointing directly at the other device's IP — this always works since it's unicast.

---

## Reference: Key Files and Commands

```sh
# Wireless config
uci show wireless

# Network/bridge config
uci show network

# Current bridge members (what's in which bridge)
brctl show

# All IP addresses on all interfaces
ip addr show

# BATMAN peers and throughput
batctl o

# BATMAN interfaces (what's in bat0)
batctl if

# DHCP leases (who is on the mesh)
cat /tmp/dhcp.leases

# Recent system log
logread | tail -50

# HaLow driver messages
dmesg | grep -i morse
```

## Reference: Correct UCI Settings

### Gate — HaLow mesh interface
```
wireless.<halow_iface>.mode='mesh'
wireless.<halow_iface>.network='batmesh0'   ← NOT 'ahwlan'
wireless.<halow_iface>.mesh_id='haven'
wireless.<halow_iface>.encryption='sae'
wireless.<halow_iface>.key='havenmesh'
wireless.<halow_iface>.mesh_fwding='0'
```

### Gate — WiFi AP interface
```
wireless.<ap_iface>.mode='ap'
wireless.<ap_iface>.network='ahwlan'        ← direct to bridge, no bat0
```

### Point node — HaLow mesh interface
```
wireless.<halow_iface>.network='batmesh'    ← NOT 'ahwlan'
network.batmesh.proto='batadv_hardif'
network.batmesh.master='bat0'
network.bat0.proto='batadv'
network.bat0.gw_mode='client'
```
