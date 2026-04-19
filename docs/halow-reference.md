# HaLow (802.11ah) Reference

Technical specifications for the HaLow radios used in Haven mesh networks.

## Supported Frequency Bands

| Region | Frequency Range | Common Channels |
|--------|-----------------|-----------------|
| US/FCC | 902-928 MHz | 1-51 |
| EU/ETSI | 863-868 MHz | Varies |
| Japan | 920-928 MHz | Varies |
| Australia | 915-928 MHz | Varies |

## Default Configuration

| Setting | Value |
|---------|-------|
| Channel | 27 (914 MHz center frequency) |
| Width | 2 MHz (HT20) |
| Encryption | WPA3 SAE (CCMP) |
| Mesh ID | haven |
| Key | havenmesh |

## Channel Widths

Max PHY rate depends on the HaLow SoC. Haven ships with the **MM6108** (MCS 0–7, 64-QAM max). The **MM8108** adds MCS 8–9 (256-QAM) for higher peak rates and an integrated 26 dBm PA.

| Setting | Width | MM6108 Max | MM8108 Max | Range | Use Case |
|---------|-------|------------|------------|-------|----------|
| HT10 | 1 MHz | 3.3 Mbps | 4.4 Mbps | Maximum | Long-range backhaul |
| HT20 | 2 MHz | 7.2 Mbps | 8.7 Mbps | Very Long | Balanced |
| HT40 | 4 MHz | 15.0 Mbps | 20.0 Mbps | Long | Higher throughput |
| HT80 | 8 MHz | 32.5 Mbps | 43.3 Mbps | Medium | Local high-speed |

> Real-world throughput is typically 40–60% of PHY rate depending on signal, interference, and distance.

### Setting Channel Width

On both gate and point nodes:
```bash
uci set wireless.radio1.htmode='HT10'    # 1 MHz (maximum range)
uci commit wireless
wifi reload
```

> **Important:** Channel width must match on all nodes in the mesh.

## Full MCS Reference Table

All rates are single-stream PHY rates in Mbps.

| MCS | Modulation | Coding | 1 MHz | 2 MHz | 4 MHz | 8 MHz |
|-----|------------|--------|------:|------:|------:|------:|
| 10 | BPSK | 1/2 x2 | 0.17 | — | — | — |
| 0 | BPSK | 1/2 | 0.33 | 0.72 | 1.50 | 3.25 |
| 1 | QPSK | 1/2 | 0.67 | 1.44 | 3.00 | 6.50 |
| 2 | QPSK | 3/4 | 1.00 | 2.17 | 4.50 | 9.75 |
| 3 | 16-QAM | 1/2 | 1.33 | 2.89 | 6.00 | 13.00 |
| 4 | 16-QAM | 3/4 | 2.00 | 4.33 | 9.00 | 19.50 |
| 5 | 64-QAM | 2/3 | 2.67 | 5.78 | 12.00 | 26.00 |
| 6 | 64-QAM | 3/4 | 3.00 | 6.50 | 13.50 | 29.25 |
| 7 | 64-QAM | 5/6 | 3.33 | 7.22 | 15.00 | 32.50 |
| 8 | 256-QAM | 3/4 | 4.00 | 8.67 | 18.00 | 39.00 |
| 9 | 256-QAM | 5/6 | 4.44 | — | 20.00 | 43.33 |

MCS 0–7 and 10: supported by both MM6108 and MM8108.
MCS 8–9 (256-QAM): **MM8108 only**.

### Receiver Sensitivity (MM8108, 10% PER, 256-byte packets)

| MCS | 1 MHz | 2 MHz | 4 MHz | 8 MHz |
|-----|------:|------:|------:|------:|
| 0 | -106 dBm | -103 dBm | -102 dBm | -98 dBm |
| 7 | -89 dBm | -86 dBm | -83 dBm | -80 dBm |
| 9 | -83 dBm | — | -78 dBm | -74 dBm |

### Max TX Power (MM8108, at module antenna pin)

| MCS | 1 MHz | 2 MHz | 4 MHz | 8 MHz |
|-----|------:|------:|------:|------:|
| 0 | 25.5 dBm | 25.0 dBm | 22.5 dBm | 22.5 dBm |
| 7 | 19.0 dBm | 20.0 dBm | 19.5 dBm | 20.0 dBm |
| 9 | 15.5 dBm | — | 17.0 dBm | 16.0 dBm |

## HaLow Channel Selection

| Region | Frequency Range | Example |
|--------|-----------------|---------|
| US/FCC | 902-928 MHz | Channel 28 = 916 MHz |
| EU/ETSI | 863-868 MHz | Region-specific |
| Japan | 920-928 MHz | Region-specific |
| Australia | 915-928 MHz | Region-specific |

US HaLow channels are in the 902-928 MHz band, shared with ISM devices (LoRa, smart meters, etc.). If you see a high noise floor, try a different channel. Check noise: `iwinfo wlan0 info | grep Noise`

## Software Stack

| Component | Version | Description |
|-----------|---------|-------------|
| **OpenMANET** | 24.10 (1.6.1) | OpenWrt-based mesh firmware |
| **OpenWrt** | 24.10 | Base embedded Linux distribution |
| **Linux Kernel** | 6.6.102 | Operating system kernel |
| **Morse Micro Driver** | 1.16.4 | HaLow radio driver |
| **BATMAN-adv** | 2025.4 | Layer 2 mesh routing protocol |
| **Python** | 3.11.14 | Runtime for Reticulum |
| **Reticulum** | 1.1.3 | Encrypted networking stack |
