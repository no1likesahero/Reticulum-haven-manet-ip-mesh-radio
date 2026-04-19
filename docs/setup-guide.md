# Haven Setup Guide

Step-by-step instructions for setting up a Haven mesh network.

**[Haven Guide](https://buildwithparallel.com/products/haven)** - Video tutorials, schematics, 3D printable enclosures, Discord community, and direct support.

> **Prerequisite:** All scripts assume each node is flashed with a fresh/recent version of [OpenMANET](https://openmanet.org/).
>
> **Fresh install:** Flash OpenMANET onto each node's microSD card using Raspberry Pi Imager, then insert the card and power on.
>
> **Upgrading an existing install:** Open LuCI → System → Backup / Flash Firmware → upload the OpenMANET image. **Uncheck "Keep settings"** for a clean slate.

## Step 1: Set Up the Gate Node (green)

This is the node that shares internet with the rest of the mesh.

1. Plug the gate node into your **upstream router via Ethernet**
2. Find the gate's IP address in your **router's device list**
3. Open a terminal on the gate — pick one:
   - **SSH:** `ssh root@<gate-ip>` from your computer
   - **Browser:** go to `http://<gate-ip>` → **Services → Terminal**
4. Run the setup script:
```bash
wget -O setup.sh https://raw.githubusercontent.com/buildwithparallel/haven-manet-ip-mesh-radio/main/scripts/setup-haven-gate.sh
sh setup.sh && reboot
```
5. Wait ~60 seconds for reboot

## Step 2: Add Point Nodes (blue)

Point nodes extend the mesh — no internet connection needed.

1. Plug Ethernet **directly from your computer to the point node**
2. Open a browser and go to `http://10.41.254.1`
3. Go to **Services → Terminal**
4. The point node has no internet, so you'll need to paste the script:
   - On your computer, open the [raw setup script](https://raw.githubusercontent.com/buildwithparallel/haven-manet-ip-mesh-radio/main/scripts/setup-haven-point.sh) in a browser tab
   - Select all and copy
   - Paste into the point node's terminal and press Enter
5. After the script finishes, type `reboot` and press Enter
6. Wait ~60 seconds for reboot

### Adding More Nodes

For each additional point node:
1. Edit `setup-haven-point.sh` with unique `HOSTNAME` and `MESH_IP`
2. Keep `MESH_ID`, `MESH_KEY`, `HALOW_CHANNEL` the same as gate
3. Run script and reboot

### Verify the Mesh

1. Connect to **green-5ghz** WiFi (password: `green-5ghz`)
2. Find the point node's mesh IP (run `uci get network.ahwlan.ipaddr` on the point node, or check its boot screen)
3. Browse to **http://\<point-mesh-ip\>** — if blue's LuCI loads, your mesh is working

```bash
iwinfo wlan0 info     # HaLow link quality
batctl n              # BATMAN-adv neighbors
ping <gate-mesh-ip>   # Ping gateway (find with: uci get network.ahwlan.ipaddr on the gate)
```

<img src="../assets/mesh-verify.png" alt="Mesh verification from point node" width="500">

> After setup, use LuCI's web interface to change passwords, WiFi SSIDs, and other settings on each node. See [Finding & Accessing Nodes](finding-nodes.md) to reach each node.

### Connect Your Device

After setup, connect your computer, phone, or tablet to the Haven network:

1. **Join the node's WiFi** — look for `green-5ghz` or `blue-5ghz` in your WiFi list
   - Gate WiFi password: `green-5ghz`
   - Point WiFi password: `blue-5ghz`
2. **Verify your device got an IP** — you should receive an address in the `10.41.x.x` range
   - **Mac/Linux:** `ifconfig` or `ip addr` — look for `10.41.x.x` on your WiFi interface
   - **Windows:** `ipconfig` — look for `10.41.x.x` under your Wi-Fi adapter
   - **Phone:** Settings → WiFi → tap the connected network to see your IP
3. **Access the node's web interface** — browse to `http://<node-mesh-ip>`
   - Find the mesh IP by running `uci get network.ahwlan.ipaddr` on the node, or check its boot screen

> **Can't see the WiFi network?** See [Troubleshooting → WiFi AP Not Broadcasting](troubleshooting.md#checklist-4--wifi-ap-not-broadcasting).
>
> **Alternative:** If the gate node is plugged into your home router, you can also connect your computer to your **regular home WiFi** and access the gate at the IP shown in your router's device list — no need to switch WiFi networks.

## Step 3: Install Reticulum (Optional)

Adds an encrypted communications overlay to the mesh. Run on **each node** that needs Reticulum:

```bash
wget -O /tmp/setup-reticulum.sh https://raw.githubusercontent.com/buildwithparallel/haven-manet-ip-mesh-radio/main/scripts/setup-reticulum.sh
sh /tmp/setup-reticulum.sh
/etc/init.d/rnsd enable && /etc/init.d/rnsd start
```

See [Reticulum/README.md](../Reticulum/README.md) for configuration details, interface types, and how HaLow traffic reaches Reticulum.

## Step 4: Send Reticulum Messages (Optional)

Three scripts for demonstrating and monitoring Reticulum data transfer over the Haven mesh. Requires [Step 3](#step-3-install-reticulum-optional).

See [scripts/README.md](../scripts/README.md) for full usage and example output of `rns_status.py`, `rns_send.py`, and `rns_receive.py`.

## Step 5: Install the ATAK Bridge (Optional)

Bridges ATAK/CivTAK situational awareness traffic over Reticulum. Requires [Step 3](#step-3-install-reticulum-optional).

```bash
wget -O /tmp/setup-cot-bridge.sh https://raw.githubusercontent.com/buildwithparallel/haven-manet-ip-mesh-radio/main/scripts/setup-cot-bridge.sh
sh /tmp/setup-cot-bridge.sh
/etc/init.d/cot_bridge enable && /etc/init.d/cot_bridge start
```

See [ATAK/README.md](../ATAK/README.md) for peering, live dashboards, and troubleshooting.

### Verify ATAK Bridge
```bash
tail -f /tmp/bridge.log
```

---

## Configuring Heltec HaLow Nodes (BATMAN-adv)

The `configure-heltec.sh` script sets up [Heltec HaLow](https://heltec.org/project/ht-hd01/) nodes running OpenWrt to join the Haven mesh using BATMAN-adv routing over 802.11s.

<img src="../assets/heltec-1.JPG" alt="Heltec HaLow node" width="500">

This is an alternative to the standard point node setup — use it when your node is a Heltec v2 HaLow board rather than a Raspberry Pi with a HaLow HAT.

**What it does:**

1. Binds the HaLow mesh radio to `bat0` via a `batadv_hardif` interface
2. Disables 802.11s forwarding (BATMAN-adv handles routing instead)
3. Creates `bat0` with BATMAN_V in client gateway mode
4. Bridges `bat0` into `br-ahwlan` with a static mesh IP
5. Connects the local WiFi AP to the mesh bridge so clients get internet
6. Removes conflicting anonymous bridge devices from the default firmware

**Usage:**

1. SSH into the Heltec node: `ssh root@10.42.0.1`
2. Edit the configuration variables at the top of the script (`HOSTNAME`, `MESH_IP`, etc.) for your node
3. Paste the script into the terminal and run it
4. Reboot: `reboot`

```bash
# Configuration variables to set per-node:
HOSTNAME="heltec-4"
MESH_IP="10.41.0.4"
MESH_NETMASK="255.255.0.0"
GATEWAY_IP="10.41.0.3"
```

After reboot, the node is reachable at `MESH_IP` on the mesh network.

> **Note:** The Heltec default firmware ships with an anonymous bridge device for `br-ahwlan` that conflicts with BATMAN-adv. The script automatically detects and removes these before creating the correct bridge configuration.

---

## Default Credentials

All nodes use `root` as the username.

| Node | Password | WiFi SSID | WiFi Password |
|------|----------|-----------|---------------|
| Gate (green) | `havengreen` | `green-5ghz` | `green-5ghz` |
| Gate (green) 2.4GHz | — | `green` | `greengreen` |
| Point (blue) | `havenblue` | `blue-5ghz` | `blue-5ghz` |
| Heltec | `heltec.org` | varies | varies |

---

## Configuration Reference

### Gate Node Defaults (green)

| Setting | Default | Description |
|---------|---------|-------------|
| `HOSTNAME` | green | Node hostname |
| `ROOT_PASSWORD` | havengreen | SSH/LuCI password |
| `MESH_ID` | haven | Mesh network name |
| `MESH_KEY` | havenmesh | Mesh encryption key |
| `MESH_IP` | 10.41.0.1 | Initial node IP (openmanetd may reassign) |
| `HALOW_CHANNEL` | 27 | HaLow channel (914 MHz) |
| `HALOW_HTMODE` | HT20 | Channel width (2 MHz) |

### Point Node Defaults (blue)

| Setting | Default | Description |
|---------|---------|-------------|
| `HOSTNAME` | blue | Node hostname |
| `ROOT_PASSWORD` | havenblue | SSH/LuCI password |
| `MESH_IP` | 10.41.0.2 | Initial node IP (openmanetd may reassign) |
| `GATEWAY_IP` | 10.41.0.1 | Initial gate node IP (openmanetd may reassign) |

> **Note:** OpenMANET's address reservation system manages mesh IPs on all nodes after setup. The defaults above are initial values — the final IPs may differ. Run `uci get network.ahwlan.ipaddr` on any node to find its current mesh IP, or check the boot screen on a connected monitor. To discover the IPs of all mesh nodes from any node, run:
> ```
> strings /etc/openmanetd/openmanetd.db
> ```
> This prints each node's MAC address, hostname, and current mesh IP.
