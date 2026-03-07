# Engineering Guide: SPI Backend Consolidation for SD SPI Driver

**Date:** 2026-03-07
**Source project:** P2-uSD-FAT32-FS (Iron Sheep Productions)
**Purpose:** Instructions for consolidating duplicated SPI transaction code in any project that incorporates the same SD SPI driver pattern. Reduces ~286 lines, creates single tested code paths, and prepares the transport layer for future 6-wire SD native mode.

---

## 1. The Problem

The SPI backend has significant code duplication across register-read methods and CMD13 handling:

1. **Five register-read methods** (readCSD, readCID, sendCMD6, readSCR, readSDStatus) each inline a near-identical ~30-line "send command, wait R1, wait $FE, read N bytes, discard CRC, deselect" sequence. Only the command number, CRC byte, and data length vary.

2. **Two CMD55 prefix sequences** (readSCR, readSDStatus) inline identical ~18-line CMD55 send-and-check patterns.

3. **Two CMD13 transaction sequences** (probeCmd13, checkCardStatus) inline identical ~45-line full-duplex CMD13 wire transactions, differing only in how they interpret the results.

This duplication means:
- Bugs in one copy don't get fixed in others (the CMD13 pad bug that motivated this work)
- Adding 6-wire SD mode would require writing 5 separate register readers instead of 1
- More code to maintain and review

---

## 2. Overview of Changes

Three new shared methods are introduced, and existing methods are refactored to call them:

| New method | Replaces inline code in | Lines saved |
|------------|------------------------|-------------|
| `readDataRegister()` | readCSD, readCID, sendCMD6, readSCR (ACMD part), readSDStatus (ACMD part) | ~180 |
| `sendAppCmdPrefix()` | readSCR (CMD55 part), readSDStatus (CMD55 part) | ~26 |
| `sendCmd13Transaction()` | probeCmd13, checkCardStatus | ~65 |

Additionally, CRC constants are centralized:
| New constant | Value | Replaces |
|-------------|-------|----------|
| `CRC_CMD9` | `$AF` | Hardcoded `$AF` in readCSD |
| `CRC_CMD10` | `$1B` | Hardcoded `$1B` in readCID |
| `CRC_ACMD51` | `$55` | Hardcoded `$55` in readSCR |
| `CRC_NONE` | `$FF` | Hardcoded `$FF` in sendCMD6, readSDStatus |

---

## 3. Step-by-Step Implementation

### Step 1: Add CRC Constants

Find the existing CRC constant block in CON:
```spin2
CON ' Pre-computed CRC bytes for fixed-argument commands
  CRC_CMD0  = $95
  CRC_CMD8  = $87
  CRC_CMD12 = $61
  CRC_CMD55 = $65
```

Add the new constants:
```spin2
CON ' Pre-computed CRC bytes for fixed-argument commands
  CRC_CMD0   = $95
  CRC_CMD8   = $87
  CRC_CMD9   = $AF
  CRC_CMD10  = $1B
  CRC_CMD12  = $61
  CRC_CMD55  = $65
  CRC_ACMD51 = $55
  CRC_NONE   = $FF    ' CRC not validated in SPI mode after init
```

### Step 2: Add `readDataRegister()` Method

Place this method immediately BEFORE `readCSD()`. It consolidates the "Shape D" transaction pattern used by all register reads.

```spin2
PRI readDataRegister(cmd_num, arg, crc_byte, p_buf, byte_count) : result | timeout, idx, resp
' Consolidated register read transaction -- sends command, waits for R1 and $FE data token,
' reads byte_count bytes into p_buf, consumes 2-byte CRC, deselects card.
' Used by: readCSD (CMD9, 16 bytes), readCID (CMD10, 16 bytes), sendCMD6 (CMD6, 64 bytes),
' readSCR (ACMD51, 8 bytes), readSDStatus (ACMD13, 64 bytes).
'
' @param cmd_num - SD command number (e.g., CMD9, CMD10, CMD6)
' @param arg - 32-bit command argument (0 for most register reads)
' @param crc_byte - Pre-computed CRC-7 byte for this command
' @param p_buf - Pointer to buffer to receive data
' @param byte_count - Number of data bytes to read (8, 16, or 64)
' @returns result - TRUE on success, FALSE on failure/timeout
' @local timeout - Timeout deadline
' @local idx - Loop counter
' @local resp - SPI response byte

  sp_transfer_8($FF)                                                               '  pre-command dummy clock
  pinl(cs)                                                                         '  CS LOW = selected
  sp_transfer_8($FF)                                                               '  required by some cards
  sp_transfer_8($40 | cmd_num)                                                     '  command byte
  sp_transfer(arg, 32)                                                             '  32-bit argument
  sp_transfer_8(crc_byte)                                                          '  CRC-7

  ' Wait for R1 response -- skip bytes with bit 7 set (SD spec 7.3.2.1)
  timeout := getct() + clkfreq                                                    '  1s timeout
  repeat
    resp := sp_transfer_8($FF)
    if (resp & $80) == 0                                                           '  valid R1 has bit 7 = 0
      quit
    if getct() - timeout > 0
      quit

  if resp == $00
    ' Wait for data token ($FE)
    timeout := getct() + clkfreq                                                   '  1s timeout
    repeat
      resp := sp_transfer_8($FF)
      if resp == TOKEN_START_BLOCK                                                 '  $FE = data coming
        quit
      if getct() - timeout > 0
        quit

    if resp == TOKEN_START_BLOCK
      ' Read data bytes into caller's buffer
      repeat idx from 0 to byte_count - 1
        byte[p_buf + idx] := sp_transfer_8($FF)

      ' Read and discard 2-byte CRC
      sp_transfer_8($FF)
      sp_transfer_8($FF)

      result := TRUE

  pinh(cs)                                                                         '  CS HIGH = deselected
```

**Key design decisions:**
- All paths converge on a single `pinh(cs)` at the end (no early returns with CS left asserted)
- Uses `TOKEN_START_BLOCK` constant (defined as `$FE` in CON) for clarity
- R1 timeout: `resp` stays `$FF` → falls through to `pinh(cs)` without entering data path
- R1 error (e.g., $04 illegal command): `resp <> $00` → falls through to `pinh(cs)`
- 1-second timeouts match existing register-read behavior (init-time operations, not performance-critical)

### Step 3: Refactor `readCSD()`

Replace the entire method body. Keep the doc comment, remove now-unnecessary locals:

**Before (~42 lines):**
```spin2
PRI readCSD(p_csd) : result | timeout, idx, resp
' Read CSD register using CMD9 - reads 16-byte CSD register into buffer.
' Uses smart pin operations for compatibility with smart pin SPI mode.
'
' @param p_csd - Pointer to 16-byte buffer to receive CSD data
' @returns result - TRUE on success, FALSE on failure
' @local timeout - Timeout deadline
' @local idx - Loop counter
' @local resp - SPI response byte

  sp_transfer_8($FF)
  pinl(cs)
  sp_transfer_8($FF)
  sp_transfer_8($40 | CMD9)
  sp_transfer(0, 32)
  sp_transfer_8($AF)
  [... 30+ more lines of inline transaction ...]
```

**After (3 lines):**
```spin2
PRI readCSD(p_csd) : result
' Read CSD register using CMD9 - reads 16-byte CSD register into buffer.
'
' @param p_csd - Pointer to 16-byte buffer to receive CSD data
' @returns result - TRUE on success, FALSE on failure

  result := readDataRegister(CMD9, 0, CRC_CMD9, p_csd, 16)
```

### Step 4: Refactor `readCID()`

Same pattern as readCSD:

**After:**
```spin2
PRI readCID(p_cid) : result
' Read CID register using CMD10 - reads 16-byte Card Identification register.
' CID layout: MID[1] OID[2] PNM[5] PRV[1] PSN[4] MDT[2] CRC[1] (big-endian from card).
'
' @param p_cid - Pointer to 16-byte buffer to receive CID data
' @returns result - TRUE on success, FALSE on failure

  result := readDataRegister(CMD10, 0, CRC_CMD10, p_cid, 16)
```

### Step 5: Refactor `sendCMD6()`

This method passes a non-zero argument and reads 64 bytes:

**After:**
```spin2
PRI sendCMD6(arg, p_status) : result
' Send CMD6 (SWITCH_FUNC) and receive 64-byte status structure.
' arg format: [31]=mode (0=check, 1=switch), [3:0]=function group 1 selection.
'
' @param arg - CMD6 argument word
' @param p_status - Pointer to 64-byte buffer to receive status
' @returns result - TRUE on success, FALSE on failure/timeout

  result := readDataRegister(CMD6, arg, CRC_NONE, p_status, 64)
```

Note: sendCMD6 is inside `#IFDEF SD_INCLUDE_SPEED`. Keep it there.

### Step 6: Add `sendAppCmdPrefix()` Method

Place immediately BEFORE `readSCR()`. Uses the existing `cmd()` method for the CMD55 transaction.

```spin2
PRI sendAppCmdPrefix() : resp
' Send CMD55 (APP_CMD) prefix for application-specific commands (ACMD*).
' Uses cmd() for the command transaction, then deasserts CS for the ACMD to follow.
'
' @returns resp - R1 response from CMD55 ($00 or $01 = success, >$01 = error)

  resp := cmd(CMD55, 0)
  pinh(cs)                                                                         '  deselect between CMD55 and ACMD
```

**Key design decision:** `cmd()` keeps CS asserted for CMD55 (it's in the exclusion list at the conditional `pinh` line). We explicitly deassert after the call because ACMD commands need a fresh CS assertion cycle. The `pinh(cs)` after `cmd()` is harmless if `cmd()` already deasserted due to timeout.

### Step 7: Refactor `readSCR()`

Replace the entire method body. The CMD55 prefix + ACMD51 register read becomes two calls:

**After:**
```spin2
PRI readSCR(p_scr) : result | resp
' Read SCR register using ACMD51 - reads 8-byte SD Configuration Register.
' Requires CMD55 prefix before ACMD51.
'
' @param p_scr - Pointer to 8-byte buffer to receive SCR data
' @returns result - TRUE on success, FALSE on failure
' @local resp - CMD55 R1 response

  resp := sendAppCmdPrefix()
  if resp > $01                                                                    '  accept $00 or $01 (idle)
    debug("  [readSCR] CMD55 error response: $", uhex_byte_(resp))
  else
    result := readDataRegister(ACMD51, 0, CRC_ACMD51, p_scr, 8)
```

### Step 8: Refactor `readSDStatus()`

Same pattern as readSCR:

**After:**
```spin2
PRI readSDStatus(p_buf) : result | resp
' Read SD Status register using ACMD13 - reads 64-byte SD Status.
' Requires CMD55 prefix before ACMD13.
'
' @param p_buf - Pointer to 64-byte buffer to receive SD Status data
' @returns result - TRUE on success, FALSE on failure
' @local resp - CMD55 R1 response

  resp := sendAppCmdPrefix()
  if resp > $01                                                                    '  accept $00 or $01 (idle)
    debug("  [readSDStatus] CMD55 error response: $", uhex_byte_(resp))
  else
    result := readDataRegister(CMD13, 0, CRC_NONE, p_buf, 64)
```

Note: readSDStatus sends CMD13 as the ACMD13 command number. In SPI mode, ACMD13 uses the same command code as CMD13 -- the CMD55 prefix is what makes it an application-specific command.

### Step 9: Add `sendCmd13Transaction()` Method

Place immediately BEFORE `probeCmd13()`. This extracts the shared CMD13 wire transaction with full-duplex capture.

```spin2
PRI sendCmd13Transaction() : r1, status | idx, resp, timeout
' Send CMD13 with full-duplex MISO capture -- shared wire transaction for probeCmd13
' and checkCardStatus. Sends dummy clocks with CS HIGH for recovery, then CMD13 with
' full-duplex capture of both pre-command MISO bytes and post-command response stream.
' Populates cmd13_pre_capture[], cmd13_capture[], cmd13_capture_len for diagnostic
' inspection. Stages last_cmd13_r1, last_cmd13_status, last_cmd13_error.
'
' @returns r1 - R1 response byte (-1 if timeout)
' @returns status - STATUS byte (second byte of R2 response), 0 if timeout
' @local idx - Capture buffer index
' @local resp - Received byte
' @local timeout - Timeout deadline

  ' Initialize capture buffers
  bytefill(@cmd13_pre_capture, $FF, 7)
  bytefill(@cmd13_capture, $FF, 8)
  cmd13_capture_len := 0

  ' Send dummy clocks with CS HIGH (card recovery time)
  pinh(cs)
  sp_transfer_8($FF)
  sp_transfer_8($FF)

  ' Send CMD13 with full-duplex MISO capture (card may still be outputting)
  pinl(cs)
  cmd13_pre_capture[0] := sp_transfer_8($40 | CMD13)                              '  command byte
  cmd13_pre_capture[1] := sp_transfer_8($00)                                      '  argument bytes
  cmd13_pre_capture[2] := sp_transfer_8($00)
  cmd13_pre_capture[3] := sp_transfer_8($00)
  cmd13_pre_capture[4] := sp_transfer_8($00)
  cmd13_pre_capture[5] := sp_transfer_8($FF)                                      '  CRC (don't care after init)

  ' Capture raw byte stream and find R1 -- skip bytes with bit 7 set (SD spec 7.3.2.1)
  timeout := getct() + clkfreq / 10                                               '  100ms timeout
  idx := 0
  r1 := -1
  repeat
    resp := sp_transfer_8($FF)
    if idx < 8
      cmd13_capture[idx] := resp
      idx++
    if (resp & $80) == 0                                                           '  valid R1 has bit 7 = 0
      cmd13_capture_len := idx
      r1 := resp
      quit
    if getct() - timeout > 0
      cmd13_capture_len := idx
      pinh(cs)
      last_cmd13_r1 := $FF
      return                                                                       '  r1 stays -1, status stays 0

  ' Capture remaining bytes after R1 (STATUS byte + extra for analysis)
  repeat while idx < 8
    cmd13_capture[idx] := sp_transfer_8($FF)
    idx++

  ' STATUS byte is immediately after R1
  status := cmd13_capture[cmd13_capture_len]

  pinh(cs)                                                                         '  deselect card

  ' Stage CMD13 results for diagnostic getters
  last_cmd13_r1 := r1
  last_cmd13_status := status
  if r1 <> 0 or status <> 0
    last_cmd13_error := (r1 << 8) | status
```

**Key design decisions:**
- Returns two values (`r1, status`) via Spin2 multiple return values
- On timeout: returns `r1 = -1`, `status = 0`, stages `last_cmd13_r1 := $FF`
- Stages `last_cmd13_r1/status/error` inside the shared method (both callers did this identically)
- Preserves full diagnostic capture into `cmd13_pre_capture[]` and `cmd13_capture[]`

### Step 10: Refactor `probeCmd13()`

Replace the wire transaction with a call to `sendCmd13Transaction()`. Keep the reliability analysis logic.

**After:**
```spin2
PRI probeCmd13() | r1, status
' Probe CMD13 reliability at end of initCard().
' Sends a single CMD13 on an idle card and checks whether the response is valid.
' If the response violates the SD spec (R1 bit 7 set, or 3+ simultaneous error
' bits in STATUS on an idle card), marks cmd13_reliable := FALSE and sets
' CW_CMD13_UNRELIABLE in card_warning_flags.
'
' @local r1 - R1 response byte from CMD13
' @local status - STATUS byte (second byte of R2 response)

  r1, status := sendCmd13Transaction()

  ' Log full capture for diagnostics
  debug("    [probeCmd13] pre=[", uhex_byte_(cmd13_pre_capture[0]), " ", ...)
  debug("    [probeCmd13] cap=[", uhex_byte_(cmd13_capture[0]), " ", ...)
  debug("    [probeCmd13] R1=$", uhex_byte_(r1), " STATUS=$", uhex_byte_(status))

  ' Check 1: Timeout -- sendCmd13Transaction returns r1 = -1
  if r1 == -1
    debug("    [probeCmd13] TIMEOUT - marking CMD13 unreliable")
    cmd13_reliable := FALSE
    card_warning_flags |= CW_CMD13_UNRELIABLE
    return

  ' Check 2: R1 bit 7 must be 0 per SD spec
  if r1 & $80
    debug("    [probeCmd13] R1 bit 7 set - marking CMD13 unreliable")
    cmd13_reliable := FALSE
    card_warning_flags |= CW_CMD13_UNRELIABLE
    return

  ' Check 3: 3+ error bits in STATUS on an idle card = garbage data
  if ones status >= 3
    debug("    [probeCmd13] STATUS has ", udec_(ones status), " error bits - marking CMD13 unreliable")
    cmd13_reliable := FALSE
    card_warning_flags |= CW_CMD13_UNRELIABLE
    return

  debug("    [probeCmd13] CMD13 OK (R1=$", uhex_byte_(r1), " STATUS=$", uhex_byte_(status), ")")
```

### Step 11: Refactor `checkCardStatus()`

Replace the wire transaction with a call to `sendCmd13Transaction()`. Keep the early-return guard and error interpretation.

**After:**
```spin2
PRI checkCardStatus(caller) : result | r1, status
' Send CMD13 to verify card status after operation - checks R2 response for errors.
' Skipped on cards where CMD13 was found unreliable at init (unless test_force_cmd13 is set).
'
' @param caller - String identifying the calling function (for debug)
' @returns result - 0 on success (card OK), negative error code on error
' @local r1 - R1 response byte
' @local status - Status byte (second byte of R2)

  ' Skip CMD13 on cards with broken implementation (unless diagnostic override is set)
  if not cmd13_reliable and not test_force_cmd13
    return

  r1, status := sendCmd13Transaction()

  ' Log pre-capture for diagnostic visibility
  debug("  [checkCardStatus] ", zstr_(caller), ": pre=[", ...)

  ' Check for errors
  if r1 == -1
    debug("  [checkCardStatus] ", zstr_(caller), ": TIMEOUT waiting for R1")
    result := E_TIMEOUT
  elseif r1 <> $00
    debug("  [checkCardStatus] ", zstr_(caller), ": R1 error=$", uhex_byte_(r1))
    result := E_IO_ERROR
  elseif status <> $00
    debug("  [checkCardStatus] ", zstr_(caller), ": STATUS error=$", uhex_byte_(status))
    [... STATUS bit decoding unchanged ...]
    result := E_IO_ERROR
```

---

## 4. What NOT to Change

### Leave these alone

| Code | Why |
|------|-----|
| **Streamer PASM blocks** (readSector, readSectors, writeSector, writeSectors) | Inline PASM by necessity -- variables are PASM registers, can't be in a Spin2 method |
| **Smart pin disable/re-enable around streamer** | 2-3 lines each, tightly coupled to adjacent PASM block |
| **readSector data token wait** (lines ~5176-5194) | Integrated with CRC retry loop; error token detection differs from simple waitDataToken() |
| **writeSector inline data-response/busy waits** | Lower priority (Tier 2); diagnostic staging differences make extraction less clean |
| **cmd() CRC logic** (CMD0/CMD8 distinction) | Only CMD0 and CMD8 go through cmd() during CRC-required init; all register reads now use readDataRegister() with explicit CRC parameter |
| **sendStopTransmission()** | CMD12 is unique (stuff byte, mid-stream full-duplex); no duplication to consolidate |
| **readSectorSlow()** | DEBUG-only diagnostic tool, deliberately different from production path |

### Methods that must NOT call `readDataRegister()`

| Method | Why |
|--------|-----|
| `readSector()` | Uses streamer DMA for 512-byte bulk transfer, not byte-by-byte |
| `readSectors()` | Uses streamer DMA in a loop with CMD18/CMD12 |
| `readSectorSlow()` | Deliberately byte-by-byte for debugging; different from register read pattern |

---

## 5. Prerequisites

### Required constants and methods

The new methods depend on these existing definitions:
- `CMD6`, `CMD9`, `CMD10`, `CMD13`, `CMD55`, `ACMD51` -- command number constants
- `TOKEN_START_BLOCK` ($FE) -- data start token constant
- `sp_transfer_8()` -- 8-bit SPI transfer primitive
- `sp_transfer()` -- variable-width SPI transfer dispatcher
- `cmd()` -- generic SPI command sender (used by sendAppCmdPrefix)
- `cmd13_pre_capture[]`, `cmd13_capture[]`, `cmd13_capture_len` -- DAT capture buffers
- `last_cmd13_r1`, `last_cmd13_status`, `last_cmd13_error` -- DAT diagnostic staging variables

### Required DAT variables for CMD13

Verify these exist in DAT:
```spin2
cmd13_pre_capture     BYTE    0[7]         ' Full-duplex MISO during CMD13 transmission
cmd13_capture         BYTE    0[8]         ' Raw post-command byte stream
cmd13_capture_len     BYTE    0            ' NCR gap length (bytes before R1)
last_cmd13_r1         BYTE    0            ' Last CMD13 R1 response
last_cmd13_status     BYTE    0            ' Last CMD13 STATUS byte
last_cmd13_error      WORD    0            ' Last CMD13 error (R1 << 8 | STATUS)
```

---

## 6. Verification

### Compile check

After all changes, verify the driver compiles with no errors. Use whatever compile check is available (e.g., `run_regression.sh --compile-only` or direct compiler invocation).

### Hardware regression

Run the full regression suite. All tests should pass with identical results. These changes are pure refactoring -- no behavioral differences.

### Specific areas to watch

1. **Card initialization** -- readCSD and readCID are called during init (via `identifyCard()`). Verify cards still identify correctly.
2. **CMD13 probe** -- probeCmd13 is called at end of init. Verify cmd13_reliable flag is set correctly.
3. **Post-operation CMD13** -- checkCardStatus is called after every read/write. Verify no regressions.
4. **High-speed mode** -- sendCMD6 is called by queryHighSpeedSupport/switchToHighSpeed (behind `#IFDEF SD_INCLUDE_SPEED`). Verify if available.
5. **SCR read** -- readSCR is called by probeCmd23. Verify CMD23 probe still works.

---

## 7. Commit Message Template

```
Consolidate SPI backend: readDataRegister, sendAppCmdPrefix, sendCmd13Transaction

Extract three shared methods from duplicated SPI transaction code:
- readDataRegister(): consolidates 5 register-read methods (CSD, CID, CMD6, SCR, SDStatus)
- sendAppCmdPrefix(): consolidates CMD55 prefix from readSCR and readSDStatus
- sendCmd13Transaction(): consolidates CMD13 wire transaction from probeCmd13 and checkCardStatus

Add CRC constants: CRC_CMD9, CRC_CMD10, CRC_ACMD51, CRC_NONE.
Pure refactoring -- no behavioral changes. Reduces SPI backend by ~286 lines.
Prepares transport layer for 6-wire SD native mode (smaller cut set).
```

---

*Engineering guide produced 2026-03-07 -- Iron Sheep Productions*
