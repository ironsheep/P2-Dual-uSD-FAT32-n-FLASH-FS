# Dual-FS Driver Utilities

Standalone utility programs for SD card and Flash filesystem formatting, characterization, and validation.

## Overview

### SD Utilities

| Utility | Purpose | Destructive? |
|---------|---------|:------------:|
| **DFS_SD_format_card.spin2** | FAT32 card formatter | Yes |
| **DFS_SD_card_characterize.spin2** | Card register reader | No |
| **DFS_SD_FAT32_audit.spin2** | FAT32 filesystem validator (read-only) | No |
| **DFS_SD_FAT32_fsck.spin2** | FAT32 filesystem check & repair | Yes |

### Flash Utilities

| Utility | Purpose | Destructive? |
|---------|---------|:------------:|
| **DFS_FL_format.spin2** | Flash filesystem formatter | Yes |
| **DFS_FL_audit.spin2** | Flash filesystem integrity check (read-only) | No |
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

See [Prerequisites](../../README.md#prerequisites) for toolchain and hardware requirements.

### Compile and Run

From this `UTILS/` directory:

```bash
# Compile a utility
pnut-ts -d -I .. <utility>.spin2

# Download and run on P2 (connects at 2 Mbit serial)
pnut-term-ts -r <utility>.bin
```

The `-I ..` flag tells the compiler to find the `dual_sd_fat32_flash_fs` driver in the parent `src/` directory.

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

## SD Utility Details

### DFS_SD_format_card.spin2

**Purpose:** Format an SD card with a FAT32 filesystem.

```bash
pnut-ts -d -I .. DFS_SD_format_card.spin2
pnut-term-ts -r DFS_SD_format_card.bin
```

**WARNING:** This will **ERASE ALL DATA** on the SD card!

Creates a standard FAT32 filesystem: MBR with single partition, VBR with backup, FSInfo with backup, dual FAT tables, and root directory with volume label. Compatible with Windows, macOS, and Linux.

### DFS_SD_card_characterize.spin2

**Purpose:** Extract and display all card register information (CID, CSD, SCR, OCR) plus FAT32 filesystem parameters. Identifies manufacturer, capacity, speed class, and supported features.

```bash
pnut-ts -d -I .. DFS_SD_card_characterize.spin2
pnut-term-ts -r DFS_SD_card_characterize.bin
```

Use this to identify untested cards, verify capacity, debug compatibility issues, or build a card catalog.

### DFS_SD_FAT32_audit.spin2

**Purpose:** Verify FAT32 filesystem integrity without modifying the card.

```bash
pnut-ts -d -I .. DFS_SD_FAT32_audit.spin2
pnut-term-ts -r DFS_SD_FAT32_audit.bin
```

**Read-Only:** Does NOT modify any data. Validates MBR, VBR, backup VBR, FSInfo, backup FSInfo, FAT table consistency, root directory structure, and mount test.

### DFS_SD_FAT32_fsck.spin2

**Purpose:** Check and repair FAT32 filesystem corruption using a four-pass architecture.

```bash
pnut-ts -d -I .. DFS_SD_FAT32_fsck.spin2
pnut-term-ts -r DFS_SD_FAT32_fsck.bin
```

**WARNING:** This tool **modifies the card** to repair detected problems.

| Pass | Name | Purpose |
|------|------|---------|
| 1 | Structural Integrity | Repair VBR backup, FSInfo, FAT[0]/[1]/[2] entries |
| 2 | Directory & Chain Validation | Walk directory tree, validate cluster chains |
| 3 | Lost Cluster Recovery | Free allocated clusters not referenced by any file |
| 4 | FAT Sync & Free Count | Synchronize FAT1/FAT2, correct free cluster count |

---

## Flash Utility Details

### DFS_FL_format.spin2

**Purpose:** Format the onboard 16MB Flash chip with a new filesystem.

```bash
pnut-ts -d -I .. DFS_FL_format.spin2
pnut-term-ts -r DFS_FL_format.bin
```

**WARNING:** This will **ERASE ALL DATA** on the Flash chip!

### DFS_FL_audit.spin2

**Purpose:** Read-only integrity check of the Flash filesystem.

```bash
pnut-ts -d -I .. DFS_FL_audit.spin2
pnut-term-ts -r DFS_FL_audit.bin
```

Checks mount health, block allocation, file count, and file iteration consistency.

### DFS_FL_fsck.spin2

**Purpose:** Check and repair Flash filesystem issues.

```bash
pnut-ts -d -I .. DFS_FL_fsck.spin2
pnut-term-ts -r DFS_FL_fsck.bin
```

Flash FSCK performs a health check followed by a repair remount that automatically resolves duplicate blocks, orphaned allocations, and bad CRC entries.

---

For additional utility documentation including sample output and theory of operations, see **[DOCs/DUAL-UTILITIES.md](../../DOCs/DUAL-UTILITIES.md)**.

---

## License

MIT License - See LICENSE file for details.

Copyright (c) 2026 Iron Sheep Productions, LLC
