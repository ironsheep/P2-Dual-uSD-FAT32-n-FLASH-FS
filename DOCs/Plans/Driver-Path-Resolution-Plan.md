# Driver-Level Path Resolution Plan

## Goal

Make path resolution transparent in the driver so callers pass full paths (e.g., `/MYDIR/FILE.TXT`, `work1/work2/file`) and both devices handle navigation internally. The demo shell should not need any navigate/nav_back wrappers.

## Current State

### SD
- `cog_dir_sec[8]` tracks per-cog current directory sector
- All file operations (`do_open`, `do_open_read`, `do_create`, `do_delete`, `do_rename`, `do_movefile`) operate on files in the current directory only
- `do_chdir()` navigates to a named subdirectory by updating `cog_dir_sec[pb_caller]`
- Path navigation is done by the shell via `navigate_to_parent()` / `nav_back()`
- `root_sec` holds the root directory sector

### Flash
- `fl_cog_cwd[8 * FL_FILENAME_SIZE]` stores per-cog CWD prefix string
- `fl_prepend_cwd()` prepends CWD to filenames before operations
- All PUB methods call `fl_prepend_cwd()` before sending commands
- Path navigation is done by the shell via `fl_navigate_to_parent()` / `fl_nav_back()`

## Design

### Phase 1: Add path resolution helpers to driver

Add two PRI methods in the driver:

```spin2
PRI sd_resolve_path(p_path) : p_leaf | saved_sec, i, seg_start, seg_len, seg_buf[4]
' Split path at last "/", cd through parent components, return leaf name.
' Saves cog_dir_sec[pb_caller] for later restore.
'
' "/MYDIR/SUBDIR/FILE.TXT" -> cd to /MYDIR/SUBDIR, return ^"FILE.TXT"
' "SUBDIR/FILE.TXT"        -> cd to SUBDIR (relative), return ^"FILE.TXT"
' "FILE.TXT"               -> no navigation, return ^"FILE.TXT"
'
' NOTE: Runs in worker cog (has access to do_chdir, cog_dir_sec, etc.)

PRI sd_restore_path(saved_sec)
' Restore cog_dir_sec[pb_caller] to saved value.
' Single assignment -- no SPI operations needed.
```

For Flash, path resolution is simpler -- it's string manipulation:

```spin2
PRI fl_resolve_path(p_path, p_dest) : p_leaf
' If path contains "/", split into parent prefix and leaf.
' Temporarily set CWD to parent prefix (saving old CWD first).
' Then fl_prepend_cwd(p_dest, p_leaf) produces the full path.
'
' "/work1/work2/file"  -> save CWD, set CWD to "work1/work2", leaf = "file"
' "subdir/file"        -> save CWD, append "subdir" to CWD, leaf = "file"
' "file"               -> no change, leaf = "file"

PRI fl_restore_path()
' Restore saved CWD string.
```

### Phase 2: Apply to SD PRI methods (worker cog)

Each SD `do_*()` method wraps its operation with resolve/restore:

**Methods to modify (8 total):**

| Worker method | PUB caller(s) | Notes |
|--------------|---------------|-------|
| `do_open(name_ptr)` | `open()` | FILEMODE_READ/WRITE/APPEND |
| `do_open_read(p_path)` | `openFileRead()` | V3 multi-file |
| `do_create(p_path)` | `createFileNew()` | V3 multi-file |
| `do_delete(name_ptr)` | `deleteFile()` | |
| `do_rename(old, new)` | `rename()` | Both args need resolution |
| `do_movefile(name, dest)` | `moveFile()` | Already does internal chdir |
| `do_new_directory(name)` | `newDirectory()` | Need to find this PRI |
| `do_open_dir(p_path)` | `openDirectory()` | Directory enumeration |

Pattern for each method:
```spin2
PRI do_delete(name_ptr) : status | saved_sec, p_leaf, ...
  saved_sec := cog_dir_sec[pb_caller]
  p_leaf := sd_resolve_path(name_ptr)
  if p_leaf <> 0
    ' ... existing delete logic using p_leaf instead of name_ptr ...
  cog_dir_sec[pb_caller] := saved_sec
```

### Phase 3: Apply to Flash PUB methods (caller cog)

Flash path resolution happens in the PUB methods (caller cog), since `fl_prepend_cwd()` already runs there. Two approaches:

**Option A (simpler):** Enhance `fl_prepend_cwd()` itself to handle paths with "/" by resolving to the correct full path. No separate resolve/restore needed.

If `p_name` contains "/":
- Absolute path (starts with "/"): use as-is, skip CWD prepend
- Relative path with "/": combine CWD + path directly

This already works! `fl_prepend_cwd()` concatenates `cwd + "/" + name`. If `name` is `"subdir/file"` and CWD is `"work1"`, the result is `"work1/subdir/file"` -- which is correct for Flash's flat namespace.

**Wait -- Flash already handles this correctly.** The Flash CWD prepend treats the filename as opaque. `fl_prepend_cwd(@fl_path, "subdir/file.txt")` with CWD `"work1"` produces `"work1/subdir/file.txt"` -- the correct flat-namespace path. No changes needed for Flash PUB methods that already call `fl_prepend_cwd()`.

The only issue is SD, which needs real directory traversal.

**Revised scope: Flash needs no changes. Only SD worker methods need path resolution.**

### Phase 4: Simplify demo shell

Remove from demo shell:
- `navigate_to_parent()` / `nav_back()` (SD path helpers)
- `fl_navigate_to_parent()` / `fl_nav_back()` (Flash path helpers)
- `flSavedCwd` VAR buffer
- All navigate/restore wrappers in command handlers

Each command handler simplifies from:
```spin2
' Before (SD branch)
p_leaf, has_path := navigate_to_parent(p_name)
if p_leaf <> 0
  status := dfs.deleteFile(dfs.DEV_SD, p_leaf)
  ...
if has_path
  nav_back(p_name)

' Before (Flash branch)
p_leaf, has_path := fl_navigate_to_parent(p_name)
if p_leaf <> 0
  status := dfs.deleteFile(dfs.DEV_FLASH, p_leaf)
  ...
if has_path
  fl_nav_back()
```
To:
```spin2
' After (both devices)
status := dfs.deleteFile(activeDev_to_dfsDev(), p_name)
```

### Phase 5: Update cross-device copy

`copyFile()` in the driver calls `openFileRead(srcDev, p_src)` and `createFileNew(dstDev, p_dst)`. Since those PUB methods will now handle path resolution for SD, and Flash already handles it via `fl_prepend_cwd()`, cross-device copy with full paths works automatically.

## Implementation Details

### sd_resolve_path() algorithm

```
1. Scan p_path for last "/" position
2. If no "/" found: return p_path as leaf (no navigation needed)
3. Save cog_dir_sec[pb_caller]
4. If path starts with "/": do_chdir to root first, advance past "/"
5. For each "/" separated segment (except the last):
   a. Null-terminate segment temporarily
   b. do_chdir(segment)
   c. If chdir fails: set error, restore saved_sec, return 0
   d. Restore "/" character
6. Return pointer to leaf (last segment)
```

**Key constraint:** `sd_resolve_path()` runs in the worker cog where `do_chdir()` is available. The path string is in hub RAM and can be temporarily modified (null-terminate segments, restore after).

### sd_restore_path() algorithm

```
1. cog_dir_sec[pb_caller] := saved_sec
```

Single assignment. No SPI operations, no directory traversal needed. The `cog_dir_sec` value is just a sector number that defines "current directory". Restoring it is instant.

### Variables needed

```spin2
DAT
  sd_saved_dir_sec  LONG  0[8]    ' Per-cog saved directory sector for path resolve
```

Or simply use a local variable in each `do_*()` method since save/restore is within one method call.

### Risk: do_rename with two paths

`do_rename(old_name, new_name)` takes two paths. Both may contain "/". The old name needs resolution to find the file. The new name's leaf is what to rename to. Current `do_rename` already handles this -- it searches for old_name in current dir and renames the entry. If new_name has a path prefix, we should only use its leaf portion (renaming doesn't move files).

### Risk: do_movefile already does chdir

`do_movefile()` already saves/restores `cog_dir_sec` and calls `do_chdir()` internally. Path resolution on the source filename should compose correctly -- resolve source path, then movefile handles dest navigation internally.

## Testing

- Existing regression tests pass (no path args = no resolve needed, passthrough)
- Demo shell exercises paths manually via interactive testing
- Key scenarios:
  - `open(DEV_SD, "FILE.TXT", ...)` -- no "/" -- passthrough
  - `open(DEV_SD, "/MYDIR/FILE.TXT", ...)` -- absolute path
  - `open(DEV_SD, "SUBDIR/FILE.TXT", ...)` -- relative path
  - `deleteFile(DEV_SD, "/MYDIR/FILE.TXT")` -- absolute delete
  - `rename(DEV_SD, "/MYDIR/OLD.TXT", "NEW.TXT")` -- rename with path
  - `copyFile(DEV_SD, "/DIR1/FILE", DEV_FLASH, "work1/file")` -- cross-device with paths

## Order of Work

1. Add `sd_resolve_path()` and `sd_restore_path()` PRI methods
2. Apply to `do_open_read()` first (simplest, most testable)
3. Apply to remaining `do_*()` methods one at a time
4. Compile-check after each
5. Strip navigate/restore code from demo shell
6. Compile-check demo
7. Hardware test with interactive demo
