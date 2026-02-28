# Phases 4-7 Implementation Plans

## Status

- **Phases 1-3**: COMPLETE + HARDWARE VERIFIED (95/95 tests pass, 2026-02-27)
- **Phases 4-7**: Planned below, ready for sequential implementation

## Naming Convention

| Scope | Test File Prefix | Example |
|-------|-----------------|---------|
| SD-only tests | `DFS_SD_RT_` | `DFS_SD_RT_mount_tests.spin2` |
| Flash-only tests | `DFS_FL_RT_` | `DFS_FL_RT_rw_tests.spin2` |
| Both/cross-device tests | `DFS_RT_` | `DFS_RT_phase6_cross_device.spin2` |
| Utilities/demos | `DFS_` | `DFS_demo_shell.spin2` |

OBJ instance name: `dfs : "dual_sd_fat32_flash_fs"` (all `dfs.` prefixes throughout).

### Existing Phase 1-3 Test Renames (housekeeping)

| Current Name | New Name | Scope |
|-------------|----------|-------|
| `DUAL_RT_phase1_verify.spin2` | `DFS_SD_RT_phase1_verify.spin2` | SD-only |
| `DUAL_RT_phase2_verify.spin2` | `DFS_RT_phase2_verify.spin2` | Both devices |
| `DUAL_RT_phase3_verify.spin2` | `DFS_RT_phase3_verify.spin2` | Both devices |

Also update OBJ inside each: `fs : "dual_sd_fat32_flash_fs"` → `dfs : "dual_sd_fat32_flash_fs"`, and all `fs.` → `dfs.`

---

# Phase 4: Migrate SD Regression Tests

## Context

19 SD regression test suites (345+ tests) in `REF-FLASH-uSD/uSD-FAT32/regression-tests/` currently test against `micro_sd_fat32_fs.spin2` directly. Phase 4 copies each suite, renames it, and adapts it to test against `dual_sd_fat32_flash_fs.spin2`. No driver changes are needed — the unified driver already has full SD support.

## Key Files

- `src/dual_sd_fat32_flash_fs.spin2` — Target driver (unchanged in this phase)
- `REF-FLASH-uSD/uSD-FAT32/regression-tests/SD_RT_*.spin2` — Source tests
- `regression-tests/DFS_SD_RT_*.spin2` — Destination (new directory at project root)

## File Placement

Create `regression-tests/` at the project root. Rename prefix `SD_RT_` to `DFS_SD_RT_`. These are SD-only regression tests exercised through the unified driver.

## API Transformation Rules

### OBJ change (all files)
```spin2
' OLD:  sd    : "micro_sd_fat32_fs"
' NEW:  dfs   : "dual_sd_fat32_flash_fs"
```
All `sd.` prefixes become `dfs.` throughout.

### Init/Mount split (all files)
```spin2
' OLD:  result := sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
' NEW:  workerCog := dfs.init(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
'       result := dfs.mount(dfs.DEV_SD)
```
Call `init()` once at top of `go()`. Then `mount(DEV_SD)` / `unmount(DEV_SD)` for cycles.

### Methods that gain `dfs.DEV_SD` first parameter
- `openFileRead`, `openFileWrite`, `createFileNew`, `deleteFile`, `rename`
- `freeSpace`, `unmount`, `openDirectory`, `newDirectory`, `changeDirectory`
- `volumeLabel`, `setVolumeLabel`, `openFile`, `moveFile`

### Methods unchanged (handle-based, no `dev` param)
- `readHandle`, `writeHandle`, `seekHandle`, `closeFileHandle`, `tellHandle`
- `eofHandle`, `fileSizeHandle`, `syncHandle`, `readDirectoryHandle`, `closeDirectoryHandle`
- `read`, `write`, `readByte`, `writeByte`, `writeString`, `seek`, `closeFile`, `sync`
- All SD diagnostic methods (CRC, registers, speed, raw sector)

### Special cases
- `sd.initCardOnly(pins)` → `dfs.init(pins)` then `dfs.initCardOnly()` (no params)
- `sd.start(pins)` (multicog) → `dfs.init(pins)` (same singleton behavior)
- Add `DEBUG_BAUD = 2_000_000` to every migrated test's CON block
- Add `dfs.stop()` at end of each test after `unmount`

## Migration Order (8 waves, simplest first)

| Wave | File | Tests | Difficulty | Notes |
|------|------|-------|-----------|-------|
| 1 | mount_tests | 21 | LOW | Canonical template |
| 1 | error_handling_tests | 7 | LOW | Small, V3 API only |
| 1 | multihandle_tests | 19 | LOW | V3 handle API throughout |
| 1 | file_ops_tests | 22 | LOW | V3 API |
| 1 | read_write_tests | 38 | LOW | V3 API, large but mechanical |
| 1 | subdir_ops_tests | 18 | LOW | V3 API with debug pragmas |
| 2 | dirhandle_tests | 22 | LOW-MED | openDirectory needs dev |
| 2 | directory_tests | 28 | MED | Heavy dir API: newDirectory, changeDirectory, moveFile |
| 2 | volume_tests | 21 | MED | volumeLabel needs dev, legacy sync/write |
| 3 | seek_tests | 37 | MED | Legacy V1/V2 API (openFile, read, seek, fileSize) |
| 4 | crc_diag_tests | 14 | LOW | SD_INCLUDE_DEBUG pragma |
| 4 | register_tests | 10 | MED | SD_INCLUDE_REGISTERS + initCardOnly change |
| 4 | speed_tests | 14 | MED | SD_INCLUDE_SPEED pragma |
| 5 | raw_sector_tests | ~17 | MED | Custom framework (recordPass/recordFail) |
| 5 | multiblock_tests | ~5 | MED | Large VAR buffers (64KB) — check compile size |
| 6 | multicog_tests | 14 | HIGH | Singleton init pattern, worker cog legacy API |
| 7 | format_tests | 46 | HIGH | Dual-driver binary (format utility + dual_sd_fat32_flash_fs) |
| 8 | testcard_validation | ~20 | MED | Requires pre-formatted test card |

**Excluded**: `SD_RT_fifo_tests.spin2` — tests `isp_string_fifo`, not the SD driver.

## Per-File Migration Procedure

1. Copy + rename (`SD_RT_xxx` → `DFS_SD_RT_xxx`)
2. Update OBJ: `sd : "micro_sd_fat32_fs"` → `dfs : "dual_sd_fat32_flash_fs"`
3. Add `DEBUG_BAUD = 2_000_000` to CON
4. Add `dfs.init()` before first mount
5. Global replace `sd.` → `dfs.`
6. Fix mount: `dfs.mount(...)` → `dfs.mount(dfs.DEV_SD)`
7. Fix unmount: `dfs.unmount()` → `dfs.unmount(dfs.DEV_SD)`
8. Add `dfs.DEV_SD` to all Category-C methods
9. Fix `initCardOnly()` signatures if present
10. Add `dfs.stop()` at end
11. Compile: `pnut-ts -d -I ../src/ DFS_SD_RT_xxx_tests.spin2`
12. Hardware verify: `./run_test.sh ../regression-tests/DFS_SD_RT_xxx_tests.spin2`

## Format Tests Special Handling

Keep `isp_format_utility.spin2` using the reference driver (it runs in its own cog). Test structure:
```spin2
OBJ
  fmt  : "isp_format_utility"    ' Uses micro_sd_fat32_fs internally
  dfs  : "dual_sd_fat32_flash_fs"               ' For verification
```
Format via `fmt`, then verify via `dfs`. Call `fmt.stop()` before `dfs.init()`.

## Verification

1. All 17 migrated tests compile cleanly
2. Each passes on hardware with same test count as original
3. Phase 1/2/3 regression tests still pass
4. Create `tools/run_phase4_regression.sh` batch script

---

# Phase 5: Migrate Flash Regression Tests

## Context

9 Flash test suites (419+ tests) in `REF-FLASH-uSD/FLASH/RegresssionTests/` test against `flash_fs.spin2`. Phase 5 migrates them to `dual_sd_fat32_flash_fs.spin2`. This is significantly more complex than Phase 4 because: (1) several Flash APIs are missing from the unified driver, (2) the test utility is tightly coupled to Flash internals, and (3) error codes have different values.

## Key Files

- `src/dual_sd_fat32_flash_fs.spin2` — Must be extended with missing APIs
- `REF-FLASH-uSD/FLASH/RegresssionTests/RT_*.spin2` — Source tests
- `REF-FLASH-uSD/FLASH/RegresssionTests/RT_utilities.spin2` — Flash test utility (817 lines)
- `src/isp_rt_utilities.spin2` — SD test utility (base framework)
- `REF-FLASH-uSD/FLASH/flash_fs.spin2` — Reference for porting missing methods

## Part A: Prerequisites — Driver Additions

These MUST be implemented before any Flash test can run.

### A1. format(DEV_FLASH) [BLOCKING — all tests need this]

CMD_FLASH_FORMAT = 51 is defined but NOT dispatched. Port `format()` from `flash_fs.spin2` lines 250-294 as `fl_format()`, add dispatch case, update `PUB format()`.

### A2. Byte-Level I/O [NEEDED by 5 of 9 suites]

`fl_rd_byte_no_locks()` and `fl_wr_byte_no_locks()` already exist internally (lines 3965-4050). Need new CMD codes and PUB wrappers:

| Method | CMD Code | Implementation |
|--------|----------|---------------|
| `wr_byte(handle, value)` | 71 | Single-byte write via worker |
| `wr_word(handle, value)` | 72 | 2-byte write in worker loop |
| `wr_long(handle, value)` | 73 | 4-byte write in worker loop |
| `wr_str(handle, p_str)` | 74 | String write in worker loop |
| `rd_byte(handle)` | 75 | Single-byte read via worker |
| `rd_word(handle)` | 76 | 2-byte read in worker |
| `rd_long(handle)` | 77 | 4-byte read in worker |
| `rd_str(handle, p_str, count)` | 78 | String read in worker |

**Critical**: Implement batch operations in the worker cog (not per-byte commands from caller). The Flash reference driver runs byte-level I/O inline in the caller's cog. In the unified driver, per-byte command overhead would make tests extremely slow.

### A3. file_size_unused(p_filename) [NEEDED by 2 suites]

Port from `flash_fs.spin2` lines 974-998. CMD_FLASH_FILE_SIZE_UNUSED = 79.

### A4. flashSeek(handle, position, whence) [NEEDED by 1 suite]

The internal `fl_seek()` already supports both `SK_FILE_START` and `SK_CURRENT_POSN`. Add a PUB that exposes the full 3-parameter seek. `seekHandle()` keeps its current 2-parameter (absolute-only) signature.

### A5. directory(DEV_FLASH, ...) PUB wrapper [NEEDED by 3 suites]

CMD_FLASH_DIRECTORY = 65 is already dispatched. Add a clean PUB wrapper matching Flash API pattern: `directory(dev, p_block_id, p_filename, p_file_size)`.

### A6. LONGS_IN_HEAD_BLOCK, LONGS_IN_BODY_BLOCK constants

Add to CON: `LONGS_IN_HEAD_BLOCK = BYTES_IN_HEAD_BLOCK / 4` (989), `LONGS_IN_BODY_BLOCK = BYTES_IN_BODY_BLOCK / 4` (1022).

### A7. version(dev) [NEEDED by 2 suites]

Add PUB returning driver version constant for each device.

### A8. canMount(DEV_FLASH) [NEEDED by 2 suites]

Existing `PUB canMount(dev)` at line 4654 has a stub for DEV_FLASH. Implement it.

### A9. TEST_count_file_bytes [OPTIONAL but recommended]

Used by `evaluateFileStats()` in 5 of 9 suites. Port from `flash_fs.spin2` lines 2909-2937 via new CMD_FLASH_TEST_COUNT = 80. Skip other TEST_ methods (replace with simpler debug output).

## Part B: Test Utility

Create `src/DFS_FL_RT_utilities.spin2` — a superset of `isp_rt_utilities.spin2` plus adapted Flash-specific methods from `RT_utilities.spin2`:

- All basic test methods (startTest, evaluateBool, evaluateSingleValue, etc.)
- Adapted Flash methods: evaluateSubStatus, evaluateHandle, evaluateFSStats, evaluateFileStats, ShowStats, showFiles, showError, ensureEmptyDirectory, blockCountForFileSize, bytesAllocatedFor, ReadFile
- Stubbed/simplified: showPendingCommitChain, showFileChain, showMountSignatures (depend on unported TEST_ methods)
- Uses `dfs : "dual_sd_fat32_flash_fs"` instead of `flash : "flash_fs"`

## Part C: API Transformation Rules

### File operations — add DEV_FLASH + rename methods
```
flash.open(fn, "r")        → dfs.open(dfs.DEV_FLASH, fn, dfs.FILEMODE_READ)
flash.open(fn, "w")        → dfs.open(dfs.DEV_FLASH, fn, dfs.FILEMODE_WRITE)
flash.open(fn, "a")        → dfs.open(dfs.DEV_FLASH, fn, dfs.FILEMODE_APPEND)
flash.open(fn, "r+")       → dfs.open(dfs.DEV_FLASH, fn, dfs.FILEMODE_READ_EXTENDED)
flash.close(h)              → dfs.close(h)
flash.read(h, buf, ct)     → dfs.readHandle(h, buf, ct)
flash.write(h, buf, ct)    → dfs.writeHandle(h, buf, ct)
flash.seek(h, pos, whence) → dfs.flashSeek(h, pos, whence)
flash.flush(h)              → dfs.flush(h)
flash.delete(fn)            → dfs.deleteFile(dfs.DEV_FLASH, fn)
flash.rename(o, n)          → dfs.rename(dfs.DEV_FLASH, o, n)
flash.exists(fn)            → dfs.exists(dfs.DEV_FLASH, fn)
flash.file_size(fn)         → dfs.file_size(dfs.DEV_FLASH, fn)
flash.stats()               → dfs.stats(dfs.DEV_FLASH)
flash.create_file(fn,f,c)   → dfs.create_file(dfs.DEV_FLASH, fn, f, c)
```

### Error code name changes
```
flash.E_BAD_HANDLE    → dfs.E_FLASH_BAD_HANDLE    (-2 → -100)
flash.E_NO_HANDLE     → dfs.E_FLASH_NO_HANDLE     (-3 → -101)
flash.E_DRIVE_FULL    → dfs.E_FLASH_DRIVE_FULL    (-4 → -102)
flash.E_FILE_MODE     → dfs.E_FLASH_FILE_MODE     (-8 → -106)
flash.E_FILE_SEEK     → dfs.E_FLASH_FILE_SEEK     (-9 → -107)
flash.E_FILE_NOT_FOUND → dfs.E_FILE_NOT_FOUND     (-11 → -40)
flash.E_END_OF_FILE   → dfs.E_END_OF_FILE         (-12 → -46)
```

### Init/Mount
```
' OLD:  flash.format()  /  flash.mount()
' NEW:  dfs.init(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
'       dfs.format(dfs.DEV_FLASH)
'       dfs.mount(dfs.DEV_FLASH)
```

## Migration Order

| Tier | File | Tests | Difficulty | Notes |
|------|------|-------|-----------|-------|
| 1 | rw_block_tests | 13 | LOW-MED | No byte-level I/O |
| 1 | rw_modify_tests | 36 | LOW-MED | Uses r+ mode, no byte I/O |
| 2 | mount_handle_basics | 48 | MED | Uses ALL byte-level methods |
| 2 | rw_tests | 70 | MED | Heavy byte-level I/O |
| 2 | append_tests | 78 | MED | wr_byte/word/long/str heavy |
| 2 | seek_tests | 33 | MED | SK_CURRENT_POSN, fileSizeHandle mapping |
| 3 | circular_tests | 40 | MED | open_circular, can_mount |
| 3 | circular_compat_tests | 30 | MED-HIGH | Depends on circular_tests data |
| 4 | 8cog_tests | 71 | HIGH | Major rearchitecture — serialized worker vs. parallel |

## 8-Cog Test Special Handling

The Flash reference driver is synchronous (each cog runs independently). The unified driver serializes through a worker cog. Key changes:
- Main cog does `dfs.init()` + `dfs.mount(DEV_FLASH)` once
- Spawned cogs do NOT call mount — just use the shared driver
- All operations serialize through the worker — timing behavior changes
- May need reduced concurrency (4 cogs instead of 8) if handle contention is too high

## Verification

1. All prerequisites compile and pass Phase 1-3 regression
2. Each migrated suite compiles
3. Each passes on hardware (test count matches original where possible)
4. Phase 1/2/3 + Phase 4 regression all still pass

---

# Phase 6: API Symmetry, Cross-Device Operations, and Tests

## Context

Both devices work independently (Phases 1-5). Phase 6 makes the unified API **device-agnostic** — callers should not need to know which device they're talking to. This phase implements Flash directory emulation, symmetric `file_size_unused()`, read-only Flash raw block access, `copyFile()`, and tests all cross-device operations.

## Design Principle

The power of this driver is that callers write device-agnostic code. Every API that works on SD should work on Flash (and vice versa) unless the underlying hardware makes it physically impossible.

## Key Files

- `src/dual_sd_fat32_flash_fs.spin2` — Directory emulation, file_size_unused(DEV_SD), readRawBlock, copyFile
- `src/regression-tests/DFS_RT_phase6_cross_device.spin2` — Cross-device test suite
- `src/regression-tests/DFS_RT_phase6_flash_dir.spin2` — Flash directory emulation tests

---

## 6A. Flash Directory Emulation (Implicit Path-Prefix Directories)

### Concept

Flash stores the full filename string in each file's head block. Path separators (`/`) in filenames naturally encode directory structure. The driver emulates directories by treating filename prefixes as paths:

- `"readme.txt"` → file in root
- `"logs/data1.txt"` → file in `logs/` directory
- `"logs/2024/jan.dat"` → file in `logs/2024/` directory

Directories are **implicit** — they exist because files with that path prefix exist. No Flash blocks are allocated for empty directories.

### Behavior

| Operation | Flash Behavior |
|-----------|---------------|
| `newDirectory(DEV_FLASH, "logs")` | Records path prefix in driver state. Writes nothing to Flash. |
| `changeDirectory(DEV_FLASH, "logs")` | Updates current path prefix. Writes nothing. |
| `open(DEV_FLASH, "data.txt", WRITE)` | Creates `"logs/data.txt"` on Flash (prefix prepended). Directory now "exists". |
| `deleteFile(DEV_FLASH, "data.txt")` | Deletes `"logs/data.txt"`. If last file with prefix, directory vanishes. |
| `openDirectory(DEV_FLASH)` | Returns virtual handle iterating files with current prefix. |
| `readDirectoryHandle(handle)` | Returns next direct child: files and unique subdirectory names. |
| `changeDirectory(DEV_FLASH, "/")` | Reset to root (empty prefix). |
| `changeDirectory(DEV_FLASH, "..")` | Strip last path segment from prefix. |

### Directory Listing Algorithm

When listing directory with prefix `"logs/"`:
1. Iterate all Flash files via existing `fl_directory()` mechanism
2. For each file, check if name starts with `"logs/"`
3. Extract remainder after prefix
4. If remainder contains no `/` → direct child file, return filename
5. If remainder contains `/` → extract next path segment as subdirectory name
6. Deduplicate subdirectory names (many files may share prefix)

### Implementation

**Driver state** (DAT section):
```spin2
fl_current_dir    BYTE  0[128]    ' Current Flash directory path prefix (zero-terminated)
fl_dir_iter_idx   LONG  0         ' Directory iteration index for virtual handle
```

**PUB methods** — existing methods gain Flash awareness:
- `changeDirectory(DEV_FLASH, p_path)` → update `fl_current_dir` prefix
- `newDirectory(DEV_FLASH, p_name)` → no-op (implicit), returns SUCCESS
- `openDirectory(DEV_FLASH)` → allocate virtual dir handle, reset iterator
- `readDirectoryHandle(handle)` → iterate Flash files, filter by prefix, return next match
- `closeDirectoryHandle(handle)` → release virtual handle
- `open/delete/rename/exists` → prepend `fl_current_dir` to filename before Flash operation

**Key constraint**: Full path + filename must fit in Flash head block's filename field. Need to verify maximum filename length in head block layout.

### Tests (~25 tests)

1. Root listing matches flat file list
2. Create files with path prefixes, list subdirectory
3. changeDirectory + open creates prefixed file
4. Subdirectory names deduplicated in listing
5. `cd ..` navigates up
6. `cd /` resets to root
7. Delete last file in directory → directory gone
8. Nested directories (2-3 levels deep)
9. newDirectory is no-op but doesn't error

---

## 6B. file_size_unused(DEV_SD)

Extend existing Flash-only API to work symmetrically on SD.

**SD/FAT32 semantics**:
- File size (exact bytes) is in the directory entry — already available
- Allocated size = cluster chain length × cluster size (from BPB)
- Unused = allocated - file_size

**Implementation**: Walk the FAT cluster chain to count clusters, or compute from `ceil(file_size / cluster_size)` if filesystem is consistent. Return `(cluster_count * cluster_size) - file_size`.

**Result**: `file_size_unused(dev, p_filename)` works identically on both devices — returns wasted tail space regardless of device block/cluster granularity.

---

## 6C. Raw Block Access Symmetry

Expose Flash raw block read for diagnostics. Internal `fl_read_block_addr()` already exists.

```spin2
PUB readRawBlock(dev, block_address, p_buffer) : status
'' Read raw block from device (diagnostic, read-only on both).
'' SD: reads 512-byte sector (existing). Flash: reads 4KB block (new).

PUB writeRawBlock(dev, block_address, p_buffer) : status
'' Write raw block to device (SD only).
'' SD: writes 512-byte sector (existing).
'' Flash: returns E_NOT_SUPPORTED — raw write would bypass wear-leveling,
''   lifecycle management, and block signatures.
```

Flash raw write is explicitly an error (`E_NOT_SUPPORTED`), not a silent no-op. Callers who attempt it get a clear signal that the operation is illegal on Flash.

---

## 6D. copyFile() — Cross-Device Copy

**Decision**: Implement as a caller-side multi-command sequence (not a single worker CMD). Reasons:
- Worker-side copy would block the API lock for the entire copy duration
- Caller can report progress and recover from errors
- Same pattern already proven in shell's `do_copy()` (SD_demo_shell.spin2 line 788)

### Implementation

Add `copy_buf BYTE 0[4096]` in DAT (4KB to match Flash block size, minimizes SPI bus switches).

Replace `copyFile()` stub with:
```spin2
PUB copyFile(srcDev, p_src_path, dstDev, p_dst_path) : status
  ' Open source for read
  srcHandle := openFileRead(srcDev, p_src_path)
  ' Open destination for write (SD: createFileNew, Flash: open WRITE)
  ' Copy loop: readHandle → writeHandle until EOF
  ' Close both handles
```

No new CMD codes needed — uses existing `openFileRead`, `createFileNew`, `readHandle`, `writeHandle`, `closeFileHandle`.

---

## 6E. Cross-Device Test Suite (~86 tests, 17 groups)

1. **Prerequisites** (4): init, mount(DEV_BOTH), both mounted
2. **Interleaved SD→Flash** (6): write SD, write Flash, read both back
3. **Interleaved Flash→SD** (6): write Flash, write SD, read both back
4. **Rapid alternation** (8): alternating writes/reads across devices
5. **copyFile SD→Flash small** (6): 26-byte file, verify content + exists
6. **copyFile Flash→SD small** (6): 25-byte file, verify content
7. **copyFile block boundary** (4): exactly 4096 bytes
8. **copyFile multi-block** (4): 8192 bytes
9. **copyFile large** (4): 12000 bytes SD→Flash
10. **copyFile error cases** (6): nonexistent source, bad device, etc.
11. **Flash dir: root listing** (4): list matches flat file set
12. **Flash dir: subdirectories** (6): create prefixed files, list, cd, navigate
13. **Flash dir: nested + cd ..** (5): multi-level paths, parent navigation
14. **Flash dir: implicit create/delete** (4): directory appears/vanishes with files
15. **file_size_unused both devices** (4): compare SD cluster waste vs Flash block waste
16. **Post-copy regression** (6): both devices still work after all operations
17. **Cleanup + stack guard** (3)

## Verification

```bash
./run_test.sh ../src/regression-tests/DFS_RT_phase6_cross_device.spin2 -t 240
./run_test.sh ../src/DFS_RT_phase3_verify.spin2 -t 120          # regression
./run_test.sh ../src/DFS_RT_phase2_verify.spin2 -t 120
./run_test.sh ../src/DFS_SD_RT_phase1_verify.spin2 -t 120
```

---

# Phase 7: Utilities and Demos

## Context

Phase 7 creates user-facing tools that leverage the unified driver: an interactive dual-device shell, format/audit utilities, benchmarks, and example programs.

## Key Files

- `src/dual_sd_fat32_flash_fs.spin2` — Add Flash format dispatch (if not done in Phase 5)
- `src/DFS_demo_shell.spin2` — New dual-device shell (~2000 lines)
- `src/DFS_format.spin2` — Format utility wrapper
- `src/DFS_benchmark.spin2` — Performance measurement
- `src/EXAMPLES/DFS_example_*.spin2` — 2-3 example programs

## Prerequisites (from Phases 5-6)

- `format(DEV_FLASH)` must be implemented
- Flash directory emulation must be working
- `copyFile()` must be implemented

## Dual-Device Shell

Copy `SD_demo_shell.spin2` (~1500 lines) → `src/DFS_demo_shell.spin2`. Key changes:

### Device-Aware Prompt
```
SD:/> dir                    ' SD mode, root
SD:/work> cd logs
FL:/> dir                    ' Flash mode, root (emulated directories)
FL:/logs> cd 2024            ' Flash subdirectory navigation
FL:/logs/2024> dir
```

### New `dev` Command
```
dev sd        ' Switch active device
dev flash
dev           ' Show current device
```

### Command Routing

| Command | SD | Flash | Both |
|---------|:--:|:-----:|:----:|
| dir/ls | Directory listing | Directory listing (emulated) | - |
| type/cat | Open + read | Open + read | - |
| del/rm | Delete file | Delete file | - |
| ren | Rename | Rename | - |
| stats/info | FAT32 stats | Block stats | Show both |
| cd/pwd/mkdir | Full path support | Emulated path-prefix directories | - |
| copy/cp | Same-device | Same-device | Cross-device: `copy sd:file flash:file` |
| mount | mount(DEV_SD) | mount(DEV_FLASH) | mount(DEV_BOTH) |
| format | Delegate to isp_format_utility | dfs.format(DEV_FLASH) | - |
| card/cid | Register dump | Raw block read | - |

### Cross-Device Copy Syntax
```
copy sd:FILE.TXT flash:FLFILE     ' Explicit device prefix parsing
```
Uses `copyFile()` from Phase 6.

## Format Utility — DFS_format.spin2

Thin wrapper (~80 lines):
- SD: `dfs.stop()`, delegate to `isp_format_utility`, then `dfs.init()` + `dfs.mount()`
- Flash: `dfs.format(DEV_FLASH)`

## Benchmark — DFS_benchmark.spin2

~400 lines. Measures throughput (KB/s) for:
- SD sequential write/read (512B, 4KB, 32KB)
- Flash sequential write/read (4KB, 8KB)
- Cross-device copy throughput

## Example Programs

- `DFS_example_basic.spin2` (~80 lines): Mount both, write/read files on each, show stats
- `DFS_example_cross_copy.spin2` (~100 lines): Copy file SD↔Flash, verify round-trip
- `DFS_example_data_logger.spin2` (~120 lines): Log to Flash, archive to SD

## Verification

Shell: Manual interactive testing (mount both, exercise commands, cross-device copy, Flash directory navigation).
Utilities: Compile + run, verify output.
Examples: Compile + run, verify debug output.

---

# Future: Circular Files on SD (Post-1.0, Cost Analysis Required)

## Concept

Flash natively supports circular (ring-buffer) files via `open_circular()`. SD/FAT32 has no equivalent. To achieve API symmetry, circular file behavior could be emulated on SD.

## Approach Options

| Option | Mechanism | Pros | Cons |
|--------|-----------|------|------|
| A. Header in file | Pre-allocate fixed-size file. First N bytes = wrap pointer + metadata. Data wraps after header. | Self-contained, one file | Header read/write on every wrap; cluster chain walk on open |
| B. Sidecar file | Data file + `.meta` companion file storing wrap pointer | Data file is plain FAT32 | Two files per circular file; sidecar can get orphaned |
| C. Pre-allocated + seek | Pre-allocate exact cluster count. Seek to wrap position. Overwrite in-place. | Simple seek-based writes | Requires in-place overwrite (SD supports this); no truncation |

## Cost Estimate

- **Driver code**: ~200-300 lines for PUB wrappers + circular state tracking
- **DAT state**: Per-handle circular metadata (wrap pointer, max length, current position) — ~16 bytes per handle
- **Hub RAM**: Minimal beyond existing handle overhead
- **Performance**: One extra seek per wrap cycle; acceptable for logging use case
- **Binary size**: ~1-2KB additional

## Decision

Defer to post-1.0. Document the API so it can be added without breaking changes. The PUB signature `open_circular(dev, p_filename, mode, max_file_length)` already takes a `dev` parameter — adding DEV_SD support is backwards-compatible.

---

# Risk Summary (All Phases)

| Phase | Risk | Severity | Mitigation |
|-------|------|----------|------------|
| 4 | Binary size (format test: dual driver + format utility) | MED | Split into two test files if needed |
| 4 | Multi-cog init() singleton from worker cogs | MED | Test specifically exercises this |
| 5 | format(DEV_FLASH) implementation correctness | HIGH | Test with format + mount + stats before other tests |
| 5 | Byte-level I/O performance through worker cog | HIGH | Batch operations in worker (not per-byte commands) |
| 5 | 8-cog test under serialized worker architecture | HIGH | Accept timing changes, may reduce to 4 cogs |
| 5 | Error code value changes across 419 tests | MED | Symbolic references (dfs.E_FLASH_*), careful audit |
| 6 | Flash filename length limit constrains directory depth | MED | Verify head block filename field size; document limit |
| 6 | Directory listing performance on large Flash file counts | MED | Linear scan is O(n) per listing; acceptable for typical file counts |
| 6 | SPI bus switching overhead makes copy slow | MED | 4KB buffer reduces switches; acceptable for correctness |
| 6 | SD re-init failure during rapid bus switching | MED | reinitCard() already handles this |
| 7 | Shell binary size approaching P2 512KB limit | MED | Use #PRAGMA EXPORTDEF selectively |
| 7 | FSCK utility requires stopping unified driver | LOW | Already handled by existing shell pattern |

---

# Implementation Sequence

Execute phases **sequentially**. Each phase gates on the previous:

1. **Phase 4** — SD test migration (mechanical transforms, no driver changes)
2. **Phase 5 Prerequisites** — Add missing APIs to `dual_sd_fat32_flash_fs.spin2` (format, byte I/O, etc.)
3. **Phase 5** — Flash test migration (utility creation + test adaptation)
4. **Phase 6** — API symmetry (Flash directory emulation, file_size_unused(SD), readRawBlock(Flash), copyFile) + cross-device tests
5. **Phase 7** — Shell, utilities, examples
