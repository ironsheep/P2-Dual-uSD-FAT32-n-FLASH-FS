# SPI Backend Consolidation Plan

**Date:** 2026-03-07
**Source:** `DOCs/Plans/SPI-BACKEND-CONSOLIDATION-GUIDE.md` (engineering guide from sister project)
**Target:** `src/dual_sd_fat32_flash_fs.spin2`
**Scope:** Extract 3 shared methods from duplicated SPI transaction code, reducing ~286 lines. Pure refactoring -- no behavioral changes.

---

## Pre-Implementation Analysis

### Current State of the Dual Driver

The guide was written for the sister standalone SD project. The dual driver has some differences:

| Item | Guide Assumes | Dual Driver Has | Action Needed |
|---|---|---|---|
| CMD6, CMD9, CMD10 constants | Named CON constants | Literal numbers (`$40 \| 9`) | Add constants |
| CMD55, ACMD51 constants | Named CON constants | Literal numbers (`$40 \| 55`, `$40 \| 51`) | Add constants |
| CRC_CMD9, CRC_CMD10, etc. | Named CON constants | Hardcoded hex values | Add constants |
| `cmd13_pre_capture[]` DAT | Exists | Does NOT exist | Add DAT variables |
| `cmd13_capture[]` DAT | Exists | Does NOT exist | Add DAT variables |
| `cmd13_capture_len` DAT | Exists | Does NOT exist | Add DAT variable |
| `test_force_cmd13` | Used in checkCardStatus guard | Does NOT exist | Omit from plan (not needed) |
| `checkCardStatus()` error returns | Uses `E_TIMEOUT`, `E_IO_ERROR` | Returns `-1` on error | Keep existing `-1` convention to avoid behavioral change |
| `probeCmd13()` implementation | Uses inline CMD13 with capture | Uses `waitR1Response()` helper | Rewrite to use `sendCmd13Transaction()` |
| `checkCardStatus()` implementation | Uses inline CMD13 with capture | Uses `waitR1Response()` helper | Rewrite to use `sendCmd13Transaction()` |

### Methods to Refactor (7 total)

| Method | Line | Current Size | After | Savings |
|---|---|---|---|---|
| `readCSD()` | 10207 | ~57 lines | ~3 lines | ~54 |
| `readCID()` | 10265 | ~59 lines | ~3 lines | ~56 |
| `sendCMD6()` | 10709 | ~60 lines | ~3 lines | ~57 |
| `readSCR()` | 10509 | ~98 lines | ~8 lines | ~90 |
| `readSDStatus()` | 10608 | ~97 lines | ~8 lines | ~89 |
| `probeCmd13()` | 10042 | ~52 lines | ~30 lines | ~22 |
| `checkCardStatus()` | 10127 | ~78 lines | ~35 lines | ~43 |

### New Methods (3 total)

| Method | Purpose | Size |
|---|---|---|
| `readDataRegister()` | Consolidated register read (cmd + R1 + $FE + data + CRC + deselect) | ~35 lines |
| `sendAppCmdPrefix()` | CMD55 prefix for ACMD commands | ~3 lines |
| `sendCmd13Transaction()` | CMD13 wire transaction with full-duplex capture | ~55 lines |

### Explicit DO NOT CHANGE List

| Code | Why |
|---|---|
| Streamer PASM blocks (readSector, readSectors, writeSector, writeSectors) | Inline PASM by necessity |
| Smart pin disable/re-enable around streamer | Tightly coupled to PASM blocks |
| readSector data token wait | Integrated with CRC retry loop |
| writeSector data-response/busy waits | Diagnostic staging differences |
| `cmd()` CRC logic | CMD0/CMD8 only, not register reads |
| `sendStopTransmission()` | CMD12 is unique (stuff byte, mid-stream) |
| `readSectorSlow()` | DEBUG-only, deliberately different |

---

## Task List (Ordered: Foundational to Derived)

### Task 1: Add SD Command Number Constants

Add named constants for SD commands currently used as literals. In the existing CON block at line ~423 (after `CMD0 = 0`), add the missing command numbers in numerical order: `CMD6 = 6` (SWITCH_FUNC), `CMD9 = 9` (SEND_CSD), `CMD10 = 10` (SEND_CID), `CMD55 = 55` (APP_CMD), and `ACMD51 = 51` (SEND_SCR). Keep the existing CMD0, CMD12, CMD13, CMD18, CMD23, CMD25. Reorder the block numerically (CMD0, CMD6, CMD9, CMD10, CMD12, CMD13, CMD18, CMD23, CMD25, CMD55, ACMD51) with inline comments matching the existing style. These constants are foundational -- all subsequent tasks reference them by name. Compile-check after.

### Task 2: Add CRC Constants

Add pre-computed CRC-7 constants to the CON block immediately after the existing `CRC_CMD12 = $61` at line ~433. Add: `CRC_CMD9 = $AF` (SEND_CSD), `CRC_CMD10 = $1B` (SEND_CID), `CRC_CMD55 = $65` (APP_CMD), `CRC_ACMD51 = $55` (SEND_SCR), `CRC_NONE = $FF` (CRC not validated in SPI mode after init -- used by CMD6 and ACMD13). Group all CRC constants together with a section comment. The existing `CRC_CMD12` stays where it is. Compile-check after.

### Task 3: Add CMD13 Diagnostic Capture DAT Variables

Add CMD13 capture buffer DAT variables in the diagnostic state section after the existing `last_cmd13_error WORD 0` at line ~538. Add: `cmd13_pre_capture BYTE 0[7]` (full-duplex MISO during CMD13 transmission -- 6 command bytes + 1 padding), `cmd13_capture BYTE 0[8]` (raw post-command byte stream for diagnostic inspection), `cmd13_capture_len BYTE 0` (number of bytes before R1 appeared, i.e., NCR gap length). These are needed by `sendCmd13Transaction()` in Task 7. Each gets an inline comment describing its purpose. Compile-check after.

### Task 4: Add `readDataRegister()` Shared Method

Add a new PRI method `readDataRegister(cmd_num, arg, crc_byte, p_buf, byte_count) : result` immediately BEFORE `readCSD()` at line ~10207. This consolidates the "Shape D" register read transaction used by all 5 register-read methods. The implementation follows the guide exactly: (1) pre-command dummy clock, (2) CS LOW, (3) send command byte (`$40 | cmd_num`), 32-bit argument via `sp_transfer()`, and CRC byte, (4) wait for R1 with bit-7 check and 1-second timeout, (5) if R1 == $00, wait for $FE data token with 1-second timeout, (6) if $FE received, read `byte_count` bytes into `p_buf`, consume 2-byte CRC, set `result := TRUE`, (7) CS HIGH (single deselect point -- all paths converge here). Default `result` is FALSE (Spin2 default 0). No early returns -- all error paths fall through to the final `pinh(cs)`. The R1 loop uses `(resp & $80) == 0` per the bit-7 fix already applied elsewhere. Compile-check after.

### Task 5: Refactor readCSD(), readCID(), and sendCMD6() to Use readDataRegister()

Replace the entire body of `readCSD()` (lines ~10207-10263) with a single call: `ok := readDataRegister(CMD9, 0, CRC_CMD9, p_csd, 16)`. Remove the now-unnecessary local variables (`timeout`, `idx`). Keep the doc comment, update `@returns` to remove `@local` lines. Similarly, replace `readCID()` (lines ~10265-10324) with: `ok := readDataRegister(CMD10, 0, CRC_CMD10, p_cid, 16)`. And replace `sendCMD6()` (lines ~10709-10768, inside `#IFDEF SD_INCLUDE_SPEED`) with: `ok := readDataRegister(CMD6, arg, CRC_NONE, p_status, 64)`. For sendCMD6, note it passes `arg` (non-zero) and reads 64 bytes. Each method drops from ~55-60 lines to ~3 lines. Compile-check after all three are done.

### Task 6: Add `sendAppCmdPrefix()` Shared Method

Add a new PRI method `sendAppCmdPrefix() : resp` immediately BEFORE `readSCR()`. This sends CMD55 via the existing `cmd()` function, then deasserts CS for the ACMD to follow. Implementation: `resp := cmd(CMD55, 0)` followed by `pinh(cs)`. The `cmd()` function handles the full CMD55 transaction (command byte, argument, CRC, R1 wait). CS deassert is needed because ACMD commands require a fresh CS assertion cycle. Note: `cmd()` keeps CS asserted after CMD55 because CMD55 is not in its deassert exclusion list -- actually verify this by checking `cmd()`'s post-command CS logic. If `cmd()` already deasserts for CMD55, the extra `pinh(cs)` is harmless. The method returns the R1 response so callers can check for errors. Compile-check after.

### Task 7: Refactor readSCR() and readSDStatus() to Use sendAppCmdPrefix() + readDataRegister()

Replace `readSCR()` (lines ~10509-10606, currently ~98 lines) with: call `sendAppCmdPrefix()`, check response (accept $00 or $01), then call `readDataRegister(ACMD51, 0, CRC_ACMD51, p_scr, 8)`. The method drops to ~8 lines. Keep the debug messages for CMD55 error. Similarly, replace `readSDStatus()` (lines ~10608-10705, currently ~97 lines) with: call `sendAppCmdPrefix()`, check response, then call `readDataRegister(CMD13, 0, CRC_NONE, p_buf, 64)`. Note that ACMD13 uses command code 13 (same as CMD13) -- the CMD55 prefix is what makes it application-specific. Remove now-unnecessary locals. Compile-check after both.

### Task 8: Add `sendCmd13Transaction()` Shared Method

Add a new PRI method `sendCmd13Transaction() : r1, status` immediately BEFORE `probeCmd13()`. This extracts the shared CMD13 wire transaction with full-duplex MISO capture. Implementation follows the guide: (1) Initialize capture buffers (`bytefill` cmd13_pre_capture to $FF, cmd13_capture to $FF, cmd13_capture_len to 0). (2) Send 2 dummy clocks with CS HIGH for card recovery. (3) CS LOW, send CMD13 byte-by-byte capturing MISO into `cmd13_pre_capture[0..5]` (6 bytes: command, 4 arg, CRC). (4) Scan for R1 with 100ms timeout and bit-7 check, capturing raw bytes into `cmd13_capture[0..7]`. On finding valid R1, record in `cmd13_capture_len` and `r1`. On timeout, set `last_cmd13_r1 := $FF`, deassert CS, and return with `r1 := -1`. (5) After R1, continue capturing remaining bytes up to 8 total. (6) STATUS byte is at `cmd13_capture[cmd13_capture_len]` (immediately after R1). (7) Deassert CS. (8) Stage diagnostics: `last_cmd13_r1 := r1`, `last_cmd13_status := status`, and if either is non-zero, `last_cmd13_error := (r1 << 8) | status`. Returns two values via Spin2 multiple return. Local variables: `idx`, `resp`, `timeout`. Compile-check after.

### Task 9: Refactor probeCmd13() and checkCardStatus() to Use sendCmd13Transaction()

Replace the wire transaction in `probeCmd13()` (lines ~10042-10093) with a call to `sendCmd13Transaction()`. The method becomes: `r1, status := sendCmd13Transaction()`, then the existing reliability analysis logic (timeout check, R1 bit-7 check, STATUS popcount check). Remove the inline CMD13 send (sp_transfer_8 sequence), the `waitR1Response()` call, and the manual `pinh(cs)` -- all handled by `sendCmd13Transaction()`. Similarly, replace the wire transaction in `checkCardStatus()` (lines ~10127-10205) with a call to `sendCmd13Transaction()`. The method becomes: early guard (`if not cmd13_reliable` then return), then `r1, status := sendCmd13Transaction()`, then the existing error interpretation (R1 check, STATUS bit decoding). Remove the inline CMD13 send, `waitR1Response()` call, and manual staging -- all handled by `sendCmd13Transaction()`. The error return values stay as-is (returns -1 for error, 0 for success, `E_TIMEOUT` for timeout) to avoid behavioral changes. Compile-check after both.

### Task 10: Full Compile-Check and Hardware Regression

Delete stale `.obj` files (`rm -f src/dual_sd_fat32_flash_fs.obj`). Compile the driver standalone: `cd src && pnut-ts -d dual_sd_fat32_flash_fs.spin2`. Run `tools/run_regression.sh --compile-only` to verify all 29+ test suites compile. Then run full hardware regression: `tools/run_regression.sh`. All tests must pass with 0 failures. This is pure refactoring -- if any test fails, the refactoring introduced a behavioral difference that must be investigated and fixed. Key areas to watch: card initialization (readCSD/readCID via identifyCard), CMD13 probe (probeCmd13 at end of init), post-operation CMD13 (checkCardStatus after every read/write), high-speed mode (sendCMD6 behind SD_INCLUDE_SPEED), SCR read (readSCR via probeCmd23).

---

## Risk Assessment

| Risk | Mitigation |
|---|---|
| `readDataRegister()` CS handling differs from inline code | Guide's single-deselect-point pattern is cleaner than per-branch deselect; verify all paths |
| `cmd()` CS behavior for CMD55 may differ from inline code | Verify `cmd()` post-command CS logic before writing `sendAppCmdPrefix()` |
| `sendCmd13Transaction()` changes CMD13 timing | 100ms timeout matches industry standard; existing code had implicit timeout via `waitR1Response()` |
| New CMD13 capture DAT adds ~16 bytes hub RAM | Negligible vs 512KB hub RAM; enables future diagnostic getters |
| `readSDStatus` uses CMD13 as ACMD13 command code | Correct per SD spec -- ACMD13 and CMD13 share command number 13; CMD55 prefix distinguishes them |

## Expected Outcome

- **Lines removed**: ~411 lines of duplicated inline SPI transactions
- **Lines added**: ~125 lines (3 new shared methods + constants + DAT variables)
- **Net reduction**: ~286 lines
- **Single code paths**: R1 detection, data token wait, register read, CMD13 transaction -- each implemented once
- **Future benefit**: 6-wire SD native mode requires modifying only 3 methods instead of 10+
