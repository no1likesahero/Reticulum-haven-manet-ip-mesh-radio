#!/bin/sh
#
# Haven Point - Mesh Extender Node Setup Script
# Configures basic mesh networking (no internet uplink)
#
# Usage: sh setup-haven-point.sh
#

set -e

#═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION - Modify these values as needed
#═══════════════════════════════════════════════════════════════════════════════

# Node identity (change for each point node)
HOSTNAME="blue"
ROOT_PASSWORD="havenblue"

# Mesh network settings - MUST MATCH GATE NODE
MESH_ID="haven"
MESH_KEY="havenmesh"
MESH_IP="10.41.0.2"           # Initial IP; openmanetd may reassign after boot
MESH_NETMASK="255.255.0.0"
GATEWAY_IP="10.41.0.1"        # Initial gate IP; openmanetd may reassign after boot
DNS_SERVERS="8.8.8.8 8.8.4.4"

# HaLow radio settings - MUST MATCH GATE NODE
HALOW_CHANNEL="28"
HALOW_HTMODE="HT80"

# Client WiFi AP (2.4GHz only: USB, e.g. Panda RT5370) — use network 'ahwlan' (flat
# 10.41.0.0/16, DHCP on the gate). This script does not configure onboard 5GHz; HaLow + USB 2.4G
# is the supported combo for point nodes. Set ENABLE_2G4_AP=0 to skip the client AP.
ENABLE_2G4_AP="1"
WIFI_2G4_SSID="blue-2g"
WIFI_2G4_KEY="blue-2g"
WIFI_2G4_CHANNEL="1"

#═══════════════════════════════════════════════════════════════════════════════
# SCRIPT START
#═══════════════════════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════════════════════"
echo "  Haven Point Setup - Mesh Extender Node"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

if [ ! -f /etc/openwrt_release ]; then
    echo "ERROR: This script must be run on OpenWrt/OpenMANET"
    exit 1
fi

echo "[1/6] Setting hostname and password..."
uci set system.@system[0].hostname="$HOSTNAME"
uci commit system
(echo "$ROOT_PASSWORD"; echo "$ROOT_PASSWORD") | passwd root

echo "[2/6] Configuring HaLow mesh radio (802.11ah)..."
HALOW_RADIO=$(uci show wireless | grep "morse" | head -1 | cut -d. -f2)
if [ -z "$HALOW_RADIO" ]; then
    echo "WARNING: No HaLow radio found, skipping"
else
    echo "  Found HaLow radio: $HALOW_RADIO"
    uci set wireless.$HALOW_RADIO.disabled='0'
    uci set wireless.$HALOW_RADIO.channel="$HALOW_CHANNEL"
    uci set wireless.$HALOW_RADIO.htmode="$HALOW_HTMODE"

    HALOW_IFACE=$(uci show wireless | grep "wireless\..*\.device='$HALOW_RADIO'" | head -1 | cut -d. -f2)
    if [ -z "$HALOW_IFACE" ]; then
        HALOW_IFACE="mesh_halow"
        uci set wireless.$HALOW_IFACE=wifi-iface
    fi

    uci set wireless.$HALOW_IFACE.device="$HALOW_RADIO"
    uci set wireless.$HALOW_IFACE.mode='mesh'
    uci set wireless.$HALOW_IFACE.mesh_id="$MESH_ID"
    uci set wireless.$HALOW_IFACE.encryption='sae'
    uci set wireless.$HALOW_IFACE.key="$MESH_KEY"
    uci set wireless.$HALOW_IFACE.network='batmesh'
    uci set wireless.$HALOW_IFACE.mesh_fwding='0'
    uci set wireless.$HALOW_IFACE.beacon_int='1000'

    # batmesh — binds the HaLow wlan to bat0 as a hard interface
    uci set network.batmesh=interface
    uci set network.batmesh.proto='batadv_hardif'
    uci set network.batmesh.master='bat0'
fi

echo "[3/6] Configuring 2.4GHz client access point (USB/RT5370-friendly)…"
WIFI2_RADIO=
if [ "$ENABLE_2G4_AP" = 1 ] && [ -n "$WIFI_2G4_SSID" ]; then
    WIFI2_RADIO=$(uci show wireless 2>/dev/null | grep "\.band='2g'" | head -1 | cut -d. -f2)
    if [ -z "$WIFI2_RADIO" ]; then
        echo "  WARNING: ENABLE_2G4_AP=1 but no 2.4GHz radio in UCI — skip (plug USB WiFi, rescan, or set ENABLE_2G4_AP=0)"
    else
        echo "  Found 2.4GHz radio: $WIFI2_RADIO"
        uci set "wireless.$WIFI2_RADIO.disabled"="0"
        uci set "wireless.$WIFI2_RADIO.channel"="$WIFI_2G4_CHANNEL"
        uci set "wireless.$WIFI2_RADIO.htmode"="HT20"

        WIFI2_IFACE=$(uci show wireless | grep "wireless\..*\.device='$WIFI2_RADIO'" | head -1 | cut -d. -f2)
        if [ -z "$WIFI2_IFACE" ]; then
            WIFI2_IFACE="ap_2g4"
            uci set "wireless.$WIFI2_IFACE=wifi-iface"
        elif [ "$(uci -q get "wireless.$WIFI2_IFACE.mode")" = "mesh" ]; then
            WIFI2_IFACE="ap_2g4"
            uci set "wireless.$WIFI2_IFACE=wifi-iface"
        fi
        uci set "wireless.$WIFI2_IFACE.device"="$WIFI2_RADIO"
        uci set "wireless.$WIFI2_IFACE.mode"="ap"
        uci set "wireless.$WIFI2_IFACE.ssid"="$WIFI_2G4_SSID"
        uci set "wireless.$WIFI2_IFACE.encryption"="psk2"
        uci set "wireless.$WIFI2_IFACE.key"="$WIFI_2G4_KEY"
        uci set "wireless.$WIFI2_IFACE.network"="ahwlan"
    fi
else
    echo "  (2.4GHz client AP disabled — set ENABLE_2G4_AP=1 and SSID/key to enable)"
fi

echo "[4/6] Configuring bridge and BATMAN-adv..."
uci set network.ahwlan=interface
uci set network.ahwlan.proto='static'
uci set network.ahwlan.ipaddr="$MESH_IP"
uci set network.ahwlan.netmask="$MESH_NETMASK"
uci set network.ahwlan.gateway="$GATEWAY_IP"
uci set network.ahwlan.dns="$DNS_SERVERS"
uci set network.ahwlan.delegate='0'
# NOTE: Do NOT set network.ahwlan.type='bridge' — it auto-creates anonymous
# bridge devices that conflict with our explicit ahwlan_dev definition.

uci set network.bat0=interface
uci set network.bat0.proto='batadv'
uci set network.bat0.routing_algo='BATMAN_V'
uci set network.bat0.aggregated_ogms='1'
uci set network.bat0.gw_mode='client'
uci set network.bat0.orig_interval='1000'

uci set network.ahwlan.device='br-ahwlan'

# Remove anonymous bridge devices for br-ahwlan — these conflict with the
# named ahwlan_dev and cause bat0 to be left out of the bridge.
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

# Named bridge device with bat0 — explicit ports list (not add_list, to avoid dupes)
uci set network.ahwlan_dev=device
uci set network.ahwlan_dev.name='br-ahwlan'
uci set network.ahwlan_dev.type='bridge'
uci delete network.ahwlan_dev.ports 2>/dev/null || true
uci add_list network.ahwlan_dev.ports='bat0'
uci commit network

echo "[5/6] Disabling point DHCP (gate hands out 10.41.x.x) and firewall zone…"
uci set dhcp.ahwlan=dhcp
uci set dhcp.ahwlan.interface='ahwlan'
uci set dhcp.ahwlan.ignore='1'
uci commit dhcp
uci add_list firewall.@zone[0].network='ahwlan' 2>/dev/null || true
uci commit firewall

# shellcheck disable=SC2013
echo "[6/6] Committing wireless, reconf, and br-ahwlan client AP port(s)…"
uci commit wireless
wifi reconf
sleep 4
# OpenMANET/Haven use an explicit ahwlan_dev.ports list (not only 'bat0'); client APs on
# network=ahwlan must be listed or clients associate but get no 10.41 address (and never
# 'join' a missing 'lan' — there is no separate lan on these images). Add any *-ap* ifaces.
_P="$(uci -q get network.ahwlan_dev.ports 2>/dev/null)"
for p in /sys/class/net/*-ap*; do
    [ -e "$p" ] || continue
    n="${p##*/}"
    echo " $_P " | grep -q " $n " && continue
    uci add_list "network.ahwlan_dev.ports"="$n"
    _P="$_P $n"
done
uci commit network
if [ -x /etc/init.d/network ]; then
    /etc/init.d/network reload
elif [ -x /sbin/wifi ]; then
    /sbin/wifi
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  Haven Point Setup Complete!"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "  Hostname:     $HOSTNAME"
echo "  Mesh IP:      $MESH_IP"
echo "  Gateway:      $GATEWAY_IP"
[ "$ENABLE_2G4_AP" = 1 ] && [ -n "$WIFI_2G4_SSID" ] && echo "  2.4GHz SSID:  $WIFI_2G4_SSID  (USB; br-ahwlan in step 6)"
echo "  Mesh ID:      $MESH_ID"
echo ""
echo "  Reboot now:   reboot"
echo ""
echo "  Optional next steps after reboot:"
echo "    - Install Reticulum:  sh setup-reticulum.sh"
echo "    - Install ATAK bridge: sh setup-cot-bridge.sh"
echo ""
echo "═══════════════════════════════════════════════════════════════════"
