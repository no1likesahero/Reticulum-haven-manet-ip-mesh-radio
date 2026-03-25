#!/bin/sh
#
# Configure Heltec HaLow Node for Haven BATMAN-adv Mesh
#
# Sets up BATMAN-adv routing over 802.11s HaLow mesh so the node
# participates in the Haven mesh network with gateway internet access.
#
# Usage: sh configure-heltec.sh
#
# What this does:
#   1. Binds the HaLow mesh radio to bat0 via batadv_hardif
#   2. Disables 802.11s forwarding (BATMAN handles routing)
#   3. Creates bat0 with BATMAN_V in client gateway mode
#   4. Bridges bat0 into br-ahwlan with static mesh IP
#   5. Connects the local WiFi AP to the mesh bridge
#
# After reboot, the node is reachable at MESH_IP on the mesh network.
# The local WiFi AP and Ethernet port both bridge to the mesh so all clients
# get a 10.41.x.x address and can reach each other (required for Reticulum).
#

set -e

#═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION - Modify these values for each node
#═══════════════════════════════════════════════════════════════════════════════

HOSTNAME="heltec-4"
MESH_IP="10.41.0.4"
MESH_NETMASK="255.255.0.0"
GATEWAY_IP="10.41.0.3"
DNS_SERVERS="8.8.8.8 8.8.4.4"

# Local WiFi AP (2.4GHz) - bridges to mesh after setup
WIFI_AP_SSID="heltec-4"
WIFI_AP_KEY="heltec-4"

#═══════════════════════════════════════════════════════════════════════════════
# SCRIPT START
#═══════════════════════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════════════════════"
echo "  Haven Mesh - Heltec Node Setup"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

if [ ! -f /etc/openwrt_release ]; then
    echo "ERROR: This script must be run on OpenWrt"
    exit 1
fi

# ── Find HaLow radio and mesh interface ──────────────────────────────────────

HALOW_RADIO=$(uci show wireless | grep "\.type='morse'" | head -1 | cut -d. -f2)
if [ -z "$HALOW_RADIO" ]; then
    echo "ERROR: No HaLow (morse) radio found"
    exit 1
fi

MESH_IFACE=$(uci show wireless | grep "wireless\..*\.device='$HALOW_RADIO'" | head -1 | cut -d. -f2)
if [ -z "$MESH_IFACE" ]; then
    echo "ERROR: No wireless interface found for $HALOW_RADIO"
    exit 1
fi

echo "[1/5] Setting hostname: $HOSTNAME"
uci set system.@system[0].hostname="$HOSTNAME"
uci commit system

echo "[2/5] Configuring HaLow mesh radio ($HALOW_RADIO / $MESH_IFACE)..."
# Disable 802.11s forwarding — BATMAN-adv handles routing instead
uci set wireless.$MESH_IFACE.mesh_fwding='0'
# Point wireless interface to batmesh hardif (not the bridge directly)
uci set wireless.$MESH_IFACE.network='batmesh'
uci commit wireless

echo "[3/5] Configuring BATMAN-adv..."
# bat0 — the BATMAN virtual interface
uci set network.bat0=interface
uci set network.bat0.proto='batadv'
uci set network.bat0.routing_algo='BATMAN_V'
uci set network.bat0.aggregated_ogms='1'
uci set network.bat0.gw_mode='client'
uci set network.bat0.orig_interval='1000'

# batmesh — binds the HaLow wlan to bat0 as a hard interface
uci set network.batmesh=interface
uci set network.batmesh.proto='batadv_hardif'
uci set network.batmesh.master='bat0'

echo "[4/5] Configuring bridge and mesh IP..."
# ahwlan — bridge interface with static IP on the mesh
uci set network.ahwlan=interface
uci set network.ahwlan.proto='static'
uci set network.ahwlan.device='br-ahwlan'
uci set network.ahwlan.ipaddr="$MESH_IP"
uci set network.ahwlan.netmask="$MESH_NETMASK"
uci set network.ahwlan.gateway="$GATEWAY_IP"
uci set network.ahwlan.dns="$DNS_SERVERS"
uci set network.ahwlan.delegate='0'
# NOTE: Do NOT set network.ahwlan.type='bridge' — it auto-creates anonymous
# bridge devices that conflict with our explicit ahwlan_dev definition.

# Remove any anonymous bridge devices for br-ahwlan that lack bat0 port.
# These conflict with the named ahwlan_dev and cause bat0 to be left out
# of the bridge, breaking IP connectivity over BATMAN.
i=0
while uci get network.@device[$i] >/dev/null 2>&1; do
    dev_name=$(uci get network.@device[$i].name 2>/dev/null)
    if [ "$dev_name" = "br-ahwlan" ]; then
        echo "  Removing conflicting anonymous device[$i] for br-ahwlan"
        uci delete network.@device[$i]
        continue
    fi
    i=$((i + 1))
done

# Bridge device — bat0 and eth0.1 so wired Ethernet clients land on the same
# 10.41.x.x mesh subnet as WiFi clients. Required for Reticulum AutoInterface
# multicast discovery to work across all client types.
# Remove eth0.1 from the default lan bridge first to avoid it being in two bridges.
LAN_DEV=$(uci show network | grep "\.name='br-lan'" | head -1 | cut -d. -f2)
if [ -n "$LAN_DEV" ]; then
    uci del_list network.$LAN_DEV.ports='eth0.1' 2>/dev/null || true
fi

uci set network.ahwlan_dev=device
uci set network.ahwlan_dev.name='br-ahwlan'
uci set network.ahwlan_dev.type='bridge'
uci delete network.ahwlan_dev.ports 2>/dev/null || true
uci add_list network.ahwlan_dev.ports='bat0'
uci add_list network.ahwlan_dev.ports='eth0.1'

uci commit network

echo "[5/5] Configuring WiFi AP, DHCP, firewall..."
# Connect local 2.4GHz AP to the mesh bridge so WiFi clients get internet
WIFI_AP_IFACE=$(uci show wireless | grep "\.mode='ap'" | head -1 | cut -d. -f2)
if [ -n "$WIFI_AP_IFACE" ]; then
    uci set wireless.$WIFI_AP_IFACE.ssid="$WIFI_AP_SSID"
    uci set wireless.$WIFI_AP_IFACE.key="$WIFI_AP_KEY"
    uci set wireless.$WIFI_AP_IFACE.network='ahwlan'
    uci commit wireless
    echo "  WiFi AP: $WIFI_AP_SSID → ahwlan bridge"
fi

# Disable DHCP — the gate handles DHCP for the mesh
uci set dhcp.ahwlan=dhcp
uci set dhcp.ahwlan.interface='ahwlan'
uci set dhcp.ahwlan.ignore='1'
uci commit dhcp

# Add mesh to firewall LAN zone
uci add_list firewall.@zone[0].network='ahwlan' 2>/dev/null || true
uci commit firewall

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  Heltec Node Setup Complete!"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "  Hostname:     $HOSTNAME"
echo "  Mesh IP:      $MESH_IP"
echo "  Gateway:      $GATEWAY_IP"
echo "  WiFi AP:      $WIFI_AP_SSID"
echo "  BATMAN mode:  client (BATMAN_V)"
echo ""
echo "  Reboot now:   reboot"
echo ""
echo "  NOTE: After reboot, this node is reachable at $MESH_IP"
echo "        on the mesh network (not 10.42.0.1)."
echo ""
echo "═══════════════════════════════════════════════════════════════════"
