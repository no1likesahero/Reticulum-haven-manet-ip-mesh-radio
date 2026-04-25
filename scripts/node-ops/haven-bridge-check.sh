#!/bin/sh
#
# Haven Mesh Health Check
#
# Runs at boot to ensure the BATMAN-adv mesh is properly configured:
#   1. bat0 is in br-ahwlan bridge (not missing due to anonymous device conflict)
#   2. HaLow mesh radio points to batmesh hardif (not directly to bridge)
#   3. batmesh hardif interface exists and points to bat0
#
# Install as an init script:
#   scp haven-bridge-check.sh root@<node>:/etc/init.d/haven-bridge-check
#   ssh root@<node> "chmod +x /etc/init.d/haven-bridge-check && /etc/init.d/haven-bridge-check enable"
#
# Run manually to diagnose:
#   sh haven-bridge-check.sh
#

BRIDGE="br-ahwlan"
PORT="bat0"
TAG="haven-mesh"

log() {
    logger -t "$TAG" "$1"
    echo "$1"
}

check_and_fix() {
    needs_restart=0

    # ── Wait for bat0 ────────────────────────────────────────────────────
    for try in 1 2 3 4 5; do
        [ -d "/sys/class/net/$PORT" ] && break
        sleep 2
    done
    if [ ! -d "/sys/class/net/$PORT" ]; then
        log "WARNING: $PORT does not exist, skipping checks"
        return
    fi

    # ── Check 1: bat0 in bridge ──────────────────────────────────────────
    if [ -d "/sys/class/net/$BRIDGE/brif/$PORT" ]; then
        log "OK: $PORT is in $BRIDGE"
    else
        log "FIXING: $PORT is NOT in $BRIDGE"

        # Clean anonymous bridge devices that shadow ahwlan_dev
        i=0
        while uci get network.@device[$i] >/dev/null 2>&1; do
            dev_name=$(uci get network.@device[$i].name 2>/dev/null)
            if [ "$dev_name" = "$BRIDGE" ]; then
                log "  Removing conflicting anonymous device[$i]"
                uci delete network.@device[$i]
                continue
            fi
            i=$((i + 1))
        done

        # Ensure named bridge device
        uci set network.ahwlan_dev=device
        uci set network.ahwlan_dev.name="$BRIDGE"
        uci set network.ahwlan_dev.type='bridge'
        uci delete network.ahwlan_dev.ports 2>/dev/null || true
        uci add_list network.ahwlan_dev.ports="$PORT"
        uci commit network
        needs_restart=1
    fi

    # ── Check 2: HaLow mesh radio uses batmesh/batmesh0, not ahwlan ────────
    # Some nodes use 'batmesh', others (e.g. gate on OpenMANET) use 'batmesh0'.
    # Both are valid — either maps to a batadv_hardif. Only 'ahwlan' is wrong.
    MESH_IFACE=$(uci show wireless 2>/dev/null | grep "\.mode='mesh'" | head -1 | cut -d. -f2)
    if [ -n "$MESH_IFACE" ]; then
        mesh_net=$(uci get wireless.$MESH_IFACE.network 2>/dev/null)
        case "$mesh_net" in
            batmesh|batmesh0)
                log "OK: wireless.$MESH_IFACE.network=$mesh_net"
                ;;
            *)
                # Detect which batmesh network exists on this node
                if uci get network.batmesh0 >/dev/null 2>&1; then
                    correct_net="batmesh0"
                else
                    correct_net="batmesh"
                fi
                log "FIXING: wireless.$MESH_IFACE.network was '$mesh_net', setting to '$correct_net'"
                uci set wireless.$MESH_IFACE.network="$correct_net"
                uci set wireless.$MESH_IFACE.mesh_fwding='0'
                uci commit wireless
                needs_restart=1
                ;;
        esac
    fi

    # ── Check 3: WiFi AP interfaces use ahwlan, not lan ─────────────────
    # If the AP network reverts to 'lan' or 'br-lan', clients get 10.42.x.x
    # and can't reach the mesh or discover Reticulum peers.
    for AP_IFACE in $(uci show wireless 2>/dev/null | grep "\.mode='ap'" | cut -d. -f2); do
        ap_net=$(uci get wireless.$AP_IFACE.network 2>/dev/null)
        case "$ap_net" in
            ahwlan)
                log "OK: wireless.$AP_IFACE.network=ahwlan"
                ;;
            lan|br-lan)
                log "FIXING: wireless.$AP_IFACE.network was '$ap_net', setting to 'ahwlan'"
                uci set wireless.$AP_IFACE.network='ahwlan'
                uci commit wireless
                needs_restart=1
                ;;
        esac
    done

    # ── Check 5: batmesh hardif exists ───────────────────────────────────
    batmesh_proto=$(uci get network.batmesh.proto 2>/dev/null)
    if [ "$batmesh_proto" = "batadv_hardif" ]; then
        log "OK: network.batmesh proto=batadv_hardif"
    else
        log "FIXING: Creating network.batmesh as batadv_hardif"
        uci set network.batmesh=interface
        uci set network.batmesh.proto='batadv_hardif'
        uci set network.batmesh.master='bat0'
        uci commit network
        needs_restart=1
    fi

    # ── Apply fixes if needed ────────────────────────────────────────────
    if [ "$needs_restart" = "1" ]; then
        log "Restarting network and wifi to apply fixes..."
        wifi down
        /etc/init.d/network restart
        sleep 3
        wifi up
        sleep 5

        if [ -d "/sys/class/net/$BRIDGE/brif/$PORT" ]; then
            log "FIXED: mesh networking repaired"
        else
            log "ERROR: repair failed — manual intervention needed"
        fi
    else
        log "All checks passed"
    fi
}

### procd init script interface ###
START=99
STOP=10

start() {
    check_and_fix &
}

boot() {
    start
}

# Allow running directly: sh haven-bridge-check.sh
case "$1" in
    start|boot) start ;;
    stop) ;;
    restart) start ;;
    enable|disable) ;;
    *) check_and_fix ;;
esac
