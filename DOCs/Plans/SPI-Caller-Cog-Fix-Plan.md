# Plan: Fix SPI-from-Caller-Cog Violations + Cross-Flag Dependencies

## Context

An audit of `src/dual_sd_fat32_flash_fs.spin2` found **6 PUB methods** that perform SPI operations directly from the caller's cog instead of routing through the worker cog via `send_command()`. The worker cog owns the SPI pins — no other cog can drive them. These bugs were inherited from the reference SD driver (`micro_sd_fat32_fs.spin2`) where they were also broken.

Additionally, **2 cross-flag compilation dependencies** were found where methods under one `#IFDEF` guard call methods under a different guard, and **1 misplaced method** was found in the wrong `#IFDEF` block.

This plan covers:
1. Fixing all issues in the unified driver
2. Creating a standalone findings document for the reference driver maintainer

## Deliverable 1: Unified Driver Fixes

### File: `src/dual_sd_fat32_flash_fs.spin2`

---

### Fix A1: `testCMD13()` (line 5173, `SD_INCLUDE_RAW`)

**Bug**: Sends CMD13 directly via `sp_transfer_8()`, `pinl(cs)`, `pinh(cs)` from caller cog.

**Fix**: Add `CMD_TEST_CMD13 = 82` under `SD_INCLUDE_RAW`. Move the SPI sequence into `do_test_cmd13()` PRI. PUB becomes a `send_command()` wrapper.

New CON (under `SD_INCLUDE_RAW`, after line 116):
```spin2
  CMD_TEST_CMD13     = 82    ' Test CMD13: returns R2 response in data0
```

New worker dispatch case (under `SD_INCLUDE_RAW`, after existing RAW cases):
```spin2
      CMD_TEST_CMD13:
        pb_data0 := do_test_cmd13()
        pb_status := SUCCESS
```

New PRI (under `SD_INCLUDE_RAW`, near other `do_*` methods ~line 1789):
```spin2
PRI do_test_cmd13() : r2_response | r1, status
  ' [move entire SPI sequence from current testCMD13 here]
  ' Same code: pinh(cs), sp_transfer_8, waitR1Response, etc.
  ' Return r2_response (WORD)
```

Rewritten PUB (stays under `SD_INCLUDE_RAW`):
```spin2
PUB testCMD13() : r2_response
  if cog_id == -1
    return $FFFF
  send_command(CMD_TEST_CMD13, 0, 0, 0, 0)
  r2_response := LONG[@saved_data0][COGID()]
  ' [keep all debug output decoding — it only reads r2_response, no SPI]
```

---

### Fix A2: `attemptHighSpeed()` (line 5833, `SD_INCLUDE_SPEED`)

**Bug**: Calls `queryHighSpeedSupport()` → `readSCR()` + `sendCMD6()`, then `switchToHighSpeed()` → `sendCMD6()`, then `setSPISpeed()`, `readSector()`, `writeSector()` — all direct SPI from caller cog.

**Fix**: Add `CMD_ATTEMPT_HIGH_SPEED = 83` under `SD_INCLUDE_SPEED`. The entire multi-step sequence (query → switch → speed change → verify read/write) runs in the worker cog.

New CON (under `SD_INCLUDE_SPEED`):
```spin2
  CMD_ATTEMPT_HIGH_SPEED = 83  ' Attempt 50 MHz high-speed: returns data0=boolean
```

New worker dispatch case (under `SD_INCLUDE_SPEED`):
```spin2
      CMD_ATTEMPT_HIGH_SPEED:
        pb_data0 := do_attempt_high_speed()
        pb_status := SUCCESS
```

New PRI (under `SD_INCLUDE_SPEED`):
```spin2
PRI do_attempt_high_speed() : hs_ok | i, mismatch
  ' [move entire sequence from current attemptHighSpeed here]
  ' All helper calls (queryHighSpeedSupport, switchToHighSpeed, setSPISpeed,
  '   readSector, writeSector) now run in worker cog context — correct.
  '
  ' CRITICAL: Worker cog stack is only 1024 bytes (STACK_SIZE=256 longs).
  ' Cannot use 1024 bytes of stack-local buffers (test_buf[128] + verify_buf[128]).
  ' Instead, use existing DAT buffers owned by the worker:
  '   - @buf (512 bytes, BUF_DATA) — used for read/write/verify
  '   - @dir_buf (512 bytes, BUF_DIR) — used as "saved copy" for comparison
  '
  ' Algorithm:
  '   1. readSector(root_sec, BUF_DATA) → data in @buf
  '   2. bytemove(@dir_buf, @buf, 512) → save original to dir_buf
  '   3. writeSector(root_sec, BUF_DATA) → write @buf back to card
  '   4. bytefill(@buf, $AA, 512) → poison @buf
  '   5. readSector(root_sec, BUF_DATA) → re-read into @buf
  '   6. Compare @dir_buf vs @buf long-by-long → count mismatches
  '   7. If mismatches: setSPISpeed(25_000_000) fallback
  '
  ' After return, invalidate dir cache: dir_sec_in_buf := -1
```

Rewritten PUB:
```spin2
PUB attemptHighSpeed() : hs_ok
  if cog_id == -1
    return false
  send_command(CMD_ATTEMPT_HIGH_SPEED, 0, 0, 0, 0)
  hs_ok := LONG[@saved_data0][COGID()]
```

**Stack safety**: The original `attemptHighSpeed()` used 1024 bytes of stack locals (`test_buf[128]` + `verify_buf[128]`). The worker cog stack is only 1024 bytes total (`STACK_SIZE=256` longs). The worker-cog version avoids this by reusing existing DAT buffers (`@buf` and `@dir_buf`) instead of stack locals. Only `i` and `mismatch` go on the stack (~8 bytes). After return, `dir_sec_in_buf` must be invalidated since we borrowed `@dir_buf`.

---

### Fix A3: `checkHighSpeedCapability()` (line 5957, `SD_INCLUDE_SPEED`)

**Bug**: Calls `sendCMD6()` which does direct SPI from caller cog.

**Fix**: Add `CMD_CHECK_HS_CAPABILITY = 84` under `SD_INCLUDE_SPEED`.

New CON (under `SD_INCLUDE_SPEED`):
```spin2
  CMD_CHECK_HS_CAPABILITY = 84  ' Check CMD6 high-speed support: returns data0=boolean
```

New worker dispatch case:
```spin2
      CMD_CHECK_HS_CAPABILITY:
        pb_data0 := do_check_hs_capability()
        pb_status := SUCCESS
```

New PRI:
```spin2
PRI do_check_hs_capability() : capable | status[16]
  if not sendCMD6($00FFFFF1, @status)
    return false
  return (status.byte[13] & $02) <> 0
```

Rewritten PUB:
```spin2
PUB checkHighSpeedCapability() : capable
  if cog_id == -1
    return false
  send_command(CMD_CHECK_HS_CAPABILITY, 0, 0, 0, 0)
  capable := LONG[@saved_data0][COGID()]
```

---

### Fix A4: `setSPISpeed()` (line 7924, **ungated**)

**Bug**: Directly writes `wxpin(sck, ...)` and `pinl(sck)` — reconfigures shared SPI clock pin from caller cog.

**Current internal callers** (all safe — run in worker cog context):
- `initCard()` (line 3123, 3197, 3199) — during mount
- `setOptimalSpeed()` (line 5705, 5710, 5712) — during mount
- `reinitCard()` (line 8147) — during bus switch

**Only unsafe caller**: `attemptHighSpeed()` — but Fix A2 moves that into the worker cog, so it becomes safe.

**Fix**: Make `setSPISpeed` PRI. All current callers are internal (worker cog context). After Fix A2, `attemptHighSpeed()` calls it from within the worker too.

If external speed control is needed in the future, add a `CMD_SET_SPI_SPEED` worker command then. For now, no external caller needs it.

```spin2
PRI setSPISpeed(freq) | half_period, actual_freq
  ' [unchanged implementation]
```

**Impact**: External objects can no longer call `setSPISpeed()` directly. This is correct — external callers have no business reconfiguring the SPI clock while the worker cog is running.

---

### Fix A5: `debugDumpRootDir()` (line 7524, `SD_INCLUDE_DEBUG`)

**Bug**: Calls `readSector(root_sec, BUF_DIR)` directly from caller cog.

**Fix**: Use existing `CMD_READ_SECTOR_RAW` to read the sector through the worker cog into a local buffer, then parse entries from the local buffer.

```spin2
PUB debugDumpRootDir() | sec, i, p_entry, local_buf[128]
  sec := root_sec
  if send_command(CMD_READ_SECTOR_RAW, sec, @local_buf, 0, 0) <> SUCCESS
    debug("  [debugDumpRootDir] FAILED to read root directory sector")
    return
  repeat i from 0 to 15
    p_entry := @local_buf + (i * 32)
    ' [same entry parsing, using local_buf instead of dir_buf]
```

**No new command needed** — reuses `CMD_READ_SECTOR_RAW`.

---

### Fix A6: `displayFAT()` (line 9213, `SD_INCLUDE_DEBUG`)

**Bug**: Calls `readSector(n_sec, BUF_DATA)` directly from caller cog.

**Fix**: Same approach as A5 — use `CMD_READ_SECTOR_RAW` into a local buffer.

```spin2
PUB displayFAT(cluster) | n_sec, local_buf[128]
  n_sec := fat_sec + cluster >> 7
  if send_command(CMD_READ_SECTOR_RAW, n_sec, @local_buf, 0, 0) <> SUCCESS
    debug("  [displayFAT] FAILED to read FAT sector")
    return
  ' displaySector() reads @buf — need to copy or inline the display logic
  ' Option 1: bytemove(@buf, @local_buf, 512) then call displaySector()
  ' Option 2: pass buffer pointer to a modified displaySector
```

**Decision needed**: `displaySector()` currently reads from `@buf` (a DAT variable). Options:
- Copy local_buf into buf before calling displaySector (simplest, slight race if worker writes buf concurrently)
- The worker won't write buf while we hold the lock from send_command... actually we don't hold the lock after send_command returns.
- Safest: copy to buf right after send_command returns and call displaySector. The worker only touches buf when processing a command, and we're not sending another command.

Use Option 1: `bytemove(@buf, @local_buf, 512)` then `displaySector()`.

---

### Fix B1/C1: `readVBRRaw()` (line 5411, currently `SD_INCLUDE_REGISTERS`)

**Bug**: Misplaced — reads a raw sector, not a card register. Creates cross-flag dependency because it uses `CMD_READ_SECTOR_RAW`.

**Fix**: Move `readVBRRaw()` from the `SD_INCLUDE_REGISTERS` block to the `SD_INCLUDE_RAW` block. It already correctly uses `send_command(CMD_READ_SECTOR_RAW, ...)` — no SPI violation, just wrong guard.

After moving, `CMD_READ_SECTOR_RAW` stays outside guards (it's used by debug methods too — see A5/A6). The comment changes from "always available for readVBRRaw" to "always available — used by readVBRRaw, debugDumpRootDir, displayFAT".

---

### Fix B2: `checkCMD6Support()` (line 5942, `SD_INCLUDE_SPEED`) calls `readSCRRaw()` (`SD_INCLUDE_REGISTERS`)

**Bug**: Cross-flag dependency — enabling SPEED without REGISTERS won't compile.

**Fix**: Document that `SD_INCLUDE_SPEED` requires `SD_INCLUDE_REGISTERS`. Add a compile-time guard:

```spin2
#IFDEF SD_INCLUDE_SPEED
#IFNDEF SD_INCLUDE_REGISTERS
  THIS IS A DELIBERATE COMPILE ERROR — SD_INCLUDE_SPEED requires SD_INCLUDE_REGISTERS
#ENDIF
```

(pnut-ts will error on undefined symbol, which is the desired behavior.)

Alternatively, if pnut-ts supports `#ERROR` or if a bare unknown symbol causes a clear error, use that. The goal is a clear message at compile time rather than a cryptic undefined-method error.

Also add a comment in the CON pragma documentation block:

```spin2
''   #PRAGMA EXPORTDEF SD_INCLUDE_SPEED      ' High-speed mode (requires SD_INCLUDE_REGISTERS)
```

---

### `CMD_READ_SECTOR_RAW` Placement

`CMD_READ_SECTOR_RAW` remains **outside all `#IFDEF` guards** (always compiled). It's infrastructure used by:
- `readSectorRaw()` (SD_INCLUDE_RAW)
- `readVBRRaw()` (SD_INCLUDE_RAW, after move)
- `debugDumpRootDir()` (SD_INCLUDE_DEBUG)
- `displayFAT()` (SD_INCLUDE_DEBUG)

Update the comment on line 109:
```spin2
  CMD_READ_SECTOR_RAW  = 20 ' Raw single sector read (infrastructure — used across multiple feature flags)
```

---

### New Command Code Summary

| Code | Name | Guard | Used by |
|------|------|-------|---------|
| 82 | `CMD_TEST_CMD13` | `SD_INCLUDE_RAW` | `testCMD13()` |
| 83 | `CMD_ATTEMPT_HIGH_SPEED` | `SD_INCLUDE_SPEED` | `attemptHighSpeed()` |
| 84 | `CMD_CHECK_HS_CAPABILITY` | `SD_INCLUDE_SPEED` | `checkHighSpeedCapability()` |

No new command needed for `setSPISpeed` (becomes PRI), `debugDumpRootDir`, or `displayFAT` (reuse CMD_READ_SECTOR_RAW).

---

### Worker Cog Stack Safety

Worker cog stack: `STACK_SIZE = 256` longs = 1024 bytes (line 275).

`do_attempt_high_speed()` reuses existing DAT buffers (`@buf` + `@dir_buf`) instead of stack locals — only `i` + `mismatch` on stack (~8 bytes). No stack size increase needed.

`do_test_cmd13()` uses `r1` + `status` on stack (~8 bytes). Safe.

`do_check_hs_capability()` uses `status[16]` on stack = 64 bytes. Safe (well within 1024).

---

## Deliverable 2: Reference Driver Findings Document

Create `DOCs/Reference/REF-DRIVER-SPI-AUDIT.md` — a standalone document listing all SPI-from-caller-cog bugs found in `REF-FLASH-uSD/uSD-FAT32/src/micro_sd_fat32_fs.spin2`.

### Content

For each bug, document:
- Method name, line number, `#IFDEF` guard
- The SPI call chain (PUB → PRI → SPI function)
- Why it's broken (caller cog can't drive worker-owned SPI pins)
- Suggested fix approach

### Bugs to document (7 methods):

| # | Method | Line | Guard | Call Chain |
|---|--------|------|-------|------------|
| 1 | `readVBRRaw()` | 2982 | `SD_INCLUDE_REGISTERS` | → `readSector()` → streamer SPI |
| 2 | `testCMD13()` | 2747 | `SD_INCLUDE_RAW` | direct `sp_transfer_8`, `pinl(cs)`, `pinh(cs)` |
| 3 | `attemptHighSpeed()` | 3404 | `SD_INCLUDE_SPEED` | → `queryHighSpeedSupport()` → `readSCR()` + `sendCMD6()` + `setSPISpeed()` + `readSector()` + `writeSector()` |
| 4 | `checkHighSpeedCapability()` | 3528 | `SD_INCLUDE_SPEED` | → `sendCMD6()` → `sp_transfer_8`, pin control |
| 5 | `setSPISpeed()` | 4738 | (none) | direct `wxpin(sck)`, `pinl(sck)` |
| 6 | `debugDumpRootDir()` | 4338 | `SD_INCLUDE_DEBUG` | → `readSector()` → streamer SPI |
| 7 | `displayFAT()` | 6014 | `SD_INCLUDE_DEBUG` | → `readSector()` → streamer SPI |

Cross-flag issue:
| Method | Guard | Calls | That method's guard |
|--------|-------|-------|---------------------|
| `checkCMD6Support()` | `SD_INCLUDE_SPEED` | `readSCRRaw()` | `SD_INCLUDE_REGISTERS` |

Misplacement:
| Method | Current guard | Should be |
|--------|---------------|-----------|
| `readVBRRaw()` | `SD_INCLUDE_REGISTERS` | `SD_INCLUDE_RAW` (reads a sector, not a register) |

---

## Implementation Order

1. Add new CMD constants (82, 83, 84)
2. Add `do_test_cmd13()`, `do_attempt_high_speed()`, `do_check_hs_capability()` PRI methods
3. Add worker dispatch cases for new commands
4. Rewrite PUB wrappers: `testCMD13()`, `attemptHighSpeed()`, `checkHighSpeedCapability()`
5. Change `setSPISpeed()` from PUB to PRI
6. Fix `debugDumpRootDir()` and `displayFAT()` to use `CMD_READ_SECTOR_RAW` + local buffer
7. Move `readVBRRaw()` from `SD_INCLUDE_REGISTERS` to `SD_INCLUDE_RAW`
8. Add compile-time guard for SPEED→REGISTERS dependency
9. Update `CMD_READ_SECTOR_RAW` comment
10. Create `DOCs/Reference/REF-DRIVER-SPI-AUDIT.md`
11. Compile and verify

## Verification

1. **Compile clean**: `pnut-ts -d dual_sd_fat32_flash_fs.spin2`
2. **Compile all regression tests**: `./run_all_regression.sh --compile-only`
3. **Compile all utilities/examples**: Each file in `src/UTILS/`, `src/EXAMPLES/`, `src/DEMO/`
4. **Hardware regression** (if available): Full `./run_all_regression.sh`
5. **Verify no PUB method does direct SPI**: Re-run the audit grep to confirm zero violations remain
6. **Verify flag isolation**: Compile with each flag individually to confirm no cross-flag errors
