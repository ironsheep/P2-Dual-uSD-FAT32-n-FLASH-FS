# Plan: Flash Directory Support in Driver and Demo Shell

## Context

The dual-FS driver has Flash CWD (current working directory) emulation via path-prefixed filenames (e.g., `dirA/dirB/FILE.TXT`). The driver already supports `changeDirectory()`, `directory()` iteration with CWD filtering, `exists()`, `file_size()`, `rename()`, `deleteFile()` -- all CWD-aware for Flash. However, `openDirectory(DEV_FLASH)` returns E_NOT_SUPPORTED, and the demo shell blocks Flash for cd, pwd, mkdir, rmdir, tree, and move with "flat namespace" messages.

Flash with directory emulation is NOT a flat namespace. This plan adds `openDirectory()`/`readDirectoryHandle()` Flash support in the driver and enables all directory commands for Flash in the demo shell.

---

## Phase 1: Driver -- Flash openDirectory/readDirectoryHandle

### File: `src/dual_sd_fat32_flash_fs.spin2`

### 1A. New PUB: `getFlashCwd()` (after line ~1681)

Exposes Flash CWD to callers (needed by shell for prompt/pwd).

```spin2
PUB getFlashCwd() : p_cwd
'' Return pointer to calling cog's Flash CWD prefix string.
'' Empty string means root.
    p_cwd := fl_get_cwd()
```

### 1B. Modify `openDirectory()` (line 1589)

Replace the `DEV_FLASH: set_error(E_NOT_SUPPORTED)` case:

```spin2
    DEV_FLASH:
      handle := fl_open_directory(p_path)
```

New PRI `fl_open_directory(p_path)`:
- Acquire `api_lock` for safe `allocateHandle()`
- Allocate handle, set `h_device := DEV_FLASH`, `h_flags := HF_DIR`
- Release lock
- Resolve path to absolute prefix, store in handle's 512-byte buffer (bytes 0-127)
- Initialize dedup area (bytes 128-383) to zero
- Set `h_position := 0` (block_id counter)

**Path resolution:**
- `""` or `"."` -- copy caller's CWD as prefix
- `"/"` -- empty prefix (root)
- `"/dirA"` -- strip leading "/", use "dirA"
- `"subdir"` -- prepend CWD via `fl_prepend_cwd()`

### 1C. Modify `readDirectoryHandle()` (line 1600)

Add device routing before `send_command`:

```spin2
PUB readDirectoryHandle(handle) : p_entry
    if handle < 0 or handle >= MAX_OPEN_FILES or h_flags[handle] == HF_FREE
        p_entry := 0
    elseif h_device[handle] == DEV_FLASH
        if fl_read_dir_handle(handle) == SUCCESS
            p_entry := @entry_buffer
        else
            p_entry := 0
    else
        ' SD path (existing)
        if send_command(CMD_READ_DIR_H, handle, 0, 0, 0) == SUCCESS
            p_entry := @entry_buffer
        else
            p_entry := 0
```

### 1D. New PRI: `fl_read_dir_handle(handle)` -- core iteration

For each call, iterates Flash files via `send_command(CMD_FLASH_DIRECTORY)` using the handle's stored prefix (NOT the caller's CWD). Returns files and subdirectory pseudo-entries.

**Logic per call:**
1. Read handle's prefix from buffer bytes 0-127
2. Use `h_position[handle]` as block_id, pass to `CMD_FLASH_DIRECTORY`
3. For each returned Flash file, check if it matches handle's prefix:
   - **Direct child file** (no "/" in remainder after prefix): populate `entry_buffer` in 8.3 FAT32 format with `$20` (ATTR_ARCHIVE), return SUCCESS
   - **Subdirectory** (remainder has "/" -- first segment is subdir name): check dedup list in buffer bytes 128-383. If not seen, add to list, populate `entry_buffer` with dir name + `DIR_ATTR_DIRECTORY ($10)`, return SUCCESS. If already seen, skip and continue.
   - **No match**: continue to next file
4. When no more files (filename[0] == 0): return E_FILE_NOT_FOUND (signals end)

**Dedup storage**: Buffer bytes 128-383 (256 bytes) hold seen directory names as packed null-terminated strings. 8-char names + null = 9 bytes each, fits ~28 unique subdirs.

### 1E. New PRI: `fl_populate_entry_buffer(p_name, attr, fsize)`

Builds a FAT32-compatible `entry_buffer` from a Flash filename so `fileName()`, `attributes()`, and `fileSize()` work transparently.

- Zero-fill `entry_buffer` (32 bytes)
- Parse name: find "." separator. Copy name part to bytes 0-7 (space-padded). Copy extension to bytes 8-10 (space-padded). For directories (no "."), name only in 0-7, spaces in 8-10.
- Set byte 11 = attr
- Set bytes 28-31 = fsize (LONG, little-endian)

### 1F. Modify `closeDirectoryHandle()` (line 1613)

Add device routing for caller-side Flash handle cleanup:

```spin2
PUB closeDirectoryHandle(handle)
    if handle >= 0 and handle < MAX_OPEN_FILES
        if h_device[handle] == DEV_FLASH
            repeat until locktry(api_lock)
            freeHandle(handle)
            lockrel(api_lock)
        else
            send_command(CMD_CLOSE_DIR_H, handle, 0, 0, 0)
```

---

## Phase 2: Demo Shell -- Enable Flash Commands

### File: `src/DEMO/DFS_demo_shell.spin2`

### 2A. Prompt -- show Flash CWD

**`show_prompt()` (line 308):** Replace Flash branch:
- Mounted: `flash:/> ` (at root) or `flash:/dirA> ` (in subdir)
- Unmounted: `flash:(unmounted)> `

Uses `dfs.getFlashCwd()` to get CWD prefix. If empty, display "/".

**`prompt_len()` (line 324):** Update Flash branch to include CWD length.

### 2B. `do_cd()` (line 814) -- enable Flash

Replace "flat namespace" with:
```
dfs.changeDirectory(dfs.DEV_FLASH, p_path)
```
No shell-side `cwd` tracking needed -- driver maintains Flash CWD internally. Shell reads it via `getFlashCwd()` for prompt.

Handle "/", "..", and relative paths -- all already supported by `changeDirectory()`.

### 2C. `do_pwd()` (line 837) -- enable Flash

Replace "flat namespace" with:
```
p_cwd := dfs.getFlashCwd()
Display "/" if empty, else "/" + p_cwd
```

### 2D. `do_mkdir()` (line 849) -- enable Flash

Replace "flat namespace" with call to `dfs.newDirectory(DEV_FLASH, name)`. Print note: "appears when files are added" since Flash dirs are implicit.

### 2E. `do_move()` (line 1085) -- enable Flash

Replace "flat namespace. Use ren" with `dfs.rename(DEV_FLASH, src, dst)`. Flash rename already supports path-based moves.

### 2F. `do_tree()` (line 1847) -- enable Flash

Replace "flat namespace" with Flash tree walk.

New PRI `fl_tree_walk(p_path, depth)`:
- Open handle: `dh := dfs.openDirectory(DEV_FLASH, p_path)`
- Iterate with `readDirectoryHandle(dh)`:
  - If `DIR_ATTR_DIRECTORY`: print with trailing "/", open NEW handle for subdir, recurse, close inner handle
  - If file: print with indentation
- Close handle

**Key advantage over SD tree**: Each recursive level has its own handle with its own stored prefix. No need for `tree_skip_to()` or CWD save/restore. No CWD manipulation during walk.

### 2G. `do_rmdir()` (line 1329) -- enable Flash

Replace "flat namespace" with:
- Open directory handle for the target name
- If first `readDirectoryHandle()` returns an entry: "Directory not empty"
- If no entries: "Directory does not exist" (implicit dirs vanish when empty)
- Close handle

### 2H. `do_delete()` (line 1306) -- cascading cd-up

After successful Flash delete, add:

New PRI `fl_cascade_cd_up()`:
```
repeat
    if at root (getFlashCwd() empty): quit
    check if current dir has files via directory() iteration
    if has files: quit
    print notice: "(directory empty, returning to parent)"
    changeDirectory(DEV_FLASH, @"..")
```

Handles the case where deleting the only file N levels deep cascades all the way up to root.

### 2I. `do_flash_dir()` -- show subdirectories

Update to use handle-based iteration (`openDirectory`/`readDirectoryHandle`) so subdirectory entries (DIR_ATTR_DIRECTORY) appear in the listing alongside files. Display dirs as `<DIR>  dirname/`.

### 2J. Help text (line 396)

Change `"Navigation (SD only)"` to `"Navigation"`.

---

## Phase 3: Regression Tests -- Flash Directory Handle

### 3A. Update `src/regression-tests/DFS_FL_RT_cwd_tests.spin2`

**Replace Group 5** "openDirectory(DEV_FLASH) not supported" (line 236-247) with "openDirectory(DEV_FLASH) basic" -- 3 tests:

1. `openDirectory(DEV_FLASH, ".") succeeds` -- returns valid handle (>= 0)
2. `readDirectoryHandle enumerates root files` -- iterate, count entries, verify count matches known root files
3. `closeDirectoryHandle releases Flash handle` -- close then reopen succeeds

This replaces the 2 tests that verified E_NOT_SUPPORTED with 3 tests that verify basic operation. Keeps existing Groups 1-4, 6-8 intact (they test CWD behavior which remains unchanged).

### 3B. New file: `src/regression-tests/DFS_FL_RT_dirhandle_tests.spin2`

Mirrors `DFS_SD_RT_dirhandle_tests.spin2` structure, adapted for Flash semantics. Uses same test framework (`DFS_RT_utilities`).

**Setup** (`createTestStructure`): Create Flash files with path prefixes to simulate directory structure:
- `dhtdir/dh1.dat` -- file in subdir
- `dhtdir/dh2.dat` -- file in subdir
- `dhtdir/dh3.dat` -- file in subdir
- `dhtdir/dhsub/sub1.dat` -- file in nested subdir
- `rootfl.dat` -- file at root

**Cleanup** (`cleanupTestItems`): Delete all test files.

**Test Groups** (~20 tests):

#### Group 1: Basic Enumeration (5 tests)
1. `openDirectory("") enumerates root` -- count entries at root (includes rootfl.dat + dhtdir/ pseudo-entry)
2. `openDirectory(".") enumerates root` -- same as ""
3. `openDirectory("dhtdir") enumerates subdir` -- finds 3 files + 1 subdir pseudo-entry
4. `closeDirectoryHandle releases handle` -- close then reopen succeeds
5. `Enumerate dhtdir finds 3 files and 1 subdir` -- count files and dirs separately via attributes()

#### Group 2: Entry Inspection (4 tests)
1. `fileName() returns valid names` -- every entry has non-empty filename
2. `attributes() distinguishes file vs directory` -- ATTR_DIRECTORY ($10) for subdir, ATTR_ARCHIVE ($20) for files
3. `Subdirectory enumeration finds nested file` -- openDirectory("dhtdir/dhsub"), finds sub1.dat
4. `fileSize() returns correct size for files` -- verify non-zero size for known files

#### Group 3: Error Conditions (3 tests)
1. `openDirectory on non-existent path returns error` -- openDirectory(DEV_FLASH, "nxdir99") returns negative
2. `readDirectoryHandle with invalid handle returns 0` -- readDirectoryHandle(-1) and readDirectoryHandle(MAX_OPEN_FILES) return 0
3. `closeDirectoryHandle with invalid handle is no-op` -- no crash

#### Group 4: Subdirectory Dedup (3 tests)
1. `Multiple files in subdir produce single dir entry` -- dhtdir has 3 files under dhsub/, but only 1 dhsub/ pseudo-entry appears
2. `Dedup survives full enumeration` -- enumerate twice, same count both times
3. `Root shows subdirectory pseudo-entry` -- root enumeration includes dhtdir/ as DIR_ATTR_DIRECTORY

#### Group 5: CWD Independence (3 tests)
1. `Handle prefix independent of CWD changes` -- open handle at root, cd to dhtdir, readDirectoryHandle still returns root entries
2. `Absolute path ignores CWD` -- cd to dhtdir, openDirectory("/") returns root entries
3. `Two handles enumerate different directories` -- open root handle and dhtdir handle simultaneously, verify different entry counts

#### Group 6: Handle Pool Interaction (2 tests)
1. `Directory handle shares file handle pool` -- open file handles until pool near-full, verify openDirectory fails gracefully
2. `Close dir handle frees slot for file open` -- after closing dir handle, file open succeeds

### 3C. Update test runner and documentation

- `tools/run_flash_regression.sh`: Add `DFS_FL_RT_dirhandle_tests.spin2` to suite list
- `tools/run_all_regression.sh`: Verify the Flash runner picks it up (should be automatic if run_flash_regression.sh is updated)
- Update test counts in READMEs as needed after final test count is known

---

## Phase 4: Verification

1. **Delete stale .obj**: `rm -f src/dual_sd_fat32_flash_fs.obj`
2. **Compile driver**: `cd src && pnut-ts -d dual_sd_fat32_flash_fs.spin2`
3. **Compile demo shell**: `cd src/DEMO && pnut-ts -I .. -I ../UTILS DFS_demo_shell.spin2`
4. **Compile new test suite**: `cd src/regression-tests && pnut-ts -d -I .. DFS_FL_RT_dirhandle_tests.spin2`
5. **Run regression tests**: `cd tools && ./run_all_regression.sh` -- all suites must pass (now 33 suites)
6. **Manual hardware testing** of demo shell:
   - `dev flash` + `mount` -- verify prompt shows `flash:/>`
   - Create files with path prefixes (copy from SD or write directly)
   - `cd dirA` -- verify prompt updates to `flash:/dirA>`
   - `dir` -- verify shows files AND subdirectories with `<DIR>` marker
   - `pwd` -- verify shows `/dirA`
   - `tree` -- verify recursive display from root
   - `del <last-file>` -- verify cascade cd-up with messages
   - `rmdir emptyDir` -- verify "does not exist" message
   - `rmdir fullDir` -- verify "not empty" message
   - `cd /` -- verify return to root
   - `move oldname newname` -- verify Flash rename works

---

## File Change Summary

| File | New Methods | Modified Methods |
|------|------------|-----------------|
| `src/dual_sd_fat32_flash_fs.spin2` | `getFlashCwd()`, `fl_open_directory()`, `fl_read_dir_handle()`, `fl_populate_entry_buffer()` | `openDirectory()`, `readDirectoryHandle()`, `closeDirectoryHandle()` |
| `src/DEMO/DFS_demo_shell.spin2` | `fl_tree_walk()`, `fl_cascade_cd_up()` | `show_prompt()`, `prompt_len()`, `do_cd()`, `do_pwd()`, `do_mkdir()`, `do_move()`, `do_tree()`, `do_rmdir()`, `do_delete()`, `do_flash_dir()`, help text |
| `src/regression-tests/DFS_FL_RT_cwd_tests.spin2` | -- | Replace Group 5 (2 tests -> 3 tests) |
| `src/regression-tests/DFS_FL_RT_dirhandle_tests.spin2` | **New file** (~20 tests across 6 groups) | -- |
| `tools/run_flash_regression.sh` | -- | Add new test suite to runner |
