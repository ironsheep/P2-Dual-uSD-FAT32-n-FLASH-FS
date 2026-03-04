# Decision 001: Worker Cog Stack Sizing

**Date:** 2026-03-03
**Status:** Implemented
**Driver:** `src/dual_sd_fat32_flash_fs.spin2`

## Context

The unified dual-FS driver runs a dedicated worker cog with a fixed-size stack buffer declared in DAT. The P2 has no hardware stack protection -- if the stack overflows, it silently corrupts adjacent hub RAM. After completing all driver features (Phases 1-7, Feature Parity, Bool-to-Status migration, return elimination, card presence detection), the stack size needed to be audited and right-sized.

The stack was previously set to `STACK_SIZE = 256` longs (1024 bytes) as a conservative estimate during development.

## Method

Used the `isp_stack_check.spin2` sentinel-fill technique documented in `DOCs/procedures/WORKER-COG-STACK-CHECK-GUIDE.md`:

1. Enabled `SD_INCLUDE_STACK_CHECK` in all 28 standard regression test suites (32 total minus format, testcard, 8cog, and one duplicate)
2. `prepStackForCheck()` fills the stack with sentinel `$a5a50df0` before `cogspin()`
3. `checkStack()` runs every worker loop iteration to catch overflow
4. `getStackDepth()` counts overwritten sentinels (high-water mark) via `CMD_STACK_DEPTH`
5. Each test reports depth before `dfs.stop()`

Ran full regression on P2 Edge Module hardware with physical SD card and onboard 16MB Flash chip.

## Results

### Complete Audit Data (2026-03-03)

| Suite | Stack (longs) | Category |
|-------|--------------|----------|
| DFS_FL_RT_circular_compat_tests | **127** | Flash |
| DFS_FL_RT_circular_tests | **127** | Flash |
| DFS_FL_RT_append_tests | 119 | Flash |
| DFS_FL_RT_cwd_tests | 118 | Flash |
| DFS_FL_RT_rw_block_tests | 118 | Flash |
| DFS_FL_RT_rw_modify_tests | 118 | Flash |
| DFS_FL_RT_rw_tests | 118 | Flash |
| DFS_FL_RT_seek_tests | 118 | Flash |
| DFS_RT_cross_device_tests | 118 | Cross-device |
| DFS_RT_dual_device_tests | 118 | Dual-device |
| DFS_SD_RT_parity_tests | 118 | SD |
| DFS_SD_RT_directory_tests | 112 | SD |
| DFS_SD_RT_error_handling_tests | 109 | SD |
| DFS_SD_RT_file_ops_tests | 109 | SD |
| DFS_SD_RT_subdir_ops_tests | 109 | SD |
| DFS_SD_RT_multihandle_tests | 101 | SD |
| DFS_SD_RT_read_write_tests | 101 | SD |
| DFS_SD_RT_crc_diag_tests | 100 | SD |
| DFS_SD_RT_dirhandle_tests | 100 | SD |
| DFS_SD_RT_multicog_tests | 100 | SD |
| DFS_SD_RT_seek_tests | 100 | SD |
| DFS_SD_RT_speed_tests | 100 | SD |
| DFS_SD_RT_volume_tests | 100 | SD |
| DFS_SD_RT_mount_tests | 96 | SD |
| DFS_SD_RT_multiblock_tests | 96 | SD |
| DFS_SD_RT_register_tests | 96 | SD |
| DFS_FL_RT_mount_handle_basics_tests | 82 | Flash |
| DFS_SD_RT_raw_sector_tests | 80 | SD |

### Summary Statistics

- **Peak observed:** 127 longs (Flash circular file operations)
- **SD-only peak:** 118 longs (parity tests)
- **Flash-only peak:** 127 longs (circular tests)
- **Minimum:** 80 longs (raw sector read/write)
- **SD median:** 100 longs
- **Flash median:** 118 longs

### Observations

1. **Flash circular file operations are the deepest call path** (127 longs). These involve append-with-wrap logic, block allocation, and CRC computation.
2. **SD operations are generally lighter** (80-118 longs). The parity test reaches 118 because it exercises both read and write paths with CRC verification.
3. **Cross-device and dual-device tests** match the Flash peak (118) because they exercise both devices.
4. **Raw sector access** is the shallowest path (80 longs) -- no filesystem overhead.

## Decision

**Set `STACK_SIZE = 160` longs (640 bytes).**

Formula from the guide: peak (127) * 1.25 = 158.75, rounded up to 160.

This provides:
- 33 longs (26%) headroom above the observed peak
- Saves 384 bytes (96 longs) of hub RAM vs. the previous 256
- The `checkStack()` guard in the worker loop catches any overflow during future development

## Alternatives Considered

| Option | Size | Headroom | Rationale |
|--------|------|----------|-----------|
| Keep 256 | 1024 bytes | 129 longs (102%) | Wastes 384 bytes, no data-driven justification |
| **160 (chosen)** | **640 bytes** | **33 longs (26%)** | **Guide-recommended 25% headroom, data-driven** |
| 144 | 576 bytes | 17 longs (13%) | Too tight -- leaves no room for future features |
| 128 | 512 bytes | 1 long (< 1%) | Unsafe -- essentially zero headroom |

## Verification

Full regression (28 suites, 912+ tests) passed with `STACK_SIZE = 160`:
- 4/4 suite groups: SD (17/17), Flash (9/9 + cwd), Cross-device, Dual-device
- 0 failures
- `checkStack()` guard never triggered (no overflow)

## Files Modified

| File | Change |
|------|--------|
| `src/dual_sd_fat32_flash_fs.spin2` | `STACK_SIZE = 256` changed to `STACK_SIZE = 160` |
| 28 regression test suites | Stack check instrumentation added/fixed |

## References

- `DOCs/procedures/WORKER-COG-STACK-CHECK-GUIDE.md` -- Implementation procedure
- `src/DEMO/isp_stack_check.spin2` -- Sentinel fill and measurement utility
