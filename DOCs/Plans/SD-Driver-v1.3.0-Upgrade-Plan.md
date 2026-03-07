# SD Driver v1.3.0 Upgrade Plan

**Date:** 2026-03-06
**Source:** `DOCs/procedures/DRIVER-V1.3.0-PORTING-GUIDE.md`
**Target:** `src/dual_sd_fat32_flash_fs.spin2` (unified dual-FS driver)
**Scope:** Port 8 changes (A-H) from standalone SD driver v1.2.0->v1.3.0 into the dual driver

---

## Pre-Implementation Analysis

### Method Name Mapping (source -> dual driver)

| Porting Guide Name | Dual Driver Equivalent | Line | Notes |
|---|---|---|---|
| `initCard()` | `initCard()` | ~8791 | PRI, identical name |
| `checkCardStatus()` | `checkCardStatus()` | ~9799 | PRI, identical name |
| `readSectors()` | `readSectors()` | ~9241 | PRI, identical name |
| `sendStopTransmission()` | `sendStopTransmission()` | ~9749 | PRI, identical name |
| `waitDataToken()` | `waitDataToken()` | ~9680 | PRI, identical name |
| `readSCR()` | `readSCR()` | ~10177 | PRI, exists and works |
| `do_mount()` | `do_mount()` | ~3935 | PRI, identical name |
| `do_init_card_only()` | `do_init_card_only()` | ~5482 | PRI, under `SD_INCLUDE_RAW` |
| `cmd()` | `cmd()` | ~8996 | PRI, identical name |

### Key Structural Observations

- **CON error codes**: Lines ~423-464 contain SD command codes and tokens
- **DAT diagnostic section**: Lines ~526-531 contain `last_cmd13_*` variables
- **PUB diagnostic getters**: Lines ~2886-2988 under `#IFDEF SD_INCLUDE_DEBUG`
- **Worker command dispatch**: Line ~3341 (`CMD_READ_SECTORS`), ~3363 (`CMD_TEST_CMD13`)
- **CRC_CMD12**: Not a named constant in dual driver; `sendStopTransmission()` uses literal `$61` at line 9761
- **`readSCR()` PRI**: Exists at line 10177, fully functional -- CMD23 probe can use it directly
- **`PARTITION_TYPE_FAT32_LBA`**: Not exported as a CON from the driver; fsck utility defines its own (`PARTITION_TYPE_FAT32_LBA = $0C` at isp_fsck_utility.spin2:56)
- **`v_warningCount`**: Already exists in isp_fsck_utility.spin2:212

### Compile Guard Decisions

- New diagnostic getters: Gate under `#IFDEF SD_INCLUDE_DEBUG` (matches existing `getLastCMD13()`)
- `cardWarnings()`: Always available (no guard) -- it's a status API like `canMount()`
- `probeCmd13()` / `probeCmd23()`: PRI methods, no guard needed (always compiled, called from `initCard()`)
- CMD23/CMD12 capture DAT vars: Always compiled (diagnostic getters read them conditionally)

---

## Task List (Ordered: Foundational -> Derived)

### Task 1: Add CON Constants for Card Warning Flags and CMD23

Add three new CON constant groups to `dual_sd_fat32_flash_fs.spin2`. First, after the existing SD command codes block (after line ~431 `CMD25 = 25`), add `CMD23 = 23` with a comment `SET_BLOCK_COUNT - pre-define sector count for CMD18/CMD25`. Second, after the data token constants block (after line ~464 `DATA_WRITE_ERROR`), add a new `CON` section titled `card warning/capability flags (bitmask, returned by cardWarnings())` containing three constants: `CW_NONE = $00` (no warnings), `CW_CMD13_UNRELIABLE = $01` (CMD13 probe failed at init), and `CW_CMD23_SUPPORTED = $02` (CMD23 confirmed working in SPI mode). These are bitmask values so they can be OR'd together. Also add `CRC_CMD12 = $61` as a named constant in the SD command codes block (replacing the literal `$61` currently used in `sendStopTransmission()` at line 9761). Compile-check with `pnut-ts -d dual_sd_fat32_flash_fs.spin2` after this task.

### Task 2: Add DAT Variables for CMD12/CMD18/CMD23 Diagnostics and Warning Flags

Add new DAT variables to the diagnostic state section of `dual_sd_fat32_flash_fs.spin2`, immediately after the existing `last_cmd13_error WORD 0` at line ~531. Add a new subsection header comment `CMD12/18/23 DIAGNOSTIC STATE` and add the following BYTE variables with their defaults: `cmd13_reliable BYTE TRUE` (FALSE if CMD13 probe failed), `cmd23_supported BYTE FALSE` (TRUE if CMD23 confirmed in SPI), `card_warning_flags BYTE CW_NONE` (advisory bitmask). Then add CMD18 diagnostics: `last_cmd18_r1 BYTE 0`, `last_cmd18_token BYTE 0`, `last_cmd18_result BYTE 0`, `last_cmd18_fail BYTE 0` (failure path 0-5), `last_cmd18_sread BYTE 0` (sectors_read snapshot). Then CMD12 diagnostics: `last_cmd12_r1 BYTE 0`, `last_cmd12_busy BYTE 0`, `cmd12_capture_len BYTE 0`, `cmd12_capture BYTE 0[16]` (raw byte stream after stuff byte), `cmd12_pre_capture BYTE 0[7]` (MISO during CMD12 transmission). Then CMD23 diagnostics: `last_cmd23_r1 BYTE 0`, `last_cmd23_verify BYTE 0`, `last_cmd23_used BYTE FALSE`. Each variable gets an inline comment describing its purpose and value meanings, matching the porting guide. Compile-check after this task.

### Task 3: Add PUB cardWarnings() and 14 Diagnostic Getter Methods

Add the `cardWarnings()` PUB method outside any `#IFDEF` guard (it's a status API), placed after the existing `canMount()`-style PUB methods or near the top of the PUB API section. It returns `card_warning_flags` (the bitmask DAT variable). Then, inside the existing `#IFDEF SD_INCLUDE_DEBUG` block (after line ~2988 `setTestForceWriteError`), add 14 new PUB getter methods, each a trivial one-liner returning the corresponding DAT variable. The methods are: `getLastCMD18R1() : r1` returns `last_cmd18_r1`; `getLastCMD18Token() : token` returns `last_cmd18_token`; `getLastCMD18Result() : code` returns `last_cmd18_result` (0=ok, 1=timeout, 2=error); `getLastCMD18FailPath() : path` returns `last_cmd18_fail` (0-5 per failure path table); `getLastCMD18SectorsRead() : count` returns `last_cmd18_sread`; `getLastCMD12R1() : r1` returns `last_cmd12_r1`; `getLastCMD12Result() : code` returns `last_cmd12_busy` (0=ok, 1=timeout, 2=R1 err, 3=busy timeout); `getLastCMD12Capture(p_dest) : count` copies 16 bytes from `cmd12_capture` to caller buffer via `bytemove` and returns `cmd12_capture_len`; `getLastCMD12PreCapture(p_dest)` copies 7 bytes from `cmd12_pre_capture` to caller buffer via `bytemove`; `getLastCMD23Used() : used` returns `last_cmd23_used`; `getLastCMD23R1() : r1` returns `last_cmd23_r1`; `getLastCMD23Verify() : verify_byte` returns `last_cmd23_verify`; `getCmd23Supported() : supported` returns `cmd23_supported`. Each method gets standard `''` doc comments with `@returns` tags describing value meanings, following the existing pattern of `getLastCMD13()`. Note: `cardWarnings()` is listed separately since it's not debug-gated. Compile-check after this task.

### Task 4: Add PRI probeCmd13() and Wire Into initCard()

Add a new PRI method `probeCmd13()` in the card-level support section of the driver, near `checkCardStatus()` (around line ~9800). This method sends a single CMD13 on an idle card and validates the R2 response to detect broken CMD13 implementations. Implementation: (1) Send dummy clocks with CS HIGH (`pinh(cs)`, two `sp_transfer_8($FF)` calls) for card recovery time. (2) Assert CS LOW, send CMD13 manually byte-by-byte (`sp_transfer_8($40 | CMD13)` + four `$00` argument bytes + `$FF` CRC). (3) Call `waitR1Response()` to get R1. If R1 < 0 (timeout), set `cmd13_reliable := FALSE`, OR `CW_CMD13_UNRELIABLE` into `card_warning_flags`, deassert CS, and return. (4) Read STATUS byte via `sp_transfer_8($FF)`, deassert CS. (5) Validate: if `r1 & $80` (bit 7 set, violates SD spec), mark unreliable. If `ones status >= 3` (3+ simultaneous error bits on idle card = garbage), mark unreliable. Otherwise, CMD13 is reliable. Each path gets a `debug()` message. Then modify `checkCardStatus()` (line ~9799): add an early guard at the very top of the method body, before the dummy clocks: `if not cmd13_reliable` then `return` (returns 0 = success, silently skipping CMD13 on broken cards). Then modify `initCard()`: after the post-init dummy clocks at the end of Step 8 (after line ~8993 `ok := true`), add Step 9: `cmd13_reliable := TRUE`, `card_warning_flags := CW_NONE`, `probeCmd13()`. Also add warning debug messages in `do_mount()` (after line ~4072 `driver_mode := MODE_FILESYSTEM`) and `do_init_card_only()` (after line ~4094 `driver_mode := MODE_RAW`): `if card_warning_flags & CW_CMD13_UNRELIABLE` then `debug("  [do_mount] WARNING: CMD13 unreliable on this card - status checks disabled")`. Compile-check after this task.

### Task 5: Add PRI probeCmd23() and Wire Into initCard()

Add a new PRI method `probeCmd23()` near `probeCmd13()`. This method checks whether the card supports CMD23 (SET_BLOCK_COUNT) in SPI mode. Implementation: (1) Set `cmd23_supported := FALSE`. (2) Call `readSCR(@scr)` (which already exists as a PRI at line ~10177) to read the SCR register into a local `scr[2]` (2 longs = 8 bytes). If `readSCR` returns FALSE, log failure and return. (3) Extract `cmd_support := scr.byte[3] & $03` (CMD_SUPPORT field from SCR). (4) If bit 1 is set (`cmd_support & $02`), the card advertises CMD23 -- send a verification CMD23: `resp := cmd(CMD23, 1)`. If `resp == $00`, set `cmd23_supported := TRUE` and OR `CW_CMD23_SUPPORTED` into `card_warning_flags`. If resp is non-zero, CMD23 is rejected in SPI mode (common -- most cards advertise it for 4-bit bus only). Each branch gets a `debug()` message. Local variables: `scr[2]`, `cmd_support`, `resp`. Then wire into `initCard()`: immediately after the `probeCmd13()` call added in Task 4 (Step 9), add Step 10: `probeCmd23()`. The `cmd()` function at line ~8996 already handles CMD23 correctly (it will send the command, get R1, deassert CS since CMD23 is not in the keep-CS-low list). Compile-check after this task.

### Task 6: Add waitDataToken() Diagnostic Capture

Modify `waitDataToken()` (line ~9680) to record diagnostic state in the DAT variables added in Task 2. At the top of the method body (after the existing `timeout` setup at line ~9689), add: `last_cmd18_token := $FF` (default: no token) and `last_cmd18_result := 1` (default: timeout). On success path (line ~9693, where `resp == TOKEN_START_BLOCK`), add: `last_cmd18_token := resp` and `last_cmd18_result := 0` (success). On error token path (line ~9696, the `elseif resp <> $FF` branch), add: `last_cmd18_token := resp` and `last_cmd18_result := 2` (error token). These are simple two-line additions at three points in the existing method -- no structural changes to the control flow. The timeout path already has `last_cmd18_result := 1` from the default set at the top. Compile-check after this task.

### Task 7: Rewrite sendStopTransmission() with Capture Buffers

Replace the entire body of `sendStopTransmission()` (lines ~9749-9774) with the new capture-based implementation from the porting guide. The new method signature is `PRI sendStopTransmission() : result | resp, idx, timeout` (adds `idx` and `timeout` locals). The new implementation: (1) Capture MISO bytes during CMD12 transmission (full-duplex) into `cmd12_pre_capture[7]` -- each of the 7 `sp_transfer_8()` calls for command byte, 4 argument bytes, CRC (`CRC_CMD12` constant from Task 1, replacing literal `$61`), and stuff byte stores its return value in the corresponding pre_capture slot. (2) Initialize `cmd12_capture` to all `$FF` via `bytefill(@cmd12_capture, $FF, 16)`, set `cmd12_capture_len := 0`, `last_cmd12_r1 := -1` (no response), `last_cmd12_busy := 1` (timeout default). (3) Scan for R1: loop with 100ms timeout (`getct() + clkfreq / 10`), clocking bytes via `sp_transfer_8($FF)`, storing each into `cmd12_capture[idx]` (up to 16), and quitting when a non-`$FF` byte is found (that's the R1). Record its position in `cmd12_capture_len` and value in `last_cmd12_r1`. If timeout, set `result := E_TIMEOUT` and return. (4) After finding R1, continue capturing remaining bytes up to 16 for post-R1 framing analysis. (5) Evaluate: if `last_cmd12_r1 <> $00`, set `last_cmd12_busy := 2` (R1 error), `result := E_IO_ERROR`. Otherwise call `waitBusyComplete()` -- if it fails set `last_cmd12_busy := 3`, else set `last_cmd12_busy := 0` (success). Note the critical difference: the old code used `waitR1Response()` which has its own polling; the new code integrates R1 polling into the capture loop. Also note `E_IO_ERROR` is used instead of `E_BAD_RESPONSE` for the R1 error case -- verify `E_IO_ERROR` exists as a CON (it does, used in `do_mount()`). Compile-check after this task.

### Task 8: Rewrite readSectors() Post-Read Path with CMD23/CMD12 Dual-Path

Modify `readSectors()` (line ~9241) in three locations. First, **pre-CMD18** (before line ~9280 `resp := cmd(CMD18, ...)`): add diagnostic state clearing: `last_cmd18_fail := 0`, `last_cmd23_used := FALSE`, `last_cmd23_r1 := $FF` (not sent), `last_cmd23_verify := $FF` (idle). Then add CMD23 preamble: `if cmd23_supported` then `resp := cmd(CMD23, count)`, `last_cmd23_r1 := resp`, `last_cmd23_used := TRUE`, with debug message. Second, **CMD18 R1 diagnostic** (after line ~9281 `if resp <> $00`): add `last_cmd18_r1 := resp` before the error check, and inside the error block add `last_cmd18_fail := 1` (Path 1: R1 reject). Third, **data token fail** (inside the per-sector loop after line ~9294 `quit`): add `last_cmd18_fail := 2` (Path 2: data token fail) before the `quit`. Fourth and most significant, **replace the entire post-read path** (lines ~9332-9344): Replace the simple CMD12-then-CMD13 sequence with the dual-path structure. Add `last_cmd18_sread := sectors_read` (capture count before CMD12/CMD13 might zero it). Then branch on `last_cmd23_used`: **CMD23 path** -- clock one byte (`resp := sp_transfer_8($FF)`), store in `last_cmd23_verify`. If not `$FF`, card didn't auto-stop: disable CMD23 (`cmd23_supported := FALSE`, `last_cmd23_used := FALSE`), call `sendStopTransmission()`. Deassert CS. Then `checkCardStatus()` -- if fails, set `last_cmd18_fail := 4`, `sectors_read := 0`. **CMD12 path** (else branch) -- call `sendStopTransmission()`. If fails: call `recoverToIdle()`, then check if `sectors_read == count` (all data received with valid CRC): if yes, set `last_cmd18_fail := 5` (tolerated), do NOT zero `sectors_read`; if no, set `last_cmd18_fail := 3` (incomplete), zero `sectors_read`. If CMD12 succeeds: deassert CS, then `checkCardStatus()` -- if fails, set `last_cmd18_fail := 4`, `sectors_read := 0`. This is the most complex change and the heart of the v1.3.0 upgrade. Compile-check after this task.

### Task 9: Audit Tolerance Improvements in isp_fsck_utility.spin2

Make two changes to `src/UTILS/isp_fsck_utility.spin2`. **Change H1** (line ~595): Replace `auditRunTest(@"Partition type ($0C = FAT32 LBA)", result == PARTITION_TYPE_FAT32_LBA)` with `auditRunTest(@"Partition type FAT32 ($0B or $0C)", result == PARTITION_TYPE_FAT32_LBA OR result == PARTITION_TYPE_FAT32_CHS)`. This requires adding a new CON constant `PARTITION_TYPE_FAT32_CHS = $0B` near the existing `PARTITION_TYPE_FAT32_LBA = $0C` at line ~56. **Change H2** (line ~731): Replace `auditRunTest(@"Backup FSInfo matches primary", mismatch == false)` with a conditional: if `mismatch` is true, emit a warning via `fifo.put(@"  [WARN] Backup FSInfo differs from primary (common, repaired by fsck)")` and increment `v_warningCount` (which already exists at line ~212). If `mismatch` is false, call `auditRunTest(@"Backup FSInfo matches primary", TRUE)` as before. This downgrades a common benign mismatch from test failure to warning. Compile-check the fsck utility: `cd src/UTILS && pnut-ts -d -I .. DFS_SD_FAT32_audit.spin2` (or whichever top-level file uses isp_fsck_utility).

### Task 10: Compile-Check All Consumers and Document Completion

Run a full compile-check across all files that consume the driver to verify no regressions from the new CON constants, DAT variables, or method signatures. Compile each of these: (1) `src/dual_sd_fat32_flash_fs.spin2` standalone, (2) all files in `src/regression-tests/` via `pnut-ts -d -I ..`, (3) all files in `src/EXAMPLES/` via `pnut-ts -d -I ..`, (4) `src/DEMO/DFS_demo_shell.spin2` via `pnut-ts -I .. -I ../UTILS`, (5) all files in `src/UTILS/` that compile standalone. Use `tools/run_regression.sh --compile-only` if available to batch-check regression tests. Fix any compile errors found. After all compile-checks pass, update the driver version comment from v1.2.0 to v1.3.0 (find the version string in the file header). This task is complete when every .spin2 file in the project compiles cleanly.

---

## Risk Assessment

| Risk | Mitigation |
|---|---|
| CMD12 capture changes break existing multi-block reads | Compile-check + hardware test on known-good card first |
| CMD23 probe interferes with card init on some cards | Probe is read-only (SCR read + single CMD23); failure is gracefully handled |
| New DAT variables increase hub RAM usage | ~50 bytes total; well within P2's 512KB hub RAM |
| `sendStopTransmission()` signature change (added locals) | PRI method, no external callers; signature is internal only |
| `ones` operator unfamiliar | Built-in Spin2 popcount operator; verified in pnut-ts v45+ |

## Verification Strategy

1. **Compile-only** (Task 10): All .spin2 files must compile
2. **Hardware baseline**: Run full regression on a known-good SD card (no behavioral change expected on standard cards)
3. **Warning flag check**: After mount, call `cardWarnings()` -- should return `CW_NONE` on standard cards
4. **CMD12 tolerance**: If SP Elite card available, verify multi-block reads succeed (was the motivating bug)
5. **CMD13 unreliable**: If AData-type card available, verify probe detects and disables CMD13
