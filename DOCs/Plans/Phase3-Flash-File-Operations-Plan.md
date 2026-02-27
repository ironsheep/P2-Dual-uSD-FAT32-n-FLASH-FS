# Phase 3: Flash File Operations in Unified Dual-FS Driver

## Context

Phase 1 (SD skeleton, 25/25 tests) and Phase 2 (Flash SPI engine + mount, 27/27 tests) are complete and hardware-verified. Phase 1 regression passed after Phase 2 changes (25/25 still pass).

Phase 3 ports all Flash file I/O methods from the reference driver into the worker cog, enabling `open`, `close`, `read`, `write`, `seek`, `flush`, `delete`, `rename`, `exists`, `file_size`, `stats`, `directory`, `create_file`, and `open_circular` for `DEV_FLASH`.

**User directive**: "Port with minimal change from the reference driver — it's already regression tested. You're adapting existing working code to the new environment."

## Key Files

- `src/dual_fs.spin2` — All changes go here (~7187 lines → ~8300 lines)
- `REF-FLASH-uSD/FLASH/flash_fs.spin2` — Source of truth (lines 504-2558 contain all methods to port)
- `src/DUAL_RT_phase3_verify.spin2` — New verification test

---

## Systematic Translation Rules

Every ported method follows these mechanical substitutions:

| flash_fs.spin2 | dual_fs.spin2 | Notes |
|---|---|---|
| `fsMounted` | `flash_mounted` | Mount flag |
| `locktry(fsLock)` / `lockrel(fsLock)` | *(removed)* | Worker cog is single-threaded |
| `LONG[@errorCode][cogid()] := X` | `fl_set_error(X)` | New helper (sets `fl_errorCode`, returns X) |
| `fsFreeHndlCt--` / `fsFreeHndlCt++` | *(removed)* | Unified pool manages |
| `MAX_FILES_OPEN` | `MAX_OPEN_FILES` | |
| `BLOCKS` | `FL_BLOCKS` | |
| `FILENAME_SIZE` | `FL_FILENAME_SIZE` | |
| `NOT_VALID` | `FL_NOT_VALID` | |
| `H_READ` / `H_WRITE` / `H_FORK` / `H_MODIFY` / `H_APPEND` / `H_READWRITE` | `FL_H_READ` / `FL_H_WRITE` / `FL_H_FORK` / `FL_H_MODIFY` / `FL_H_APPEND` / `FL_H_READWRITE` | |
| `hStatus[]` | `fl_hStatus[]` | (and all other `h*` → `fl_h*` DAT arrays) |
| `hBlockBuff` / `tmpBlockBuffer` | `fl_hBlockBuff` / `fl_tmpBlockBuff` | |
| `IDToBlock` / `IDValid` / `BlockState` | `fl_IDToBlock` / `fl_IDValid` / `fl_BlockState` | Field pointers |
| `flash_read_block_addr` | `fl_read_block_addr` | Already ported in Phase 2 |
| `flash_read_block_id` | `fl_read_block_id` | Already ported in Phase 2 |
| `flash_program_block` / `flash_activate_block` / `flash_cancel_block` | `fl_program_block` / `fl_activate_block` / `fl_cancel_block` | Already ported in Phase 2 |
| `next_active_cycle` / `block_crc` | `fl_next_active_cycle` / `fl_block_crc` | Already ported in Phase 2 |
| `showRTdebug` | `fl_showRTdebug` | |
| Every PRI method name | prefixed with `fl_` | e.g. `write_block` → `fl_write_block` |

---

## Step 1: Add Missing Constants and DAT

**CON additions** (near line 312, after existing Flash CON):
```
  FL_NOT_ENABLED       = -1
  FL_FILENAME_SIZE_EXP = 7                  ' encod 128
  FL_H_READ_WRITE      = FL_H_READ | FL_H_WRITE
  #0, SK_Unknown, SK_FILE_START, SK_CURRENT_POSN
```

**DAT additions** (near line 609):
```
  fl_errorCode    LONG    0
```

**Parameter block addition** (near line 430, after `pb_data1`):
```
  pb_data2        LONG    0                 ' Third return value from worker
```

---

## Step 2: Port `fl_activate_updated_block`

This was missed in Phase 2 but is called by `rename`, `rewrite_block`, `froncate_file`, and `close_no_lock`. Port from flash_fs.spin2 line 2686:

```spin2
PRI fl_activate_updated_block(block_address, pBuff) | nextCycleBits
  nextCycleBits := fl_next_active_cycle(LONG[pBuff].[7..5])
  fl_program_block(block_address, pBuff, nextCycleBits)
  fl_activate_block(block_address, nextCycleBits)
```

---

## Step 3: Port Non-SPI Helpers (~15 methods)

These are pure computation, handle management, or table lookups:

| # | Method | Ref Lines | Notes |
|---|---|---|---|
| 1 | `fl_set_error(code) : result` | NEW | `fl_errorCode := code; return code` |
| 2 | `fl_filename_crc(p_filename) : crc` | 1733 | One-liner: `getcrc(...)` |
| 3 | `fl_filename_pointer(handle) : p` | 2028 | `@fl_hFilename + handle * FL_FILENAME_SIZE` |
| 4 | `fl_buffer_pointer(handle) : p` | 2038 | `@fl_hBlockBuff + handle << BLOCK_SIZE_EXP` |
| 5 | `fl_ensure_handle_mode(handle, mode) : status` | 2048 | Check `fl_hStatus[handle]` |
| 6 | `fl_new_handle(p_filename) : handle` | 1706 | **Adapted**: calls `allocateHandle()`, sets `h_device[handle] := DEV_FLASH`, `h_flags[handle] := HF_READ`, copies filename to `fl_hFilename` |
| 7 | `fl_free_handle(handle)` | NEW | Clears `fl_hStatus`, resets `fl_hHeadBlockID` to `FL_NOT_VALID`, calls `freeHandle(handle)` |
| 8 | `fl_build_head_block(pBuff, p_filename, id)` | 1667 | Uses `fl_filename_crc` |
| 9 | `fl_is_file_open(p_filename, mode) : result` | 1684 | Checks `fl_hStatus`, `fl_hFilename` |
| 10 | `fl_exists_no_lock(p_filename) : bool` | 1608 | One-liner: `fl_get_file_head_signature()` |
| 11 | `fl_blocks_free() : count` | 2467 | Scans `fl_BlockState` for B_FREE |
| 12 | `fl_available_blocks() : bool` | 2500 | Scans `fl_IDValids` for any $FF bytes |
| 13 | `fl_next_available_block_id() : id` | 2481 | First clear bit in `fl_IDValid` |
| 14 | `fl_start_write(handle, mode, id, cycle)` | 1746 | All `h*` → `fl_h*` |
| 15 | `fl_is_old_format_file_head(addr, pBuf) : old` | 2261 | Uses `fl_read_block_addr`, `fl_tmpBlockBuff` |

---

## Step 4: Port Block-Chain Read Helpers (~6 methods)

These do Flash SPI reads to traverse file chains:

| # | Method | Ref Lines | Notes |
|---|---|---|---|
| 16 | `fl_get_file_head_signature(p_filename) : sig` | 1619-1664 | Scans B_HEAD blocks, compares CRC |
| 17 | `fl_count_file_bytes(addr) : used, free, count` | 2396-2425 | Traces block chain |
| 18 | `fl_count_file_bytes_id(id) : bytes` | 2171 | One-liner via `fl_locate_file_byte` |
| 19 | `fl_locate_file_byte(id, pos) : rID, rOfs, rLoc` | 2176-2216 | Traces chain to find position |
| 20 | `fl_start_modify(handle, mode, id, pos, exists)` | 1764-1794 | Locates position, reads block |
| 21 | `fl_seek_no_locks(handle, position)` | 1900-1921 | Uses `fl_locate_file_byte`, calls `fl_rewrite_block` |

Note: `fl_seek_no_locks` calls `fl_rewrite_block` (Step 5). Spin2 allows forward references.

---

## Step 5: Port Write Helpers (~5 methods)

These mutate Flash (erase/program blocks):

| # | Method | Ref Lines | Notes |
|---|---|---|---|
| 22 | `fl_next_block_address() : addr` | 2519-2558 | Random block selection + wear-leveling eviction |
| 23 | `fl_write_block(handle, NextID_EndPtr)` | 1970-2001 | Programs block, tracks chain head |
| 24 | `fl_rewrite_block(handle)` | 2004-2025 | In-place update with new lifecycle |
| 25 | `fl_delete_chain_from_id(id, EndID, mode, keep)` | 2219-2256 | Cancels blocks in chain |
| 26 | `fl_froncate_file(head_id, limit)` | 2068-2138 | Circular file front-truncation (~70 lines) |

---

## Step 6: Port Core I/O Engine (~6 methods)

The byte-level read/write engine and open finishers:

| # | Method | Ref Lines | Notes |
|---|---|---|---|
| 27 | `fl_rd_byte_no_locks(handle) : byte` | 1797-1845 | EOF detection, block chain traversal |
| 28 | `fl_wr_byte_no_locks(handle, value) : status` | 1848-1897 | Block allocation on full, seek support |
| 29 | `fl_close_no_lock(handle) : status` | 1924-1968 | Finalizes writes, activates chain, froncate |
| 30 | `fl_finish_open_read(p_fn, max_len) : handle` | 1486-1524 | Handles circular offset, calls `fl_seek_no_locks` |
| 31 | `fl_finish_open_write(p_fn, max_len) : handle` | 1527-1554 | Overwrite existing or create new |
| 32 | `fl_finish_open_append(p_fn, max_len) : handle` | 1557-1581 | Append via `fl_start_modify` |
| 33 | `fl_finish_open_readwrite(p_fn) : handle` | 1584-1605 | Read/modify/write mode |

All `finish_open_*` methods: remove `lockrel(fsLock)` at end (no lock in worker cog).

---

## Step 7: Port Top-Level Operations (~14 methods)

Each is a direct port of the corresponding PUB from flash_fs.spin2, but as a PRI (runs in worker cog). Remove mount checks (dispatch handles), remove lock/unlock:

| # | Method | Ref Lines | Reference PUB |
|---|---|---|---|
| 34 | `fl_open(p_fn, mode) : handle` | 504-594 | `open()` |
| 35 | `fl_open_circular(p_fn, mode, len) : handle` | 596-663 | `open_circular()` |
| 36 | `fl_close(handle) : status` | 703-728 | `close()` — also calls `fl_free_handle` |
| 37 | `fl_flush(handle) : status` | 665-700 | `flush()` |
| 38 | `fl_read(handle, p_buf, count) : bytes` | 1205-1251 | `read()` |
| 39 | `fl_write(handle, p_buf, count) : bytes` | 1079-1123 | `write()` |
| 40 | `fl_seek(handle, pos, whence) : end_pos` | 1003-1076 | `seek()` |
| 41 | `fl_delete(p_fn) : status` | 792-822 | `delete()` |
| 42 | `fl_rename(p_cur, p_new) : status` | 731-789 | `rename()` |
| 43 | `fl_exists(p_fn) : bool` | 899-917 | `exists()` |
| 44 | `fl_file_size(p_fn) : bytes` | 920-944 | `file_size()` |
| 45 | `fl_stats() : used, free, files` | 1417-1447 | `stats()` |
| 46 | `fl_directory(p_id, p_fn, p_sz) : status` | 1380-1414 | `directory()` |
| 47 | `fl_create_file(p_fn, fill, count) : status` | 825-896 | `create_file()` |

---

## Step 8: Wire Worker Command Dispatch

Add cases in `fs_worker()` (before `other:` at ~line 1074). Pattern:

```spin2
CMD_FLASH_OPEN:
  switch_to_flash()
  pb_data0 := fl_open(pb_param0, pb_param1)
  switch_to_sd()
  pb_status := pb_data0 < 0 ? pb_data0 : SUCCESS

CMD_FLASH_CLOSE:
  switch_to_flash()
  pb_status := fl_close(pb_param0)
  switch_to_sd()
```

All 14 CMD_FLASH_* codes (52-65) dispatched this way. For `CMD_FLASH_STATS` (returns 3 values), use `pb_data0`, `pb_data1`, `pb_data2`.

---

## Step 9: Update PUB API Routing

Update the existing PUB stubs that currently return `E_NOT_MOUNTED` for `DEV_FLASH`:

**Device-parameter PUBs** — `exists()`, `file_size()`, `stats()`, `deleteFile()`, `rename()`, `open()`, `open_circular()`, `create_file()`: add `DEV_FLASH` case that calls `send_command(CMD_FLASH_*, ...)`.

**Handle-based PUBs** — `readHandle()`, `writeHandle()`, `seekHandle()`, `closeFileHandle()`, `syncHandle()`, `tellHandle()`, `eofHandle()`, `fileSizeHandle()`: check `h_device[handle]` and route to `CMD_FLASH_*` when `DEV_FLASH`.

For `openFileRead`/`openFileWrite`/`createFileNew` (DEV_FLASH): map to `CMD_FLASH_OPEN` with the appropriate FILEMODE_* constant.

---

## Step 10: Verification Test

Create `src/DUAL_RT_phase3_verify.spin2` (~40 tests, 11 groups):

1. **SD regression** (5): init, mount, SD write/read round-trip
2. **Flash mount** (2): mount, mounted check
3. **Flash exists + file_size** (4): exists(nonexistent)=false, create_file, exists=true, file_size
4. **Flash write/read round-trip** (8): open-write, write data, close, open-read, read, compare, close, file_size
5. **Flash append** (4): open-append, write more, close, verify combined length
6. **Flash seek** (3): open-read, seek to offset, read from there, verify
7. **Flash delete** (3): delete, exists=false, file_size=error
8. **Flash rename** (3): rename, exists(old)=false, exists(new)=true
9. **Flash stats** (2): returns non-negative values, file_count matches
10. **SD regression after Flash ops** (3): SD still works after all Flash operations
11. **Stack guard** (1): checkStackGuard() intact

Run: `tools/run_test.sh ../src/DUAL_RT_phase3_verify.spin2 -t 120`

---

## Implementation Order

1. Constants + DAT additions (Step 1)
2. `fl_activate_updated_block` (Step 2)
3. Non-SPI helpers (Step 3)
4. Block-chain read helpers (Step 4)
5. Write helpers (Step 5)
6. Core I/O engine (Step 6)
7. Top-level operations (Step 7)
8. Worker dispatch wiring (Step 8)
9. PUB API routing (Step 9)
10. Verification test (Step 10)

Compile-check after each step with `pnut-ts -d DUAL_RT_phase2_verify.spin2` (uses dual_fs.spin2).

---

## Risks & Mitigations

- **Stack overflow**: Adding ~47 PRI methods increases call depth. Deepest chain is ~5 deep (dispatch → fl_open → fl_finish_open_append → fl_start_modify → fl_locate_file_byte). Current 256 LONGs should suffice; stack guard catches overflow. Bump to 384 if needed.

- **Hub RAM**: Flash state adds ~35KB (6 x 4KB buffers, translation tables). P2 has 512KB — well within budget.

- **Bus switch overhead**: Every Flash dispatch does switch_to_flash/switch_to_sd (~100ms for SD recovery). Acceptable for file-level ops. Future lazy-switch optimization deferred.

- **Name collisions**: All Flash methods use `fl_` prefix. Spin2 is case-insensitive; no SD methods start with `fl_`.

- **Missing `fl_activate_updated_block`**: Identified during planning. Must be ported before write helpers.
