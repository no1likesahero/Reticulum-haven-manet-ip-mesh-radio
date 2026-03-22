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
sh -c '
  echo "=== br-ahwlan members ==="
  brctl show br-ahwlan | awk "/br-ahwlan/{found=1} found && /[a-z]/{print \"  \" $NF}" | grep -v "^  $"

  echo ""
  echo "=== checks ==="

  brctl show br-ahwlan | grep -q "bat0"      \
    && echo "  [OK]  bat0 is in br-ahwlan"   \
    || echo "  [BAD] bat0 missing from br-ahwlan — run: ifup bat0"

  batctl if 2>/dev/null | grep -q "wlan0"    \
    && echo "  [OK]  wlan0 is inside bat0"   \
    || echo "  [BAD] wlan0 not in bat0 — run: rmmod morse && modprobe morse"

  ip link show wlan0 2>/dev/null | grep -q "master bat0" \
    && echo "  [OK]  wlan0 master is bat0"               \
    || echo "  [BAD] wlan0 bypassing bat0 — set mesh interface network=batmesh0 not ahwlan"

  brctl show br-ahwlan | grep -qE "phy[0-9]" \
    && echo "  [OK]  WiFi AP is in br-ahwlan" \
    || echo "  [BAD] WiFi AP missing from br-ahwlan — set AP interface network=ahwlan"

  batctl o 2>/dev/null | grep -qE "([0-9a-f]{2}:){5}" \
    && echo "  [OK]  BATMAN sees mesh peers"            \
    || echo "  [BAD] No mesh peers — check other nodes are on same channel/key"
'
```

**Healthy output looks like this:**
```
=== br-ahwlan members ===
  bat0
  phy2-ap0

=== checks ===
  [OK]  bat0 is in br-ahwlan
  [OK]  wlan0 is inside bat0
  [OK]  wlan0 master is bat0
  [OK]  WiFi AP is in br-ahwlan
  [OK]  BATMAN sees mesh peers
```

Any `[BAD]` line tells you exactly what is wrong and what to run to fix it.

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

**Symptom:** `batctl if` shows `wlan0: active` but `batctl o` is empty — or `batctl if` is empty entirely.

The HaLow radio joined the 802.11s mesh but BATMAN isn't routing. This also happens intermittently after running `wifi reconf` or reloading other interfaces — the HaLow mesh network assignment can silently revert from `batmesh0` to `ahwlan`.

- [ ] **Check wlan0 is actually in bat0, not in br-ahwlan:**
  ```sh
  batctl if
  # Should say: wlan0: active
  # Bad: empty — wlan0 is not inside bat0

  ip link show wlan0 | grep master
  # Should say: master bat0
  # Bad:        master br-ahwlan  ← wlan0 bypassed bat0
  ```
  If `batctl if` is empty or wlan0 says `master br-ahwlan`, fix it:
  ```sh
  uci show wireless | grep "mode='mesh'" | cut -d. -f2
  # Note the interface name (e.g. default_radio2), then:
  uci set wireless.<mesh_iface>.network='batmesh0'
  uci commit wireless && wifi reconf
  ```
  > **Note:** Use `batmesh0` on the gate (OpenMANET), `batmesh` on point nodes. Run `uci show network | grep batmesh` to see which one exists on your node.

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

## Checklist 4 — WiFi AP Not Broadcasting

**Symptom:** The AP SSID doesn't appear on scanners, or it appears but connections fail. `ip link show <ap-iface>` shows `state DOWN` and `hostapd` logs show `nl80211: Could not set interface UP` / `No such device`.

This happens when a USB WiFi adapter (e.g. Panda RT5370) gets into a ghost state — the interface object exists in the kernel but the underlying device is unresponsive. `ip link set <iface> up` returns `RTNETLINK answers: No such device` even though the interface appears in `ip link show`.

- [ ] **Try reloading wifi first:**
  ```sh
  wifi reconf
  sleep 5
  ip link show phy2-ap0   # check if it's UP
  ```

- [ ] **If still DOWN, reset the USB adapter by unbinding and rebinding the driver:**
  ```sh
  # Find the USB path for your adapter (look for the RT5370 / 148F:5370 device)
  ls /sys/bus/usb/drivers/rt2800usb/
  # Should show something like "1-1.2:1.0"

  echo "1-1.2:1.0" > /sys/bus/usb/drivers/rt2800usb/unbind
  sleep 2
  echo "1-1.2:1.0" > /sys/bus/usb/drivers/rt2800usb/bind
  sleep 3
  wifi reconf
  ```
  After this, the AP should come up and be joinable.

- [ ] **If the channel is set to `auto`**, the driver may fail to start the AP. Fix it:
  ```sh
  uci set wireless.radio0.channel='6'
  uci set wireless.radio0.htmode='HT20'
  uci commit wireless && wifi reconf
  ```

- [ ] **If encryption is `sae` (WPA3)**, the RT5370 doesn't support it. Downgrade to WPA2:
  ```sh
  uci set wireless.default_radio0.encryption='psk2'
  uci commit wireless && wifi reconf
  ```

- [ ] **If the SSID name changed in LuCI but scanners still show the old name** — this is normal device/OS caching. Wait 30–60 seconds, toggle WiFi off and on on your device, or try a different scanner.

---

## Checklist 5 — Reticulum Peers Not Discovering Each Other

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
