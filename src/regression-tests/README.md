# Regression Tests

Hardware-verified regression test suites for the unified dual-FS driver. Tests execute on real P2 hardware with a physical SD card and onboard Flash chip.

## Test Suites

### Dual-Device and Cross-Device Tests

| File | Tests | Description |
|------|-------|-------------|
| `DFS_RT_dual_device_tests.spin2` | 37 | Flash mount, bus switching, SD integrity, handle pool |
| `DFS_RT_cross_device_tests.spin2` | 21 | Interleaved I/O, copyFile() SD <-> Flash, edge cases |

### SD Regression Tests

| File | Tests | Description |
|------|-------|-------------|
| `DFS_SD_RT_mount_tests.spin2` | 21 | Mount, unmount, remount cycles |
| `DFS_SD_RT_read_write_tests.spin2` | 38 | File write/read round-trips |
| `DFS_SD_RT_file_ops_tests.spin2` | 22 | Create, delete, rename, exists |
| `DFS_SD_RT_directory_tests.spin2` | 31 | Directory listing (index-based) |
| `DFS_SD_RT_dirhandle_tests.spin2` | 22 | Directory handles |
| `DFS_SD_RT_subdir_ops_tests.spin2` | 18 | Subdirectory create/delete/navigate |
| `DFS_SD_RT_seek_tests.spin2` | 37 | Seek and tell operations |
| `DFS_SD_RT_multihandle_tests.spin2` | 19 | Multiple simultaneous file handles |
| `DFS_SD_RT_multicog_tests.spin2` | 14 | Multi-cog concurrent access |
| `DFS_SD_RT_multiblock_tests.spin2` | 5* | Multi-sector read/write (*manual assertions) |
| `DFS_SD_RT_raw_sector_tests.spin2` | — | Raw sector read/write (behind SD_INCLUDE_RAW) |
| `DFS_SD_RT_volume_tests.spin2` | 23 | Volume label operations |
| `DFS_SD_RT_register_tests.spin2` | 18 | Card register access (CID/CSD/SCR/OCR/SD Status) |
| `DFS_SD_RT_speed_tests.spin2` | 14 | SPI speed control |
| `DFS_SD_RT_error_handling_tests.spin2` | 16 | Error handling and edge cases |
| `DFS_SD_RT_recovery_tests.spin2` | 7 | Recovery from error conditions |
| `DFS_SD_RT_format_tests.spin2` | 46 | Format and verify (erases card!) |
| `DFS_SD_RT_crc_validation_tests.spin2` | 6 | CRC validation |
| `DFS_SD_RT_crc_diag_tests.spin2` | 14 | CRC diagnostic counters |
| `DFS_SD_RT_testcard_validation.spin2` | 39 | Test card characterization |
| `DFS_SD_RT_parity_tests.spin2` | 32 | Feature parity: exists, file_size, seek, open modes |

### Flash Regression Tests

| File | Tests | Description |
|------|-------|-------------|
| `DFS_FL_RT_mount_handle_basics_tests.spin2` | 50 | Flash mount and handle basics |
| `DFS_FL_RT_rw_tests.spin2` | 70 | Flash read/write operations |
| `DFS_FL_RT_rw_block_tests.spin2` | 13 | Flash block-level read/write |
| `DFS_FL_RT_rw_modify_tests.spin2` | 36 | Flash read/write/modify patterns |
| `DFS_FL_RT_append_tests.spin2` | 78 | Flash append operations |
| `DFS_FL_RT_seek_tests.spin2` | 33 | Flash seek operations |
| `DFS_FL_RT_circular_tests.spin2` | 37 | Flash circular file operations |
| `DFS_FL_RT_circular_compat_tests.spin2` | 27 | Flash circular file compatibility |
| `DFS_FL_RT_cwd_tests.spin2` | 20 | Flash CWD emulation (changeDirectory, isolation) |
| `DFS_FL_RT_8cog_tests.spin2` | 66 | 8-cog concurrent Flash stress test |

### Support Files

| File | Description |
|------|-------------|
| `isp_rt_utilities.spin2` | SD test framework (startTest, evaluateBool, etc.) |
| `DFS_FL_RT_utilities.spin2` | Flash test framework |

## Test Counts

| Category | Suites | Tests |
|----------|--------|-------|
| Dual/Cross-device | 2 | 58 |
| SD | 20 | 424 |
| Flash | 10 | 430 |
| **Total** | **32** | **912** |

## Building and Running

From this directory:

```bash
pnut-ts -d -I .. <test_file>.spin2
```

The `-I ..` flag finds `dual_sd_fat32_flash_fs.spin2` in the parent directory.

Use the runner scripts from `tools/`:

```bash
cd ../../tools/
./run_all_regression.sh              # Full suite
./run_all_regression.sh --include-8cog  # All + 8-cog stress tests
```

---

*Part of the [P2 Dual SD FAT32 + Flash Filesystem](../../README.md) project — Iron Sheep Productions*
