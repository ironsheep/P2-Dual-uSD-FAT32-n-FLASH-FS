# P2 Dual SD FAT32 + Flash Filesystem Driver

A unified filesystem driver for the Parallax Propeller 2 (P2) that provides simultaneous access to both the onboard 16MB Flash chip and a microSD card through a single cog and a single API.

> **See also:** The two individual drivers are also available as standalone alternatives:
> [P2 FLASH Filesystem](https://github.com/ironsheep/P2-FLASH-FS) (Flash-only) and
> [P2 microSD FAT32 Filesystem](https://github.com/ironsheep/P2-uSD-FAT32-FS) (SD-only).

## What's in this Package

```
dual-fs-driver/
├── README.md                           This file
├── LICENSE                             MIT License
├── CHANGELOG.md                        Release history
│
├── DOCs/                               Reference documentation
│   ├── CONDITIONAL-COMPILATION-GUIDE.md     SD driver build options and pragmas
│   ├── DUAL-DRIVER-THEORY.md              Architecture and driver internals
│   ├── DUAL-DRIVER-TUTORIAL.md            Getting started guide with examples
│   ├── DUAL-UTILITIES.md                  Utility program documentation
│   ├── FLASH-FS-THEORY.md                 Flash filesystem internals
│   ├── images/                            Diagrams and photos
│   └── Reference/                         Memory sizing, debugging, datasheets
│
└── src/                                Driver and application source
    ├── dual_sd_fat32_flash_fs.spin2       The unified dual-FS driver
    ├── DEMO/                              Interactive dual-device shell
    │   ├── DFS_demo_shell.spin2              Shell application
    │   ├── isp_serial_singleton.spin2        Serial terminal driver
    │   └── isp_mem_strings.spin2             String formatting utilities
    ├── EXAMPLES/                          Compilable example programs
    │   ├── DFS_example_basic.spin2           Mount, read, write both devices
    │   ├── DFS_example_cross_copy.spin2      Copy files between SD and Flash
    │   ├── DFS_example_data_logger.spin2     Log to Flash, archive to SD
    │   └── DFS_example_sd_manifest.spin2     Read manifest from SD, copy files to Flash
    ├── UTILS/                             Standalone utilities
    │   ├── DFS_SD_format_card.spin2          SD FAT32 card formatter
    │   ├── DFS_SD_card_characterize.spin2    SD card register reader
    │   ├── DFS_SD_FAT32_audit.spin2          SD filesystem validator (read-only)
    │   ├── DFS_SD_FAT32_fsck.spin2           SD filesystem check & repair
    │   ├── DFS_FL_format.spin2               Flash filesystem formatter
    │   ├── DFS_FL_audit.spin2                Flash integrity check (read-only)
    │   ├── DFS_FL_fsck.spin2                 Flash check & repair
    │   ├── isp_format_utility.spin2          FAT32 format library
    │   ├── isp_fsck_utility.spin2            FSCK + Audit library
    │   ├── isp_mem_strings.spin2             String utilities
    │   └── isp_string_fifo.spin2             Inter-cog string FIFO
    └── regression-tests/                  Regression test suites
        ├── DFS_SD_RT_*_tests.spin2           SD test suites (20)
        ├── DFS_FL_RT_*_tests.spin2           Flash test suites (10)
        ├── DFS_RT_*_tests.spin2              Cross-device test suites (2)
        └── DFS_RT_utilities.spin2             Unified test framework
```

## Prerequisites

### Toolchain (choose one)

- **pnut-ts + pnut-term-ts** -- Command-line Spin2 compiler and terminal. See detailed install instructions for **[macOS](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-macOS.md#installing-pnut-term-ts-on-macos)**, **[Windows](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-win.md#installing-pnut-term-ts-on-windows)**, and **[Linux/RPi](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-RPi.md#installing-pnut-term-ts-on-rpilinux)**
- **Spin Tools IDE** -- Cross-platform Spin2/PASM2 IDE ([MaccaSoft](https://maccasoft.com/en/spin-tools-ide/))
- **Propeller Tool** -- Parallax's official IDE ([Downloads](https://www.parallax.com/propeller-tool/))

### Hardware

- Parallax Propeller 2 -- [P2-EC](https://www.parallax.com/product/p2-edge-module/) or [P2-EC32MB](https://www.parallax.com/product/p2-edge-module-32mb/)
- microSD card (SDHC or SDXC) -- the included format utility can format cards that are not already FAT32

### Default Pin Configuration (P2 Edge)

| Pin | SD Card | Flash |
|-----|---------|-------|
| P58 | MISO (DAT0) | MISO |
| P59 | MOSI (CMD) | MOSI |
| P60 | CS (DAT3) | SCK |
| P61 | SCK (CLK) | CS |

The SD card and Flash chip share the same four SPI pins, with P60 and P61 swapping roles between devices. Pin assignments are fixed CON constants for the P2 Edge Module.

## Quick Start

### Using the Driver in Your Project

Copy `src/dual_sd_fat32_flash_fs.spin2` into your project directory, then:

```spin2
OBJ
    dfs : "dual_sd_fat32_flash_fs"

DAT
    sdFile    BYTE  "DATA.TXT", 0
    flFile    BYTE  "config", 0
    sdMsg     BYTE  "Hello from the dual driver!", 0
    flMsg     BYTE  "sensor_interval=5", 0

PUB main() | status, handle
    ' Initialize driver (starts worker cog)
    dfs.init()                         ' Starts worker cog (P2 Edge Module pins)

    ' Mount both devices
    status := dfs.mount(dfs.DEV_SD)
    if status < 0
        debug("SD mount failed: ", sdec_(status))
        return

    status := dfs.mount(dfs.DEV_FLASH)
    if status < 0
        debug("Flash mount failed: ", sdec_(status))
        return

    ' Write to SD
    handle := dfs.open(dfs.DEV_SD, @sdFile, dfs.MODE_WRITE)
    if handle >= 0
        dfs.wr_str(handle, @sdMsg)
        dfs.close(handle)

    ' Write to Flash
    handle := dfs.open(dfs.DEV_FLASH, @flFile, dfs.MODE_WRITE)
    if handle >= 0
        dfs.wr_str(handle, @flMsg)
        dfs.close(handle)

    dfs.unmount(dfs.DEV_SD)
    dfs.unmount(dfs.DEV_FLASH)
    dfs.stop()
```

### Running the Demo Shell

```bash
cd src/DEMO/
pnut-ts -I .. -I ../UTILS DFS_demo_shell.spin2
pnut-term-ts -r DFS_demo_shell.bin
```

Make sure pnut-term-ts is configured for 2,000,000 baud serial. See `src/DEMO/README.md` for full usage.

### Running a Utility

```bash
cd src/UTILS/
pnut-ts -d -I .. DFS_SD_card_characterize.spin2
pnut-term-ts -r DFS_SD_card_characterize.bin
```

See `src/UTILS/README.md` for all available utilities.

## Documentation

| Document | Description |
|----------|-------------|
| [Tutorial](DOCs/DUAL-DRIVER-TUTORIAL.md) | Getting started guide with code examples for all API areas |
| [Theory of Operations](DOCs/DUAL-DRIVER-THEORY.md) | Architecture, command protocol, SPI bus management, handle pool |
| [Utilities Guide](DOCs/DUAL-UTILITIES.md) | Format, audit, fsck, and characterize utilities |
| [Flash FS Theory](DOCs/FLASH-FS-THEORY.md) | Block format, wear leveling, mount process, circular files |
| [Memory Sizing Guide](DOCs/Reference/MEMORY-SIZING-GUIDE.md) | Hub RAM sizing for the dual-FS driver |

## Regression Tests

The regression test suite (1,350 tests across 32 standard suites) is included in `src/regression-tests/`. Tests compile with pnut-ts and run on P2 hardware, producing pass/fail results via debug output.

## License

MIT License

Copyright (c) 2026 Iron Sheep Productions, LLC
