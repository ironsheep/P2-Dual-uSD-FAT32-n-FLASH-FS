# Regression Tests

Hardware-verified regression test suites for the unified dual-FS driver. All tests execute on real P2 hardware with a physical SD card and onboard Flash chip.

## Test Suites

### Dual-Device and Cross-Device Tests

| File | Tests | Description |
|------|:-----:|-------------|
| `DFS_RT_dual_device_tests.spin2` | 36 | Flash mount, bus switching, SD integrity, handle pool |
| `DFS_RT_cross_device_tests.spin2` | 21 | Interleaved I/O, copyFile() SD<->Flash, edge cases |

### SD Regression Tests

| File | Tests | Description |
|------|:-----:|-------------|
| `DFS_SD_RT_mount_tests.spin2` | 21 | Mount, unmount, remount cycles |
| `DFS_SD_RT_file_ops_tests.spin2` | 22 | Create, open, close, delete, rename (V3 handle API) |
| `DFS_SD_RT_read_write_tests.spin2` | 38 | Data integrity, sector boundaries, multi-cluster |
| `DFS_SD_RT_directory_tests.spin2` | 31 | Directory listing, create, navigate, deep nesting |
| `DFS_SD_RT_dirhandle_tests.spin2` | 22 | V3 directory handle enumeration |
| `DFS_SD_RT_subdir_ops_tests.spin2` | 18 | Cross-buffer cache coherence, subdirectory ops |
| `DFS_SD_RT_seek_tests.spin2` | 37 | Seek and tell operations |
| `DFS_SD_RT_multihandle_tests.spin2` | 19 | Multiple simultaneous file handles |
| `DFS_SD_RT_multicog_tests.spin2` | 14 | Multi-cog concurrent access, lock serialization |
| `DFS_SD_RT_multiblock_tests.spin2` | 6 | Multi-sector streamer DMA transfers (CMD18/CMD25) |
| `DFS_SD_RT_raw_sector_tests.spin2` | 14 | Raw sector read/write round-trips |
| `DFS_SD_RT_volume_tests.spin2` | 23 | Volume label, VBR access, sync, setDate |
| `DFS_SD_RT_register_tests.spin2` | 6 | Card register access (CID/CSD/SCR/OCR/SD Status) |
| `DFS_SD_RT_speed_tests.spin2` | 14 | SPI speed control, CMD6 high-speed mode |
| `DFS_SD_RT_error_handling_tests.spin2` | 17 | Error conditions, invalid handles, state errors |
| `DFS_SD_RT_recovery_tests.spin2` | 7 | Recovery from CRC errors |
| `DFS_SD_RT_crc_validation_tests.spin2` | 6 | CRC error injection hooks |
| `DFS_SD_RT_crc_diag_tests.spin2` | 14 | CRC diagnostic counters |
| `DFS_SD_RT_parity_tests.spin2` | 32 | Feature parity: exists, file_size, stats, seek, open modes |
| `DFS_SD_RT_testcard_validation.spin2` | 39 | Test card characterization (read-only) |

**Destructive (run separately):**

| File | Tests | Description |
|------|:-----:|-------------|
| `DFS_SD_RT_format_tests.spin2` | 46 | FAT32 format and verify (erases card!) |

### Flash Regression Tests

| File | Tests | Description |
|------|:-----:|-------------|
| `DFS_FL_RT_mount_handle_basics_tests.spin2` | 50 | Flash mount, format, handle basics |
| `DFS_FL_RT_rw_tests.spin2` | 118 | Flash read/write operations |
| `DFS_FL_RT_rw_block_tests.spin2` | 39 | Flash block-level read/write |
| `DFS_FL_RT_rw_modify_tests.spin2` | 102 | Flash read/modify/write patterns |
| `DFS_FL_RT_append_tests.spin2` | 114 | Flash append and flush() |
| `DFS_FL_RT_seek_tests.spin2` | 81 | Flash seek operations |
| `DFS_FL_RT_circular_tests.spin2` | 262 | Flash circular file operations |
| `DFS_FL_RT_circular_compat_tests.spin2` | 79 | Flash circular file compatibility |
| `DFS_FL_RT_cwd_tests.spin2` | 31 | Flash CWD emulation, absolute paths |

**Optional stress test:**

| File | Tests | Description |
|------|:-----:|-------------|
| `DFS_FL_RT_8cog_tests.spin2` | 66 | 8-cog concurrent Flash stress test |

### Support Files

| File | Description |
|------|-------------|
| `DFS_RT_utilities.spin2` | Unified test framework (assertions, patterns, Flash helpers, per-cog counters) |

## Test Counts

| Category | Suites | Tests |
|----------|:------:|------:|
| Dual/Cross-device | 2 | 57 |
| SD (standard) | 20 | 402 |
| Flash (standard) | 10 | 876 |
| **Total (standard)** | **32** | **1,335** |

Optional suites add: format (+46), 8-cog stress.

## Prerequisites

- **pnut-ts** and **pnut-term-ts** -- Parallax Spin2 compiler and serial terminal
- Parallax Propeller 2 (P2 Edge Module) connected via USB
- FAT32-formatted SD card (see [Test Card Specification](TEST-CARD-SPECIFICATION.md))
- Onboard 16MB Flash chip (standard on P2 Edge)

## Building and Running

### Compile a single test

From this directory:

```bash
pnut-ts -d -I .. <test_file>.spin2
```

The `-I ..` flag finds `dual_sd_fat32_flash_fs.spin2` in the parent `src/` directory.

### Run a single test via runner

```bash
cd ../../tools/
./run_test.sh ../src/regression-tests/DFS_SD_RT_mount_tests.spin2

# With custom timeout (seconds, default 60)
./run_test.sh ../src/regression-tests/DFS_SD_RT_multicog_tests.spin2 -t 120
```

### Run all regression suites

```bash
cd ../../tools/

# Standard suite (32 suites, 1,335 tests)
./run_all_regression.sh

# Include 8-cog stress test
./run_all_regression.sh --include-8cog

# Include destructive format test (erases SD card!)
./run_all_regression.sh --include-format

# SD-only or Flash-only
./run_sd_regression.sh
./run_flash_regression.sh
```

Logs are saved to `tools/logs/`.

## Interpreting Results

### Successful test output

```
=== Test Group: Card Initialization ===

* Test #1: Mount SD card
   mount() returns success: result = 0
    -> pass

...

============================================================
* 21 Tests - Pass: 21, Fail: 0
============================================================

END_SESSION
```

### Failed test output

```
* Test #5: Verify file content
   byte at 0: result = 65 (expected 0)
    -> FAIL
```

## Hardware Configuration

Default SD pins (P2 Edge Module): CS=P60, MOSI=P59, MISO=P58, SCK=P61. The Flash chip shares MOSI/MISO/SCK with a separate CS. Pin assignments are defined in the `CON` block of each test file.

## Documentation

- [THEORY-OF-OPERATIONS.md](THEORY-OF-OPERATIONS.md) -- Detailed theory of operations for each test suite
- [TEST-CARD-SPECIFICATION.md](TEST-CARD-SPECIFICATION.md) -- SD test card file layout and contents
- [REGRESSION-TEST-ANALYSIS.md](../../DOCs/Analysis/REGRESSION-TEST-ANALYSIS.md) -- Pre-release quality audit and hardening results

---

*Part of the [P2 Dual SD FAT32 + Flash Filesystem](../../README.md) project -- Iron Sheep Productions*
