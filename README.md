# P2 Dual uSD FAT32 n FLASH FS

A unified filesystem driver for the Parallax Propeller 2 (P2) that provides simultaneous access to both the onboard 16MB FLASH chip and a microSD card through a single cog and a single API.

![Project Status](https://img.shields.io/badge/status-active-brightgreen)
![Platform](https://img.shields.io/badge/platform-Propeller%202-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Goal

Create a single Spin2 driver — patterned after the [microSD FAT32 driver](REF-FLASH-uSD/uSD-FAT32/) — that integrates the [Flash filesystem](REF-FLASH-uSD/FLASH/) within the same worker cog. Users interact with one object, one set of file handles, and one API to read, write, and copy files across both storage devices. The two storage systems become a unified filesystem.

## Why a Unified Driver?

On the P2 Edge Module the Flash chip and the microSD card share the same SPI bus (MOSI=P59, MISO=P58, SCK=P60/P61) with separate chip-select lines. Today they require two independent driver objects, two cogs, and two APIs. A unified driver:

- **Frees a cog** — one worker cog handles both devices instead of two
- **Simplifies the API** — mount once, open/read/write/close on either device with the same calls
- **Enables cross-device copy** — copy files between Flash and SD through one driver
- **Coordinates SPI bus access** — the worker cog owns the bus and switches between devices safely, eliminating external bus arbitration

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

### SPI Mode Challenge

The SD card uses **SPI Mode 0** (CPOL=0, CPHA=0 — clock idles LOW) while the Flash chip uses **SPI Mode 3** (CPOL=1, CPHA=1 — clock idles HIGH). The worker cog must reconfigure the smart pin clock polarity when switching between devices.

### Design Approach

| Aspect | Reference SD Driver | Unified Driver |
|--------|-------------------|----------------|
| Worker cog | Single cog, command loop | Same — extended with Flash commands |
| Command dispatch | ~46 SD command codes | SD commands + new Flash command codes |
| SPI engine | Smart pin Mode 0 | Smart pin Mode 0 (SD) + Mode 3 (Flash), switched per device |
| File handles | Up to 6 (SD only) | Shared pool across both devices, handle tracks which device |
| Mount | `mount(cs, mosi, miso, sck)` | `mount(sd_cs, flash_cs, mosi, miso, sck)` — mounts both |
| Lock | One hardware lock | Same — one lock serializes all access |
| Bus safety | CS HIGH after every op | Same — plus mode switch on device transitions |

## Reference Implementations

The `REF-FLASH-uSD/` directory contains the two standalone drivers that serve as the basis for the unified driver:

| Driver | Description | Tests |
|--------|-------------|-------|
| [**Flash FS**](REF-FLASH-uSD/FLASH/) | Wear-leveling filesystem for onboard 16MB FLASH. Circular files, read-modify-write, 4KB blocks, 127-char filenames. | 900+ |
| [**microSD FAT32**](REF-FLASH-uSD/uSD-FAT32/) | Full FAT32 driver with smart pin SPI, streamer DMA, multi-sector transfers. 8.3 filenames, up to 2TB. | 345+ |

Both test suites will be migrated to validate the unified driver.

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

*Note: Exact pin assignments for the unified driver will be finalized during implementation — the Flash chip on the P2 Edge Module shares physical pins with the SD header group.*

## Project Structure

```
src/                            # Unified driver (target)
REF-FLASH-uSD/
├── FLASH/                      # Reference: Flash filesystem driver
│   ├── flash_fs.spin2              # Core driver
│   ├── THEOPSv2.md                # Theory of operations
│   └── RegresssionTests/          # 900+ tests
└── uSD-FAT32/                  # Reference: microSD FAT32 driver
    ├── src/
    │   ├── micro_sd_fat32_fs.spin2 # Core driver
    │   ├── DEMO/                   # Interactive shell
    │   ├── EXAMPLES/               # Example programs
    │   └── UTILS/                  # Utilities (format, audit, fsck, bench)
    ├── regression-tests/          # 345+ tests across 19 suites
    └── tools/                     # Test runner and logs
DOCs/
└── Analysis/
    └── SPI-BUS-STATE-ANALYSIS.md  # SPI bus sharing feasibility study
```

## Development Roadmap

1. **Study complete** — Both drivers analyzed, SPI bus sharing confirmed feasible
2. **Plan the unified API** — Define command codes, handle allocation, mount sequence
3. **Implement unified worker cog** — SD driver as base, integrate Flash SPI engine with mode switching
4. **Migrate SD regression tests** — 345+ tests against unified driver
5. **Migrate Flash regression tests** — 900+ tests against unified driver
6. **Add cross-device tests** — Copy between Flash and SD, interleaved operations
7. **Utilities and demos** — Update shell, format, audit, fsck for dual-device awareness

## Toolchain

- **Compiler**: [pnut-ts](https://github.com/ironsheep/P2-vscode-langserv-extension) (Parallax Spin2 compiler, v45+)
- **Downloader**: pnut-term-ts (serial terminal for P2 hardware)

```bash
pnut-ts -d -I ../src <filename>.spin2     # Compile
pnut-term-ts -r <filename>.bin            # Download and run
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
