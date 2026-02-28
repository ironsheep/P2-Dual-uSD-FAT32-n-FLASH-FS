# Phase 5b: SD Driver Post-v1.0.0 Updates

## Context

The unified driver (`dual_sd_fat32_flash_fs.spin2`) was based on the SD reference driver at v1.0.0 (`54121d8`, Feb 25, 2026). Since then, 15 commits have landed in the reference driver adding bug fixes, enhancements, and V1 API removal. This phase ports ALL 18 items from `REF-FLASH-uSD/UPDATES/POST-V1.0.0-PORTING-GUIDE.md` into the unified driver and updates the migrated SD test suites accordingly.

**Code style guide** (`REF-FLASH-uSD/UPDATES/CODE-STYLE-GUIDE.md`): Applied to all new code written in this phase. Full codebase restyle deferred to a later sweeping pass.

---

## All 18 Items — Included

| # | Item | Type | Wave |
|---|---|---|---|
| 1 | readVBRRaw() wrong-cog SPI | Bug fix | 1 |
| 2 | Unsigned FAT32 end-of-chain | Bug fix | 1 |
| 3 | Volume label root dir scan | Enhancement | 2 |
| 4 | entry_buffer struct typing | Enhancement | 1 |
| 5 | Struct accessor doc comments | Documentation | 2 |
| 6 | CON section doc comment cleanup | Documentation | 2 |
| 7 | Windowed bitmap FSCK | Enhancement | 6 |
| 8 | Cross-compiler PRAGMA blocks | Compatibility | 3 |
| 9 | flexspin line-continuation | Compatibility | 3 |
| 10 | CRC test expectation fix | Test fix | 5 |
| 11 | readVBRRaw test coverage | Test addition | 5 |
| 12 | Windowed FSCK diagnostic test | Test addition | 6 |
| 13 | Version bump / .txt removal | Administrative | 2 |
| 14 | do_rename() E_FILE_EXISTS | Bug fix | 1 |
| 15 | CRC error injection hooks | Enhancement | 3 |
| 16 | V1 legacy API removal | Cleanup | 4 |
| 17 | CRC validation/recovery tests | Test addition | 5 |
| 18 | Error handling/directory stress | Test addition | 5 |

---

## Wave 1: Critical Bug Fixes

All changes to `src/dual_sd_fat32_flash_fs.spin2`. No test changes needed — all existing tests still pass after these fixes.

### 1A. Unsigned FAT32 end-of-chain comparisons (#2)

Change 8 locations from signed to unsigned comparison operators:

| Line | Current | Fix |
|------|---------|-----|
| 1810 | `current_cluster >= $0FFF_FFF8` | `current_cluster +>= $0FFF_FFF8` |
| 1991 | `next_cluster >= $0FFF_FFF8` | `next_cluster +>= $0FFF_FFF8` |
| 2033 | `next_cluster >= $0FFF_FFF8` | `next_cluster +>= $0FFF_FFF8` |
| 2213 | `cluster >= $0FFF_FFF8` | `cluster +>= $0FFF_FFF8` |
| 2370 | `next_cluster >= $0FFF_FFF8` | `next_cluster +>= $0FFF_FFF8` |
| 2748 | `cluster >= $0FFF_FFF8` | `cluster +>= $0FFF_FFF8` |
| 7509 | `contents >= $0FFF_FFF8` | `contents +>= $0FFF_FFF8` |
| 7539 | `contents < $0FFF_FFF8` | `contents +< $0FFF_FFF8` |

### 1B. do_rename() missing E_FILE_EXISTS (#14)

Line 2854-2855: Add `return E_FILE_EXISTS` after "New name already exists!" debug.

### 1C. readVBRRaw() wrong-cog SPI (#1) — 3-part fix

**Part A** — Move `CMD_READ_SECTOR_RAW = 20` (line 122) out of `#IFDEF SD_INCLUDE_RAW` to be unconditional. Keep `CMD_WRITE_SECTOR_RAW` inside.

**Part B** — Move `CMD_READ_SECTOR_RAW:` handler (lines 995-1001) out of `#IFDEF SD_INCLUDE_RAW` (line 986) to be unconditional. Keep all other handlers inside.

**Part C** — Rewrite `readVBRRaw()` (lines 5221-5237) to use `send_command()`:
```spin2
PUB readVBRRaw(p_buf) : result
'' Read Volume Boot Record (512 bytes) into buffer.
''
'' @param p_buf - Pointer to 512-byte buffer to receive VBR data
'' @returns result - TRUE on success, FALSE if not mounted
  if not (flags & F_MOUNTED)
    debug("  [readVBRRaw] FAILED: Card not mounted")
    return false
  result := send_command(CMD_READ_SECTOR_RAW, vbr_sec, p_buf, 0, 0) == SUCCESS
```

### 1D. entry_buffer struct typing (#4)

**Part A** — DAT declaration (line 573): Change from `BYTE 0[32]` to struct-typed:
```spin2
  entry_buffer  dir_entry_t
                BYTE    0[14]           ' name[8], ext[3], attr, ntRes, crtTenth
                WORD    0[7]            ' crtTime, crtDate, accDate, clusHI, wrtTime, wrtDate, clusLO
                LONG    0              ' fileSize
```

**Part B** — Fix 5 direct byte-index accesses:
- Line 7175: `entry_buffer[i]` → `BYTE[@entry_buffer][i]`
- Line 7176: `entry_buffer[i]` → `BYTE[@entry_buffer][i]`
- Line 7181: `entry_buffer[i++]` → `BYTE[@entry_buffer][i++]`
- Line 7185: `entry_buffer[11]` → `BYTE[@entry_buffer][11]`
- Line 8944: `entry_buffer[address + i]` → `BYTE[@entry_buffer][address + i]`

**Verify**: Compile + run all Phase 1-5 tests. Behavior unchanged.

---

## Wave 2: Enhancements + Documentation

### 2A. Volume label root directory scan (#3)
**File**: `src/dual_sd_fat32_flash_fs.spin2`, `do_mount()` after line 1498

Add locals: `i, p_entry, cluster, sector, sec_idx, next_cluster, found`

Change debug to: `"VBR volume label:"`. Insert root directory scan code per porting guide Section 3. Uses unsigned `+<` comparison per fix 1A. Scans cluster chain for `ATTR_VOLUME_ID` ($08) entry.

### 2B. Struct accessor doc comments (#5)
**File**: `src/dual_sd_fat32_flash_fs.spin2`

Add single-apostrophe `'` doc comments to all 22+ PRI struct accessor methods (partType, partLbaStart, vbrBytesPerSec, etc.) following the code style guide pattern for PRI methods.

### 2C. CON section doc comment cleanup (#6)
**File**: `src/dual_sd_fat32_flash_fs.spin2`

Change all `CON ''` and standalone `'' ═══` lines in CON sections to `CON '` and `' ═══`. ~26 locations. Also strip indentation from `#IFDEF SD_INCLUDE_ALL` block directives.

### 2D. Version/administrative (#13)
**File**: `src/dual_sd_fat32_flash_fs.spin2`
- Update header version string
- Ensure `.txt` not tracked (check .gitignore)

**Verify**: Compile + mount tests + volume tests on hardware.

---

## Wave 3: Cross-Compiler Support + CRC Hooks

### 3A. Cross-compiler PRAGMA blocks (#8)
**Files**: `src/dual_sd_fat32_flash_fs.spin2` + all migrated test files that use `#PRAGMA EXPORTDEF`

Wrap every `#PRAGMA EXPORTDEF` in compiler-detection blocks:
```spin2
#IFDEF __SPINTOOLS__
#DEFINE SYMBOL_NAME
#ELSEIFDEF __FLEXSPIN__
#define SYMBOL_NAME
#pragma exportdef SYMBOL_NAME
#ELSE
#PRAGMA EXPORTDEF SYMBOL_NAME
#ENDIF
```

**Affected files** (check each for `#PRAGMA EXPORTDEF`):
- `src/dual_sd_fat32_flash_fs.spin2` — SD_INCLUDE_ALL expansion
- All `DFS_SD_RT_*.spin2` test files that export pragma flags
- `DFS_FL_RT_utilities.spin2` — MAX_OPEN_FILES
- `DFS_FL_RT_8cog_tests.spin2` — MAX_OPEN_FILES

### 3B. flexspin line-continuation workaround (#9)
**File**: `REF-FLASH-uSD/uSD-FAT32/src/UTILS/isp_format_utility.spin2`

Wrap 3 multi-line `debug()` calls in `#IFDEF __FLEXSPIN__` blocks with single-line alternatives. Only needed if format utility is used in unified project tests.

### 3C. CRC error injection hooks (#15)
**File**: `src/dual_sd_fat32_flash_fs.spin2`

**DAT additions**: `test_force_read_crc_error BYTE 0`, `test_force_write_crc_error BYTE 0`, `test_error_count LONG 0`

**4 PUB methods** (inside `#IFDEF SD_INCLUDE_DEBUG`): `setTestForceReadError(count)`, `setTestForceWriteError(enabled)`, `getTestErrorCount()`, `clearTestErrors()`

**readSector() hook**: After `diag_calc_crc := calcDataCRC(...)`, if hook counter > 0 XOR with $FFFF

**writeSector() hook**: After `diag_sent_crc := calcDataCRC(...)`, if hook flag set XOR with $FFFF (one-shot)

**Verify**: Compile. Existing tests pass (hooks default to 0).

---

## Wave 4: V1 Legacy API Removal

### 4A-4D. Migrate 4 test files from V1 → V3 API

| File | V1 Calls |
|---|---|
| `DFS_SD_RT_seek_tests.spin2` | openFile, newFile, closeFile, read, write, seek, fileSize, readByte |
| `DFS_SD_RT_directory_tests.spin2` | openFile, newFile, closeFile, writeString, read |
| `DFS_SD_RT_mount_tests.spin2` | openFile, closeFile, readByte |
| `DFS_SD_RT_testcard_validation.spin2` | openFile, closeFile, read, readByte |

V1→V3 mapping:
| V1 | V3 |
|---|---|
| `dfs.newFile(dev, @name)` | `handle := dfs.createFileNew(dev, @name)` |
| `dfs.openFile(dev, @name)` | `handle := dfs.openFileRead(dev, @name)` |
| `dfs.closeFile()` | `dfs.closeFileHandle(handle)` |
| `dfs.read(@buf, count)` | `dfs.readHandle(handle, @buf, count)` |
| `dfs.write(@buf, count)` | `dfs.writeHandle(handle, @buf, count)` |
| `dfs.writeString(@str)` | `dfs.writeHandle(handle, @str, strsize(@str))` |
| `dfs.seek(pos)` | `dfs.seekHandle(handle, pos)` |
| `dfs.fileSize()` | `dfs.fileSizeHandle(handle)` |
| `dfs.readByte(addr)` | `dfs.seekHandle(h, addr)` + `dfs.readHandle(h, @buf, 1)` |

**Verify**: All 4 files compile + pass on hardware with same test counts.

### 4E. Remove V1 from dual_sd_fat32_flash_fs.spin2 (#16)

**Remove 9 PUB methods**: `newFile`, `openFile`, `closeFile`, `read`, `readByte`, `write`, `writeByte`, `writeString`, `seek`
**Keep**: `fileSize()` (used by `readDirectory()` context)

**Remove 6 CMD constants**: `CMD_OPEN=3`, `CMD_CLOSE=4`, `CMD_READ=5`, `CMD_WRITE=6`, `CMD_SEEK=7`, `CMD_NEWFILE=8`

**Remove 6 dispatch entries** from `fs_worker()`: lines 921-939

**Remove 3 PRI methods**: `do_read()`, `do_write()`, `do_seek()`

**Simplify 3 PRI methods** (kept for internal use by do_movefile, do_delete, do_chdir, do_unmount):
- `do_open()`: Remove `flags |= F_OPEN`
- `do_close()`: Remove `F_NEWDATA` check, `F_OPEN` clearing, `file_idx := 0`
- `do_newfile()`: `flags |= F_OPEN | F_NEWDIR` → `flags |= F_NEWDIR`
- `do_sync()`: Remove `F_NEWDATA` check block

**Remove V1 state**: `F_OPEN` (line 83), `F_NEWDATA` (line 85), `file_idx` (line 503)

**Update mode enforcement range** in fs_worker():
```spin2
' BEFORE: if (cur_cmd >= CMD_OPEN and cur_cmd <= CMD_MOVEFILE) or ...
' AFTER:  if (cur_cmd >= CMD_NEWDIR and cur_cmd <= CMD_MOVEFILE) or ...
```

**Remove** `file_idx := 0` from `searchDirectory()` and update `followFatChain()` comment.

**Verify**: Full regression — all Phase 1-5b tests pass.

---

## Wave 5: Test Coverage Expansion

### 5A. CRC test expectation fix (#10)
**File**: `src/regression-tests/DFS_SD_RT_crc_diag_tests.spin2`

Change `lastReceivedCRC != 0` → compare `lastReceivedCRC == lastCalculatedCRC`.

### 5B. readVBRRaw test coverage (#11)
**File**: `src/regression-tests/DFS_SD_RT_volume_tests.spin2`

- Add `vbrBuf2 BYTE 0[512]` + guard in DAT
- Remove "readVBRRaw is broken" comment
- Add 2 tests: readVBRRaw succeeds + matches readSectorRaw data
- Test count: 21 → 23

### 5C. Error handling + rename tests (#18 partial)
**File**: `src/regression-tests/DFS_SD_RT_error_handling_tests.spin2`

Add 3 tests: write-to-read-handle error, read-from-write-handle error, rename-to-existing returns E_FILE_EXISTS.

### 5D. Directory stress test (#18 partial)
**File**: `src/regression-tests/DFS_SD_RT_directory_tests.spin2`

Add "Many File Stress Test" group: create 20 files, enumerate, verify, clean up.

### 5E. CRC validation test suite (#17) — NEW FILE
**File**: `src/regression-tests/DFS_SD_RT_crc_validation_tests.spin2`

6 tests exercising CRC error injection hooks. Based on reference `SD_RT_crc_validation_tests.spin2`.

### 5F. CRC recovery test suite (#17) — NEW FILE
**File**: `src/regression-tests/DFS_SD_RT_recovery_tests.spin2`

7 tests exercising recovery after error conditions. Based on reference `SD_RT_recovery_tests.spin2`.

---

## Wave 6: FSCK Utility Updates

### 6A. Windowed bitmap FSCK (#7)
**File**: `REF-FLASH-uSD/uSD-FAT32/src/UTILS/isp_fsck_utility.spin2`

Major rewrite of FSCK to support cards >64GB via windowed bitmap processing:
- Remove `bitmapCapable` variable
- Add window tracking variables: `v_lostCount`, `windowStart`, `windowEnd`, `currentWindow`, `windowCount`
- Rewrite `fsckPass2()` with outer window loop
- Update `fsckScanDir()` and `fsckValidateChain()` for window-conditional behavior
- Rename `fsckPass3()` → `fsckPass3Window()` (scans only current window range)
- Update `setBit()` and `testBit()` for window-relative indexing

### 6B. Windowed FSCK diagnostic test (#12) — NEW FILE
**File**: `src/regression-tests/DFS_SD_RT_fsck_window_test.spin2` (or `diagnostic-tests/`)

Self-contained 394-line test: format card, run FSCK, inject defects in window-2 range, verify repair. Requires 128GB+ card.

**Verify**: FSCK audit passes on available test cards.

---

## Verification Plan

After each wave, compile + hardware verify:

| Wave | Verify |
|---|---|
| 1 | `./run_all_regression.sh` (full Phase 1-5 regression) |
| 2 | Mount tests + volume tests on hardware |
| 3 | Compile all files. Existing tests pass. |
| 4 | All 4 migrated test files on hardware. Then full regression after V1 removal. |
| 5 | Each new/modified test file on hardware |
| 6 | FSCK audit on test card |

Final: Full regression pass across all phases.

---

## Key Files

| File | Waves |
|---|---|
| `src/dual_sd_fat32_flash_fs.spin2` | 1, 2, 3C, 4E |
| `src/regression-tests/DFS_SD_RT_seek_tests.spin2` | 4A |
| `src/regression-tests/DFS_SD_RT_directory_tests.spin2` | 4B, 5D |
| `src/regression-tests/DFS_SD_RT_mount_tests.spin2` | 4C |
| `src/regression-tests/DFS_SD_RT_testcard_validation.spin2` | 4D |
| `src/regression-tests/DFS_SD_RT_crc_diag_tests.spin2` | 5A |
| `src/regression-tests/DFS_SD_RT_volume_tests.spin2` | 5B |
| `src/regression-tests/DFS_SD_RT_error_handling_tests.spin2` | 5C |
| `src/regression-tests/DFS_SD_RT_crc_validation_tests.spin2` | 5E (NEW) |
| `src/regression-tests/DFS_SD_RT_recovery_tests.spin2` | 5F (NEW) |
| `REF-FLASH-uSD/uSD-FAT32/src/UTILS/isp_fsck_utility.spin2` | 6A |
| `REF-FLASH-uSD/uSD-FAT32/src/UTILS/isp_format_utility.spin2` | 3B |
| All `DFS_*_RT_*.spin2` with `#PRAGMA EXPORTDEF` | 3A |
