# Plan: Feature Parity

Bring SD and Flash APIs to near-transparent parity, port utilities, create Flash utilities, update documentation. Circular files on SD are a separate plan (deferred).

## Context

The unified dual-FS driver (`src/dual_sd_fat32_flash_fs.spin2`) merges SD FAT32 and Flash block-based filesystems behind a single API. However, many methods are stubs or only work for one device. The user wants near-transparent API parity so callers don't need to know which device they're using (where feasible). Additionally, existing SD utilities in `src/UTILS/` need porting from the reference driver to the unified driver, new Flash utilities are needed, and the Flash Theory of Operations document needs to be brought into the project DOCs tree.

## Phases

### Phase A: Documentation Foundation

**A1. Bring Flash Theory of Operations to DOCs tree**
- Source: `REF-FLASH-uSD/FLASH/DOCs/THEOPSv2.md` (448 lines)
- Target: `DOCs/FLASH-FS-THEORY.md`
- Changes needed:
  - Rename to project-consistent name
  - Update header/title for unified driver context (this is now a reference doc explaining Flash internals, used alongside DUAL-DRIVER-THEORY.md)
  - Update references from `flash_fs.spin2` to `dual_sd_fat32_flash_fs.spin2`
  - Update SPI pin references (shared bus, not standalone)
  - Update constant names to match unified driver (e.g., `MAX_FILES_OPEN` -> `MAX_OPEN_FILES`)
  - Remove standalone project links/badges (this is now part of the dual-FS project)
  - Add note that this describes the Flash subsystem within the unified driver
  - Keep all technical content (block formats, lifecycle bits, translation tables, mount process, wear leveling) -- this is the authoritative Flash reference

**A2. Update DUAL-DRIVER-THEORY.md -- Flash directory emulation**
- Section 5B currently says "flat namespace (no directories)"
- Add subsection explaining directory emulation via path-segmented filenames:
  - Flash filenames support "/" characters (127 chars, no filtering)
  - Per-cog CWD prefix string (like SD's `cog_dir_sec[8]` but a string)
  - `mkdir` records path prefix
  - `cd` changes CWD prefix
  - File creation embeds CWD prefix in filename
  - `dir` filters by CWD prefix
  - Limitation: empty directories cannot be stored (directories exist only because files with those path segments exist)
- Update Section 11 (Multi-Cog Support) to mention per-cog Flash CWD

**A3. Update DUAL-DRIVER-TUTORIAL.md**
- Remove "flat namespace" absolute statements
- Add Flash directory emulation usage examples
- Correct any remaining factual issues

### Phase B: Feature Parity -- Driver Changes (`src/dual_sd_fat32_flash_fs.spin2`)

**B1. Flash directory emulation** (NEW feature, highest priority)
- Add per-cog Flash CWD: `fl_cog_cwd BYTE 0[8 * 128]` in DAT (128 bytes per cog, 8 cogs = 1KB)
- Implement `changeDirectory(DEV_FLASH, @path)`:
  - Store path as CWD prefix string for calling cog
  - "/" navigates to root (empty prefix)
  - ".." strips last path segment
  - Relative paths append to current prefix
- Implement `newDirectory(DEV_FLASH, @name)`:
  - **Decision: No marker file** -- mkdir validates the path but doesn't store anything. Empty directories vanish when their last file is deleted. Simpler, no hidden files.
- Fix `openDirectory(DEV_FLASH, ...)`:
  - Use Flash `directory()` iteration but filter by CWD prefix
  - Return only filenames with matching prefix, stripping the prefix from returned names
- Fix dead `dev` parameter in `changeDirectory`, `newDirectory`, `openDirectory`, `moveFile`:
  - Currently all ignore `dev` and always operate on SD
  - Add `case dev` dispatch: DEV_SD -> existing SD logic, DEV_FLASH -> new Flash logic

**B2. `exists()` for SD** (currently STUB, always returns false -- line 6735)
- Implement using worker cog `searchDirectory()` or open-then-close pattern:
  - Add new command `CMD_SD_EXISTS` (or reuse existing directory search in worker)
  - Worker tries to locate file in current directory
  - Returns true/false without opening a handle
- Alternative (simpler): open for read, check result, close if successful -- but this wastes a handle slot
- Preferred: add CMD_SD_EXISTS using internal `findFileEntry()` (the worker already has this for openFileRead)

**B3. `file_size()` by name for SD** (currently returns E_NOT_SUPPORTED -- line 6758)
- Implement using directory entry lookup (the dir entry contains the file size)
- Add CMD_SD_FILE_SIZE or piggyback on the exists mechanism
- Worker searches directory for filename, reads 32-bit size from dir entry bytes 28-31

**B4. `file_size_unused()` for SD** (currently returns E_BAD_DEVICE -- line 6653)
- Meaning: allocated space minus actual file size
- Implementation: walk the cluster chain counting clusters, multiply by cluster_size, subtract actual file_size
- Add CMD_SD_FILE_SIZE_UNUSED
- Worker: findFileEntry -> get file_size -> walk cluster chain counting clusters -> return (clusters * bytes_per_cluster) - file_size

**B5. `serial_number()` for SD** (currently returns 0,0 -- line 6476)
- **Decision: Cache PSN at init** (no SD_INCLUDE_REGISTERS dependency)
- `identifyCard()` (line 5411) already reads CID into local `cid[4]` via CMD10
- Add: `card_serial_number LONG 0` to DAT (after `card_mfr_id` at line 511)
- Extract PSN (bytes 9-12 of CID) in `identifyCard()`: `card_serial_number := BYTE[@cid][9] << 24 | BYTE[@cid][10] << 16 | BYTE[@cid][11] << 8 | BYTE[@cid][12]`
- `serial_number(DEV_SD)` returns `0, card_serial_number` (high=0, low=32-bit PSN)
- Flash returns (jedec_hi, jedec_lo) -- 64-bit JEDEC unique ID

**B6. `stats()` full implementation for SD** (currently partial -- line 6686)
- Currently: `used=0, free_ct=freeSpace(DEV_SD), file_count=0`
- **Decision: CWD file count for both devices** -- with Flash directory emulation, both devices have CWD. stats() should consistently return file count in the current working directory.
- SD: `used = cardSizeSectors - freeSpace`, `free_ct = freeSpace(DEV_SD)`, `file_count = count files in cog_dir_sec[COGID()]`
- Flash: update existing `stats()` to count only files matching current CWD prefix (not all files)
- Add CMD_SD_STATS, worker walks current directory counting file entries
- This gives consistent semantics: "how many files are in my current directory?" for both devices

**B7. Byte/word/long/string I/O wrappers for SD handles**
- Currently Flash-only: `wr_byte`, `rd_byte`, `wr_word`, `rd_word`, `wr_long`, `rd_long`, `wr_str`, `rd_str`
- Implementation: detect `h_device[handle] == DEV_SD` and use existing SD handle I/O
- For each method:
  - `wr_byte(handle, val)` -> write 1 byte via `writeHandle(handle, @val, 1)`
  - `rd_byte(handle)` -> read 1 byte via `readHandle(handle, @val, 1)`
  - `wr_word(handle, val)` -> write 2 bytes via `writeHandle(handle, @val, 2)`
  - `rd_word(handle)` -> read 2 bytes via `readHandle(handle, @val, 2)`
  - `wr_long(handle, val)` -> write 4 bytes via `writeHandle(handle, @val, 4)`
  - `rd_long(handle)` -> read 4 bytes via `readHandle(handle, @val, 4)`
  - `wr_str(handle, p_str)` -> write string via `writeHandle(handle, p_str, strsize(p_str)+1)`
  - `rd_str(handle, p_str, count)` -> read bytes via `readHandle(handle, p_str, count)`, find null terminator
- These are PUB-level dispatchers -- the existing Flash path sends commands to worker, SD path calls handle-based methods directly (or sends existing SD commands)
- **Key consideration**: SD handle ops (readHandle/writeHandle) happen via worker cog commands. So the SD path in wr_byte etc. must also use send_command (CMD_WRITE_H / CMD_READ_H). This should work since writeHandle/readHandle already exist.

**B8. Seek with whence for SD**
- Currently: `seekHandle(handle, position)` is absolute-only; `flashSeek(handle, position, whence)` is Flash-only
- Plan: extend seekHandle OR unify into single `seek(handle, position, whence)`:
  - **Option A**: Add whence to seekHandle -> breaking change for existing callers
  - **Option B**: Create unified `seek(handle, position, whence)` as new method, keep seekHandle as-is
  - **Recommended**: Option B -- add `seek(handle, position, whence)` that dispatches to seekHandle (with computed absolute position) or flashSeek, keeping backward compatibility
  - For SD: SK_FILE_START -> pass position directly, SK_CURRENT_POSN -> compute `tellHandle(handle) + position`

**B9. openFileWrite semantic alignment**
- Currently: SD `openFileWrite` = append, Flash `FILEMODE_WRITE` = truncate/overwrite
- The unified `open()` method (line 6787) maps both FILEMODE_WRITE and FILEMODE_APPEND on SD to append
- Plan: make SD `open(DEV_SD, @name, FILEMODE_WRITE)` = truncate (delete + createFileNew)
  - Check if file exists -> deleteFile -> createFileNew -> return handle
  - `open(DEV_SD, @name, FILEMODE_APPEND)` = existing append behavior (openFileWrite)
  - This makes the semantic consistent: FILEMODE_WRITE = fresh write on both devices
- Update `openFileWrite()` doc to clarify it's always append mode
- **Document the difference** in tutorial: `openFileWrite()` is always append; use `open()` with FILEMODE_WRITE for truncate semantics

### Phase C: Utility Porting (`src/UTILS/`)

All ported utility files get the `DFS_` prefix per project convention. The `isp_` library files keep their names.

**C1. Copy `isp_mem_strings.spin2` to `src/UTILS/`**
- Source: `REF-FLASH-uSD/uSD-FAT32/src/DEMO/isp_mem_strings.spin2`
- Required by `isp_string_fifo.spin2` (already in src/UTILS/)

**C2. Port `isp_format_utility.spin2`** (782 lines)
- `sd : "micro_sd_fat32_fs"` -> `dfs : "dual_sd_fat32_flash_fs"`
- Method changes:
  - `sd.initCardOnly(cs, mosi, miso, sck)` -> `dfs.init(basePin)` + `dfs.initCardOnly()`
  - `sd.cardSizeSectors()` -> `dfs.cardSizeSectors()`
  - `sd.readSectorRaw(sec, @buf)` -> `dfs.readSectorRaw(sec, @buf)` (same)
  - `sd.writeSectorRaw(sec, @buf)` -> `dfs.writeSectorRaw(sec, @buf)` (same)
  - `sd.writeSectorsRaw(sec, cnt, @buf)` -> `dfs.writeSectorsRaw(sec, cnt, @buf)` (same)
  - `sd.stop()` -> `dfs.stop()`
- Public API: `format(cs, mosi, miso, sck)` -> `format(basePin)` (single pin parameter)
- Internal: store `basePin` in DAT, call `dfs.init(basePin)` once

**C3. Port `isp_fsck_utility.spin2`** (1270 lines)
- `sd : "micro_sd_fat32_fs"` -> `dfs : "dual_sd_fat32_flash_fs"`
- Method changes (same raw sector changes as C2, plus):
  - `sd.mount(cs, mosi, miso, sck)` -> `dfs.init(basePin)` + `dfs.mount(dfs.DEV_SD)`
  - `sd.unmount()` -> `dfs.unmount(dfs.DEV_SD)`
  - `sd.freeSpace()` -> `dfs.freeSpace(dfs.DEV_SD)`
- Public API: `startFsck(cs, mosi, miso, sck)` -> `startFsck(basePin)`, same for `startAudit()`
- Internal FAT caching, bitmap, directory scanning: **no changes** (these are internal algorithms)

**C4. Rename SD utility wrappers** (thin wrappers, minimal changes)
- `SD_format_card.spin2` -> `DFS_SD_format_card.spin2`
  - Update OBJ: `fmt : "isp_format_utility"`
  - Update call: `fmt.formatWithLabel(basePin, @label)` (new signature)
- `SD_FAT32_audit.spin2` -> `DFS_SD_FAT32_audit.spin2`
  - Update OBJ: `fsck : "isp_fsck_utility"`
  - Update call: `fsck.startAudit(basePin)` (new signature)
- `SD_FAT32_fsck.spin2` -> `DFS_SD_FAT32_fsck.spin2`
  - Update OBJ: `fsck : "isp_fsck_utility"`
  - Update call: `fsck.startFsck(basePin)` (new signature)
- `SD_card_characterize.spin2` -> `DFS_SD_card_characterize.spin2`
  - `sd : "micro_sd_fat32_fs"` -> `dfs : "dual_sd_fat32_flash_fs"`
  - `sd.initCardOnly(cs, mosi, miso, sck)` -> `dfs.init(basePin)` + `dfs.initCardOnly()`
  - All register read methods: `sd.readCIDRaw(@buf)` -> `dfs.readCIDRaw(@buf)` (same signatures)
  - Pin CON section: 4 individual pins -> single `BASE_PIN = 56`

**C5. Keep `isp_string_fifo.spin2` as-is** (no driver dependency, no changes needed)

### Phase D: New Flash Utilities

**D1. `DFS_FL_format.spin2`** (thin wrapper)
- Calls `dfs.init(basePin)` -> `dfs.mount(dfs.DEV_FLASH)` -> `dfs.format(dfs.DEV_FLASH)`
- `format(DEV_FLASH)` already exists in the driver (cancels all active blocks + remounts)
- Output: format status via debug()
- ~30 lines, same structure as DFS_SD_format_card

**D2. `DFS_FL_audit.spin2`** (read-only Flash integrity check)
- Uses `dfs.canMount(DEV_FLASH)` for basic health check
- Additional checks via Flash API:
  - `dfs.stats(DEV_FLASH)` -> verify used + free = total blocks
  - `dfs.mount(DEV_FLASH)` -> verify mount succeeds
  - Iterate all files via `dfs.directory()` -> count files, sum sizes, verify chain consistency
  - Compare file_count from `stats()` vs iteration count
- Output: structured report via debug()
- **Does NOT need raw Flash block access** -- uses existing public API only
- ~150-200 lines

**D3. `DFS_FL_fsck.spin2`** (Flash check & repair)
- This is more complex. The Flash mount process (`do_flash_mount` + `fl_check_block_fix_dupe_id`) already performs repair during mount:
  - M1: Scans all blocks, validates CRC-32, resolves duplicate IDs, cancels bad blocks
  - M2: Locates complete files, identifies orphaned blocks
  - M3: Cancels orphaned blocks
- So `mount(DEV_FLASH)` IS effectively an FSCK already
- The `canMount(DEV_FLASH)` does the same scan read-only
- Plan:
  - Run `canMount()` first (read-only audit) -> report findings
  - If problems found, run `format(DEV_FLASH)` would be too destructive
  - Instead: `unmount()` -> `mount()` -> mount process repairs automatically
  - Report what mount repaired (need to add diagnostic counters to mount process, or compare before/after stats)
  - **Minimum viable**: wrapper that runs canMount (audit mode), then if issues found, offers remount as repair
- ~100-150 lines

### Phase E: Documentation Updates

**E1. Update `DOCs/DUAL-UTILITIES.md`**
- Rename all SD utility references to `DFS_SD_*` names
- Add Flash utility sections (DFS_FL_format, DFS_FL_audit, DFS_FL_fsck)
- Update pin configuration section (single basePin instead of 4 pins)
- Add Flash-specific workflows

**E2. Update `src/UTILS/README.md`**
- Should match DUAL-UTILITIES.md content or link to it
- Update for new file names and Flash utilities

## File Change Summary

| File | Action | Effort |
|------|--------|--------|
| `DOCs/FLASH-FS-THEORY.md` | NEW (copy + update from REF) | Medium |
| `DOCs/DUAL-DRIVER-THEORY.md` | Edit (Flash dir emulation) | Low |
| `DOCs/DUAL-DRIVER-TUTORIAL.md` | Edit (Flash dir emulation) | Low |
| `src/dual_sd_fat32_flash_fs.spin2` | Edit (B1-B9: ~500 lines new code) | High |
| `src/UTILS/isp_mem_strings.spin2` | NEW (copy from REF) | Trivial |
| `src/UTILS/isp_format_utility.spin2` | Edit (OBJ + signatures) | Medium |
| `src/UTILS/isp_fsck_utility.spin2` | Edit (OBJ + signatures + DEV_SD) | Medium |
| `src/UTILS/DFS_SD_format_card.spin2` | NEW (rename + update) | Low |
| `src/UTILS/DFS_SD_FAT32_audit.spin2` | NEW (rename + update) | Low |
| `src/UTILS/DFS_SD_FAT32_fsck.spin2` | NEW (rename + update) | Low |
| `src/UTILS/DFS_SD_card_characterize.spin2` | NEW (rename + update) | Medium |
| `src/UTILS/DFS_FL_format.spin2` | NEW | Low |
| `src/UTILS/DFS_FL_audit.spin2` | NEW | Medium |
| `src/UTILS/DFS_FL_fsck.spin2` | NEW | Medium |
| `DOCs/DUAL-UTILITIES.md` | Edit (new names + Flash) | Medium |
| `src/UTILS/README.md` | Edit | Low |

Delete after porting (old names):
- `src/UTILS/SD_format_card.spin2`
- `src/UTILS/SD_FAT32_audit.spin2`
- `src/UTILS/SD_FAT32_fsck.spin2`
- `src/UTILS/SD_card_characterize.spin2`

## Implementation Order

1. **Phase A** first (documentation foundation -- Flash THEOPS needed for D2/D3 design)
2. **Phase C** next (utility porting -- mechanical, unblocks testing)
3. **Phase B** (driver feature parity -- the bulk of the work)
4. **Phase D** (Flash utilities -- depends on driver changes in B)
5. **Phase E** last (documentation updates -- reflects all changes)

## Verification

- Compile all ported utilities with `pnut-ts -d -I ../. <file>.spin2`
- Run existing Phase 1-6 regression tests to verify no regressions
- Test exists(), file_size(), serial_number(), stats() for SD via new test or shell commands
- Test byte/word/long/string I/O for SD handles
- Test seek with whence for SD
- Test Flash directory emulation (cd, mkdir, dir filtering)
- Run ported SD utilities on hardware
- Run new Flash utilities on hardware

## Resolved Design Decisions

1. **serial_number(DEV_SD)**: Cache PSN at init -- no SD_INCLUDE_REGISTERS dependency
2. **newDirectory(DEV_FLASH)**: No marker file -- empty dirs vanish naturally
3. **stats() file_count**: CWD file count for both devices -- consistent semantics with directory emulation
4. **wr_str/rd_str for SD**: Identical to Flash -- wr_str includes null terminator, rd_str returns length without terminator

> **Circular Files on SD**: Separate plan, deferred. See `DOCs/Plans/Circular-Files-on-SD-Plan.md`. Will be activated independently after feature parity work is complete.
