# Haven MANET IP Mesh Radio

Build decentralized, long-range mesh networks with **Haven** - a complete open-source solution for creating self-healing IP networks that share internet access across kilometers without any central infrastructure.

**[Haven Guide](https://buildwithparallel.com/products/haven)** - Video tutorials, schematics, 3D printable enclosures, Discord community, and direct support.

## What is Haven?

Haven is a mesh networking platform that combines:

- **HaLow radios** (802.11ah) operating in sub-1GHz spectrum for multi-kilometer range
- **BATMAN-adv** for automatic Layer 2 mesh routing
- **OpenMANET** firmware (OpenWrt-based) for reliable embedded networking
- **Optional Reticulum** for encrypted overlay communications
- **Optional ATAK/CivTAK** integration for situational awareness

### Why Haven?

| Feature | Benefit |
|---------|---------|
| **Decentralized** | No central server, no single point of failure |
| **Long Range** | 1-10+ km node-to-node with HaLow radios |
| **Self-Healing** | Automatic route discovery and failover |
| **Internet Sharing** | One uplink serves the entire mesh |
| **Fully Open Source** | No proprietary lock-in, audit everything |
| **Multi-hop** | Traffic routes through intermediate nodes |
| **Low Power** | Sub-1GHz radios are power efficient |

## Haven Nodes

Haven nodes are compact, rugged units built for field deployment. Each node includes HaLow (sub-1GHz) and WiFi radios, USB and power ports, and versatile mounting (GoPro-style bracket and bolt holes).

![Haven node](assets/node-hero.png)

| | | |
|:---:|:---:|:---:|
| ![Node in hand](assets/node-hand.png) | ![Node vehicle mount](assets/node-vehicle-mount.png) | ![Node ports and mount](assets/node-ports-mount.png) |
| Handheld | Vehicle deployment | Ports and mounting |

## Network Architecture

```
                              Internet
                                  │
                                  ▼
    ┌─────────────────────────────────────────────────────────┐
    │              HAVEN GATE — green (Gateway)                │
    │                                                         │
    │   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐   │
    │   │  eth0   │  │  HaLow  │  │  5GHz   │  │  2.4GHz │   │
    │   │ uplink  │  │  mesh   │  │   AP    │  │   AP    │   │
    │   └─────────┘  └─────────┘  └─────────┘  └─────────┘   │
    │        │            │            │            │         │
    │        └────────────┴────────────┴────────────┘         │
    │                    br-ahwlan bridge                     │
    │                    IP assigned by openmanetd            │
    │                    DHCP Server                          │
    └─────────────────────────────────────────────────────────┘
                                  │
                                  │ HaLow Sub-1GHz Mesh
                                  │ (1-10+ km range)
                                  ▼
    ┌─────────────────────────────────────────────────────────┐
    │              HAVEN POINT — blue (Extender)               │
    │                                                         │
    │             ┌─────────┐          ┌─────────┐            │
    │             │  HaLow  │          │  5GHz   │            │
    │             │  mesh   │          │   AP    │            │
    │             └─────────┘          └─────────┘            │
    │                  │                    │                 │
    │                  └────────────────────┘                 │
    │                    br-ahwlan bridge                     │
    │                    10.41.x.x/16                         │
    └─────────────────────────────────────────────────────────┘
                                  │
                                  ▼
                           [Mobile Devices]
                          Phones, Laptops, ATAK
```

## Documentation

| Document | What it covers |
|----------|----------------|
| **[Setup Guide](docs/setup-guide.md)** | Step-by-step: gate setup, point nodes, Reticulum, ATAK, Heltec nodes |
| **[Finding & Accessing Nodes](docs/finding-nodes.md)** | How to find node IPs and reach LuCI — the thing you'll need most often |
| **[Troubleshooting](docs/troubleshooting.md)** | Mental model, diagnostics, fix checklists for every common failure |
| **[HaLow Reference](docs/halow-reference.md)** | Radio specs, channel widths, MCS tables, software versions |
| **[Range Optimization](docs/range-optimization.md)** | Antenna selection, TX power, channel width tuning, range testing |
| **[Antenna Smart Routing](docs/antenna-smart-routing.md)** | Automatic antenna switching with RF SPDT switch |
| **[Gate Node Config](docs/haven-gate.md)** | Manual gate configuration reference |
| **[Point Node Config](docs/haven-point.md)** | Manual point configuration reference |
| **[Reticulum](Reticulum/README.md)** | Encrypted overlay network — configuration, monitoring, apps |
| **[ATAK Bridge](ATAK/README.md)** | ATAK/CivTAK situational awareness over Reticulum |
| **[Scripts](scripts/README.md)** | Script reference and Reticulum demo tools |
| **[AI Agents](agents.md)** | Context for AI agents (Claude, Cursor, etc.) to diagnose and fix your mesh |

## Quick Start

All Haven setup scripts assume each node is flashed with a fresh/recent version of [OpenMANET](https://openmanet.org/). Flash the image onto a microSD card using Raspberry Pi Imager, insert it into the node, and power on. If the card still looks like it has old data after flashing, use Raspberry Pi Imager’s **Erase** (or SD **format/erase** utility) on the card first, then write the image — see the [setup guide](docs/setup-guide.md) for details.

| Step | What | How |
|------|------|-----|
| **1** | Set up the Gate node | Plug into router, run setup script → [Setup Guide](docs/setup-guide.md#step-1-set-up-the-gate-node-green) |
| **2** | Add Point nodes | Plug into laptop, paste setup script → [Setup Guide](docs/setup-guide.md#step-2-add-point-nodes-blue) |
| **3** | Install Reticulum *(optional)* | Encrypted overlay → [Setup Guide](docs/setup-guide.md#step-3-install-reticulum-optional) |
| **4** | Send Reticulum messages *(optional)* | Test encrypted messaging → [Scripts](scripts/README.md#reticulum-demo-scripts) |
| **5** | Install the ATAK bridge *(optional)* | Situational awareness → [Setup Guide](docs/setup-guide.md#step-5-install-the-atak-bridge-optional) |

> After any step, use LuCI's web interface to change passwords, WiFi SSIDs, and other settings. See **[Finding & Accessing Nodes](docs/finding-nodes.md)** to reach each node.

**Default credentials** (user: `root`):

| Node | Password | WiFi SSID | WiFi Password |
|------|----------|-----------|---------------|
| Gate (green) | `havengreen` | `green-5ghz` | `green-5ghz` |
| Gate (green) 2.4GHz | — | `green` | `greengreen` |
| Point (blue) | `havenblue` | `blue-5ghz` | `blue-5ghz` |

## Hardware Requirements

### Tested Platform
- **SBC**: Raspberry Pi CM4 / Pi 4
- **HaLow Radio**: Morse Micro MM601X (SPI interface)
- **5GHz WiFi**: Cypress CYW43455 (onboard on Pi)
- **2.4GHz WiFi**: RT5370 USB adapter (optional)

### Minimum Requirements
- ARM or x86 device with SPI interface
- HaLow radio module (Morse Micro recommended)
- Standard WiFi for client access

## Use Cases

- **Disaster Response**: Deploy mesh networks where infrastructure is damaged
- **Remote Operations**: Connect sites across kilometers without internet
- **Events**: Temporary networks for large gatherings
- **Maritime**: Ship-to-ship and ship-to-shore communications
- **Agriculture**: Connect sensors and equipment across large properties
- **Community Networks**: Neighborhood internet sharing

## Security

| Layer | Protection |
|-------|------------|
| HaLow Mesh | WPA3 SAE (CCMP) - strongest WiFi encryption |
| Reticulum | Curve25519 + AES-128 end-to-end encryption |
| ATAK | Optional additional encryption |

## Support & Community

- **[Haven Guide](https://buildwithparallel.com/products/haven)** - Complete build guide with videos
- **Discord** - Join the community (link in Haven Guide)
- **Direct Support** - Available through Parallel

## Contributing

Contributions welcome:
- Hardware compatibility testing
- Documentation improvements
- Bug fixes and features
- Use case examples

## License

MIT License - See [LICENSE](LICENSE) file.

## 3D Printable Enclosure

The official Haven case is released into the **public domain** — free for anyone to print, modify, and distribute. Designed for Parallel by [MOROSX](https://morosx.com/).

[Download on Printables](https://www.printables.com/model/1468595-haven-case-for-raspberry-pi-based-manet-by-paralle)

## Acknowledgments

- [OpenMANET](https://openmanet.org/) - Mesh networking firmware
- [Reticulum](https://reticulum.network/) by Mark Qvist
- [ATAK](https://tak.gov/) by TAK Product Center
- [Morse Micro](https://www.morsemicro.com/) - HaLow radio technology
- [OpenWrt](https://openwrt.org/) Project
- [MOROSX](https://morosx.com/) - Haven enclosure design
- [BATMAN-adv](https://www.open-mesh.org/) mesh protocol
