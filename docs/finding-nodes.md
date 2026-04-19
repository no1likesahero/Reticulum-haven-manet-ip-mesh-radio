# Finding & Accessing Nodes

After setup, you need to find each node's IP to access its web interface (LuCI) or SSH in. This is the most common task on the mesh — especially for point nodes connected via BATMAN-adv, which don't have predictable IPs.

**Default credentials** (user: `root`):

| Node | Password |
|------|----------|
| Gate (green) | `havengreen` |
| Point (blue) | `havenblue` |
| Heltec | `heltec.org` |

---

## Quick Answer: "I'm on green's WiFi, how do I reach blue's LuCI?"

1. SSH into the gate: `ssh root@<gate-ip>`
2. Find blue's IP: `cat /tmp/dhcp.leases` or `strings /etc/openmanetd/openmanetd.db`
3. Open `http://<blue-ip>` in your browser (while still on green's WiFi)

This works because the gate bridges WiFi clients onto the same mesh subnet. Your laptop on green's WiFi can reach any `10.41.x.x` address directly.

---

## Method 1: Run a command on the node

If you can reach the node's web interface or SSH into it, run this command to print its mesh IP:
```bash
uci get network.ahwlan.ipaddr
```

Two ways to get a terminal on the node:
- **SSH from your computer:** `ssh root@<node-ip>` (use the node's password)
- **LuCI web terminal:** browse to `http://<node-ip>`, then go to **Services → Terminal**. Log in as `root` with the node's password.

<img src="../assets/luci-terminal-ip.png" alt="LuCI terminal showing uci get network.ahwlan.ipaddr" width="500">

To find the node's MAC address instead:
```bash
cat /sys/class/net/wlan0/address    # HaLow mesh radio MAC
cat /sys/class/net/eth0/address     # Ethernet MAC
```

Use this when you can already reach the node but need to confirm its IP or MAC for other tools.

## Method 2: Query from the gate

If you can access the gate but need to find other nodes on the mesh:

```bash
# OpenMANET nodes (gate, point) — lists all known nodes with MAC, hostname, and IP
strings /etc/openmanetd/openmanetd.db

# All devices on the mesh (nodes AND clients like phones/laptops)
# Look for hostnames to tell nodes apart from client devices
cat /tmp/dhcp.leases

# All devices — shows ARP neighbors currently reachable on the mesh
ip neigh show dev br-ahwlan
```

The `strings` command only shows OpenMANET nodes (gate, point). Heltec/OpenWrt nodes won't appear there — use `cat /tmp/dhcp.leases` or `ip neigh` for those.

> **Tip:** `dhcp.leases` only shows devices that received a DHCP lease from the gate. If a node has a static IP and never requested DHCP, it won't appear here. Use `ip neigh` or `batctl n` to find it.

## Method 3: Connect to the node's WiFi

Connect your computer to the node's WiFi AP (e.g. `green-5ghz`, `blue-5ghz`, `heltec-5`). If the mesh is working, DHCP will give your computer a `10.41.x.x` address. Check the **Router** field in your network settings — that's the node's IP. Browse to `http://<router-ip>`.

## Method 4: HDMI monitor + static IP (node not on the mesh)

If the node isn't on the mesh yet (no gate, first-time setup, or misconfigured), connecting to its WiFi will give you a `169.254.x.x` self-assigned IP because there's no DHCP server. To get in:

1. **Connect a monitor** to the node via HDMI. The boot screen shows the IP at the bottom — look for the `br-ahwlan` line after `inet`:

<img src="../assets/point-boot-screen.JPG" alt="Point node boot screen" width="500">

<img src="../assets/point-boot-ip.JPG" alt="Point node IP on boot screen" width="500">

2. **Connect to the node's WiFi** (or plug in via Ethernet)

3. **Set a static IP** on your computer on the same subnet as the node:
   - **Configure IPv4**: Manually
   - **IP Address**: same as the node but change the last number (e.g. `10.41.126.199`)
   - **Subnet Mask**: `255.255.255.0`
   - **Router**: the node's IP (e.g. `10.41.126.198`)

<img src="../assets/meshpoint-wifi-settings.png" alt="macOS WiFi static IP configuration" width="500">

4. **Browse to** `http://<node-ip>` — LuCI should load

> **Remember** to set your WiFi back to DHCP (automatic) when you're done.

## Method 5: SSH through the gate (Heltec/OpenWrt nodes)

Heltec HaLow nodes running OpenWrt aren't in the OpenMANET database and may not be directly reachable from your computer. You can reach them by jumping through the gate:

1. Find the Heltec node's IP from the gate: `cat /tmp/dhcp.leases`
2. SSH through the gate using ProxyCommand:
```bash
ssh -o ProxyCommand="ssh -W %h:%p root@<gate-ip>" root@<node-mesh-ip>
```
3. Or with `sshpass` for scripting:
```bash
sshpass -p '<node-pw>' ssh -o StrictHostKeyChecking=no \
  -o ProxyCommand="sshpass -p '<gate-pw>' ssh -o StrictHostKeyChecking=no -W %h:%p root@<gate-ip>" \
  root@<node-mesh-ip>
```

This is how you manage Heltec nodes that are only reachable on the mesh — your computer talks to the gate over your LAN, and the gate forwards the connection over the mesh to the Heltec node.

## Method 6: Connect directly to a Heltec node's WiFi

Heltec nodes have a 2.4GHz WiFi AP and a separate LAN on `10.42.0.0/24`. Connect to the Heltec's WiFi, then:

- **Web interface:** browse to `http://10.42.0.1`
- **SSH:** `ssh root@10.42.0.1`

This bypasses the mesh entirely — useful for initial setup or when the mesh is down. The default password is `heltec.org` unless you changed it.

---

## Node-Specific Access

### Gate Node (green)

| Method | Steps |
|--------|-------|
| Gate WiFi | Connect to **green-5ghz** (password: `green-5ghz`), browse to **http://\<gate-mesh-ip\>** |
| Upstream network | Connect to your upstream router's WiFi, find the gate's IP in your router's device list, browse to that IP |

### Point Node (blue)

| Method | Steps |
|--------|-------|
| Point WiFi | Connect to **blue-5ghz** (password: `blue-5ghz`), browse to **http://\<point-mesh-ip\>** |
| Gate WiFi (via mesh) | Connect to **green-5ghz**, browse to **http://\<point-mesh-ip\>** (find the IP using Method 2) |

> **Tip:** If you can reach the point node's LuCI through the gate node's WiFi, your mesh is working.

---

## Still Can't Find or Reach a Node?

If none of the methods above work, the node may not be on the mesh yet:

```bash
# On the gate — check if BATMAN sees any neighbors
batctl n

# No neighbors? The node's HaLow radio isn't meshing.
# Check: is it powered on? In range? Same channel/key?
# See the full troubleshooting guide: docs/troubleshooting.md
```

See [Troubleshooting](troubleshooting.md) for detailed diagnostics.
