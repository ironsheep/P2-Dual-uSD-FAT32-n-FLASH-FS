# Regression Test Suite - Theory of Operations

*Technical reference for the P2 Dual SD FAT32 + Flash FS unified driver regression test suite.*

---

## 1. Executive Summary

The regression test suite validates the `dual_sd_fat32_flash_fs.spin2` unified driver -- a Propeller 2 dual-device filesystem driver that provides simultaneous access to a microSD card (FAT32) and the onboard 16MB Flash chip through a single worker cog and a single API. The suite contains **32 standard suites** across four device categories producing **1,350 test assertions**, all verified on real P2 hardware.

**Verified on hardware (2026-03-29):** 32 standard suites totaling **1,350 tests** -- all passing on both GigaStone 32GB and Elite SD cards:

| Group | Suites | Tests |
|-------|--------|-------|
| Dual-device verification | 1 | 36 |
| SD regression | 20 | 392 |
| Flash regression | 10 | 901 |
| Cross-device tests | 1 | 21 |

The tests exercise the driver from dual-device bus switching through both filesystem stacks, including cross-device file copying, multi-cog concurrent access, handle pool management, and filesystem formatting/repair validation. Every test runs on real hardware (P2 Edge + physical SD card + onboard Flash) via the `run_test.sh` headless test runner.

---

## 2. Test Framework Architecture

### 2.1 Unified Test Framework

The suite uses a single unified test framework:

| Framework | File | Used By | Key Feature |
|-----------|------|---------|-------------|
| Unified framework | `DFS_RT_utilities.spin2` | All tests (SD, Flash, dual/cross) | Per-cog VAR arrays (indexed by `cogid()`) for multi-cog safety |

The unified framework provides the core assertion API:

| Method | Purpose |
|--------|---------|
| `startTestGroup(pDesc)` | Begin a named group of related tests |
| `startTest(pDesc)` | Begin a single numbered test; auto-increments count |
| `evaluateSingleValue(result, pMsg, expected)` | Assert exact value match |
| `evaluateBool(result, pMsg, expected)` | Assert boolean match |
| `evaluateSubValue(result, pMsg, expected)` | Assert value within a sub-test series |
| `evaluateSubBool(result, pMsg, expected)` | Assert boolean within a sub-test series |
| `setCheckCountPerTest(n)` | Configure sub-test grouping divisor |
| `ShowTestEndCounts()` | Print final summary with pass/fail totals |

**Pattern generation and verification:**

| Method | Purpose |
|--------|---------|
| `fillBufferWithPattern(pBuf, len, start)` | Fill with incrementing byte pattern |
| `fillBufferWithValue(pBuf, len, val)` | Fill with constant value |
| `verifyBufferPattern(pBuf, len, start)` | Verify incrementing pattern match |
| `verifyBufferValue(pBuf, len, val)` | Verify constant value match |

The Flash framework adds Flash-specific helpers:

| Method | Purpose |
|--------|---------|
| `mountFlash()` | Init driver, mount Flash, format if needed |
| `openWriteClose(pName, pBuf, len)` | Write a test file in one call |
| `openReadVerify(pName, pBuf, expectedLen)` | Read and verify file content |
| `deleteIfExists(pName)` | Clean up test file |

### 2.2 Test Execution Model

```
run_test.sh (from tools/ directory)
  +-- pnut-ts compile (-I paths for driver and utilities)
      +-- pnut-term-ts -r download to P2 RAM
          +-- Headless capture via debug() output
              +-- Parse "END_SESSION" to detect completion
                  +-- Log saved to tools/logs/
```

- All output is via `debug()` statements (P2 debug channel on pin 62)
- Tests signal completion with `debug("END_SESSION")`
- The test runner captures output until END_SESSION or timeout
- Each test file is self-contained: inits driver, mounts, runs tests, unmounts, reports summary

### 2.3 Runner Scripts

| Script | Purpose |
|--------|---------|
| `run_test.sh <file> [-t timeout]` | Run a single test suite |
| `run_regression.sh` | All 32 standard suites in dependency order (stop on first failure) |

Options: `--from <name>` (resume from suite matching name), `--include-format` (destructive SD format), `--include-8cog` (Flash 8-cog stress), `--compile-only` (compile without running).

---

## 3. Test Suite Overview

### 3.1 Dual-Device and Cross-Device Tests (2 suites, 57 tests)

*Standard suites -- included in `run_regression.sh`.*

| File | Tests | Focus Area |
|------|:-----:|------------|
| `DFS_RT_dual_device_tests.spin2` | 36 | Flash mount, SPI bus switching, SD integrity after Flash ops, handle pool |
| `DFS_RT_cross_device_tests.spin2` | 21 | Interleaved I/O on both devices, `copyFile()` SD<->Flash, device alternation |

### 3.2 SD Regression Tests (20 standard suites, 392 tests)

| File | Tests | Focus Area |
|------|:-----:|------------|
| `DFS_SD_RT_mount_tests.spin2` | 21 | Mount, unmount, remount cycles, pre-mount errors |
| `DFS_SD_RT_file_ops_tests.spin2` | 22 | Create, open, close, delete, rename (V3 handle API) |
| `DFS_SD_RT_read_write_tests.spin2` | 38 | Data integrity, sector boundaries, multi-cluster, large files |
| `DFS_SD_RT_directory_tests.spin2` | 37 | Directory listing, create, navigate, deep nesting |
| `DFS_SD_RT_dirhandle_tests.spin2` | 22 | V3 directory handle enumeration, pool interaction |
| `DFS_SD_RT_subdir_ops_tests.spin2` | 18 | Cross-buffer cache coherence, empty files, subdirectory ops |
| `DFS_SD_RT_seek_tests.spin2` | 37 | Seek and tell operations, cross-sector seeks |
| `DFS_SD_RT_multihandle_tests.spin2` | 19 | Multiple simultaneous file handles, error boundaries |
| `DFS_SD_RT_multicog_tests.spin2` | 14 | Multi-cog singleton, concurrent access, lock serialization |
| `DFS_SD_RT_multiblock_tests.spin2` | 6 | Multi-sector streamer DMA transfers (CMD18/CMD25) |
| `DFS_SD_RT_raw_sector_tests.spin2` | 14 | Raw sector read/write round-trips |
| `DFS_SD_RT_volume_tests.spin2` | 28 | Volume label, VBR access, syncAll, sync, setDate, auto-flush |
| `DFS_SD_RT_register_tests.spin2` | 6 | Card register access (CID/CSD/SCR/OCR/SD Status) |
| `DFS_SD_RT_speed_tests.spin2` | 14 | SPI speed control, CMD6 high-speed mode |
| `DFS_SD_RT_error_handling_tests.spin2` | 17 | Error conditions, invalid handles, state errors |
| `DFS_SD_RT_recovery_tests.spin2` | 7 | Recovery scenarios after CRC errors |
| `DFS_SD_RT_crc_validation_tests.spin2` | 6 | CRC error injection hooks |
| `DFS_SD_RT_crc_diag_tests.spin2` | 14 | CRC diagnostic counters, validation toggle |
| `DFS_SD_RT_parity_tests.spin2` | 32 | Feature parity: exists, file_size, stats, seek, open modes |
| `DFS_SD_RT_defrag_tests.spin2` | 12 | Defrag API, contiguous creation, next-fit allocation |

**Destructive (run separately):**

| File | Tests | Focus Area |
|------|:-----:|------------|
| `DFS_SD_RT_format_tests.spin2` | 46 | FAT32 format and verify (erases card!) |

### 3.3 Flash Regression Tests (10 standard suites, 901 tests)

| File | Tests | Focus Area |
|------|:-----:|------------|
| `DFS_FL_RT_mount_handle_basics_tests.spin2` | 50 | Flash mount, format, handle open/close/delete |
| `DFS_FL_RT_rw_tests.spin2` | 118 | Flash read/write operations, data integrity |
| `DFS_FL_RT_rw_block_tests.spin2` | 39 | Flash block-level read/write |
| `DFS_FL_RT_rw_modify_tests.spin2` | 102 | Flash read/modify/write patterns |
| `DFS_FL_RT_append_tests.spin2` | 114 | Flash append operations, flush() |
| `DFS_FL_RT_seek_tests.spin2` | 81 | Flash seek operations |
| `DFS_FL_RT_circular_tests.spin2` | 262 | Flash circular file read/write |
| `DFS_FL_RT_circular_compat_tests.spin2` | 79 | Flash circular file compatibility |
| `DFS_FL_RT_cwd_tests.spin2` | 36 | Flash CWD emulation, absolute paths |
| `DFS_FL_RT_dirhandle_tests.spin2` | 20 | Flash directory handle enumeration |

**Optional stress test:**

| File | Tests | Focus Area |
|------|:-----:|------------|
| `DFS_FL_RT_8cog_tests.spin2` | 66 | 8-cog concurrent Flash read/write stress |

### 3.4 Support Files

| File | Purpose |
|------|---------|
| `DFS_RT_utilities.spin2` | Unified test framework (assertions, patterns, memory dump, Flash helpers) |

---

## 4. Detailed Theory of Operations

### 4.1 Dual-Device Verification (36 tests)

**Purpose:** Validate that both devices work correctly through the unified driver -- Flash mounts, SPI bus switches cleanly between devices, SD data integrity is preserved after Flash operations, and the shared handle pool works across devices.

**Why we test this:** The unified driver shares a single SPI bus between SD (Mode 0, clock idles LOW) and Flash (Mode 3, clock idles HIGH). P60 doubles as both SD CS and Flash SCK, so Flash operations corrupt the SD card's SPI state. The driver must reinitialize the SD card after Flash operations. These tests verify that bus switching is transparent to the caller.

**Test groups:**
- **Flash mount and format** -- Flash initializes and mounts through the shared SPI bus
- **Bus switching** -- Alternating SD and Flash operations without corruption
- **SD integrity** -- SD reads return correct data after Flash writes
- **Handle pool** -- Handles allocated on one device don't interfere with the other
- **Device stats** -- `stats()` returns correct values for each device independently

### 4.2 Cross-Device Tests (21 tests)

**Purpose:** Validate interleaved I/O across both devices and the `copyFile()` API that transfers files between SD and Flash.

**Why we test this:** Cross-device operations are the primary use case for the dual driver. The `copyFile()` method reads from one device's SPI protocol and writes to the other's, requiring multiple bus switches per transfer. These tests verify data integrity across the full round-trip.

**Test groups:**
- **Interleaved I/O** -- Write to SD, write to Flash, read both back
- **copyFile() SD->Flash** -- Copy a file from SD to Flash, verify content
- **copyFile() Flash->SD** -- Copy a file from Flash to SD, verify content
- **Edge cases** -- Copy empty files, overwrite existing, copy non-existent

### 4.3 SD Mount Tests (21 tests)

**Purpose:** Validate the driver lifecycle -- initialization, mount, unmount, remount, and error handling for operations attempted without a mounted filesystem.

**Why we test this:** The mount sequence is the entry point for all filesystem operations. It initializes the SPI bus, performs the SD card identification protocol (CMD0/CMD8/ACMD41/CMD58), reads the MBR and VBR to locate the FAT32 partition, and configures the smart pin SPI engine. If mounting fails or produces corrupt state, every subsequent operation is unreliable.

**Test groups:**
- **Pre-mount error handling** -- Operations fail gracefully before mount
- **Mount and card detection** -- `init()` + `mount()` succeeds, card size reasonable
- **Unmount and remount** -- Clean teardown, operations fail after unmount, remount works
- **Singleton pattern** -- Repeated `init()` calls return the same worker cog

### 4.4 SD File Operations Tests (22 tests)

**Purpose:** Validate file lifecycle operations -- create, open, close, delete, rename using the V3 handle-based API.

**Why we test this:** File operations involve directory entry manipulation, FAT chain allocation, and sector caching. Bugs here manifest as data loss, phantom files, or filesystem corruption.

**Test groups:**
- **File creation and deletion** -- `open(MODE_WRITE)` creates, `delete()` removes
- **File open/close cycle** -- Open existing, open non-existent, close flushes
- **Rename** -- Name changes, old name gone, new name accessible
- **V3 handle operations** -- Handle-based create, write, close, reopen

### 4.5 SD Read/Write Tests (38 tests)

**Purpose:** Validate data integrity for read and write operations across various sizes, patterns, and boundary conditions.

**Why we test this:** Data integrity is the most critical property of a storage driver. The P2 driver uses the streamer for bulk transfers, which means timing alignment between the SPI clock smart pin and the streamer data path must be exact. A single-bit timing error produces silent data corruption. These tests catch such errors by writing known patterns and verifying every byte on readback.

**Test groups:**
- **Small writes and reads** -- 1 byte, string, 10 bytes
- **Sector-boundary writes** -- 512, 513, 1024 bytes
- **Pattern verification** -- Sequential, alternating, all-FF, all-00, random
- **Large file writes** -- 2 KB, 4 KB, cluster boundary crossing
- **Overwrite and append** -- Shorter/longer rewrites, append at EOF

### 4.6 SD Directory Tests (37 tests)

**Purpose:** Validate directory creation, navigation, enumeration, and cleanup across nested structures.

**Why we test this:** Directory operations modify the FAT32 directory table -- creating 32-byte entries, allocating clusters for new directories, and maintaining `.`/`..` self/parent references. Navigation uses per-cog directory context, which must be correctly maintained across cog boundaries.

**Test groups:**
- **Directory creation** -- Create, verify visible, duplicate fails
- **Directory navigation** -- changeDirectory into/out, absolute paths, ".." parent
- **Directory enumeration** -- Listing contents, file count, attributes
- **Deep nesting** -- Multi-level create, navigate back via ".."
- **Boundary conditions** -- Empty directories, max filename length (8.3)

### 4.7 SD Seek Tests (37 tests)

**Purpose:** Validate file position management -- seek to absolute positions, cross-sector seeks, and boundary conditions including EOF.

**Why we test this:** Seek operations require following the FAT chain to locate the correct cluster and sector for any arbitrary byte position. Errors produce reads from wrong positions -- silent data corruption that's hard to diagnose in applications.

**Test groups:**
- **Basic seek** -- seek(0), mid-sector, pattern boundaries
- **Cross-sector seeks** -- Jump across sector boundaries (512-byte aligned)
- **Cross-cluster seeks** -- Jump across cluster boundaries (FAT chain traversal)
- **Tell verification** -- `tell()` returns correct position after seeks and reads
- **EOF behavior** -- Seek past end, seek to exact end

### 4.8 SD Multi-Handle Tests (19 tests)

**Purpose:** Validate the V3 handle pool -- multiple simultaneous file handles with independent positions and state.

**Why we test this:** The unified driver supports up to 6 concurrent file/directory handles across both devices. Each handle must maintain independent file position, open mode, and device association. These tests verify that handles don't interfere with each other.

**Test groups:**
- **Multiple open files** -- Open several files simultaneously
- **Independent positions** -- Seek in one handle doesn't affect others
- **Handle limits** -- Exceeding MAX_OPEN_FILES returns proper error
- **Handle reuse** -- Closing a handle makes it available for reuse

### 4.9 SD Multi-Cog Tests (14 tests)

**Purpose:** Validate multi-cog safety -- the hardware lock serializes access from multiple cogs, and the singleton pattern prevents cog leaks.

**Why we test this:** The unified driver uses `locktry()`/`lockrel()` to serialize multi-cog access to the SPI bus. If the locking protocol fails, concurrent operations corrupt the SPI state or produce garbled data. The singleton pattern ensures only one worker cog runs regardless of how many cogs call `init()`.

**Test groups:**
- **Singleton enforcement** -- Multiple `init()` calls return same cog
- **Concurrent read** -- Two cogs reading simultaneously
- **Lock serialization** -- Operations from different cogs don't interleave

### 4.10 SD Multi-Block Tests (6 tests)

**Purpose:** Validate multi-sector read/write using CMD18 (read multiple) and CMD25 (write multiple) with streamer DMA transfers.

**Why we test this:** Multi-block transfers use the P2 streamer for DMA, which is 4-5x faster than byte-by-byte SPI but requires precise timing and correct STOP_TRANSMISSION (CMD12) handling. These tests verify data integrity for bulk transfers.

### 4.11 SD Raw Sector Tests (14 tests)

**Purpose:** Validate raw sector read/write round-trips using `readSectorRaw()` and `writeSectorRaw()`.

**Why we test this:** Raw sector access bypasses the FAT32 filesystem and writes directly to specified sectors. The format utility and FSCK utility depend on this API. These tests verify that data written to a sector can be read back correctly.

### 4.12 SD Volume Tests (25 tests)

**Purpose:** Validate volume-level operations -- volume label, VBR access, syncAll, sync, and setDate.

**Why we test this:** Volume operations access filesystem metadata outside of normal file I/O. `syncAll()` flushes all cached data to the card, `setDate()` modifies directory entry timestamps, and volume label access reads the root directory's special entry.

### 4.13 SD Register Tests (6 tests)

**Purpose:** Validate card register access APIs for CID, CSD, SCR, OCR, and SD Status registers.

**Why we test this:** The register APIs (`readCIDRaw`, `readCSDRaw`, `readSCRRaw`, `readSDStatusRaw`, `getOCR`) provide card identification and capability information. The driver uses these internally for speed configuration and capacity calculation. The characterize utility depends on them.

### 4.14 SD Speed Tests (14 tests)

**Purpose:** Validate SPI speed control and CMD6 (High Speed mode) switching.

**Why we test this:** The driver supports dynamic SPI frequency changes and CMD6-based 50 MHz High Speed mode. Incorrect speed switching can cause SPI clock misconfiguration, leading to communication failures or silent data corruption.

### 4.15 SD Error Handling Tests (17 tests)

**Purpose:** Validate that error conditions produce correct error codes and don't crash or corrupt state.

**Why we test this:** Robust error handling prevents cascading failures. Invalid handles, operations on closed files, directory errors, and handle reuse must all return proper error codes without side effects.

### 4.16 SD CRC Tests (20 tests across 2 suites)

**SD CRC Diagnostic Tests (14 tests):** Validate CRC counter APIs and validation toggle. These tests verify that the driver correctly counts CRC errors and that CRC validation can be enabled/disabled.

**SD CRC Validation Tests (6 tests):** Validate CRC error injection hooks. These tests use internal hooks to inject CRC errors and verify that the driver detects and reports them.

### 4.17 SD Recovery Tests (7 tests)

**Purpose:** Validate recovery after injected CRC errors.

**Why we test this:** After a CRC error, the driver must retry the operation and recover to a known-good state. These tests inject errors and verify that subsequent operations succeed.

### 4.18 SD Feature Parity Tests (32 tests)

**Purpose:** Validate that unified driver SD methods match expected behavior for `exists()`, `file_size()`, `file_size_unused()`, `serial_number()`, `stats()`, `seek()`, and open modes.

**Why we test this:** The unified driver adds several methods that were not in the standalone SD driver. These tests verify that the new methods return correct results on the SD device.

### 4.19 SD Defrag Tests (12 tests)

**Purpose:** Validate the defragmentation API -- `fileFragments()`, `isFileContiguous()`, `createFileContiguous()`, and `compactFile()` -- as well as the next-fit allocator.

**Why we test this:** The defrag API relocates file clusters to achieve contiguous storage, improving sequential read performance. `compactFile()` uses a copy-then-free strategy with mandatory read-back verification. Incorrect cluster relocation or FAT chain updates would silently corrupt files.

**Test groups:**
- **Next-fit allocation** -- New files allocate from the previous allocation point, not cluster 2
- **Fragment counting** -- `fileFragments()` returns correct fragment count for contiguous and fragmented files
- **Contiguous creation** -- `createFileContiguous()` pre-allocates a contiguous cluster chain
- **Compaction** -- `compactFile()` defragments a file with data integrity verification

### 4.21 SD Format Tests (46 tests)

**Purpose:** Validate the FAT32 format utility creates a correct, cross-OS-compatible filesystem.

**Why we test this:** The format utility writes all FAT32 structures from scratch -- MBR, VBR, FSInfo, FAT tables, root directory. Any incorrect byte in these structures makes the card unreadable. The tests verify every field against the FAT32 specification after formatting.

**WARNING:** This test **erases all data** on the SD card.

**Test groups:**
- **MBR verification** -- Partition table, boot signature, partition type
- **VBR verification** -- All BPB fields, OEM name, FS type string
- **Backup VBR** -- Byte-for-byte match with primary
- **FSInfo** -- Signatures, free count, backup match
- **FAT tables** -- Special entries, FAT1/FAT2 sync
- **Root directory** -- Volume label entry
- **Mount test** -- Driver mounts the freshly formatted card

### 4.22 Flash Mount/Handle Basics Tests (50 tests)

**Purpose:** Validate Flash filesystem mount, format, and basic handle operations -- open, close, delete, exists, stats.

**Why we test this:** Flash mount scans all 3,968 blocks, builds translation tables, and resolves any corruption. Handle operations must correctly manage the block-based storage, including head/body block chains and the 4 KB block size.

### 4.23 Flash Read/Write Tests (118 tests)

**Purpose:** Validate Flash data integrity for read and write operations.

**Why we test this:** Flash I/O uses GPIO bit-bang SPI (Mode 3), which differs from the SD's smart pin SPI (Mode 0). The different SPI engine means different timing characteristics and potential failure modes.

### 4.24 Flash Block Read/Write Tests (39 tests)

**Purpose:** Validate Flash block-level read/write operations, testing the underlying 4 KB block allocation and data storage.

### 4.25 Flash Read/Modify/Write Tests (102 tests)

**Purpose:** Validate that existing files can be reopened, modified (overwritten), and the modified data persists correctly.

**Why we test this:** Flash read/modify/write involves the "fork" mechanism -- creating a new copy of the file with modifications while the old version remains until the new version is committed. This copy-on-write approach must preserve unmodified data.

### 4.26 Flash Append Tests (114 tests)

**Purpose:** Validate Flash append operations and `flush()` for data persistence.

**Why we test this:** Flash append grows a file by allocating additional body blocks and linking them into the chain. `flush()` commits the current write buffer to Flash. These operations must maintain chain integrity and data ordering.

### 4.27 Flash Seek Tests (81 tests)

**Purpose:** Validate Flash seek operations for random access reading within files.

**Why we test this:** Flash seek must follow the block chain to locate the correct 4 KB block and offset for any arbitrary byte position. Unlike SD (which can seek within contiguous sectors), Flash blocks are not necessarily contiguous on the chip.

### 4.28 Flash Circular File Tests (262 + 79 = 341 tests across 2 suites)

**Circular Tests (262 tests):** Validate Flash circular file create, write, read, and wrap-around behavior across 15 scenarios (under/at/over limit). Circular files have a fixed maximum size and overwrite the oldest data when full.

**Circular Compatibility Tests (79 tests):** Validate that circular files created by write operations can be correctly read back, including persistence verification across unmount/mount cycles.

### 4.29 Flash CWD Tests (36 tests)

**Purpose:** Validate Flash current working directory (CWD) emulation -- `changeDirectory()`, per-cog directory isolation, and absolute path support on the flat Flash filesystem.

**Why we test this:** The Flash filesystem is flat (no real directories), but the unified driver emulates CWD using filename prefixes. These tests verify that the emulation works correctly, per-cog directory state is properly isolated, and absolute paths (e.g., "/dirA/file.dat") bypass CWD and work from any directory context.

**Test groups:**
- **changeDirectory() basics** -- cd to directory, root, ".." parent navigation
- **CWD file isolation** -- files in dirA not visible from dirB and vice versa
- **CWD-aware operations** -- open, read, delete, rename all respect CWD prefix
- **Absolute path basics** -- exists(), file_size(), create, delete via absolute paths
- **Absolute path edge cases** -- root path, no double prefix, relative isolation, rename, round-trip

### 4.30 Flash Directory Handle Tests (20 tests)

**Purpose:** Validate Flash directory handle enumeration -- `openDirectory()`, `readDirectoryHandle()`, and `closeDirectoryHandle()` on the Flash device.

**Why we test this:** The Flash filesystem is flat (no real directories), but the unified driver provides directory handle enumeration that lists files matching the current CWD prefix. These tests verify that the handle-based enumeration API works correctly for Flash, returning proper filenames, sizes, and attributes.

### 4.31 Flash 8-Cog Stress Tests (66 tests)

**Purpose:** Validate concurrent Flash access from all 8 P2 cogs simultaneously.

**Why we test this:** The hardware lock must serialize all 8 cogs without deadlock or data corruption. This is the most aggressive concurrency test in the suite.

**Note:** Run separately with `--include-8cog` flag due to extended runtime.

---

## 5. Test Card Requirements

SD tests require a FAT32-formatted test card with specific test files. See `TestCard/TEST-CARD-SPECIFICATION.md` for the required directory structure and file contents.

Flash tests use the onboard 16MB W25Q128JV Flash chip. Most Flash test suites format the Flash at startup, so no special preparation is needed.

---

## 6. Coverage Analysis

### 6.1 API Coverage

The test suite covers the following driver API categories:

| Category | SD | Flash | Cross-Device |
|----------|:--:|:-----:|:------------:|
| Mount/Unmount | Yes | Yes | Yes |
| File Open/Close | Yes | Yes | Yes |
| Read/Write | Yes | Yes | Yes |
| Seek/Tell | Yes | Yes | - |
| Directory Operations | Yes | Yes (CWD) | - |
| Delete/Rename | Yes | Yes | - |
| Exists/FileSize | Yes | Yes | - |
| Stats | Yes | Yes | Yes |
| CopyFile | - | - | Yes |
| Format | Yes | Yes | - |
| Multi-Handle | Yes | Yes | - |
| Multi-Cog | Yes | Yes (8-cog) | - |
| Raw Sector | Yes | - | - |
| Card Registers | Yes | - | - |
| Speed Control | Yes | - | - |
| CRC Diagnostics | Yes | - | - |
| Circular Files | - | Yes | - |
| Serial Number | Yes | Yes | - |

### 6.2 Boundary Conditions

Tests specifically target these boundary conditions:

- **Sector boundaries** -- Reads/writes that cross 512-byte sector boundaries
- **Cluster boundaries** -- Operations that cross FAT cluster boundaries (FAT chain traversal)
- **Block boundaries** -- Flash writes that span multiple 4 KB blocks
- **Handle pool limits** -- Opening more than MAX_OPEN_FILES handles
- **EOF behavior** -- Read past end, seek past end, write at end
- **Empty files** -- Zero-length files on both devices
- **Deep nesting** -- Multi-level directory structures (SD)
- **Bus switching** -- Alternating SD and Flash operations without corruption
- **CRC errors** -- Injected errors with retry and recovery verification

---

## 7. Adding New Tests

### 7.1 SD Test Template

```spin2
OBJ
    dfs   : "dual_sd_fat32_flash_fs"
    utils : "DFS_RT_utilities"

PUB go() | status, handle
    dfs.init()
    status := dfs.mount(dfs.DEV_SD)

    utils.startTestGroup(@"My Test Group")

    utils.startTest(@"Test description")
    handle := dfs.open(dfs.DEV_SD, @"TEST.TXT", dfs.MODE_READ)
    utils.evaluateBool(handle >= 0, @"open() succeeds", true)

    dfs.close(handle)
    dfs.unmount(dfs.DEV_SD)
    dfs.stop()
    utils.ShowTestEndCounts()
    debug("END_SESSION")
```

### 7.2 Flash Test Template

```spin2
OBJ
    dfs   : "dual_sd_fat32_flash_fs"
    utils : "DFS_RT_utilities"

PUB go() | status
    utils.mountFlash()

    utils.startTestGroup(@"My Flash Test Group")

    utils.startTest(@"Write and read back")
    utils.openWriteClose(@"TEST", @testData, 100)
    status := utils.openReadVerify(@"TEST", @readBuf, 100)
    utils.evaluateBool(status, @"data matches", true)

    utils.deleteIfExists(@"TEST")
    dfs.stop()
    utils.ShowTestEndCounts()
    debug("END_SESSION")
```

### 7.3 Naming Convention

- `DFS_SD_RT_<feature>_tests.spin2` -- SD device tests
- `DFS_FL_RT_<feature>_tests.spin2` -- Flash device tests
- `DFS_RT_<feature>_tests.spin2` -- Cross-device or dual-device tests
