#!/usr/bin/env python3
"""
HaLow Range Test — audible mesh signal monitor for drive testing.

Run on a laptop connected to a Haven node's WiFi. SSHes into the node,
reads HaLow radio + BATMAN-adv stats every 4 seconds, and beeps based on
signal quality. Rapid high-pitched beeps = strong. Slow low beeps = weak.
Silence = dead.

Usage:
    python3 halow_range_test.py -p havenblue       # connected to blue's WiFi
    python3 halow_range_test.py -p havengreen       # connected to green's WiFi
    python3 halow_range_test.py -H 10.42.0.1 -p pw  # explicit host
    python3 halow_range_test.py --no-audio           # visual only
"""

import argparse
import json
import math
import os
import platform
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import time
import wave

# -- SNR thresholds (dB) --
SNR_DEAD = 2        # Below this: link unusable, silence
SNR_MAX  = 35       # Above this: max beep rate

# -- Beep timing (seconds between beeps) --
BEEP_FAST = 0.12    # At best signal
BEEP_SLOW = 2.5     # At worst usable signal

# -- Tone pitches (Hz) for signal quality bands --
TONE_FREQS = [500, 650, 800, 950, 1100]


def detect_gateway():
    """Auto-detect the default gateway (the mesh node we're connected to)."""
    try:
        if platform.system() == 'Darwin':
            r = subprocess.run(['route', '-n', 'get', 'default'],
                               capture_output=True, text=True, timeout=5)
            m = re.search(r'gateway:\s+([0-9.]+)', r.stdout)
        else:
            r = subprocess.run(['ip', 'route', 'show', 'default'],
                               capture_output=True, text=True, timeout=5)
            m = re.search(r'via\s+([0-9.]+)', r.stdout)
        return m.group(1) if m else None
    except Exception:
        return None


def make_beep(path, freq=900, duration=0.05, volume=0.7):
    """Generate a short beep WAV file."""
    rate = 44100
    n = int(rate * duration)
    with wave.open(path, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        for i in range(n):
            env = min(1.0, min(i, n - i) / (rate * 0.003))
            s = volume * env * math.sin(2 * math.pi * freq * i / rate)
            w.writeframes(struct.pack('<h', int(s * 32767)))


def find_player():
    """Find an audio player command."""
    for cmd in ['afplay', 'aplay', 'paplay']:
        try:
            if subprocess.run(['which', cmd], capture_output=True,
                              timeout=3).returncode == 0:
                return cmd
        except Exception:
            continue
    return None


def play(player, path):
    """Play a WAV file in the background."""
    if player:
        subprocess.Popen([player, path],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def ssh_run(ssh_base, cmd, timeout=10):
    """Run a single SSH command and return (stdout, stderr, returncode)."""
    r = subprocess.run(ssh_base + [cmd],
                       capture_output=True, text=True, timeout=timeout)
    return r.stdout.strip(), r.stderr.strip(), r.returncode


def short_mac(mac):
    """Shorten a MAC for display: 2c:c6:82:8a:2a:f6 -> 2c:c6:..2a:f6"""
    parts = mac.split(':')
    if len(parts) == 6:
        return f"{parts[0]}:{parts[1]}..{parts[4]}:{parts[5]}"
    return mac


def main():
    ap = argparse.ArgumentParser(
        description='HaLow Range Test — audible signal monitor for drive testing')
    ap.add_argument('-H', '--host',
                    help='Node IP (default: auto-detect gateway)')
    ap.add_argument('-u', '--user', default='root',
                    help='SSH user (default: root)')
    ap.add_argument('-p', '--password',
                    help='SSH password (e.g. havenblue, havengreen)')
    ap.add_argument('--no-audio', action='store_true',
                    help='Visual only, no beeps')
    args = ap.parse_args()

    # -- Resolve host --
    host = args.host or detect_gateway()
    if not host:
        print("ERROR: Could not detect gateway. Use -H <ip>")
        sys.exit(1)

    # -- Resolve password --
    password = args.password
    if not password:
        import getpass
        password = getpass.getpass(f"SSH password for {args.user}@{host}: ")

    # -- Check sshpass --
    if subprocess.run(['which', 'sshpass'], capture_output=True).returncode != 0:
        print("ERROR: sshpass required.")
        print("  macOS:  brew install hudochenkov/sshpass/sshpass")
        print("  Linux:  apt install sshpass")
        sys.exit(1)

    ssh_base = ['sshpass', '-p', password, 'ssh',
                '-o', 'StrictHostKeyChecking=no',
                '-o', 'ConnectTimeout=5',
                f'{args.user}@{host}']

    # ── Verify SSH connection ────────────────────────────────────────
    print(f"\n  Connecting to {args.user}@{host}...")
    try:
        out, err, rc = ssh_run(ssh_base, 'echo OK')
    except subprocess.TimeoutExpired:
        print("ERROR: SSH connection timed out")
        sys.exit(1)
    if 'OK' not in out:
        print("ERROR: SSH connection failed")
        if err:
            for line in err.splitlines()[:3]:
                print(f"  {line}")
        sys.exit(1)

    # ── Verify iwinfo is available ───────────────────────────────────
    out, _, _ = ssh_run(ssh_base, 'iwinfo wlan0 info 2>/dev/null | head -1')
    if not out:
        print("ERROR: 'iwinfo wlan0 info' returned nothing — no HaLow radio?")
        sys.exit(1)
    print(f"  Radio: {out.strip()}")

    # ── Get node hostname ────────────────────────────────────────────
    node_name, _, _ = ssh_run(ssh_base, 'hostname')
    node_name = node_name or host

    # ── Verify the full polling command ──────────────────────────────
    poll_once = (
        'INFO=$(iwinfo wlan0 info 2>/dev/null);'
        'SIG=$(echo "$INFO" | grep -oE "Signal: [-0-9]+" | grep -oE "[-0-9]+$");'
        'NOISE=$(echo "$INFO" | grep -oE "Noise: [-0-9]+" | grep -oE "[-0-9]+$");'
        'if [ -n "$SIG" ] && [ -n "$NOISE" ]; then'
        '  SNR=$((SIG - NOISE));'
        '  SELF=$(cat /sys/class/net/wlan0/address 2>/dev/null);'
        '  BAT=$(batctl meshif bat0 neighbors_json 2>/dev/null || echo "[]");'
        '  GWL=$(batctl meshif bat0 gwl -n 2>/dev/null | grep "^[*]" | head -1);'
        '  if [ -n "$GWL" ]; then'
        '    GW_ROUTER=$(echo "$GWL" | grep -oE "[0-9a-f:]{17}" | head -1);'
        '    GW_NEXTHOP=$(echo "$GWL" | grep -oE "[0-9a-f:]{17}" | head -2 | tail -1);'
        '  else'
        '    GW_ROUTER=none; GW_NEXTHOP=none;'
        '  fi;'
        '  echo "DATA|${SNR}|${SIG}|${NOISE}|${SELF}|${GW_ROUTER}|${GW_NEXTHOP}|${BAT}";'
        'else'
        '  echo "NOSIGNAL";'
        'fi'
    )
    out, _, _ = ssh_run(ssh_base, poll_once)
    if not out.startswith('DATA|'):
        print(f"ERROR: Poll command failed. Got: {out!r}")
        sys.exit(1)
    print(f"  Verified: {out[:70]}...")

    # ── Audio setup ──────────────────────────────────────────────────
    player = None if args.no_audio else find_player()
    tmpdir = tempfile.mkdtemp()
    tones = {}
    for freq in TONE_FREQS:
        path = os.path.join(tmpdir, f'beep_{freq}.wav')
        make_beep(path, freq=freq)
        tones[freq] = path

    print(f"  Audio: {player or 'disabled'}")
    print(f"  Starting monitor...\n")
    time.sleep(0.5)

    # ── Shared state between threads ─────────────────────────────────
    state = {
        'snr': None, 'signal': None, 'noise': None,
        'self_mac': None,
        'gw_router': None, 'gw_nexthop': None,
        'neighbors': [],
        'version': 0,
    }
    running = [True]

    ssh_stream = ['sshpass', '-p', password, 'ssh',
                  '-o', 'StrictHostKeyChecking=no',
                  '-o', 'ConnectTimeout=5',
                  '-o', 'ServerAliveInterval=3',
                  '-o', 'ServerAliveCountMax=2',
                  f'{args.user}@{host}']

    remote_loop = (
        'while true; do'
        '  INFO=$(iwinfo wlan0 info 2>/dev/null);'
        '  SIG=$(echo "$INFO" | grep -oE "Signal: [-0-9]+" | grep -oE "[-0-9]+$");'
        '  NOISE=$(echo "$INFO" | grep -oE "Noise: [-0-9]+" | grep -oE "[-0-9]+$");'
        '  if [ -n "$SIG" ] && [ -n "$NOISE" ]; then'
        '    SNR=$((SIG - NOISE));'
        '    SELF=$(cat /sys/class/net/wlan0/address 2>/dev/null);'
        '    BAT=$(batctl meshif bat0 neighbors_json 2>/dev/null || echo "[]");'
        '    GWL=$(batctl meshif bat0 gwl -n 2>/dev/null | grep "^[*]" | head -1);'
        '    if [ -n "$GWL" ]; then'
        '      GW_ROUTER=$(echo "$GWL" | grep -oE "[0-9a-f:]{17}" | head -1);'
        '      GW_NEXTHOP=$(echo "$GWL" | grep -oE "[0-9a-f:]{17}" | head -2 | tail -1);'
        '    else'
        '      GW_ROUTER=none; GW_NEXTHOP=none;'
        '    fi;'
        '    echo "DATA|${SNR}|${SIG}|${NOISE}|${SELF}|${GW_ROUTER}|${GW_NEXTHOP}|${BAT}";'
        '  else'
        '    echo "NOSIGNAL";'
        '  fi;'
        '  sleep 4;'
        'done'
    )

    def poller():
        """Background: persistent SSH session streaming stats every 4s."""
        while running[0]:
            try:
                proc = subprocess.Popen(
                    ssh_stream + [remote_loop],
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                    text=True, bufsize=1)
                while running[0]:
                    line = proc.stdout.readline()
                    if not line:
                        break
                    line = line.strip()
                    if line.startswith('DATA|'):
                        # DATA|SNR|SIG|NOISE|SELF|GW_ROUTER|GW_NEXTHOP|BAT_JSON
                        parts = line.split('|', 7)
                        if len(parts) >= 7:
                            state['snr'] = int(parts[1])
                            state['signal'] = int(parts[2])
                            state['noise'] = int(parts[3])
                            state['self_mac'] = parts[4]
                            gw_r = parts[5]
                            gw_n = parts[6]
                            state['gw_router'] = None if gw_r == 'none' else gw_r
                            state['gw_nexthop'] = None if gw_n == 'none' else gw_n
                            if len(parts) >= 8:
                                try:
                                    state['neighbors'] = json.loads(parts[7])
                                except (json.JSONDecodeError, ValueError):
                                    state['neighbors'] = []
                            else:
                                state['neighbors'] = []
                            state['version'] += 1
                    elif 'NOSIGNAL' in line:
                        state['snr'] = None
                        state['signal'] = None
                        state['noise'] = None
                        state['neighbors'] = []
                        state['gw_router'] = None
                        state['gw_nexthop'] = None
                        state['version'] += 1
                proc.terminate()
            except Exception:
                pass
            if running[0]:
                state['snr'] = None
                state['signal'] = None
                state['noise'] = None
                state['neighbors'] = []
                state['gw_router'] = None
                state['gw_nexthop'] = None
                state['version'] += 1
                time.sleep(3)

    threading.Thread(target=poller, daemon=True).start()

    def pick_tone(snr):
        """Select beep pitch based on SNR — higher pitch = stronger signal."""
        norm = max(0.0, min(1.0, (snr - SNR_DEAD) / (SNR_MAX - SNR_DEAD)))
        idx = min(int(norm * len(TONE_FREQS)), len(TONE_FREQS) - 1)
        return tones[TONE_FREQS[idx]]

    def draw():
        """Redraw the full-screen display."""
        snr = state['snr']
        sig = state['signal']
        noise = state['noise']
        self_mac = state['self_mac']
        gw_router = state['gw_router']
        gw_nexthop = state['gw_nexthop']
        neighbors = state['neighbors']

        W = 54  # display width

        print("\033[2J\033[H", end="")  # clear screen, cursor to top
        print()
        print(f"  HaLow Range Test \u2014 {node_name}")
        print("  " + "\u2550" * W)

        if snr is not None:
            norm = max(0.0, min(1.0, (snr - SNR_DEAD) / (SNR_MAX - SNR_DEAD)))
            bar_len = int(norm * 20)
            bar = '\u2588' * bar_len + '\u2591' * (20 - bar_len)

            if snr >= 20:
                label = 'excellent'
            elif snr >= 10:
                label = 'good'
            elif snr >= 5:
                label = 'weak'
            elif snr >= SNR_DEAD:
                label = 'marginal'
            else:
                label = 'DEAD'

            print()
            print(f"  SNR: {snr} dB    Signal: {sig} dBm    Floor: {noise} dBm")
            print(f"  [{bar}]  {label}")

            if snr >= SNR_DEAD:
                interval = BEEP_SLOW - norm * (BEEP_SLOW - BEEP_FAST)
                print(f"  Beep: every {interval:.1f}s")
            else:
                print(f"  Beep: silent (unusable)")
        else:
            print()
            print("  Signal: waiting for data...")

        # ── Mesh Neighbors ───────────────────────────────────────────
        print()
        print(f"  Mesh Neighbors")
        print("  " + "\u2500" * W)
        if self_mac:
            print(f"    YOU  {self_mac}")
        if neighbors:
            for i, n in enumerate(neighbors):
                mac = n.get('neigh_address', '?')
                tp = n.get('throughput', 0)
                tp_mbps = tp / 1000 if tp else 0
                seen = n.get('last_seen_msecs', 0)
                is_gw = (mac == gw_router)
                marker = '  \u2605 GW' if is_gw else ''
                is_last = (i == len(neighbors) - 1)
                branch = '\u2514\u2500\u2500' if is_last else '\u251c\u2500\u2500'
                print(f"     {branch} {mac}   {tp_mbps:.1f} Mbit/s   "
                      f"{seen}ms ago{marker}")
        else:
            print("    (none)")

        # ── Internet Route ───────────────────────────────────────────
        print()
        print(f"  Internet Route")
        print("  " + "\u2500" * W)
        if gw_router:
            self_short = short_mac(self_mac) if self_mac else 'YOU'
            gw_short = short_mac(gw_router)

            if gw_nexthop and gw_nexthop != gw_router:
                # Multi-hop: traffic goes through an intermediate node
                hop_short = short_mac(gw_nexthop)
                print(f"    {self_short} \u2500\u2500\u25b6 "
                      f"{hop_short} \u2500\u2500\u25b6 "
                      f"{gw_short} \u2605 \u2500\u2500\u25b6 internet")
                print(f"    (routing through {gw_nexthop})")
            else:
                # Direct: we reach the gateway in one hop
                print(f"    {self_short} \u2500\u2500\u25b6 "
                      f"{gw_short} \u2605 \u2500\u2500\u25b6 internet")
                print(f"    (direct link)")
        else:
            print("    no gateway")

        print()
        print("  Refreshing every 4s \u2014 Ctrl+C to stop")
        sys.stdout.flush()

    # ── Main loop: display + beep ────────────────────────────────────
    last_version = -1
    try:
        while True:
            v = state['version']
            if v != last_version:
                draw()
                last_version = v

            snr = state['snr']
            if snr is not None and snr >= SNR_DEAD:
                norm = max(0.0, min(1.0, (snr - SNR_DEAD) / (SNR_MAX - SNR_DEAD)))
                interval = BEEP_SLOW - norm * (BEEP_SLOW - BEEP_FAST)
                play(player, pick_tone(snr))
                time.sleep(interval)
            else:
                time.sleep(0.5)
    except KeyboardInterrupt:
        running[0] = False
        print('\n\n  Stopped.')
    finally:
        running[0] = False
        shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == '__main__':
    main()
