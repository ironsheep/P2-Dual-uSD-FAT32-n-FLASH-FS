# P2 Dual uSD FAT32 and FLASH FS

A unified filesystem driver for the Parallax Propeller 2 (P2) that provides simultaneous access to both the onboard 16MB FLASH chip and a microSD card through a single cog and a single API.

[Wondering why we used FAT32?](#why-fat32)

![Project Status](https://img.shields.io/badge/status-active-brightgreen)
![Platform](https://img.shields.io/badge/platform-Propeller%202-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> **See also:** The two individual drivers are also available as standalone alternatives:
> [P2 FLASH Filesystem](https://github.com/ironsheep/P2-FLASH-FS) (Flash-only) and
> [P2 microSD FAT32 Filesystem](https://github.com/ironsheep/P2-uSD-FAT32-FS) (SD-only).

## When to Use This Driver

This driver is larger than either standalone driver because it includes both filesystems. There are several ways to use it depending on your project needs:

- **Dual-device product** — Your application uses both SD and Flash at runtime. One cog, one API, both devices always available.

- **Provisioning tool** — Use the SD card to load configuration files, firmware images, or data onto Flash during manufacturing or field setup. Once Flash is populated, ship the product with the smaller [standalone Flash driver](https://github.com/ironsheep/P2-FLASH-FS) for a reduced image size.

- **Development and testing** — Use the SD card as a convenient way to get data onto the board during development, then switch to Flash-only for production.

If your product only ever needs one device, the standalone drivers ([Flash-only](https://github.com/ironsheep/P2-FLASH-FS), [SD-only](https://github.com/ironsheep/P2-uSD-FAT32-FS)) produce smaller binaries.

## Features

- **One worker cog, two devices** — a dedicated cog owns all SPI I/O for both SD and Flash, eliminating bus contention
- **Unified API** — mount, open, read, write, close, and copy files on either device with the same calls
- **Cross-device copy** — copy files between Flash and SD through one driver with `copyFile()`
- **Shared SPI bus management** — automatic bus switching between SD (Mode 0) and Flash (Mode 3) with proper smart pin reconfiguration
- **Flash directory emulation** — per-cog current working directory on the flat Flash filesystem using slash-delimited filename convention
- **Multi-cog safety** — hardware lock serializes access from up to 8 cogs
- **Conditional compilation** — `SD_INCLUDE_RAW`, `SD_INCLUDE_REGISTERS`, `SD_INCLUDE_SPEED`, `SD_INCLUDE_DEBUG` for minimal or full builds
- **1,332 regression tests** across 31 standard test suites verified on real P2 hardware

## Architecture Overview

The unified driver is built on the SD driver's **worker cog + command dispatch** architecture:

```
 ┌──────────┐  ┌──────────┐  ┌──────────┐
 │  Cog 0   │  │  Cog 1   │  │  Cog N   │   Application cogs
 │ (caller) │  │ (caller) │  │ (caller) │   call public API
 └────┬─────┘  └────┬─────┘  └────┬─────┘
      │             │             │
      └─────────────┼─────────────┘
                    │  hardware lock serialization
              ┌─────▼─────┐
              │ Parameter  │  command + params + caller ID
              │   Block    │
              └─────┬─────┘
                    │  WAITATN / COGATN signaling
              ┌─────▼─────┐
              │  Worker    │  single dedicated cog
              │   Cog      │  owns all SPI pins
              │            │
              │  ┌───────┐ │
              │  │ CMD    │ │  command dispatch (case statement)
              │  │dispatch│ │
              │  └───┬───┘ │
              │      │     │
              │  ┌───▼───┐ │
              │  │  SPI   │ │  smart pins + inline PASM2
              │  │ engine │ │
              │  └───┬───┘ │
              │      │     │
              │  ┌───▼───┐ │
              │  │  Bus   │ │  CS management + mode switching
              │  │ switch │ │
              │  └─┬───┬─┘ │
              └───┼───┼───┘
                  │   │
           ┌──────┘   └──────┐
     ┌─────▼─────┐     ┌─────▼─────┐
     │  SD Card   │     │  FLASH    │
     │  CS=P60    │     │  CS=P61   │
     │  SPI Mode 0│     │  SPI Mode 3│
     └───────────┘     └───────────┘
```

### SPI Bus Sharing

The [SPI Bus State Analysis](DOCs/Analysis/SPI-BUS-STATE-ANALYSIS.md) confirms that bus sharing is safe: each device releases MISO (high-impedance) when its CS goes HIGH. The worker cog is the sole bus owner and switches between devices by:

1. Completing the current device operation (CS HIGH)
2. Settling the bus (SCK to expected idle state)
3. Selecting the target device (CS LOW)

The SD card uses **SPI Mode 0** (CPOL=0, CPHA=0 — clock idles LOW) while the Flash chip ([W25Q128JV](DOCs/Reference/W25Q128JV-210823.pdf)) uses **SPI Mode 3** (CPOL=1, CPHA=1 — clock idles HIGH). The worker cog reconfigures the smart pin clock polarity when switching between devices.

## Hardware Requirements

- Parallax Propeller 2 — [P2-EC](https://www.parallax.com/product/p2-edge-module/) or [P2-EC32MB](https://www.parallax.com/product/p2-edge-module-32mb/)
- microSD card (SDHC or SDXC) — the included format utility can format cards that are not already FAT32

### Pin Configuration (P2 Edge)

| Pin | SD Card | Flash |
|-----|---------|-------|
| P58 | MISO (DAT0) | MISO |
| P59 | MOSI (CMD) | MOSI |
| P60 | CS (DAT3) | SCK |
| P61 | SCK (CLK) | CS |

The SD card and Flash chip share the same four SPI pins, with P60 and P61 swapping roles between devices. Pin assignments are configurable at `init()` time.

## Project Structure

```
src/
├── dual_sd_fat32_flash_fs.spin2   # Unified dual-FS driver
├── DEMO/                          # Interactive dual-device shell
│   └── DFS_demo_shell.spin2
├── EXAMPLES/                      # Compilable example programs (4)
├── UTILS/                         # Standalone utilities (format, audit, fsck, characterize)
└── regression-tests/              # 31 standard suites, 1,332 tests

DOCs/
├── DUAL-DRIVER-THEORY.md          # Theory of operations
├── DUAL-DRIVER-TUTORIAL.md        # Getting started tutorial
├── DUAL-UTILITIES.md              # Utility program guide
├── FLASH-FS-THEORY.md             # Flash filesystem internals
├── Analysis/                      # SPI bus state analysis
├── Plans/                         # Implementation plans and style guides
├── Reference/                     # Technical reference, datasheets, user guides
└── Utils/                         # Utility theory of operations

tools/                             # Test runner scripts and logs
```

## Documentation

| Document | Description |
|----------|-------------|
| [Theory of Operations](DOCs/DUAL-DRIVER-THEORY.md) | Architecture, command protocol, SPI bus management, handle pool |
| [Tutorial](DOCs/DUAL-DRIVER-TUTORIAL.md) | Getting started guide with code examples for all API areas |
| [Utilities Guide](DOCs/DUAL-UTILITIES.md) | Format, audit, fsck, and characterize utilities |
| [Flash FS Theory](DOCs/FLASH-FS-THEORY.md) | Block format, wear leveling, mount process, circular files |
| [Memory Sizing Guide](DOCs/Reference/MEMORY-SIZING-GUIDE.md) | Hub RAM sizing for the dual-FS driver |
| [Flash Chip Datasheet](DOCs/Reference/W25Q128JV-210823.pdf) | W25Q128JV SPI Flash datasheet (Winbond) |

## Toolchain

- **Compiler**: [pnut-ts](https://github.com/ironsheep/P2-vscode-langserv-extension) (Parallax Spin2 compiler, v45+)
- **Downloader**: pnut-term-ts (serial terminal for P2 hardware)

```bash
# From src/
pnut-ts -d dual_sd_fat32_flash_fs.spin2

# From a subdirectory
pnut-ts -d -I .. <filename>.spin2

# Download and run
pnut-term-ts -r <filename>.bin
```

---

## Why FAT32?

### Our reasoning for choosing FAT32 over exFAT

*Our storage subsystem uses FAT32 rather than exFAT to avoid the patent and licensing constraints that still apply to exFAT in commercial products. exFAT remains covered by Microsoft intellectual property, and compliant implementations are generally expected to be licensed, which can add cost, legal complexity, and contractual obligations that are disproportionate for many embedded systems. In contrast, the relevant FAT patents (including those covering long filenames) have expired, so a clean-room FAT32 implementation can be shipped royalty-free, making it a safer and more predictable choice from an IP and compliance standpoint.*

*Technically, FAT32 also remains the most broadly compatible filesystem for removable media in the embedded space. It is supported by virtually all major desktop and mobile operating systems, works out of the box with common SD and microSD cards up to 32 GB, and has a relatively small code and RAM footprint - important advantages on microcontrollers. By standardizing on FAT32, our driver delivers simple integration, excellent cross-platform interoperability, and a clear legal posture, which together make it a practical and low-risk foundation for products that need removable storage without the overhead of exFAT licensing.*

---

## Credits

- **Flash FS Core**: Chip Gracey
- **Flash FS API & Direction**: Jon McPhalen
- **SD Driver Concept**: Chris Gadd (OB4269, Parallax OBEX)
- **Unified Driver Development**: Stephen M. Moraco, Iron Sheep Productions

## License

MIT License — See [LICENSE](LICENSE) for details.

---

*Part of the Iron Sheep Productions Propeller 2 Projects Collection*
