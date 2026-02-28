# Dual-FS Utilities

This document describes the standalone utility programs included with the P2 Dual-FS Driver. These utilities help with card/Flash formatting, characterization, performance testing, and filesystem validation for both SD and Flash devices.

## Overview

The utilities are located in `src/UTILS/` and can be run independently using the test runner from the `tools/` directory.

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

---

## Running Utilities

All utilities are run from the `tools/` directory using the test runner:

```bash
cd tools/
./run_test.sh ../src/UTILS/<utility>.spin2 [-t timeout]
```

Alternatively, from the `src/UTILS/` directory:

```bash
# Compile a utility
pnut-ts -d -I ../. <utility>.spin2

# Download and run on P2 (connects at 2 Mbit serial)
pnut-term-ts -r <utility>.bin
```

The `-I ../.` flag tells the compiler to find the `dual_sd_fat32_flash_fs` driver in the parent `src/` directory.

---

## SD Utility Details

### 1. DFS_SD_format_card.spin2

**Purpose:** Format an SD card with a FAT32 filesystem.

Uses `isp_format_utility.spin2` (library) which provides the formatting logic.

**Usage:**
```bash
./run_test.sh ../src/UTILS/DFS_SD_format_card.spin2 -t 120
```

**WARNING:** This will **ERASE ALL DATA** on the SD card!

**Creates:**
- MBR with single FAT32 LBA partition (type $0C)
- 4MB-aligned partition start (sector 8192)
- VBR (Volume Boot Record) with standard BPB
- Backup VBR at sector 6
- FSInfo sector with free cluster tracking
- Backup FSInfo at sector 7
- Dual FAT tables (FAT1 and FAT2)
- Root directory with volume label entry

**Cross-OS Compatibility:**
- Windows, macOS, and Linux compatible
- Follows Microsoft FAT32 specification
- Uses standard sector sizes and alignments

**Output:**
```
======================================================
  SD Card Format Utility
======================================================

WARNING: This will ERASE ALL DATA on the card!

Formatting card with label 'P2-BENCH'...

FORMAT SUCCESSFUL!

END_SESSION
```

---

### 2. DFS_SD_card_characterize.spin2

**Purpose:** Extract and display all card register information.

**Usage:**
```bash
./run_test.sh ../src/UTILS/DFS_SD_card_characterize.spin2 -t 60
```

**Reads and Displays:**

| Register | Size | Information |
|----------|------|-------------|
| **CID** | 16 bytes | Manufacturer ID, OEM ID, Product Name, Revision, Serial Number, Manufacturing Date |
| **CSD** | 16 bytes | Card capacity, transfer speeds, command classes, read/write block sizes |
| **SCR** | 8 bytes | SD specification version, security features, bus widths supported |
| **OCR** | 4 bytes | Operating voltage ranges, card capacity status |
| **VBR/BPB** | 512 bytes | FAT32 filesystem parameters |

**Sample Output:**
```
======================================================
  SD Card Characterization Diagnostic
======================================================

========== CID (Card Identification) ==========
  Manufacturer ID:    $03 (SanDisk)
  OEM/Application ID: "SD"
  Product Name:       "SD64G"
  Product Revision:   8.0
  Serial Number:      $12345678
  Manufacturing Date: 2023/06

========== CSD (Card Specific Data) ==========
  CSD Version:        2.0 (SDHC/SDXC)
  Card Capacity:      59.48 GB
  Max Transfer Rate:  50 MHz
  Read Block Length:  512 bytes
  ...

========== Filesystem (VBR/BPB) ==========
  Volume Label:       P2-XFER
  Sectors per Cluster: 64
  Total Sectors:      124735488
  Free Space:         59.45 GB
```

**Use Cases:**
- Identify card manufacturer and model
- Verify card capacity matches specification
- Check supported features before use
- Debug card compatibility issues

---

### 3. DFS_SD_FAT32_audit.spin2

**Purpose:** Verify FAT32 filesystem integrity without modifying the card.

**Usage:**
```bash
./run_test.sh ../src/UTILS/DFS_SD_FAT32_audit.spin2 -t 60
```

**Read-Only:** This tool does NOT modify any data on the card.

**Checks Performed:**

| Structure | Validations |
|-----------|-------------|
| **MBR** | Boot signature, partition type, partition boundaries |
| **VBR** | Jump instruction, BPB fields, extended signature |
| **Backup VBR** | Matches primary VBR (sector 6) |
| **FSInfo** | All three signatures valid, free cluster count reasonable |
| **Backup FSInfo** | Matches primary FSInfo (sector 7) |
| **FAT Tables** | FAT1 and FAT2 match, media descriptor valid |
| **Root Directory** | Volume label present, structure valid |
| **Mount Test** | Driver can mount and read filesystem |

**Sample Output:**
```
==============================================
  FAT32 Filesystem Audit Tool
  (Read-only - does not modify card)
==============================================

* Initializing card...
Card initialized successfully

=== MBR Structure ===
[PASS] Boot signature: $AA55
[PASS] Partition type: $0C (FAT32 LBA)
[PASS] Partition start: 8192 (4MB aligned)

=== VBR Structure ===
[PASS] Jump instruction: $EB
[PASS] Bytes per sector: 512
[PASS] Sectors per cluster: 64
[PASS] Reserved sectors: 32
...

=== FAT Consistency ===
[PASS] FAT1 media descriptor: $F8
[PASS] FAT2 matches FAT1

=== Summary ===
Tests: 24, Passed: 24, Failed: 0
Filesystem integrity: OK

END_SESSION
```

**Use Cases:**
- Verify filesystem after running tests
- Check card health before deployment
- Debug mount failures
- Validate format utility output

---

### 4. DFS_SD_FAT32_fsck.spin2

**Purpose:** Check and repair FAT32 filesystem corruption.

**Usage:**
```bash
./run_test.sh ../src/UTILS/DFS_SD_FAT32_fsck.spin2 -t 300
```

**WARNING:** This tool **modifies the card** to repair detected problems. Run the audit tool first if you want a read-only check.

**Four-Pass Architecture:**

| Pass | Name | Purpose |
|------|------|---------|
| **Pass 1** | Structural Integrity | Repair VBR backup, FSInfo signatures/backup, FAT[0]/[1]/[2] entries |
| **Pass 2** | Directory & Chain Validation | Walk directory tree, validate cluster chains, detect cross-links |
| **Pass 3** | Lost Cluster Recovery | Free allocated clusters not referenced by any file or directory |
| **Pass 4** | FAT Sync & Free Count | Synchronize FAT1 -> FAT2, correct FSInfo free cluster count |

**Repairs Performed:**

| Category | Repairs |
|----------|---------|
| **VBR** | Restore backup VBR from primary |
| **FSInfo** | Fix lead/struct/trail signatures, restore backup |
| **FAT entries** | Fix media type (FAT[0]), EOC marker (FAT[1]), root cluster (FAT[2]) |
| **Cluster chains** | Truncate chains with bad references |
| **Cross-links** | Detect clusters referenced by multiple chains |
| **Lost clusters** | Free allocated but unreferenced clusters |
| **FAT sync** | Copy FAT1 to FAT2 where sectors differ |
| **Free count** | Recalculate and update FSInfo free cluster count |

**Memory Requirements:**

The cluster bitmap uses 256KB (LONG[65536]) covering 2,097,152 clusters per window. For cards up to approximately 64GB, a single window suffices. Larger cards are processed using multiple bitmap windows — the directory tree is re-walked for each window, and lost cluster recovery runs per window. All four passes execute regardless of card size.

**Sample Output:**
```
==============================================
  FAT32 Filesystem Check & Repair (FSCK)
==============================================

* Initializing card...
  Card: 31_207_424 sectors (15_238 MB)

  Geometry:
    Partition start:  8_192
    Sectors/cluster:  16
    Sectors/FAT:      15_234
    Total clusters:   1_948_045

--- Pass 1: Structural Integrity ---
  [OK] Backup VBR matches primary
  [OK] FSInfo signatures correct
  [OK] Backup FSInfo matches primary
  [OK] FAT[0] media type correct
  [OK] FAT[1] EOC marker correct
  [OK] FAT[2] root cluster allocated
  Pass 1: 0 repairs

--- Pass 2: Directory & Chain Validation ---
  Directories scanned: 1
  Files scanned:       0
  Pass 2: 0 repairs

--- Pass 3: Lost Cluster Recovery ---
  [OK] No lost clusters found
  Pass 3: 0 repairs

--- Pass 4: FAT Sync & Free Count ---
  [OK] FAT1 and FAT2 in sync
  Free clusters: 1_948_044
  [OK] FSInfo free count correct
  Pass 4: 0 repairs

==============================================
  FSCK COMPLETE
==============================================
  Errors found:  0
  Repairs made:  0
  Warnings:      0
  Directories:   1
  Files:         0

  FILESYSTEM STATUS: CLEAN
==============================================

END_SESSION
```

**Status Messages:**
- **CLEAN** - No errors or repairs needed
- **REPAIRED** - Errors found and successfully repaired
- **ERRORS REMAIN** - Some errors could not be automatically repaired

**Use Cases:**
- Repair filesystem after unexpected power loss or reset
- Fix corruption after failed write operations
- Recover lost disk space from orphaned cluster chains
- Synchronize FAT1 and FAT2 after partial writes
- Verify and correct FSInfo free cluster count
- Run after audit reports failures to auto-repair them

---

## Flash Utility Details

### 5. DFS_FL_format.spin2

**Purpose:** Format the onboard 16MB Flash filesystem.

**Usage:**
```bash
./run_test.sh ../src/UTILS/DFS_FL_format.spin2 -t 120
```

**WARNING:** This will **ERASE ALL FILES** stored in Flash!

The Flash format operation cancels all active blocks and remounts the filesystem, effectively starting with a clean slate.

**Output:**
```
======================================================
  Flash Filesystem Format Utility
======================================================

WARNING: This will ERASE ALL FILES in Flash!

Formatting Flash filesystem...

FORMAT SUCCESSFUL!

END_SESSION
```

**Use Cases:**
- Initialize Flash filesystem on a new board
- Reset Flash after development/testing
- Recover from severe corruption when fsck cannot repair

---

### 6. DFS_FL_audit.spin2

**Purpose:** Read-only integrity check for the onboard Flash filesystem.

**Usage:**
```bash
./run_test.sh ../src/UTILS/DFS_FL_audit.spin2 -t 120
```

**Read-Only:** This tool does NOT modify the Flash chip.

**Three-Phase Check:**

| Phase | Operation | Purpose |
|-------|-----------|---------|
| **Phase 1** | `canMount()` | Non-destructive health check (scans all blocks, validates CRC-32) |
| **Phase 2** | `mount()` + `stats()` | Verify mount succeeds, read block/file counts |
| **Phase 3** | File iteration | Walk all files via `directory()`, compare count against `stats()` |

**Verifications:**
- canMount reports no issues (CRC-32 valid, no duplicate IDs, no orphaned blocks)
- Mount succeeds
- Used blocks + free blocks = total blocks
- File count from stats() matches file count from iteration
- JEDEC ID readable

**Sample Output:**
```
======================================================
  Flash Filesystem Audit (Read-Only)
======================================================

Phase 1: canMount() health check...
  canMount: PASS

Phase 2: Mount and statistics...
  Mount: PASS
  Used blocks:  42
  Free blocks:  3798
  File count:   5
  Total blocks: 3840
  JEDEC ID: $00EF4018_12345678

Phase 3: File iteration verification...
  [1] config.dat (256 bytes)
  [2] log_001.txt (1024 bytes)
  [3] log_002.txt (512 bytes)
  [4] settings.bin (128 bytes)
  [5] firmware.img (8192 bytes)
  Iterated files: 5
  Total bytes:    10112
  File count: MATCH

======================================================
  AUDIT PASSED - Flash filesystem is healthy
======================================================

END_SESSION
```

**Use Cases:**
- Verify Flash filesystem health before deployment
- Check integrity after unexpected power loss
- Monitor Flash wear and utilization
- Debug mount or file access failures

---

### 7. DFS_FL_fsck.spin2

**Purpose:** Check and repair Flash filesystem corruption.

**Usage:**
```bash
./run_test.sh ../src/UTILS/DFS_FL_fsck.spin2 -t 120
```

**How Repair Works:**

The Flash mount process already performs automatic repair:
- **M1**: Scans all blocks, validates CRC-32, resolves duplicate block IDs, cancels corrupted blocks
- **M2**: Locates complete files, identifies orphaned blocks
- **M3**: Cancels orphaned blocks

The fsck utility leverages this by first running a read-only check (`canMount`), then triggering a repair-mount if issues are detected.

**Two-Phase Process:**

| Phase | Operation | Purpose |
|-------|-----------|---------|
| **Phase 1** | `canMount()` | Read-only audit to detect issues |
| **Phase 2** | `mount()` | Triggers automatic repair (only if Phase 1 finds issues) |

**Sample Output (no issues):**
```
======================================================
  Flash Filesystem Check & Repair (FSCK)
======================================================

Phase 1: Read-only health check (canMount)...
  Health check: PASS (no issues detected)

  Mounting to verify file statistics...
  Used blocks:  42
  Free blocks:  3798
  File count:   5

======================================================
  FSCK COMPLETE - No repairs needed
======================================================

END_SESSION
```

**Sample Output (with repair):**
```
======================================================
  Flash Filesystem Check & Repair (FSCK)
======================================================

Phase 1: Read-only health check (canMount)...
  Health check: ISSUES DETECTED (status=-23)

Phase 2: Repairing via mount (resolves duplicates, orphans, bad CRC)...
  Mount/repair: SUCCESS

  Post-repair statistics:
  Used blocks:  40
  Free blocks:  3800
  File count:   4

======================================================
  FSCK COMPLETE - Repairs applied
======================================================

END_SESSION
```

**Use Cases:**
- Repair Flash after unexpected power loss during write operations
- Resolve duplicate block IDs from interrupted make-before-break replacements
- Clean up orphaned blocks from incomplete file operations
- Recover from CRC-32 failures caused by bit errors

---

## Directory Structure

```
src/UTILS/
├── DFS_SD_format_card.spin2        # FAT32 card formatter
├── DFS_SD_card_characterize.spin2  # SD card register reader
├── DFS_SD_FAT32_audit.spin2        # FAT32 filesystem validator
├── DFS_SD_FAT32_fsck.spin2         # FAT32 filesystem check & repair
├── DFS_FL_format.spin2             # Flash filesystem formatter
├── DFS_FL_audit.spin2              # Flash filesystem integrity check
├── DFS_FL_fsck.spin2               # Flash filesystem check & repair
├── isp_format_utility.spin2        # FAT32 format library (used by DFS_SD_format_card)
├── isp_fsck_utility.spin2          # Combined FSCK + Audit library (runs in temp cog)
├── isp_mem_strings.spin2           # String manipulation library
└── isp_string_fifo.spin2           # Lock-free inter-cog string FIFO
```

---

## Recommended Workflows

### New SD Card Setup

1. **Characterize** - Read card registers to identify the card
   ```bash
   ./run_test.sh ../src/UTILS/DFS_SD_card_characterize.spin2 -t 60
   ```

2. **Format** - Create clean FAT32 filesystem
   ```bash
   ./run_test.sh ../src/UTILS/DFS_SD_format_card.spin2 -t 120
   ```

3. **Audit** - Verify filesystem structure
   ```bash
   ./run_test.sh ../src/UTILS/DFS_SD_FAT32_audit.spin2 -t 60
   ```

### After SD Testing

Run the audit tool to verify filesystem integrity:
```bash
./run_test.sh ../src/UTILS/DFS_SD_FAT32_audit.spin2 -t 60
```

If the audit reports failures, run FSCK to auto-repair:
```bash
./run_test.sh ../src/UTILS/DFS_SD_FAT32_fsck.spin2 -t 300
```

### Flash Filesystem Setup

1. **Format** - Initialize Flash filesystem (erases all existing files)
   ```bash
   ./run_test.sh ../src/UTILS/DFS_FL_format.spin2 -t 120
   ```

2. **Audit** - Verify filesystem health
   ```bash
   ./run_test.sh ../src/UTILS/DFS_FL_audit.spin2 -t 120
   ```

### After Flash Testing

Run the audit tool for a non-destructive health check:
```bash
./run_test.sh ../src/UTILS/DFS_FL_audit.spin2 -t 120
```

If the audit reports issues, run FSCK to trigger auto-repair:
```bash
./run_test.sh ../src/UTILS/DFS_FL_fsck.spin2 -t 120
```

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

## Support Libraries

| Library | Purpose |
|---------|---------|
| **isp_format_utility.spin2** | FAT32 format engine — creates MBR, VBR, FAT tables, root directory. Used by `DFS_SD_format_card`. |
| **isp_fsck_utility.spin2** | FAT32 FSCK + Audit engine — 4-pass structural repair, directory/chain validation, lost cluster recovery. Runs in a temporary cog. Used by `DFS_SD_FAT32_audit` and `DFS_SD_FAT32_fsck`. |
| **isp_mem_strings.spin2** | String manipulation routines for hub memory. |
| **isp_string_fifo.spin2** | Lock-free inter-cog string FIFO for passing debug output from the FSCK/Audit cog back to the main cog. |

---

## License

MIT License - See LICENSE file for details.

Copyright (c) 2026 Iron Sheep Productions, LLC
