# Dual-FS Driver Utilities

Standalone utility programs for SD card and Flash filesystem formatting, characterization, and validation.

## Overview

### SD Utilities

| Utility | Purpose | Destructive? |
|---------|---------|:------------:|
| **DFS_SD_format_card.spin2** | FAT32 card formatter (standalone) | Yes |
| **DFS_SD_card_characterize.spin2** | Card register reader | No |
| **DFS_SD_FAT32_audit.spin2** | FAT32 filesystem validator | No |
| **DFS_SD_FAT32_fsck.spin2** | FAT32 filesystem check & repair | Yes |

### Flash Utilities

| Utility | Purpose | Destructive? |
|---------|---------|:------------:|
| **DFS_FL_format.spin2** | Flash filesystem formatter | Yes |
| **DFS_FL_audit.spin2** | Flash filesystem integrity check | No |
| **DFS_FL_fsck.spin2** | Flash filesystem check & repair | Yes* |

*Repair is performed by remounting, which automatically resolves duplicates, orphans, and bad CRC blocks.

### Support Libraries

| Library | Purpose |
|---------|---------|
| **isp_format_utility.spin2** | FAT32 format engine (runs in temp cog) |
| **isp_fsck_utility.spin2** | FAT32 FSCK + Audit engine (runs in temp cog) |
| **isp_mem_strings.spin2** | String manipulation routines |
| **isp_string_fifo.spin2** | Lock-free inter-cog string FIFO |

---

## Building and Running Utilities

### Prerequisites

- **pnut-ts** and **pnut-term-ts** - See detailed installation instructions for **[macOS](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-macOS.md#installing-pnut-term-ts-on-macos)**, **[Windows](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-win.md#installing-pnut-term-ts-on-windows)**, and **[Linux/RPi](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-RPi.md#installing-pnut-term-ts-on-rpilinux)**
- Parallax Propeller 2 (P2 Edge or P2 board with microSD add-on) connected via USB

### Using the Test Runner

All utilities are run from the `tools/` directory using the test runner:

```bash
cd tools/
./run_test.sh ../src/UTILS/<utility>.spin2 [-t timeout]
```

The test runner compiles with `pnut-ts`, downloads to P2 hardware, captures debug output in headless mode, and saves logs to `tools/logs/`.

### Manual Compile and Run

From this `UTILS/` directory:

```bash
# Compile a utility
pnut-ts -d -I ../. <utility>.spin2

# Download and run on P2 (connects at 2 Mbit serial)
pnut-term-ts -r <utility>.bin
```

The `-I ../.` flag tells the compiler to find the `dual_sd_fat32_flash_fs` driver in the parent `src/` directory.

---

## Hardware Configuration

All utilities use the P2 Edge default pin configuration:

```spin2
CON
    SD_CS   = 60    ' Chip Select
    SD_MOSI = 59    ' Master Out Slave In
    SD_MISO = 58    ' Master In Slave Out
    SD_SCK  = 61    ' Serial Clock
```

The Flash chip shares MOSI, MISO, and SCK with the SD card but has a separate chip select. Both devices are managed by the unified `dual_sd_fat32_flash_fs` driver which handles SPI bus arbitration automatically.

Modify the `CON` section in each utility if using different pins.

---

## Recommended Workflows

### New SD Card Setup

1. **Characterize** - Read card registers: `DFS_SD_card_characterize.spin2`
2. **Format** - Create clean FAT32 filesystem: `DFS_SD_format_card.spin2`
3. **Audit** - Verify filesystem structure: `DFS_SD_FAT32_audit.spin2`

### SD Health Check

1. **Audit** - Read-only filesystem validation: `DFS_SD_FAT32_audit.spin2`
2. **FSCK** (if audit fails) - Auto-repair: `DFS_SD_FAT32_fsck.spin2`

### Flash Filesystem Setup

1. **Format** - Initialize Flash filesystem: `DFS_FL_format.spin2`
2. **Audit** - Verify filesystem health: `DFS_FL_audit.spin2`

### Flash Health Check

1. **Audit** - Read-only integrity check: `DFS_FL_audit.spin2`
2. **FSCK** (if audit finds issues) - Auto-repair via remount: `DFS_FL_fsck.spin2`

---

For detailed utility documentation including sample output, see **[DOCs/DUAL-UTILITIES.md](../../DOCs/DUAL-UTILITIES.md)**.

---

## License

MIT License - See LICENSE file for details.

Copyright (c) 2026 Iron Sheep Productions, LLC
