# SD Card Test Specification

**Purpose**: Read-only validation of OB4269 FAT32 driver
**Card Type**: 32GB SDHC (block addressing, FAT32)
**Date Created**: 2026-01-14

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

**Test**: `openFile(string("/LEVEL1/INLEVEL1.TXT"))`

---

### DEEP.TXT (71 bytes)

**Purpose**: Nested subdirectory access test

| Property | Value |
|----------|-------|
| Path | `/LEVEL1/LEVEL2/DEEP.TXT` |
| Size | 71 bytes |
| Content | `Deepest level - LEVEL2 directory test file for nested path resolution.` |

**Test**: `openFile(string("/LEVEL1/LEVEL2/DEEP.TXT"))`

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

**Test**: `changeDirectory(string("MULTI"))` then enumerate with `readDirectory()`, expect 5 files.

---

## Test Suite

### Test 1: Mount Validation

```spin2
PUB test_mount() : pass
  pass := sd.mount(CS_PIN, MOSI_PIN, MISO_PIN, SCK_PIN)
  ' Expected: pass == true
```

### Test 2: Root Directory Enumeration

```spin2
PUB test_root_directory() : count
  count := 0
  repeat until sd.readDirectory(count) == 0
    count++
  ' Expected: count >= 7 (TINY.TXT, EXACT512.BIN, etc. + directories)
```

### Test 3: Small File Read

```spin2
PUB test_tiny_read() : pass | size
  pass := sd.openFile(string("TINY.TXT"))
  size := sd.fileSize()
  sd.read(@buffer, size)
  sd.closeFile()
  ' Expected: size == 29
  ' Expected: buffer starts with "TINY TEST"
```

### Test 4: Exact Sector Boundary

```spin2
PUB test_exact_512() : pass | i
  sd.openFile(string("EXACT512.BIN"))
  sd.read(@buffer, 512)
  sd.closeFile()
  pass := true
  repeat i from 0 to 511
    if buffer[i] <> $58
      pass := false
      quit
  ' Expected: pass == true (all bytes are 0x58)
```

### Test 5: Multi-Sector Read

```spin2
PUB test_four_k() : pass | i, expected
  sd.openFile(string("FOUR_K.BIN"))
  sd.read(@buffer, 4096)
  sd.closeFile()
  pass := true
  repeat i from 0 to 4095
    expected := i & $FF
    if buffer[i] <> expected
      pass := false
      quit
  ' Expected: pass == true
```

### Test 6: Seek Test

```spin2
PUB test_seek() : pass
  sd.openFile(string("SEEKTEST.BIN"))

  ' Test seek to block 0
  sd.seek(0)
  sd.read(@buffer, 8)
  pass := strcomp(@buffer, string("BLK00---"))

  ' Test seek to block 10
  sd.seek(630)  ' 10 * 63
  sd.read(@buffer, 8)
  pass &= strcomp(@buffer, string("BLK10---"))

  sd.closeFile()
  ' Expected: pass == true
```

### Test 7: Path Resolution

```spin2
PUB test_deep_path() : pass
  pass := sd.openFile(string("/LEVEL1/LEVEL2/DEEP.TXT"))
  if pass
    pass := (sd.fileSize() == 71)
  sd.closeFile()
  ' Expected: pass == true
```

### Test 8: Multi-Cluster File

```spin2
PUB test_large_file() : pass | pos, expected, actual
  sd.openFile(string("SIXTYFK.BIN"))
  pass := (sd.fileSize() == 65536)

  ' Check bytes at various positions
  repeat pos from 0 to 65535 step 1024
    sd.seek(pos)
    sd.read(@buffer, 1)
    expected := ((pos / 512) << 1) ^ (pos & $FF)
    if buffer[0] <> expected
      pass := false
      quit

  sd.closeFile()
  ' Expected: pass == true
```

### Test 9: Directory Navigation

```spin2
PUB test_directory_nav() : pass | count
  pass := sd.changeDirectory(string("MULTI"))
  count := 0
  repeat until sd.readDirectory(count) == 0
    count++
  sd.changeDirectory(string(".."))
  ' Expected: pass == true, count == 5
```

### Test 10: Checksum Verification

```spin2
PUB test_checksum() : pass | i, sum
  sd.openFile(string("CHECKSUM.BIN"))
  sd.read(@buffer, 1024)
  sd.closeFile()
  sum := 0
  repeat i from 0 to 1023
    sum += buffer[i]
  pass := (sum == 130560)
  ' Expected: pass == true
```

---

## Performance Benchmarks

### Sector Read Timing

```spin2
PUB benchmark_sector_read() : microseconds | start, i
  sd.openFile(string("SIXTYFK.BIN"))
  start := getct()
  repeat i from 0 to 127
    sd.read(@buffer, 512)
  microseconds := (getct() - start) / (clkfreq / 1_000_000)
  sd.closeFile()
  ' Report: microseconds for 128 sector reads (64 KB)
  ' Calculate: bytes/second = 65536 * 1000000 / microseconds
```

### Sequential vs Random Access

```spin2
PUB benchmark_sequential() : us_seq, us_random | start, i
  ' Sequential read
  sd.openFile(string("SIXTYFK.BIN"))
  start := getct()
  repeat 64
    sd.read(@buffer, 1024)
  us_seq := (getct() - start) / (clkfreq / 1_000_000)
  sd.closeFile()

  ' Random access read
  sd.openFile(string("SIXTYFK.BIN"))
  start := getct()
  repeat i from 0 to 63
    sd.seek((i * 17) & $FFFF)  ' Pseudo-random positions
    sd.read(@buffer, 512)
  us_random := (getct() - start) / (clkfreq / 1_000_000)
  sd.closeFile()
```

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

*Test specification for OB4269 FAT32 driver validation*
