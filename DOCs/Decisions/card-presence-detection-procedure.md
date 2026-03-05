# Card Presence Detection Implementation Procedure

**Status: IMPLEMENTED** (2026-03-03) -- Hardware verified: card-in/out/in all correct. Full regression passes.

## Overview

Implement card-presence detection during SD card initialization using the P2's built-in programmable pull-up resistors and CMD0 timeout analysis.

**Reference documents:**
- `DOCs/Reference/CARD-PRESENCE-DETECTION.md` -- Full electrical analysis and SD spec research
- `DOCs/Decisions/ARCHITECTURE-DECISIONS.md` -- Decision 13
- `DOCs/SD-CARD-DRIVER-THEORY.md` -- "Card Presence Detection" section

---

## Problem

The P2 Edge Module microSD socket has no card-detect pin. The SD specification defines no software-only detection method for SPI mode. Without detection, `mount()` returns a generic `E_INIT_FAILED` (-21) whether the card is missing, broken, or has a wiring fault. Callers cannot distinguish "no card" from "card present but failing."

## Solution Summary

1. Enable a P2 internal 15K pull-up on MISO before the CMD0 probe
2. Track whether any CMD0 attempt got a non-timeout response
3. Return `E_NO_CARD` (-8) when all CMD0 attempts time out (MISO never driven)
4. Propagate the specific error through `do_mount()` / `do_init_card_only()`

---

## Implementation Steps

### Step 1: Add E_NO_CARD Error Code

**File:** `src/micro_sd_fat32_fs.spin2`

In the `CON ' error codes` section, add `E_NO_CARD` after `E_IO_ERROR`:

```spin2
  E_IO_ERROR        = -7        ' General I/O error during read/write
  E_NO_CARD         = -8        ' No card detected in slot (MISO idle during CMD0 probe)
```

### Step 2: Add last_init_error DAT Variable

In the `DAT ' ---- Singleton Control ----` section, add after `driver_mode`:

```spin2
  driver_mode   LONG    0               ' Current mode: MODE_NONE, MODE_RAW, or MODE_FILESYSTEM
  last_init_error LONG  0               ' Specific error from last initCard() failure
```

This allows `initCard()` (which returns boolean TRUE/FALSE) to communicate the specific failure reason to its callers.

### Step 3: Add got_response Local to initCard()

Add `got_response` to `initCard()`'s local variable list:

```spin2
PRI initCard() : result | timeout, resp, card_version, acmd41_arg, got_response
```

### Step 4: Enable MISO Pull-Up in Step 2 (Pin Setup)

In `initCard()`, Step 2 (after configuring CS, MOSI, SCK), replace the bare `pinf(miso)` with pull-up activation:

```spin2
  ' Enable 15K pull-up on MISO for card-presence detection
  ' If no card is present, MISO reads $FF (pulled high by P2 internal resistor)
  ' If card is present, card drives MISO (easily overpowers 15K pull-up)
  ' Pull-up is cleared later when initSPIPins() configures MISO for smart pin SPI
  wrpin(miso, P_HIGH_15K)
  pinf(miso)                                                                    '  MISO as input with pull-up active
  waitus(10)                                                                    '  Let pull-up settle
```

**Why P_HIGH_15K:** Strong enough for reliable $FF reads with no card, weak enough that any SD card (output impedance under 100 ohms) easily overpowers it.

**Pull-up cleanup:** The pull-up is automatically cleared in Step 3.5 when `initSPIPins()` calls `wrpin(miso, spi_rx_mode)`, which overwrites the pull-up configuration. No explicit cleanup needed.

### Step 5: Track CMD0 Responses in Step 4

Replace the Step 4 CMD0 loop with got_response tracking:

```spin2
  ' STEP 4: CMD0 - GO_IDLE_STATE
  debug("    [initCard] Step 4: CMD0 (GO_IDLE_STATE)...")
  resp := 0
  got_response := false
  repeat CMD0_MAX_RETRIES
    resp := cmd(CMD0, 0)
    debug("    [initCard] CMD0 response: $", uhex_(resp))
    if resp <> 0                                                                '  cmd() returns 0 on timeout
      got_response := true
    if resp == R1_IN_IDLE
      quit
    waitms(CMD_RETRY_DELAY_MS)

  result := true                                                                '  optimistic - set false on any failure

  if resp <> $01
    if not got_response
      debug("    [initCard] No card detected (MISO idle across all CMD0 attempts)")
      result := false
      last_init_error := E_NO_CARD
    else
      debug("    [initCard] Card responded but CMD0 failed: $", uhex_(resp))
      result := false
      last_init_error := E_BAD_RESPONSE
```

**Key logic:**
- `cmd()` returns 0 on timeout (never saw a non-$FF byte from MISO)
- If ALL 5 attempts return 0: nothing is driving MISO -- no card present
- If at least one attempt returned non-zero but never got $01: card is there but not cooperating

### Step 6: Set last_init_error on ACMD41 Timeout

In the ACMD41 timeout path, add `last_init_error := E_TIMEOUT`:

```spin2
      if getct() - timeout > 0
        debug("    [initCard] FAIL: ACMD41 timeout after 2 seconds")
        debug("    [initCard] Last response: $", uhex_(resp))
        result := false
        last_init_error := E_TIMEOUT
        quit
```

### Step 7: Propagate Specific Error in do_mount()

In `do_mount()`, change the `initCard()` failure path from generic `E_INIT_FAILED` to the specific error:

```spin2
    if not initCard()
      debug("  [do_mount] FAIL: initCard() returned false")
      result := last_init_error
```

Was: `result := E_INIT_FAILED`

### Step 8: Propagate Specific Error in do_init_card_only()

Same change in `do_init_card_only()`:

```spin2
  else
    debug("  [do_init_card_only] FAIL: initCard() returned false")
    driver_mode := MODE_NONE
    result := last_init_error
```

Was: `result := E_INIT_FAILED`

---

## Verification

### Compile Check

```bash
cd tools/
./run_test.sh ../regression-tests/SD_RT_mount_tests.spin2
```

All mount tests must pass (card is present during testing, so E_NO_CARD path is not exercised but must not break the normal path).

### Key Test Suites

```bash
./run_test.sh ../regression-tests/SD_RT_mount_tests.spin2
./run_test.sh ../regression-tests/SD_RT_file_ops_tests.spin2
./run_test.sh ../regression-tests/SD_RT_error_handling_tests.spin2
```

### Manual No-Card Test (Optional)

To verify E_NO_CARD behavior, physically remove the SD card and run a simple test program:

```spin2
PUB go() | result
  result := sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
  if result == sd.E_NO_CARD
    debug("PASS: Got E_NO_CARD as expected")
  else
    debug("FAIL: Expected E_NO_CARD, got ", sdec(result))
  debug("END_SESSION")
```

Expected debug output with no card:
```
[initCard] No card detected (MISO idle across all CMD0 attempts)
```

---

## Error Flow Summary

```
User calls mount(CS, MOSI, MISO, SCK)
  -> PUB mount() acquires lock, sends CMD_MOUNT
    -> Worker dispatches to do_mount()
      -> do_mount() calls initCard()
        -> Step 2: wrpin(miso, P_HIGH_15K) enables pull-up
        -> Step 3.5: initSPIPins() clears pull-up (wrpin(miso, spi_rx_mode))
        -> Step 4: CMD0 loop, all timeouts
        -> result := false, last_init_error := E_NO_CARD
      -> do_mount() reads last_init_error -> E_NO_CARD
      -> pb_status := E_NO_CARD
    -> Worker wakes caller via COGATN
  -> mount() reads pb_status, returns E_NO_CARD
```

---

## Files Modified

| File | Change |
|------|--------|
| `src/micro_sd_fat32_fs.spin2` | All code changes (Steps 1-8) |

## New Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `E_NO_CARD` | -8 | No card detected in slot |

## New DAT Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `last_init_error` | LONG | Specific error from last initCard() failure |

## New Local Variables

| Variable | Method | Purpose |
|----------|--------|---------|
| `got_response` | `initCard()` | Tracks if any CMD0 attempt got a non-timeout response |
