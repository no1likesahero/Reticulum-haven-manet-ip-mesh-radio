#!/bin/sh
# haven-diag.sh — Run on any Haven node to diagnose mesh problems.
# Prints plain-English verdicts for every common failure mode.
#
# Usage:  sh haven-diag.sh
#         wget -O- https://raw.githubusercontent.com/buildwithparallel/haven-manet-ip-mesh-radio/main/scripts/node-ops/haven-diag.sh | sh

PASS="[OK]"
FAIL="[!!]"
WARN="[??]"
problems=0

echo ""
echo "=============================="
echo "  Haven Mesh Diagnostics"
echo "=============================="
echo ""

# --- Node identity ---
hostname=$(cat /proc/sys/kernel/hostname 2>/dev/null)
mesh_ip=$(uci get network.ahwlan.ipaddr 2>/dev/null)
gateway=$(uci get network.ahwlan.gateway 2>/dev/null)
echo "Node:     $hostname"
echo "Mesh IP:  ${mesh_ip:-unknown}"
echo "Gateway:  ${gateway:-none (this may be the gate)}"
echo ""

# --- 1. HaLow driver ---
echo "--- HaLow Radio ---"
if dmesg | grep -q "morse_spi.*cmd53.*failed\|errno=-71"; then
    echo "$FAIL HaLow SPI errors detected — radio chip not responding"
    echo "     Fix: rmmod morse && modprobe morse"
    echo "     If that fails: full power cycle (unplug from wall)"
    problems=$((problems + 1))
elif ! ip link show wlan0 >/dev/null 2>&1; then
    echo "$FAIL wlan0 does not exist — HaLow driver not loaded"
    echo "     Fix: modprobe morse && sleep 5"
    problems=$((problems + 1))
else
    signal=$(iwinfo wlan0 info 2>/dev/null | grep Signal | awk '{print $2}')
    echo "$PASS wlan0 exists (signal: ${signal:-unknown} dBm)"
fi

# --- 2. BATMAN ---
echo ""
echo "--- BATMAN-adv ---"
batctl_if=$(batctl if 2>/dev/null)
if echo "$batctl_if" | grep -q "wlan0.*active"; then
    echo "$PASS wlan0 is in bat0 (BATMAN active)"
else
    echo "$FAIL wlan0 is NOT in bat0 — BATMAN routing disabled"
    # Diagnose why
    mesh_net=$(uci show wireless 2>/dev/null | grep "mode='mesh'" | head -1 | cut -d. -f2)
    if [ -n "$mesh_net" ]; then
        current_net=$(uci get wireless.$mesh_net.network 2>/dev/null)
        echo "     Mesh interface '$mesh_net' has network='$current_net'"
        if [ "$current_net" = "ahwlan" ]; then
            echo "     Problem: network should be 'batmesh0' (gate) or 'batmesh' (point)"
            echo "     Fix: uci set wireless.$mesh_net.network='batmesh0'"
            echo "          uci commit wireless && wifi reload"
        fi
    fi
    # Check if batmesh hardif exists
    if ! uci show network.batmesh0 >/dev/null 2>&1 && ! uci show network.batmesh >/dev/null 2>&1; then
        echo "     Problem: no batmesh hardif interface exists"
        echo "     Fix: uci set network.batmesh0=interface"
        echo "          uci set network.batmesh0.proto='batadv_hardif'"
        echo "          uci set network.batmesh0.master='bat0'"
        echo "          uci commit network && service network restart"
    fi
    problems=$((problems + 1))
fi

# BATMAN neighbors
neighbors=$(batctl n 2>/dev/null | grep -c "wlan0")
if [ "$neighbors" -gt 0 ]; then
    echo "$PASS BATMAN sees $neighbors neighbor(s)"
else
    echo "$WARN No BATMAN neighbors — other nodes may be off or out of range"
fi

# --- 3. Bridge ---
echo ""
echo "--- Bridge (br-ahwlan) ---"
bridge_members=$(brctl show br-ahwlan 2>/dev/null)

if echo "$bridge_members" | grep -q "bat0"; then
    echo "$PASS bat0 is in br-ahwlan"
else
    echo "$FAIL bat0 is NOT in br-ahwlan — mesh traffic can't reach clients"
    echo "     Quick fix: ip link set bat0 up && ip link set bat0 master br-ahwlan"
    echo "     Permanent: check network.ahwlan_dev.ports includes 'bat0'"
    problems=$((problems + 1))
fi

# Check bat0 is UP
bat0_state=$(ip link show bat0 2>/dev/null | grep -o "state [A-Z]*" | awk '{print $2}')
if [ "$bat0_state" = "DOWN" ]; then
    echo "$FAIL bat0 is DOWN — needs to be brought up"
    echo "     Fix: ip link set bat0 up"
    problems=$((problems + 1))
elif [ -n "$bat0_state" ]; then
    echo "$PASS bat0 is $bat0_state"
fi

if echo "$bridge_members" | grep -qE "phy[0-9]"; then
    echo "$PASS WiFi AP is in br-ahwlan"
else
    echo "$FAIL WiFi AP missing from br-ahwlan — clients can't reach the mesh"
    problems=$((problems + 1))
fi

# Check for anonymous bridge device conflict
anon_br=$(uci show network 2>/dev/null | grep "@device.*name='br-ahwlan'")
if [ -n "$anon_br" ]; then
    echo "$FAIL Anonymous br-ahwlan device found — this shadows the named one"
    echo "     Fix: run haven-bridge-check.sh or see troubleshooting docs"
    problems=$((problems + 1))
fi

# Check wlan0 isn't directly in bridge (bypassing bat0)
wlan0_master=$(ip link show wlan0 2>/dev/null | grep -o "master [a-z0-9-]*" | awk '{print $2}')
if [ "$wlan0_master" = "br-ahwlan" ]; then
    echo "$FAIL wlan0 is in br-ahwlan directly (bypassing bat0!)"
    echo "     This means BATMAN routing is completely bypassed"
    echo "     Fix: set mesh interface network to 'batmesh0' (gate) or 'batmesh' (point)"
    problems=$((problems + 1))
elif [ "$wlan0_master" = "bat0" ]; then
    echo "$PASS wlan0 → bat0 → br-ahwlan (correct path)"
fi

# --- 4. IP connectivity ---
echo ""
echo "--- Connectivity ---"
if [ -n "$mesh_ip" ]; then
    echo "$PASS br-ahwlan has IP $mesh_ip"
else
    echo "$FAIL br-ahwlan has no IP — DHCP may have failed"
    problems=$((problems + 1))
fi

if [ -n "$gateway" ]; then
    if ping -c 1 -W 3 "$gateway" >/dev/null 2>&1; then
        echo "$PASS Can ping gateway ($gateway)"
    else
        echo "$FAIL Cannot ping gateway ($gateway)"
        problems=$((problems + 1))
    fi
fi

if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
    echo "$PASS Internet reachable"
else
    if [ -z "$gateway" ]; then
        # This might be the gate — check eth0
        if ip route show default | grep -q eth0; then
            echo "$FAIL Internet unreachable — check eth0 uplink"
        else
            echo "$FAIL No default route — check eth0 connection"
        fi
    else
        echo "$FAIL No internet — gateway unreachable or gate has no uplink"
    fi
    problems=$((problems + 1))
fi

# --- 5. WiFi APs ---
echo ""
echo "--- WiFi APs ---"
for iface in $(iwinfo 2>/dev/null | grep "ESSID" | awk '{print $1}'); do
    mode=$(iwinfo "$iface" info 2>/dev/null | grep Mode | awk '{print $2}')
    if [ "$mode" = "Master" ]; then
        ssid=$(iwinfo "$iface" info 2>/dev/null | grep ESSID | sed 's/.*ESSID: "\(.*\)"/\1/')
        echo "$PASS $iface broadcasting \"$ssid\""
    fi
done

# --- Summary ---
echo ""
echo "=============================="
if [ "$problems" -eq 0 ]; then
    echo "  All checks passed"
else
    echo "  $problems problem(s) found — see [!!] items above"
fi
echo "=============================="
echo ""
