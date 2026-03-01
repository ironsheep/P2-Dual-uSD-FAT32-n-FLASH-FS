# Regression Test Coverage Gap Analysis

## Context

After the Phase 1-7 implementation and Feature Parity work, the unified driver (`dual_sd_fat32_flash_fs.spin2`) has **104 PUB methods** and **1,255+ regression tests** across 31 test suites. This analysis cross-references every public method against every test file to find what's NOT covered.

**Method**: Extracted all 104 PUB method signatures, then searched every test file for calls to each method. Classified each as: tested (return value asserted), setup-only (called but not asserted), or untested (never called).

---

## Summary

| Category | Count | Critical | Important | Nice-to-have |
|----------|:-----:|:--------:|:---------:|:------------:|
| A: Untested methods | 16 | 1 | 3 | 12 |
| B: Setup-only methods | 4 | 0 | 0 | 4 |
| C1: Device cross-applicability | 11 | 3 | 5 | 3 |
| C2: Missing error paths | 6 | 0 | 4 | 2 |
| C3: Missing boundary conditions | 3 | 0 | 1 | 2 |
| C4: Multi-cog gaps | 2 | 0 | 2 | 0 |
| C5: Flash CWD emulation | 3 | 0 | 2 | 1 |
| **TOTAL** | **45** | **4** | **17** | **24** |

---

## Critical Gaps (4 items -- could hide real bugs)

### CRIT-1: `seek()` unified method -- ZERO coverage
- **Line 6362**: `PUB seek(handle, position, whence) : end_position`
- Brand new Feature Parity method. Supports `SK_FILE_START`, `SK_CURRENT_POSN`, `SK_FILE_END` whence values.
- SD path computes absolute position from `tellHandle()` + offset. Flash path dispatches `CMD_FLASH_SEEK`.
- **Risk**: A bug in the whence arithmetic would silently corrupt file positions. No test uses this method at all -- tests use legacy `seekHandle()` exclusively.
- **Fix**: Add tests for all 3 whence modes on both SD and Flash, including seek-from-end and seek-from-current.

### CRIT-2: `exists(DEV_SD)` -- never tested on SD
- **Line 7032**: `PUB exists(dev, p_filename) : found`
- Tested on Flash 8 times. SD implementation uses `CMD_SD_EXISTS` worker command with `searchDirectory()` + `entry_buffer` bytes 28-31. **Zero** SD-side test coverage.
- **Risk**: SD `exists()` could return wrong answers (false positives/negatives) and no test would catch it.
- **Fix**: Add exists tests for SD: file exists, file doesn't exist, after delete, in subdirectory.

### CRIT-3: `file_size(DEV_SD)` -- never tested on SD
- **Line 7058**: `PUB file_size(dev, p_filename) : size`
- Tested on Flash 19 times. SD implementation uses `CMD_SD_FILE_SIZE` worker command. **Zero** SD-side coverage.
- **Risk**: Could return 0 or garbage for SD files and nothing would catch it.
- **Fix**: Add file_size tests for SD: known-size file, empty file, after write, after append.

### CRIT-4: `file_size_unused(DEV_SD)` -- never tested on SD
- **Line 6920**: `PUB file_size_unused(dev, p_filename) : size_unused`
- Tested on Flash 4 times. SD implementation walks FAT chain via `readFAT()`, counting clusters until `$0FFF_FFF8+`. Most complex untested SD-side code path among the parity methods.
- **Risk**: FAT chain walk could miscalculate, reporting wrong unused space.
- **Fix**: Add file_size_unused tests for SD: small file (lots of slack), file filling exact cluster, large multi-cluster file.

---

## Important Gaps (17 items)

### Device Cross-Applicability (5 important)

**IMP-1: `serial_number(DEV_SD)` -- never tested on SD**
- Line 6739. SD serial number extracted from CID bytes 9-12. Tested on Flash 5 times, SD zero.
- Should return sn_hi=0, sn_lo=32-bit CID serial.

**IMP-2: `stats(DEV_SD)` -- never tested on SD**
- Line 6963. SD stats uses openDirectory/readDirectoryHandle loop for file_count, needs `SD_INCLUDE_RAW` for used sectors. Tested on Flash 3 times, SD zero.

**IMP-3: `changeDirectory(DEV_FLASH)` -- Flash CWD emulation untested**
- Line 6111. Tested on SD 82 times. Flash CWD emulation via `fl_cog_cwd` prefix manipulation has zero coverage. Bug in `fl_prepend_cwd()` or `fl_cwd_matches()` would go undetected.

**IMP-4: `open(DEV_SD)` -- unified open never tested on SD**
- Line 7091. Tested on Flash 58 times. SD dispatch logic (mode -> openFileRead/createFileNew/openFileWrite, truncate-on-WRITE semantics from Phase B) has zero coverage.

**IMP-5: `close()` and `flush()` on SD handles -- never tested on SD**
- Lines 7172, 7184. Flash-API compatibility wrappers. Tested on Flash only. SD dispatch untested.

### Missing Error Path Tests (4 important)

**IMP-6: `copyFile()` when destination already exists**
- Line 7200. Tests cover source-not-found and bad device. Missing: overwrite behavior when destination already exists. Undocumented and untested.

**IMP-7: `deleteFile()` on a file with an open handle**
- Line 6567. Tests delete closed files only. What happens to the open handle? Could leave dangling handle or corrupt FAT.

**IMP-8: `rename()` on a file with an open handle**
- Line 6592. Never tested. Could corrupt internal handle state or orphan the handle.

**IMP-9: `seekHandle()` on a write-mode handle**
- Line 6341. All seek tests use read handles. Seeking on a write handle (random-access write) is supported but untested.

### Multi-Cog Gaps (2 important)

**IMP-10: Multi-cog cross-device I/O**
- One cog doing SD I/O while another does Flash I/O simultaneously. The worker cog handles both devices serially; concurrent requests from multiple cogs to different devices need verification.

**IMP-11: Per-cog Flash CWD isolation**
- Flash CWD emulation uses per-cog `fl_cog_cwd` DAT arrays. No test verifies two cogs can have different Flash CWDs simultaneously.

### Flash CWD Emulation (2 important)

**IMP-12: `changeDirectory(DEV_FLASH, "..")` -- parent navigation**
- Never tested. Flash CWD stripping logic could fail at boundaries: `..` from root, multiple `..` calls.

**IMP-13: `changeDirectory(DEV_FLASH, "/")` -- reset to root**
- Never tested. Should clear the CWD prefix entirely.

### Untested Methods (3 important)

**IMP-14: `getWriteDiag()` -- Line 842**
- Returns detailed write diagnostic info (result_code, R1, data_resp, sector_num). Never called in any test. Behind `SD_INCLUDE_DEBUG`.

**IMP-15: `testCMD13()` -- Line 5105**
- Sends CMD13 and returns raw R2 response. CRC diag tests call `getLastCMD13()` but never `testCMD13()` directly. Behind `SD_INCLUDE_RAW`.

**IMP-16: `readCIDRaw()` -- Line 5272**
- Reads CID register (16 bytes). `readCSDRaw()` IS tested but CID is not. CID contains manufacturer ID, serial number, product name. Behind `SD_INCLUDE_REGISTERS`.

### Missing Boundary Conditions (1 important)

**IMP-17: Maximum handles across BOTH devices simultaneously**
- Tests exhaust 6 handles on SD or Flash independently. Never tested: opening 3 SD + 3 Flash handles simultaneously to verify the shared handle pool works across devices.

---

## Nice-to-Have Gaps (24 items)

### Untested Methods (12 -- mostly debug/display or legacy)
- `null()` (line 656) -- no-op anchor, untestable
- `readSCRRaw()` (line 5306) -- SCR register, rarely used
- `readSDStatusRaw()` (line 5323) -- SD Status register, diagnostic
- `getOCR()` (line 5339) -- cached OCR, diagnostic
- `getManufacturerID()` (line 5845) -- read-only accessor
- `fileSize()` (line 7623) -- V1 legacy, `fileSizeHandle()` is tested
- `displaySector()` (line 9128) -- debug display, no return value
- `displayEntry()` (line 9148) -- debug display, no return value
- `displayFAT()` (line 9168) -- debug display, no return value
- `debugDumpRootDir()` (line 7479) -- debug dump
- `debugGetDirSec()` (line 7522) -- debug accessor
- `flashSeek()` (line 6395) -- deprecated, `seek()` replaces it

### Setup-Only Methods (4)
- `setDate()` -- called but verified via side-effects (directory timestamps); effectively tested
- `syncDirCache()` -- no return value; implicitly tested via subsequent operations
- `clearTestErrors()` -- reset function; implicitly verified by error count checks
- `setSPISpeed()` -- verified via `getSPIFrequency()` side-effect

### Device Cross-Applicability (3)
- `directory(DEV_SD)` -- SD uses `readDirectory()`/`readDirectoryHandle()` instead
- `open_circular(DEV_SD)` -- circular files on SD are post-1.0 (should return E_NOT_SUPPORTED)
- `create_file(DEV_SD)` -- Flash-origin method, may not be implemented for SD

### Error Paths (2)
- `mount()` with invalid device code (e.g., 99) -- E_BAD_DEVICE path
- `writeHandle()` with count=0 -- edge case

### Boundary Conditions (2)
- Write at exact cluster boundary (FAT chain extension in single call)
- Flash file I/O on freshly-formatted Flash (format -> mount -> write/read)

### Flash CWD (1)
- `openDirectory(DEV_FLASH)` returns E_NOT_SUPPORTED -- documented but never asserted

---

## Implementation Plan

### Phase 1: Critical -- New Test File for Feature Parity Methods

**File: `DFS_SD_RT_parity_tests.spin2`** (~35 tests)

Tests the Feature Parity methods that were added for SD but have zero SD-side coverage:

| Group | Tests | What |
|-------|:-----:|------|
| exists(DEV_SD) | 5 | file exists, doesn't exist, after delete, in subdir, empty name |
| file_size(DEV_SD) | 5 | known-size file, empty file (0 bytes), after write, after append, non-existent file |
| file_size_unused(DEV_SD) | 5 | small file (slack bytes), file filling exact cluster, multi-cluster file, empty file, non-existent |
| serial_number(DEV_SD) | 3 | returns non-zero sn_lo, sn_hi == 0, matches across calls |
| stats(DEV_SD) | 4 | file_count matches directory, free_ct > 0, after create/delete, used > 0 |
| seek() unified | 8 | SK_FILE_START on SD, SK_CURRENT_POSN on SD, SK_FILE_END on SD, same 3 on Flash, seek-past-end, seek-negative-from-end |
| open(DEV_SD) modes | 5 | FILEMODE_READ, FILEMODE_WRITE (truncates), FILEMODE_APPEND, open non-existent for read (error), write creates new |

**Pragmas needed**: `SD_INCLUDE_RAW` (for stats used-sectors)

### Phase 2: Important -- Flash CWD + Error Paths

**File: `DFS_FL_RT_cwd_tests.spin2`** (~20 tests)

| Group | Tests | What |
|-------|:-----:|------|
| changeDirectory basics | 4 | cd to subdir, open file, cd back to root, verify CWD prefix |
| changeDirectory("..") | 4 | parent navigation, from root (should no-op), multiple levels, after nested cd |
| changeDirectory("/") | 2 | reset to root, verify files visible again |
| CWD file isolation | 4 | file in /A not visible from /B, create in CWD only affects that prefix |
| openDirectory(DEV_FLASH) | 2 | returns E_NOT_SUPPORTED, no side effects |
| CWD + open/delete/rename | 4 | operations respect current CWD prefix |

**Add to existing `DFS_SD_RT_error_handling_tests.spin2`** (~6 tests):

| Tests | What |
|:-----:|------|
| 1 | deleteFile on file with open handle |
| 1 | rename on file with open handle |
| 1 | seekHandle on write-mode handle |
| 1 | copyFile when destination exists |
| 1 | mount with invalid device code |
| 1 | writeHandle with count=0 |

### Phase 3: Important -- Cross-Device Handle Pool + Multi-Cog

**Add to existing `DFS_RT_dual_device_tests.spin2`** (~6 tests):

| Tests | What |
|:-----:|------|
| 3 | Open 3 SD + 3 Flash handles simultaneously, verify all work |
| 1 | 7th handle (either device) returns E_TOO_MANY_FILES |
| 2 | close one, reopen on other device, verify pool reclaim |

**Add to existing `DFS_RT_cross_device_tests.spin2`** (~4 tests):

| Tests | What |
|:-----:|------|
| 2 | copyFile when destination already exists (overwrite vs error) |
| 2 | seekHandle on write-mode handle, write at seek position, verify |

### Phase 4: Nice-to-Have -- Register Tests

**Add to existing `DFS_SD_RT_register_tests.spin2`** (~8 tests):

| Tests | What |
|:-----:|------|
| 3 | readCIDRaw: returns data, manufacturer ID > 0, serial number matches getManufacturerID() |
| 2 | readSCRRaw: returns data, SD_SPEC version reasonable |
| 1 | getOCR: non-zero, bit 30 or 31 set (capacity indicator) |
| 1 | readSDStatusRaw: returns data |
| 1 | testCMD13: returns R2 response, no error on healthy card |

---

## Estimated Total New Tests

| Phase | New Tests | Priority |
|-------|:---------:|----------|
| Phase 1: Parity methods | ~35 | Critical |
| Phase 2: Flash CWD + error paths | ~26 | Important |
| Phase 3: Handle pool + multi-cog | ~10 | Important |
| Phase 4: Register tests | ~8 | Nice-to-have |
| **Total** | **~79** | |

Post-implementation total: ~1,334 tests across 32 test suites.

---

## Part 2: Boolean-to-Status Return Value Audit

### Problem

13 PUB action methods return TRUE/FALSE (boolean) when they should return proper status codes (SUCCESS=0 or negative error codes). This discards useful error information -- callers can't tell **why** something failed, only that it did.

Worse, several methods have a **split personality bug**: the Flash unmounted guard returns a proper error code (`return set_error(E_NOT_MOUNTED)`), but the SD success/failure path converts to boolean. This means the same method returns different types depending on device and error path.

### Convention

- **Action methods** (create, delete, rename, move, format, sync) should return `SUCCESS` or negative error code
- **Query methods** (mounted?, exists?, isHighSpeedActive?) should return TRUE/FALSE
- **Value methods** (openFile, readHandle, tellHandle) should return the value or negative error code

### Methods to Change (13 action methods)

#### File Management (4 methods)

| # | Line | Method | Current Return | Should Return |
|---|------|--------|---------------|---------------|
| S1 | 6567 | `deleteFile(dev, name_ptr) : deleted` | TRUE/FALSE | SUCCESS or E_FILE_NOT_FOUND, E_NOT_MOUNTED, E_BAD_DEVICE |
| S2 | 6592 | `rename(dev, old_name, new_name) : renamed` | TRUE/FALSE | SUCCESS or E_FILE_NOT_FOUND, E_FILE_EXISTS, E_NOT_MOUNTED |
| S3 | 6619 | `moveFile(dev, name_ptr, dest_folder) : ok` | TRUE/FALSE | SUCCESS or E_FILE_NOT_FOUND, E_NOT_A_DIR, E_NOT_SUPPORTED |
| S4 | 7464 | `setVolumeLabel(dev, p_label) : result` | TRUE/FALSE | SUCCESS or error code |

#### Directory Operations (2 methods)

| # | Line | Method | Current Return | Should Return |
|---|------|--------|---------------|---------------|
| S5 | 6083 | `newDirectory(dev, name_ptr) : ok` | TRUE/FALSE | SUCCESS or E_FILE_EXISTS, E_NOT_MOUNTED, E_BAD_DEVICE |
| S6 | 6111 | `changeDirectory(dev, name_ptr) : ok` | TRUE/FALSE | SUCCESS or E_FILE_NOT_FOUND, E_NOT_A_DIR, E_NOT_MOUNTED |

#### Sync (1 method)

| # | Line | Method | Current Return | Should Return |
|---|------|--------|---------------|---------------|
| S7 | 6172 | `sync() : result` | TRUE/FALSE | SUCCESS or error code (modern equivalents `syncHandle`/`syncAllHandles` already return status) |

#### Card Init (1 method)

| # | Line | Method | Current Return | Should Return |
|---|------|--------|---------------|---------------|
| S8 | 5059 | `initCardOnly() : result` | TRUE/FALSE | SUCCESS or E_INIT_FAILED (behind SD_INCLUDE_RAW) |

#### Register Access (5 methods)

| # | Line | Method | Current Return | Should Return |
|---|------|--------|---------------|---------------|
| S9 | 5272 | `readCIDRaw(p_buf) : result` | TRUE/FALSE | SUCCESS or error code (SD_INCLUDE_REGISTERS) |
| S10 | 5289 | `readCSDRaw(p_buf) : result` | TRUE/FALSE | SUCCESS or error code (SD_INCLUDE_REGISTERS) |
| S11 | 5306 | `readSCRRaw(p_buf) : result` | TRUE/FALSE | SUCCESS or error code (SD_INCLUDE_REGISTERS) |
| S12 | 5323 | `readSDStatusRaw(p_buf) : result` | TRUE/FALSE | SUCCESS or error code (SD_INCLUDE_REGISTERS) |
| S13 | 5348 | `readVBRRaw(p_buf) : result` | TRUE/FALSE | SUCCESS or error code (SD_INCLUDE_REGISTERS) |

#### Raw Sector Access (2 methods -- borderline)

| # | Line | Method | Current Return | Should Return |
|---|------|--------|---------------|---------------|
| S14 | 5184 | `writeSectorRaw(sector, p_buffer) : result` | TRUE/FALSE | SUCCESS or error code (SD_INCLUDE_RAW) |
| S15 | 5206 | `readSectorRaw(sector, p_buffer) : result` | TRUE/FALSE | SUCCESS or error code (SD_INCLUDE_RAW) |

### The Split Personality Bug

These methods have inconsistent return types depending on code path:

```
deleteFile(DEV_FLASH, @name):
  if NOT mounted → return set_error(E_NOT_MOUNTED)    ← returns negative error code!
  if mounted → send_command → if SUCCESS return TRUE   ← returns boolean!
```

Flash mount-guard tests (`DFS_FL_RT_mount_handle_basics_tests.spin2`) pass because `set_error()` bypasses the boolean conversion. But a test expecting `SUCCESS` (0) on success would get `TRUE` (-1 in Spin2) instead. This is a latent bug in `DFS_FL_RT_circular_compat_tests.spin2` line 289.

### Return Variable Renames

Per project coding rules (NEVER name a return variable `result`), all changed methods get descriptive return names:

| Method | Old Return Var | New Return Var |
|--------|---------------|----------------|
| `deleteFile` | `deleted` | `status` |
| `rename` | `renamed` | `status` |
| `moveFile` | `ok` | `status` |
| `setVolumeLabel` | `result` | `status` |
| `newDirectory` | `ok` | `status` |
| `changeDirectory` | `ok` | `status` |
| `sync` | `result` | `status` |
| `initCardOnly` | `result` | `status` |
| `readCIDRaw` | `result` | `status` |
| `readCSDRaw` | `result` | `status` |
| `readSCRRaw` | `result` | `status` |
| `readSDStatusRaw` | `result` | `status` |
| `readVBRRaw` | `result` | `status` |
| `writeSectorRaw` | `result` | `status` |
| `readSectorRaw` | `result` | `status` |

### Driver Changes (Pattern)

Each method follows the same fix pattern. Example for `deleteFile`:

**Before:**
```spin2
PUB deleteFile(dev, name_ptr) : deleted | status, fl_path[32]
    ...
    status := send_command(CMD_DELETE_FILE, ...)
    if status == SUCCESS
        return true
    return false
```

**After:**
```spin2
PUB deleteFile(dev, name_ptr) : status | fl_path[32]
    ...
    status := send_command(CMD_DELETE_FILE, ...)
    ' status already contains SUCCESS or negative error code — return as-is
```

The fix is a simplification — remove the boolean conversion and return the worker's status directly.

### Files Requiring Test Updates

When these methods switch from boolean to status, every test that asserts on their return value needs updating:

**Pattern**: `evaluateBool(result, @"...", true)` → `evaluateSingleValue(status, @"...", dfs.SUCCESS)`
**Pattern**: `evaluateBool(result, @"...", false)` → `evaluateBool(status < 0, @"...", true)` or `evaluateResultNegError(status, dfs.E_FILE_NOT_FOUND)` (if specific error expected)

#### Test files affected (~70 assertion changes):

| File | ~Changes | Methods Affected |
|------|:--------:|-----------------|
| `DFS_SD_RT_directory_tests.spin2` | 25 | newDirectory, changeDirectory, moveFile |
| `DFS_SD_RT_file_ops_tests.spin2` | 6 | deleteFile, rename, newDirectory |
| `DFS_SD_RT_subdir_ops_tests.spin2` | 8 | newDirectory, changeDirectory, deleteFile, rename |
| `DFS_SD_RT_error_handling_tests.spin2` | 6 | changeDirectory, newDirectory, rename |
| `DFS_SD_RT_volume_tests.spin2` | 8 | setVolumeLabel, sync, readSectorRaw, readVBRRaw |
| `DFS_SD_RT_mount_tests.spin2` | 2 | changeDirectory, readSectorRaw |
| `DFS_SD_RT_register_tests.spin2` | 4 | readCSDRaw, initCardOnly |
| `DFS_SD_RT_raw_sector_tests.spin2` | 4 | initCardOnly, readSectorRaw, writeSectorRaw |
| `DFS_SD_RT_format_tests.spin2` | 2 | initCardOnly, readSectorRaw |
| `DFS_SD_RT_testcard_validation.spin2` | 2 | changeDirectory |
| `DFS_SD_RT_multiblock_tests.spin2` | 3 | readSectorRaw, writeSectorRaw |
| `DFS_FL_RT_circular_compat_tests.spin2` | 1 | deleteFile (latent bug fix) |

#### Shell and utility files affected (~20 call-site changes):

| File | ~Changes | Pattern |
|------|:--------:|---------|
| `DFS_demo_shell.spin2` | 15 | `if (status)` → `if (status == dfs.SUCCESS)` |
| `DFS_SD_format_card.spin2` | 2 | initCardOnly, readSectorRaw, writeSectorRaw |
| `DFS_SD_card_characterize.spin2` | 3 | readCIDRaw, readCSDRaw, readSCRRaw |
| `DFS_SD_FAT32_audit.spin2` | 2 | readSectorRaw |
| `DFS_SD_FAT32_fsck.spin2` | 2 | readSectorRaw |
| `DFS_example_basic.spin2` | 1 | deleteFile |
| `DFS_example_cross_copy.spin2` | 1 | deleteFile |
| `DFS_example_data_logger.spin2` | 1 | deleteFile |

### Methods Correctly Returning Boolean (no changes needed)

These are genuine yes/no queries — boolean is the right return type:

| Method | Why Boolean is Correct |
|--------|----------------------|
| `mounted(dev)` | "Is device mounted?" |
| `canMount(dev)` | "Can device be mounted?" |
| `exists(dev, p_filename)` | "Does file exist?" |
| `isHighSpeedActive()` | "Is high-speed mode on?" |
| `checkCMD6Support()` | "Does card support CMD6?" |
| `checkHighSpeedCapability()` | "Can card do high-speed?" |
| `attemptHighSpeed()` | "Did high-speed switch work?" |
| `eofHandle(handle)` | "At end of file?" |
| `checkStackGuard()` | "Is stack guard intact?" |

---

## Updated Implementation Plan

### Phase 0: Boolean-to-Status Migration (MUST DO FIRST)

This phase changes the API contract for 15 methods and must be done before adding new tests, since new tests should use the correct status-based assertions from the start.

**Step 0a: Driver changes** (~15 methods in `dual_sd_fat32_flash_fs.spin2`)
- Remove boolean conversion, return worker status directly
- Rename return variables to `status`
- Each method is a 3-5 line change

**Step 0b: Regression test updates** (~70 assertion changes across 12 test files)
- `evaluateBool(result, ..., true)` → `evaluateSingleValue(status, ..., dfs.SUCCESS)`
- `evaluateBool(result, ..., false)` → `evaluateBool(status < 0, ..., true)` or specific error check
- Fix latent bug in `DFS_FL_RT_circular_compat_tests.spin2`

**Step 0c: Shell and utility updates** (~20 call-site changes across 8 files)
- `if (status)` → `if (status == dfs.SUCCESS)`
- `if not dfs.changeDirectory(...)` → `if dfs.changeDirectory(...) <> dfs.SUCCESS`

**Step 0d: Compile and verify**
- Compile all modified files
- Run full regression suite
- Verify zero test failures

### Phase 1: Critical -- Feature Parity Tests (unchanged from above, ~35 tests)

### Phase 2: Important -- Flash CWD + Error Paths (unchanged from above, ~26 tests)

### Phase 3: Important -- Handle Pool + Multi-Cog (unchanged from above, ~10 tests)

### Phase 4: Nice-to-Have -- Register Tests (unchanged from above, ~8 tests)

---

## Updated Totals

| Phase | Work | Priority |
|-------|------|----------|
| Phase 0: Boolean-to-status migration | 15 driver methods + ~90 call-site updates | Critical (API fix) |
| Phase 1: Parity method tests | ~35 new tests | Critical |
| Phase 2: Flash CWD + error paths | ~26 new tests | Important |
| Phase 3: Handle pool + multi-cog | ~10 new tests | Important |
| Phase 4: Register tests | ~8 new tests | Nice-to-have |

---

## Verification

After each phase:
1. Compile new/modified test files: `pnut-ts -d -I .. <file>.spin2`
2. Run on hardware via `tools/run_test.sh`
3. Run full regression to confirm no regressions: `tools/run_all_regression.sh`
