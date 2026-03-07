# R1 Response Bit-7 Fix Plan

**Date:** 2026-03-07
**Source:** `DOCs/procedures/R1-BIT7-FIX-ENGINEERING-GUIDE.md`
**Target:** `src/dual_sd_fat32_flash_fs.spin2`
**Scope:** Fix all R1 response detection loops to skip bytes with bit 7 set (SD spec 7.3.2.1)

---

## Problem

The driver accepts the first non-$FF byte as R1 response. The SD spec requires bit 7 = 0 for valid R1. Pre-response bus artifacts ($C1, $FE, etc.) have bit 7 set and are not R1 responses. Cards like AData 16GB return $C1 before the real R1 ($00), causing false CMD13-unreliable diagnosis.

## Fix Pattern

**Detection loop only** (not post-loop evaluation):
- Before: `if resp <> $FF` (or `ok <> $FF`, `response <> $FF`)
- After: `if (resp & $80) == 0` (or `(ok & $80) == 0`, `(response & $80) == 0`)

---

## Task List

### Task 1: Fix cmd() R1 Detection Loop

In `cmd()` (~line 9181), change the R1 detection from `if response <> $FF` to `if (response & $80) == 0`. This is the central command dispatch used by all standard SD commands (CMD0, CMD8, CMD17, CMD18, CMD23, CMD24, CMD25, CMD41, CMD55, CMD58). The loop reads single bytes via `sp_transfer(-1,8)` and currently accepts the first non-$FF byte. After this fix, it will skip bus artifacts with bit 7 set and accept only valid R1 bytes. The post-loop logic (CMD8/CMD58 32-bit response reading, CS deassert decisions) is unchanged -- it already correctly handles the R1 value once detected. Compile-check after.

### Task 2: Fix waitR1Response() R1 Detection Loop

In `waitR1Response()` (~line 9875), change `if resp <> $FF` to `if (resp & $80) == 0`. This shared helper is used by `probeCmd13()`, `checkCardStatus()`, and `do_test_cmd13()`. Fixing it here automatically fixes R1 detection for all three callers. The post-loop `response := resp` assignment and timeout path are unchanged. Compile-check after.

### Task 3: Fix readCSD() R1 Detection Loop

In `readCSD()` (~line 10227), change the first R1 detection loop from `if ok <> $FF` to `if (ok & $80) == 0`. This is the CMD9 response loop. The second loop (waiting for $FE data token at ~line 10244) must NOT change -- it waits for a specific data token value, not R1. The post-loop `if ok <> $00` / `if ok <> $FF` evaluation is unchanged. Compile-check after.

### Task 4: Fix readCID() R1 Detection Loop

In `readCID()` (~line 10285), change the first R1 detection loop from `if ok <> $FF` to `if (ok & $80) == 0`. Same pattern as readCSD -- CMD10 response loop. The data token loop ($FE) at ~line 10302 must NOT change. Post-loop evaluation unchanged. Compile-check after.

### Task 5: Fix readSCR() Two R1 Detection Loops

In `readSCR()`, fix BOTH R1 detection loops. First loop (~line 10533): CMD55 response -- change `if ok <> $FF` to `if (ok & $80) == 0`. Second loop (~line 10563): ACMD51 response -- change `if ok <> $FF` to `if (ok & $80) == 0`. The data token loop ($FE) at ~line 10582 must NOT change. Post-loop evaluations (`if ok <> $FF` at ~lines 10543, 10573) are unchanged -- those check whether the loop timed out vs found a valid R1 with error bits. Compile-check after.

### Task 6: Fix readSDStatus() Two R1 Detection Loops

In `readSDStatus()`, fix BOTH R1 detection loops. First loop (~line 10632): CMD55 response -- change `if ok <> $FF` to `if (ok & $80) == 0`. Second loop (~line 10662): ACMD13 response -- change `if ok <> $FF` to `if (ok & $80) == 0`. The data token loop ($FE) must NOT change. Post-loop evaluations unchanged. Compile-check after.

### Task 7: Fix sendCMD6() R1 Detection Loop

In `sendCMD6()` (~line 10730), change `if ok <> $FF` to `if (ok & $80) == 0`. This is the CMD6 (high-speed mode switch) R1 detection. Post-loop evaluation unchanged. Compile-check after.

### Task 8: Full Compile-Check and Hardware Regression

Clear all .obj files. Compile-check the driver standalone, then run `run_regression.sh --compile-only` for all 29 test suites. Then run full hardware regression. All 1,308 tests should pass with 0 failures. The fix should be transparent to cards that already worked.

---

## Explicit DO NOT CHANGE List

| Location | Why |
|---|---|
| `sendStopTransmission()` ~line 9991 | CMD12 mid-stream -- file data has arbitrary bit patterns |
| `waitDataToken()` ~line 9903 | Waits for $FE data token, not R1 |
| `waitDataResponse()` ~line 9927 | Write data-response token format, not R1 |
| `writeSector()` ~line 9683 | Write data-response, not R1 |
| `readSectors()` CMD23 verify ~line 9513 | Checking if card stopped outputting, not R1 |
| All post-loop `if ok <> $FF` checks | Evaluating R1 value after loop (timeout vs error), not detection |
| `waitBusyComplete()` | Waits for $00->$FF busy end, not R1 |

---

## Total Changes

9 R1 detection loops across 7 methods. Each is a single-line change: `<> $FF` to `(& $80) == 0`.
