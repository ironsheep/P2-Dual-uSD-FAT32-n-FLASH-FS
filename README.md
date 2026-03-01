# P2 Dual uSD FAT32 n FLASH FS

A unified filesystem driver for the Parallax Propeller 2 (P2) that provides simultaneous access to both the onboard 16MB FLASH chip and a microSD card through a single cog and a single API.

![Project Status](https://img.shields.io/badge/status-active-brightgreen)
![Platform](https://img.shields.io/badge/platform-Propeller%202-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> **See also:** The standalone microSD FAT32 driver (SD-only, no Flash) is available separately at [P2 microSD FAT32 Filesystem](https://github.com/ironsheep/P2-uSD-FAT32-FS).

## Features

- **One worker cog, two devices** — a dedicated cog owns all SPI I/O for both SD and Flash, eliminating bus contention
- **Unified API** — mount, open, read, write, close, and copy files on either device with the same calls
- **Cross-device copy** — copy files between Flash and SD through one driver with `copyFile()`
- **Shared SPI bus management** — automatic bus switching between SD (Mode 0) and Flash (Mode 3) with proper smart pin reconfiguration
- **Multi-cog safety** — hardware lock serializes access from up to 8 cogs
- **Conditional compilation** — `SD_INCLUDE_RAW`, `SD_INCLUDE_REGISTERS`, `SD_INCLUDE_SPEED`, `SD_INCLUDE_DEBUG` for minimal or full builds
- **1,200+ regression tests** across 35 test suites verified on real P2 hardware

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
- microSD Add-on Board — [#64009](https://www.parallax.com/product/micro-sd-card-add-on-board/)
- microSD card (SDHC or SDXC, FAT32 formatted)

### Default Pin Configuration (P2 Edge)

| Signal | Pin | Device |
|--------|-----|--------|
| MISO (DAT0) | P58 | Shared |
| MOSI (CMD) | P59 | Shared |
| SD CS (DAT3) | P60 | SD Card |
| SD SCK (CLK) / FLASH CS | P61 | SD Card clock / Flash select |
| FLASH SCK | P60 | Flash clock (shared with SD CS) |

The Flash chip on the P2 Edge Module shares physical pins with the SD header group. Pin assignments are configurable at `init()` time.

## Project Structure

```
src/
├── dual_sd_fat32_flash_fs.spin2   # Unified dual-FS driver
├── DEMO/                          # Interactive dual-device shell
│   └── DFS_demo_shell.spin2
├── EXAMPLES/                      # Compilable example programs (3)
├── UTILS/                         # Standalone utilities (format, audit, fsck, characterize)
└── regression-tests/              # 35 test suites, 912+ tests

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

REF-FLASH-uSD/                     # Read-only reference drivers (development baseline)
├── FLASH/                         # Flash FS reference (Chip Gracey / Jon McPhalen)
└── uSD-FAT32/                     # microSD FAT32 reference (Chris Gadd / Stephen Moraco)
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

## Reference Implementations

The `REF-FLASH-uSD/` directory contains the two standalone drivers that served as the development baseline:

| Driver | Description | Original Tests |
|--------|-------------|----------------|
| [**Flash FS**](REF-FLASH-uSD/FLASH/) | Wear-leveling filesystem for onboard 16MB FLASH. Circular files, read-modify-write, 4KB blocks, 127-char filenames. | 900+ |
| [**microSD FAT32**](REF-FLASH-uSD/uSD-FAT32/) | Full FAT32 driver with smart pin SPI, streamer DMA, multi-sector transfers. 8.3 filenames, up to 2TB. | 345+ |

Both test suites have been migrated and expanded in the unified driver's [regression test suite](src/regression-tests/).

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

## Credits

- **Flash FS Core**: Chip Gracey
- **Flash FS API & Direction**: Jon McPhalen
- **SD Driver Concept**: Chris Gadd (OB4269, Parallax OBEX)
- **Unified Driver Development**: Stephen M. Moraco, Iron Sheep Productions

## License

MIT License — See [LICENSE](LICENSE) for details.

---

*Part of the Iron Sheep Productions Propeller 2 Projects Collection*
