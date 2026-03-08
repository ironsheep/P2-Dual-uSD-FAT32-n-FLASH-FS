# SD Card Test Specification

**Purpose**: Read-only validation of the unified dual-FS driver's SD FAT32 subsystem
**Card Type**: 32GB SDHC (block addressing, FAT32)
**Date Created**: 2026-01-14
**Test Program**: `DFS_SD_RT_testcard_validation.spin2` (39 tests)

---

## Directory Structure

Copy the contents of `TESTROOT/` to the **root** of the SD card.

```
SD Card Root/
├── TINY.TXT           (29 bytes)
├── EXACT512.BIN       (512 bytes)
├── TWOSEC.TXT         (2,550 bytes)
├── FOUR_K.BIN         (4,096 bytes)
├── SIXTYFK.BIN        (65,536 bytes)
├── SEEKTEST.BIN       (2,016 bytes)
├── CHECKSUM.BIN       (1,024 bytes)
├── LEVEL1/
│   ├── INLEVEL1.TXT   (54 bytes)
│   └── LEVEL2/
│       └── DEEP.TXT   (71 bytes)
└── MULTI/
    ├── FILE1.TXT      (18 bytes)
    ├── FILE2.TXT      (18 bytes)
    ├── FILE3.TXT      (18 bytes)
    ├── FILE4.TXT      (18 bytes)
    └── FILE5.TXT      (18 bytes)
```

---

## Test Files Reference

### TINY.TXT (29 bytes)

**Purpose**: Minimal file, single partial sector

| Property | Value |
|----------|-------|
| Size | 29 bytes |
| Sectors | 1 (partial) |
| MD5 | `30dbd93601aca775cd5df043b6b4c03f` |
| Content | `TINY TEST FILE - 32 BYTES OK!` |
| First byte | `T` (0x54) |
| Last byte | `!` (0x21) |

**Test**: Read entire file, verify content matches exactly.

---

### EXACT512.BIN (512 bytes)

**Purpose**: Exactly one sector boundary test

| Property | Value |
|----------|-------|
| Size | 512 bytes |
| Sectors | 1 (exact) |
| MD5 | `07f12645cfba360a95457892c0f279c5` |
| Content | 512 bytes of `X` (0x58) |
| All bytes | 0x58 |

**Test**: Read 512 bytes, verify all are 0x58.

---

### TWOSEC.TXT (2,550 bytes)

**Purpose**: Multi-sector text file, sector boundary crossing

| Property | Value |
|----------|-------|
| Size | 2,550 bytes |
| Sectors | 5 (partial last) |
| MD5 | `714324af4041dd7c5fb530cf40e2b6a1` |
| Pattern | `LINE####--` repeated, 50 lines |
| First line | `LINE0001--LINE0001--LINE0001--LINE0001--LINE0001--` |
| Last line | `LINE0050--LINE0050--LINE0050--LINE0050--LINE0050--` |

**Test**: Read file, verify line count and pattern.

---

### FOUR_K.BIN (4,096 bytes)

**Purpose**: Multi-sector binary, likely single cluster

| Property | Value |
|----------|-------|
| Size | 4,096 bytes (4 KB) |
| Sectors | 8 |
| MD5 | `2bcd3c4de20c918e19fab5c36249c70d` |
| Pattern | Sequential bytes: byte[i] = i & 0xFF |
| Byte 0 | 0x00 |
| Byte 255 | 0xFF |
| Byte 256 | 0x00 |
| Byte 4095 | 0xFF |

**Test**: Read sequential positions, verify (position & 0xFF) pattern.

---

### SIXTYFK.BIN (65,536 bytes)

**Purpose**: Multi-cluster file (64 KB), FAT chain following

| Property | Value |
|----------|-------|
| Size | 65,536 bytes (64 KB) |
| Sectors | 128 |
| Clusters | Multiple (depends on cluster size) |
| MD5 | `614a45721283c3457630c6fd7d18198b` |
| Pattern | byte[i] = (block << 1) XOR (i & 0xFF) where block = i / 512 |

**Test**: Verify multi-cluster reading, check pattern at sector boundaries.

**Verification formula**:
```spin2
expected_byte := ((position / 512) << 1) ^ (position & $FF)
```

---

### SEEKTEST.BIN (2,016 bytes)

**Purpose**: Random access / seek() testing

| Property | Value |
|----------|-------|
| Size | 2,016 bytes |
| Sectors | 4 (partial last) |
| MD5 | `7d6921146d3fcbbeccbd7947087e1b07` |
| Structure | 32 blocks of 63 bytes each |
| Block header | `BLK##---` (8 bytes, ## = 00-31) |
| Block filler | 55 bytes of 0x55 |

**Block layout** (63 bytes per block):
```
Offset 0:    "BLK00---" (8 bytes) + 55 bytes of 0x55
Offset 63:   "BLK01---" (8 bytes) + 55 bytes of 0x55
Offset 126:  "BLK02---" (8 bytes) + 55 bytes of 0x55
...
Offset 1953: "BLK31---" (8 bytes) + 55 bytes of 0x55
```

**Seek test positions**:

| Seek To | Expected First Bytes |
|---------|---------------------|
| 0 | `BLK00---` |
| 63 | `BLK01---` |
| 126 | `BLK02---` |
| 512 | (within block 8) |
| 1000 | (within block 15) |

---

### CHECKSUM.BIN (1,024 bytes)

**Purpose**: Data integrity verification

| Property | Value |
|----------|-------|
| Size | 1,024 bytes (1 KB) |
| Sectors | 2 |
| MD5 | `b2ea9f7fcea831a4a63b213f41a8855b` |
| Pattern | bytes 0-255 repeated 4 times |
| Sum of all bytes | 130,560 (0x0001FE00) |

**Verification**:
```spin2
checksum := 0
repeat i from 0 to 1023
  checksum += buf[i]
' Expected: checksum == 130560
```

---

### INLEVEL1.TXT (54 bytes)

**Purpose**: Subdirectory access test

| Property | Value |
|----------|-------|
| Path | `/LEVEL1/INLEVEL1.TXT` |
| Size | 54 bytes |
| Content | `This file is in LEVEL1 subdirectory for path testing.` |

**Test**: `dfs.openFileRead(dfs.DEV_SD, @"/LEVEL1/INLEVEL1.TXT")`

---

### DEEP.TXT (71 bytes)

**Purpose**: Nested subdirectory access test

| Property | Value |
|----------|-------|
| Path | `/LEVEL1/LEVEL2/DEEP.TXT` |
| Size | 71 bytes |
| Content | `Deepest level - LEVEL2 directory test file for nested path resolution.` |

**Test**: `dfs.openFileRead(dfs.DEV_SD, @"/LEVEL1/LEVEL2/DEEP.TXT")`

---

### MULTI/FILE1-5.TXT (18 bytes each)

**Purpose**: Directory enumeration test

| File | Content |
|------|---------|
| FILE1.TXT | `Multi-file test 1` |
| FILE2.TXT | `Multi-file test 2` |
| FILE3.TXT | `Multi-file test 3` |
| FILE4.TXT | `Multi-file test 4` |
| FILE5.TXT | `Multi-file test 5` |

**Test**: `dfs.changeDirectory(dfs.DEV_SD, @"MULTI")` then enumerate with `dfs.readDirectory()`, expect 5 files.

---

## Running the Validation Test

```bash
cd tools/
./run_test.sh ../src/regression-tests/DFS_SD_RT_testcard_validation.spin2
```

The test is read-only and produces 39 assertions across 13 test groups: mount validation, root directory enumeration, file reads at various sizes and boundaries, seek operations, checksum integrity, path resolution (1 and 2 levels deep), directory navigation, and a sequential read benchmark.

---

## Card Preparation Instructions

1. Format 32GB SDHC card as FAT32 (default cluster size)
2. Copy contents of `TestCard/TESTROOT/` to card root
3. Safely eject card
4. Card is ready for P2 testing

**Verify on host OS**:
```bash
# On Mac/Linux
find /Volumes/SDCARD -type f -exec ls -la {} \;
md5sum /Volumes/SDCARD/*.BIN /Volumes/SDCARD/*.TXT
```

---

*Test specification for the P2 Dual SD FAT32 + Flash Filesystem project -- Iron Sheep Productions*
