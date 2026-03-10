# Range Optimization Guide

Practical tips for maximizing HaLow (802.11ah) mesh range based on real-world field testing.

## Quick Reference

| Factor | Impact | Effort |
|--------|--------|--------|
| Antenna height | Huge (~2x range) | Low-Medium |
| Channel width (1 MHz) | Large (~9 dB gain over 8 MHz) | Config change |
| TX power (27 dBm hardware) | Large (~6 dB over 21 dBm) | Hardware swap |
| Antenna type | Moderate | Swap |
| Channel selection | Small-Moderate | Config change |

## Antenna Height

**This is the single biggest factor for range.** At 915 MHz, the Fresnel zone (the elliptical area around the line-of-sight that signals need clear) is wide. Even small obstructions — fences, cars, bushes — cause significant loss.

- Raising the gate antenna from ground level to **3 meters** can roughly **double** usable range
- A rooftop or pole mount at **5-10 meters** is ideal
- The mesh point (mobile end) benefits from height too, but even dashboard-level vs. ground-level helps

> **Rule of thumb:** Every doubling of antenna height above ground roughly adds 6 dB of path clearance in typical suburban environments.

## Channel Width

HaLow supports 1, 2, 4, and 8 MHz channel widths. Narrower = more range, less throughput.

### Why Narrower Channels Increase Range

A radio receiver's noise floor is determined by physics: **thermal noise = kTB** (Boltzmann's constant x temperature x bandwidth). Halving the bandwidth drops the noise floor by 3 dB, which directly increases SNR and therefore range — without changing anything about your transmitter or antennas.

This relationship is identical for both the MM6108 and MM8108 — it's a property of the RF front-end and physics, not the digital modem. Both chips benefit equally from narrowing the channel.

```
Noise Floor vs. Channel Width (at room temperature)

  -94 ┤
      │                                              ██████████  8 MHz
  -97 ┤                                              ██████████  -97 dBm
      │
 -100 ┤                              ██████████                  4 MHz
      │                              ██████████                  -100 dBm
 -103 ┤              ██████████                                  2 MHz
      │              ██████████                                  -103 dBm
 -106 ┤  ██████████                                              1 MHz
      │  ██████████                                              -106 dBm
 -109 ┤
      └──────────────────────────────────────────────────────
         1 MHz       2 MHz       4 MHz       8 MHz

      Every halving of bandwidth = 3 dB lower noise floor = ~40% more range
```

### Channel Width Comparison

| Width | Setting | Noise Floor | SNR Gain | MM6108 Max | MM8108 Max | Use Case |
|-------|---------|-------------|----------|------------|------------|----------|
| **1 MHz** | HT10 | **-106 dBm** | **+9 dB** | 3.3 Mbps | 4.4 Mbps | Maximum range, messaging, telemetry |
| 2 MHz | HT20 | -103 dBm | +6 dB | 7.2 Mbps | 8.7 Mbps | Good balance of range and throughput |
| 4 MHz | HT40 | -100 dBm | +3 dB | 15.0 Mbps | 20.0 Mbps | Higher throughput, moderate range |
| 8 MHz | HT80 | -97 dBm | baseline | 32.5 Mbps | 43.3 Mbps | Maximum throughput, shortest range |

Going from 8 MHz to 1 MHz gives **~9 dB of SNR improvement** — equivalent to roughly 2-3x more range. The 3 Mbps throughput at 1 MHz is more than enough for most applications.

### Receiver Sensitivity by Channel Width

Receiver sensitivity tells you the weakest signal the radio can decode at each MCS rate. These values apply to both MM6108 and MM8108 for MCS 0-7 (the MM8108 adds MCS 8-9):

| MCS | Modulation | 1 MHz | 2 MHz | 4 MHz | 8 MHz |
|-----|-----------|------:|------:|------:|------:|
| 0 | BPSK | -106 dBm | -103 dBm | -102 dBm | -98 dBm |
| 7 | 64-QAM 5/6 | -89 dBm | -86 dBm | -83 dBm | -80 dBm |
| 9 | 256-QAM 5/6 (MM8108 only) | -83 dBm | — | -78 dBm | -74 dBm |
| 10 | BPSK repeated (1 MHz only) | -109 dBm | — | — | — |

> MCS 10 at 1 MHz is the extreme range mode — 150 kbps at -109 dBm sensitivity, operating at nearly 0 dB SNR. Enough for text, telemetry, and mesh keepalives.

**1 MHz also unlocks MCS 10**, a special ultra-low-rate mode (150 kbps) that can operate at nearly 0 dB SNR, squeezing out maximum range.

### Setting Channel Width

On both gate and point nodes:

```bash
# Set to 1 MHz (maximum range)
uci set wireless.radio1.htmode='HT10'

# Or via LUCI: Network → Wireless → HaLow radio → Channel Width
```

> **Important:** Channel width must match on all nodes in the mesh.

## TX Power

The difference between 21 and 27 dBm is **~6 dB = 4x the output power**, which translates to roughly **40-60% more range**. TX power is determined by the hardware (chip + power amplifier) and the BCF (Board Configuration File). You cannot increase it beyond what the hardware supports.

### Known Hardware TX Power Levels

#### 27 dBm Devices (High Power)

| Device | Chip | Form Factor | Notes |
|--------|------|-------------|-------|
| **Haven Node** (Parallel) | Seeed FGH100M-H + OpenMANET BCF | Standalone mesh node | Custom BCF enables 27 dBm |
| **Heltec HT-HD01 V2** | MM6108A1 | USB/Ethernet dongle | BCF: `bcf_HD01_v2.bin` |

#### 26 dBm Devices

| Device | Chip | Form Factor | Notes |
|--------|------|-------------|-------|
| **Morse Micro MM8108-EKH19** | MM8108 (Gen 2) | USB dongle eval kit | Integrated PA, up to 43 Mbps, 256-QAM |
| **Morse Micro MM8108-EKH01** | MM8108 (Gen 2) | RPi 4 eval kit | Integrated 26 dBm PA |

#### 21-22 dBm Devices (Standard Power)

| Device | Chip | Form Factor | Notes |
|--------|------|-------------|-------|
| **Heltec HT-HD01 V1/V1.1** | MM6108A1 | USB/Ethernet dongle | BCF: `bcf_mf08551.bin`, no external PA |
| **Silex SX-SDMAH-EVB-US** | MM6108 | Industrial eval board | 22 dBm |
| **Morse Micro MM6108-EKH01** | MM6108 | Eval kit | First-gen reference design |
| **Alfa HaLow-R** | MM6108 | Indoor router | 802.11ah + WiFi 4 |
| **Alfa HaLow-U** | MM6108 | USB adapter | AP & client mode |
| **Seeed Wio-WM6180** | MM6108 | Mini-PCIe module | Default BCF (~21 dBm) |

> **Note:** The Morse Micro MM8108 (Gen 2) is a significant upgrade — it has an **integrated** 26 dBm PA (no external PA needed), supports 256-QAM for up to 43 Mbps, and is more power efficient. As boards based on the MM8108 become available, they will be the best option for both range and throughput.

### How to Check Your TX Power

```bash
# Reported TX power
iwinfo wlan0 info | grep "Tx-Power"

# Hardware max from driver
dmesg | grep "tx_max_power_mbm"

# BCF file in use
uci get wireless.radio1.bcf
```

### Identifying Heltec HT-HD01 Version

The V1 and V2 look identical externally. Check via SSH:

```bash
# 21 dBm = V1/V1.1
# 27 dBm = V2
iwinfo wlan0 info | grep "Tx-Power"

# Or check BCF file
uci get wireless.radio1.bcf
# bcf_mf08551.bin = V1 (21 dBm)
# bcf_HD01_v2.bin = V2 (27 dBm)
```

## Antenna Selection

### Recommended Antennas (915 MHz)

Based on field testing in suburban environments (cement block construction, mobile/vehicle use):

| Antenna | Type | Best For | Field Results |
|---------|------|----------|---------------|
| **RHCP 915 MHz** (e.g. TrueRC) | Right-hand circular polarized | Gate + mobile | Best overall performer — handles reflections off buildings, ground, and vehicles. Best signal through cement block walls. |
| **Muzi 915 MHz** | Omni whip | Gate + mobile | Strong all-around performer |
| **Alfa AOA-915-5ACM** | Omni (5 dBi) | Gate (fixed) | Good for fixed gate installations |
| **HDCU "Yogurt Cup"** (Five Four Communications) | Omni, 3 dBi, BNC | Mobile / manpack | 3D printed, gooseneck mount, lightweight and easy to deploy |

### Antennas That Underperform

| Antenna | Type | Issue |
|---------|------|-------|
| **Taoglas Sighunter** | Directional panel | Rejects useful multipath; no improvement over omni even when aimed correctly |
| **Fiberglass outdoor omni (10 dBi, Amazon)** | High-gain omni | Poor performance in testing; possibly poor tuning or vendor quality |

### Why RHCP Works Best

At 915 MHz, signals bounce off everything — buildings, ground, trees, vehicles, cement walls. Each reflection can flip the signal's polarization. A standard linear antenna (vertical whip) loses up to 20 dB when receiving a signal whose polarization has been rotated by reflections.

**Circular polarized (RHCP) antennas** receive any polarization with at most 3 dB loss. This makes them ideal for:
- Signals passing through walls (cement block, brick)
- Mobile use where the antenna orientation varies
- Suburban environments with heavy multipath

### Why Directional Antennas Often Disappoint

At 900 MHz in a mobile or suburban scenario, **multipath reflections carry significant energy**. Omni and RHCP antennas capture all of these, while a directional antenna rejects reflections coming from "off-axis" directions — which can actually **reduce** total received power.

Directional antennas only help when:
- Both ends are **fixed** (not mobile)
- There is **clear line of sight** between them
- You need to **reach a specific distant point** without interfering with others

> **Recommendation:** Use RHCP on both ends if possible. Fall back to omni whip (Muzi, Alfa) for general use. Reserve directional for fixed long-range point-to-point links only.

### Antenna Diversity (Automatic Switching)

Instead of choosing one antenna, you can connect two antennas via an RF SPDT switch (e.g. HMC349) and let the node automatically select the best one. The `antenna_diversity.py` daemon monitors SNR and switches between antennas based on link quality — the node gets the best of both antennas without manual intervention.

This is especially useful when pairing antennas with different strengths (e.g. RHCP for multipath environments + omni for open areas). See [Antenna Diversity](antenna-diversity.md) for hardware wiring and setup.

## SNR Requirements by MCS Rate

The radio automatically selects the best MCS rate for the current SNR. Understanding the thresholds helps predict when the link will degrade:

| MCS | Modulation | Min SNR | Data Rate (1 MHz) | Notes |
|-----|-----------|---------|-------------------|-------|
| 10 | BPSK (repeated) | ~-1 dB | 150 kbps | 1 MHz only, maximum range |
| 0 | BPSK | ~2 dB | 300 kbps | |
| 1 | QPSK 1/2 | ~5 dB | 600 kbps | |
| 2 | QPSK 3/4 | ~7 dB | 900 kbps | |
| 3 | 16-QAM 1/2 | ~10 dB | 1.2 Mbps | |
| 4 | 16-QAM 3/4 | ~13 dB | 1.8 Mbps | |
| 5 | 64-QAM 2/3 | ~17 dB | 2.4 Mbps | |
| 6 | 64-QAM 3/4 | ~19 dB | 2.7 Mbps | |
| 7 | 64-QAM 5/6 | ~21 dB | 3.0 Mbps | |

Below ~2 dB SNR, only MCS 10 works. Below ~-1 dB, the link drops entirely.

> **Why internet stops before the link drops:** At marginal SNR (3-10 dB), the link is technically alive but packet loss is high. TCP retransmissions pile up, and practical throughput drops to near zero even though `iwinfo` still shows a connected peer with some SNR. This is normal — the link is in a gray zone where mesh beacons survive but data doesn't flow reliably.

## Channel Selection

US HaLow channels are in the 902-928 MHz band. Things to consider:

- **Interference:** 915 MHz is shared with ISM devices (LoRa, smart meters, etc.). If you see a high noise floor, try a different channel.
- **All nodes must use the same channel.**
- Check the noise floor: `iwinfo wlan0 info | grep Noise` — lower (more negative) is better.

## Range Testing

Use the included `halow_monitor.py` script to test range in real-time:

```bash
# Connect your laptop to the mesh point's WiFi or ethernet, then:
python3 scripts/halow_monitor.py -p <password>

# Auto-detects the mesh point, beeps based on SNR,
# announces download speed and ping periodically
```

Drive or walk away from the gate and listen:
- **Rapid beeps** = strong signal
- **Slow beeps** = weak signal
- **Silence** = link unusable
- **Chime + speech** = internet confirmed with speed/latency
- **"No internet connection"** = link alive but no data flowing

## Summary: Maximum Range Checklist

1. **Mount the gate antenna as high as possible** (roof, pole, mast)
2. **Use 1 MHz channel width** on all nodes
3. **Use 27 dBm hardware** if available
4. **Use omni or RHCP antennas** for mobile use
5. **Add antenna diversity** with an RF switch for automatic best-antenna selection ([guide](antenna-diversity.md))
6. **Check noise floor** and pick a clean channel
7. **Test with `halow_monitor.py`** to find your actual coverage area
