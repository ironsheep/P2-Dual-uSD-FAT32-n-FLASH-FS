# SD Card Utilities

This document describes the standalone utility programs included with the P2 SD Card Driver. These utilities help with card formatting, characterization, performance testing, and filesystem validation.

## Overview

The utilities are located in `src/UTILS/` and can be run independently using the test runner from the `tools/` directory.

### Utility Summary

| Utility | Purpose | Destructive? |
|---------|---------|:------------:|
| **SD_format_card.spin2** | FAT32 card formatter (standalone) | Yes |
| **SD_card_characterize.spin2** | Card register reader | No |
| **SD_speed_characterize.spin2** | SPI speed tester | No |
| **SD_frequency_characterize.spin2** | Sysclk frequency tester | No |
| **SD_performance_benchmark.spin2** | Throughput measurement | Yes* |
| **SD_FAT32_audit.spin2** | Filesystem validator | No |
| **SD_FAT32_fsck.spin2** | Filesystem check & repair | Yes |

*Creates temporary test files that are deleted after testing.

---

## Running Utilities

All utilities are run from the `tools/` directory using the test runner:

```bash
cd tools/
./run_test.sh ../src/UTILS/<utility>.spin2 [-t timeout]
```

---

## Utility Details

### 1. SD_format_card.spin2

**Purpose:** Format an SD card with a FAT32 filesystem.

Uses `isp_format_utility.spin2` (library) which provides the formatting logic.

**Usage:**
```bash
./run_test.sh ../src/UTILS/SD_format_card.spin2 -t 120
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

### 2. SD_card_characterize.spin2

**Purpose:** Extract and display all card register information.

**Usage:**
```bash
./run_test.sh ../src/UTILS/SD_card_characterize.spin2 -t 60
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
┌──────────────────────────────────────────┐
│ SD Card Characterization Diagnostic      │
└──────────────────────────────────────────┘

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
- Build a card database/catalog

---

### 3. SD_speed_characterize.spin2

**Purpose:** Find maximum reliable SPI clock speed for a specific card.

**Usage:**
```bash
./run_test.sh ../src/UTILS/SD_speed_characterize.spin2 -t 300
```

**Test Strategy:**

| Phase | Test | Purpose |
|-------|------|---------|
| **Phase 1** | 1,000 single-sector reads | Quick reliability check |
| **Phase 2** | 10,000 single-sector reads | Statistical confidence |
| **Phase 3** | 100 × 8-sector reads | Sustained transfer test |

Testing proceeds from lowest to highest speed. If any phase fails, testing stops for that speed and higher speeds are skipped.

**Speed Levels Tested:**
- 18 MHz, 20 MHz, 22 MHz, 25 MHz, 28 MHz
- 30 MHz, 33 MHz, 37 MHz, 40 MHz, 45 MHz, 50 MHz

**Output Includes:**
- Target frequency vs actual achievable frequency
- Delta percentage from ideal (due to P2 clock division)
- Pass/fail status for each phase
- CRC error counts and timeout counts
- Maximum reliable speed recommendation

**Sample Output:**
```
SD Card SPI Speed Characterization
==================================
Card: SanDisk Extreme 64GB

Speed Tests:
  18 MHz: Phase 1 PASS, Phase 2 PASS, Phase 3 PASS
  20 MHz: Phase 1 PASS, Phase 2 PASS, Phase 3 PASS
  25 MHz: Phase 1 PASS, Phase 2 PASS, Phase 3 PASS
  30 MHz: Phase 1 PASS, Phase 2 PASS, Phase 3 PASS
  33 MHz: Phase 1 PASS, Phase 2 FAIL (3 CRC errors)

Recommended Maximum Speed: 30 MHz
```

**Use Cases:**
- Determine safe operating speed for production
- Compare cards for speed capability
- Identify marginal cards with reliability issues
- Optimize driver configuration per card type

---

### 4. SD_frequency_characterize.spin2

**Purpose:** Find sysclk frequency boundaries for reliable streamer timing.

**Usage:**
```bash
./run_test.sh ../src/UTILS/SD_frequency_characterize.spin2 -t 300
```

**Test Method:**
This utility dynamically changes the P2 sysclk frequency using `clkset()` to identify exactly where multi-block operations fail. It helps find timing-sensitive frequency ranges and quantization boundaries.

**Test Frequencies:**
- 320 MHz (baseline)
- 310 MHz, 305 MHz, 300 MHz
- 295 MHz, 290 MHz, 280 MHz, 270 MHz
- 260 MHz, 255 MHz, 250 MHz, 240 MHz
- 220 MHz, 200 MHz

At each frequency, the test performs:
1. `writeSectorsRaw(8)` - Write 8 sectors (4KB)
2. `readSectorsRaw(8)` - Read 8 sectors back
3. Data integrity verification

**Output Includes:**
- Half-period value at each frequency
- Pass/fail status for multi-block operations
- Data integrity verification results
- Identification of working vs failing frequencies

**Use Cases:**
- Determine safe sysclk frequencies for production
- Identify timing boundaries for streamer operations
- Debug frequency-related failures
- Validate driver timing across frequency ranges

---

### 5. SD_performance_benchmark.spin2

**Purpose:** Measure read/write throughput for real-world performance data.

**Usage:**
```bash
./run_test.sh ../src/UTILS/SD_performance_benchmark.spin2 -t 180
```

**Measurements:**

| Category | Tests |
|----------|-------|
| **Mount/Unmount** | Timing for card initialization and filesystem mount |
| **Raw Sector** | Hardware-level read/write bypassing filesystem |
| **Multi-Sector** | CMD18/CMD25 bulk transfers (8, 32, 64 sectors) |
| **Filesystem** | Real-world file read/write through driver API |
| **Overhead** | File open/close timing |

**Test Sizes (Based on Embedded Use Cases):**

| Size | Use Case |
|------|----------|
| 512 B | Single log entry |
| 4 KB | Configuration file |
| 32 KB | Icon or small data batch |
| 128 KB | Small display image |
| 256 KB | Larger display image |

**Output Format:**
```
SD Card Performance Benchmark
=============================
Card: Gigastone 32GB

Raw Sector Performance:
  Read:  512 bytes in 0.42 ms (1.19 MB/s)
  Write: 512 bytes in 2.31 ms (0.22 MB/s)

Multi-Sector Performance (64 sectors = 32KB):
  Read:  32768 bytes in 18.2 ms (1.76 MB/s)
  Write: 32768 bytes in 45.7 ms (0.70 MB/s)

Filesystem Performance:
  File Read (32KB):  62.3 ms (513 KB/s)
  File Write (32KB): 89.1 ms (359 KB/s)
  File Open:         12.4 ms
  File Close:        8.7 ms
```

**Statistics:**
- Each measurement repeated 10 times
- Reports min/avg/max values
- Calculates throughput in KB/s and MB/s

**Use Cases:**
- Establish performance baselines
- Compare different SD cards
- Measure impact of driver optimizations
- Verify production card performance

---

### 6. SD_FAT32_audit.spin2

**Purpose:** Verify FAT32 filesystem integrity without modifying the card.

**Usage:**
```bash
./run_test.sh ../src/UTILS/SD_FAT32_audit.spin2 -t 60
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

### 7. SD_FAT32_fsck.spin2

**Purpose:** Check and repair FAT32 filesystem corruption.

**Usage:**
```bash
./run_test.sh ../src/UTILS/SD_FAT32_fsck.spin2 -t 300
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

The cluster bitmap uses 256 KB of P2 hub RAM (LONG[65536]), covering up to 2,097,152 clusters — sufficient for cards up to approximately 64 GB. Cards with more clusters receive structural integrity checks only (passes 1 and 4); chain validation and lost cluster recovery (passes 2 and 3) are skipped.

This is a current constraint of the P2's 512 KB hub memory, not a fundamental design limitation. Research into windowed or overlay-based bitmap approaches that could extend full validation to larger cards is on the [Punch List](Plans/PUNCH-LIST.md).

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

## Directory Structure

```
src/UTILS/
├── SD_format_card.spin2            # FAT32 card formatter
├── SD_card_characterize.spin2      # Card register reader
├── SD_speed_characterize.spin2     # SPI speed tester
├── SD_frequency_characterize.spin2 # Sysclk frequency tester
├── SD_performance_benchmark.spin2  # Throughput measurement
├── SD_FAT32_audit.spin2            # Filesystem validator
├── SD_FAT32_fsck.spin2             # Filesystem check & repair
├── isp_format_utility.spin2        # FAT32 format library (used by SD_format_card)
├── isp_fsck_utility.spin2          # Combined FSCK + Audit library (runs in temp cog)
└── isp_string_fifo.spin2           # Lock-free inter-cog string FIFO
```

---

## Recommended Workflow

### New Card Setup

1. **Characterize** - Read card registers to identify the card
   ```bash
   ./run_test.sh ../src/UTILS/SD_card_characterize.spin2 -t 60
   ```

2. **Speed Test** - Find maximum reliable SPI speed
   ```bash
   ./run_test.sh ../src/UTILS/SD_speed_characterize.spin2 -t 300
   ```

3. **Format** - Create clean FAT32 filesystem
   ```bash
   ./run_test.sh ../src/UTILS/SD_format_card.spin2 -t 120
   ```

4. **Audit** - Verify filesystem structure
   ```bash
   ./run_test.sh ../src/UTILS/SD_FAT32_audit.spin2 -t 60
   ```

5. **Benchmark** - Measure performance baseline
   ```bash
   ./run_test.sh ../src/UTILS/SD_performance_benchmark.spin2 -t 180
   ```

### After Testing

Run the audit tool to verify filesystem integrity:
```bash
./run_test.sh ../src/UTILS/SD_FAT32_audit.spin2 -t 60
```

If the audit reports failures, run FSCK to auto-repair:
```bash
./run_test.sh ../src/UTILS/SD_FAT32_fsck.spin2 -t 300
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

Modify the `CON` section in each utility if using different pins.

---

## License

MIT License - See LICENSE file for details.

Copyright (c) 2026 Iron Sheep Productions, LLC
