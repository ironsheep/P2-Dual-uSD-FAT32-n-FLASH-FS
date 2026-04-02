# Independent SPI Bus Analysis

Analysis of changes required to support **separate Flash and SD SPI pin groups** as a conditionally compiled option. The current driver is designed for the P2 Edge Module, where Flash and SD share MOSI/MISO with an efficient cross-wired CS/SCK layout. This document details what must change to also support independent 4-wire SPI buses on custom hardware where Flash and SD have their own dedicated pin groups.

**Date**: 2026-03-24
**Driver version**: 1.3.0 (SD sub-driver v1.5.0, Flash sub-driver v2.0.0)

---

## 1. Current Pin Architecture

### 1.1 Shared-Bus Pin Layout (P2 Edge Module)

The current hardware cross-wires P60/P61 between devices:

```
              SD Mode              Flash Mode
              --------             ----------
  P58         MISO (P_SYNC_RX)    MISO (GPIO testp)
  P59         MOSI (P_SYNC_TX)    MOSI (GPIO drvc)
  P60         CS   (GPIO)         SCK  (P_TRANSITION inv)
  P61         SCK  (P_TRANSITION) CS   (P_TRANSITION)
```

Pin constants (driver line 64-70):

```spin2
CON
  PIN_SD_CS   = 60    ' SD chip select (also Flash SCK)
  PIN_MOSI    = 59    ' Shared MOSI
  PIN_MISO    = 58    ' Shared MISO
  PIN_SD_SCK  = 61    ' SD serial clock (also Flash CS)
  PIN_FL_CS   = 61    ' Flash chip select (= SD SCK pin)
  PIN_FL_SCK  = 60    ' Flash serial clock (= SD CS pin)
```

### 1.2 How Shared-Bus Switching Works

The shared-bus design is an efficient use of the P2 Edge Module's 4-pin SPI header, allowing both devices on just 4 pins by swapping the roles of P60/P61. Because P60 serves as SD CS **and** Flash SCK, the driver includes a well-tested bus switching mechanism:

1. **`switch_to_flash()`** (line 6138): PINCLEAR all SD smart pins before Flash GPIO bit-bang
2. **`switch_to_sd()`** (line 6158): `reinitCard()` -- 7-step recovery sequence including CMD0/CMD8/ACMD41/CMD58
3. **`reinitCard()`** (line 6184): 4096-clock GPIO flush + card re-initialization (~50-100ms)

This works reliably on the P2 Edge Module and is verified by 1,350 regression tests. However, on custom hardware where Flash and SD have their own dedicated pin groups, this switching overhead is unnecessary -- each device's pins are independent, so operating one device never affects the other.

### 1.3 Independent Pin Layout (Custom Hardware)

On custom boards where Flash and SD are wired to separate pin groups:

```
              SD Bus (4 pins)           Flash Bus (4 pins)
              ----------------          ------------------
  SD_MISO     P_SYNC_RX                FL_MISO  GPIO testp
  SD_MOSI     P_SYNC_TX                FL_MOSI  GPIO drvc
  SD_CS       GPIO                     FL_CS    P_TRANSITION
  SD_SCK      P_TRANSITION             FL_SCK   P_TRANSITION inv
```

Each device has its own dedicated MOSI, MISO, CS, and SCK. The driver can skip bus switching entirely since operating one device never disturbs the other.

---

## 2. Conditional Compilation Design

### 2.1 New Feature Flag

```spin2
' In driver CON section, alongside existing feature flags:
#pragma exportdef SPI_INDEPENDENT_BUSES    ' Separate Flash and SD SPI pin groups
```

Parent files enable it the same way as existing flags:

```spin2
' In top-level application:
#define SPI_INDEPENDENT_BUSES
#pragma exportdef SPI_INDEPENDENT_BUSES
```

### 2.2 Pin Constant Restructuring

```spin2
#ifdef SPI_INDEPENDENT_BUSES
  ' ---- Independent SPI Buses (user must override these via OBJ pipe or #define) ----
  ' SD bus pins
  PIN_SD_CS   = 60    ' SD chip select
  PIN_SD_MOSI = 59    ' SD data out (to card)
  PIN_SD_MISO = 58    ' SD data in (from card)
  PIN_SD_SCK  = 61    ' SD serial clock
  ' Flash bus pins (completely separate)
  PIN_FL_CS   = 57    ' Flash chip select (example -- user sets actual pins)
  PIN_FL_SCK  = 56    ' Flash serial clock
  PIN_FL_MOSI = 55    ' Flash data out (to chip)
  PIN_FL_MISO = 54    ' Flash data in (from chip)
#else
  ' ---- Shared SPI Bus (P2 Edge Module default) ----
  PIN_SD_CS   = 60    ' SD chip select (also Flash SCK)
  PIN_MOSI    = 59    ' Shared MOSI
  PIN_MISO    = 58    ' Shared MISO
  PIN_SD_SCK  = 61    ' SD serial clock (also Flash CS)
  PIN_FL_CS   = 61    ' Flash chip select (= SD SCK pin)
  PIN_FL_SCK  = 60    ' Flash serial clock (= SD CS pin)
  ' Aliases for shared-bus mode (SD and Flash share MOSI/MISO)
  PIN_SD_MOSI = PIN_MOSI
  PIN_SD_MISO = PIN_MISO
  PIN_FL_MOSI = PIN_MOSI
  PIN_FL_MISO = PIN_MISO
#endif
```

**Key design decision**: In shared-bus mode, `PIN_SD_MOSI`/`PIN_FL_MOSI` are aliases for `PIN_MOSI`, and the same for MISO. This lets all code reference device-specific pin names uniformly, with the compiler resolving them to the same physical pin in shared mode.

### 2.3 OBJ Override for User Pin Configuration

Users with custom board layouts override pin assignments via OBJ pipe syntax:

```spin2
OBJ
  dfs : "dual_sd_fat32_flash_fs" | PIN_SD_CS = 28, PIN_SD_MOSI = 27, PIN_SD_MISO = 26, PIN_SD_SCK = 29, PIN_FL_CS = 24, PIN_FL_SCK = 25, PIN_FL_MOSI = 23, PIN_FL_MISO = 22
```

---

## 3. Code Changes Required

### 3.1 Smart Pin Relative Addressing (CRITICAL -- highest complexity)

**Problem**: P2 smart pins use relative pin selectors (`P_PLUS2_B`, `P_PLUS3_B`) to identify the clock source. The current code hardcodes these based on the fixed pin layout where SCK is always 2 pins above MOSI and 3 above MISO.

```spin2
' Current code (line 8953-8954):
spi_tx_mode := P_SYNC_TX | P_OE | P_PLUS2_B    ' Clock from pin+2 (SCK=P61, MOSI=P59)
spi_rx_mode := P_SYNC_RX | P_PLUS3_B           ' Clock from pin+3 (SCK=P61, MISO=P58)
```

**What P_PLUSn_B means**: The B-input of a smart pin (used for clock synchronization) can come from pin+0 through pin+3, selected by these mode bits. For P_SYNC_TX on MOSI, B-input must be connected to SCK.

**Required change**: Compute the correct `P_PLUSn_B` selector at runtime based on the actual pin offset:

```spin2
' Compute B-input selector for smart pin clock source
' offset = SCK_pin - data_pin (must be 0..3 for P_PLUSn_B)
PRI computeBSelector(sck_pin, data_pin) : selector | offset
  offset := sck_pin - data_pin
  case offset
    0: selector := P_PLUS0_B
    1: selector := P_PLUS1_B
    2: selector := P_PLUS2_B
    3: selector := P_PLUS3_B
    other:
      ' Fatal: pins too far apart for smart pin B-input routing
      debug("FATAL: SCK must be within +0..+3 of data pin")
      selector := 0
```

**Constraint**: SD SCK must be within +0 to +3 pins above both SD MOSI and SD MISO. This is a **P2 hardware limitation** -- smart pin B-input routing only supports pin, pin+1, pin+2, or pin+3. Users must choose SD pins accordingly.

Updated `initSPIPins()`:

```spin2
PRI initSPIPins()
  spi_clk_mode := P_TRANSITION | P_OE
  spi_tx_mode := P_SYNC_TX | P_OE | computeBSelector(PIN_SD_SCK, PIN_SD_MOSI)
  spi_rx_mode := P_SYNC_RX | computeBSelector(PIN_SD_SCK, PIN_SD_MISO)
  ' ... rest of init unchanged but uses PIN_SD_MOSI/PIN_SD_MISO ...
```

**Impact**: ~15 lines changed in `initSPIPins()` (line 8933).

### 3.2 Pin References in Inline PASM2 (53 occurrences)

All inline assembly uses `#PIN_xxx` syntax which resolves CON constants at compile time. These need to be updated to use the new device-specific names:

| Current Reference | Change To | Occurrences | Location |
|---|---|---|---|
| `#PIN_MOSI` | `#PIN_SD_MOSI` (SD methods) or `#PIN_FL_MOSI` (Flash methods) | ~18 | SD: sp_transfer_8/32, readSector, writeSector. Flash: fl_send, fl_receive |
| `#PIN_MISO` | `#PIN_SD_MISO` (SD methods) or `#PIN_FL_MISO` (Flash methods) | ~20 | SD: sp_transfer_8/32, readSector, writeSector, cmd. Flash: fl_command, fl_receive |
| `#PIN_SD_CS` | `#PIN_SD_CS` (unchanged) | ~8 | SD methods only |
| `#PIN_SD_SCK` | `#PIN_SD_SCK` (unchanged) | ~7 | SD methods only |
| `#PIN_FL_CS` | `#PIN_FL_CS` (unchanged) | ~3 | Flash methods only |
| `#PIN_FL_SCK` | `#PIN_FL_SCK` (unchanged) | ~7 | Flash methods only |

**In shared-bus mode** (`#else` path), `PIN_SD_MOSI` aliases to `PIN_MOSI` etc., so the inline assembly resolves identically to today.

**Key methods requiring PASM pin reference updates**:

| Method | Line | Pins Referenced | Notes |
|---|---|---|---|
| `fl_command()` | 6337 | FL_MISO, FL_SCK, FL_CS | Flash-specific -- use FL_ pins |
| `fl_send()` | 6364 | FL_SCK, FL_MOSI (currently PIN_MOSI) | **Must change** PIN_MOSI -> PIN_FL_MOSI |
| `fl_receive()` | 6393 | FL_SCK, FL_CS, FL_MISO (currently PIN_MISO) | **Must change** PIN_MISO -> PIN_FL_MISO |
| `sp_transfer_8()` | 9102 | SD_MOSI, SD_MISO, SD_SCK | **Must change** PIN_MOSI -> PIN_SD_MOSI, PIN_MISO -> PIN_SD_MISO |
| `sp_transfer_32()` | 9149 | SD_MOSI, SD_MISO, SD_SCK | Same as above |
| `readSector()` streamer | 9546 | SD_SCK, SD_MISO (in stream_mode) | PIN_MISO -> PIN_SD_MISO in streamer config (line 9484) |
| `writeSector()` streamer | ~9850 | SD_SCK, SD_MOSI | PIN_MOSI -> PIN_SD_MOSI |
| `readSectors()` streamer | 9637 | SD_SCK, SD_MISO | PIN_MISO -> PIN_SD_MISO |
| `transfer()` bit-bang | 9611 | SD_SCK, SD_MOSI, SD_MISO | PIN_MOSI/MISO -> PIN_SD_MOSI/MISO |
| `configureEvent()` | 9017 | SD_SCK | Already uses PIN_SD_SCK |

### 3.3 Device Switching (Streamlined for Independent Buses)

**`switch_to_flash()`** (line 6138-6156):

```spin2
#ifdef SPI_INDEPENDENT_BUSES
PRI switch_to_flash()
  ' Independent buses: no pin reconfiguration needed.
  ' Flash has its own dedicated pins that are always ready.
  current_spi_device := DEV_FLASH
#else
PRI switch_to_flash()
  ' Shared bus: reconfigure shared pins from SD smart pins to Flash GPIO bit-bang
  if current_spi_device <> DEV_FLASH
    pinh(PIN_SD_CS)
    pinclear(PIN_SD_CS)
    pinclear(PIN_SD_SCK)
    pinclear(PIN_MOSI)
    pinclear(PIN_MISO)
    current_spi_device := DEV_FLASH
#endif
```

**`switch_to_sd()`** (line 6158-6182):

```spin2
#ifdef SPI_INDEPENDENT_BUSES
PRI switch_to_sd() : ok
  ' Independent buses: SD card state is never corrupted by Flash operations.
  ' No re-initialization needed.
  current_spi_device := DEV_SD
  ok := TRUE
#else
PRI switch_to_sd() : ok
  ' Shared bus: P60 (SD CS) doubles as Flash SCK, so SD card needs re-initialization
  ' after Flash operations to restore its SPI state.
  if current_spi_device == DEV_SD
    ok := TRUE
  else
    pinfloat(PIN_FL_CS)
    pinfloat(PIN_FL_SCK)
    ok := reinitCard()
    if ok
      current_spi_device := DEV_SD
#endif
```

**Performance benefit**: With independent buses, device switching becomes a simple state variable update. The shared-bus `reinitCard()` recovery (~50-100ms per Flash-to-SD switch) is no longer needed since Flash operations never disturb SD pin state.

### 3.4 reinitCard() -- Conditional Compilation

```spin2
#ifndef SPI_INDEPENDENT_BUSES
PRI reinitCard() : ok | resp, timeout, saved_freq
  ' ... entire 140-line method only needed for shared bus ...
#endif
```

With independent buses, `reinitCard()` is not needed (Flash operations don't affect SD pin state). Wrap it in `#ifndef` to save ~2KB of code space.

Similarly, the GPIO recovery flush constants and `saved_acmd41_arg` DAT variable are only needed for shared-bus mode.

### 3.5 Worker Cog Initialization (line 3541)

```spin2
PRI fs_worker() | cur_cmd
  ' Initialize SD SPI pins
  pinh(PIN_SD_CS)
  pinl(PIN_SD_SCK)

#ifdef SPI_INDEPENDENT_BUSES
  ' Also initialize Flash SPI pins (independent bus)
  pinl(PIN_FL_CS)            ' CS deselected (Flash CS polarity: HIGH=selected)
  pinl(PIN_FL_SCK)           ' SCK idle (will be configured per-command)
  pinf(PIN_FL_MISO)          ' MISO as input
  pinl(PIN_FL_MOSI)          ' MOSI idle LOW
#endif
```

### 3.6 Flash SPI Init During Mount

The Flash mount (`do_flash_mount()`, line 6625) doesn't currently have explicit pin initialization because `switch_to_flash()` handles it. With independent buses, Flash pins should be initialized once during mount:

```spin2
#ifdef SPI_INDEPENDENT_BUSES
  ' Initialize Flash SPI pins (independent bus -- one-time setup)
  pinl(PIN_FL_CS)             ' CS deselect
  pinf(PIN_FL_MISO)           ' MISO as input
  pinl(PIN_FL_MOSI)           ' MOSI idle
  ' FL_SCK configured per-command in fl_command()
#endif
```

### 3.7 SD initCard() Pin Setup (line 9183)

The `initCard()` method sets up pins at mount time. Pin references need updating:

```spin2
' Current (line 9215-9220):
pinh(PIN_SD_CS)
pinh(PIN_MOSI)        ' -> pinh(PIN_SD_MOSI)
pinl(PIN_SD_SCK)
wrpin(PIN_MISO, P_HIGH_15K)  ' -> wrpin(PIN_SD_MISO, P_HIGH_15K)
pinf(PIN_MISO)               ' -> pinf(PIN_SD_MISO)
```

And the GPIO recovery flush loop:

```spin2
' Current (line 9224-9229):
repeat GPIO_FLUSH_CYCLES
  pinh(PIN_SD_SCK)
  waitus(10)
  pinl(PIN_SD_SCK)
  waitus(10)
```

These already use `PIN_SD_SCK` so no change needed for the flush. But MOSI/MISO references in nearby code need `PIN_SD_` prefix.

### 3.8 Spin-Level Pin References (non-PASM)

Many Spin-level statements reference pins. All `PIN_MOSI`/`PIN_MISO` in SD context become `PIN_SD_MOSI`/`PIN_SD_MISO`:

```spin2
' Examples:
pinclear(PIN_MISO)    ' -> pinclear(PIN_SD_MISO)   (readSector, line 9533)
pinf(PIN_MISO)        ' -> pinf(PIN_SD_MISO)        (readSector, line 9534)
wrpin(PIN_MISO, ...)  ' -> wrpin(PIN_SD_MISO, ...)  (readSector, line 9568)
pinclear(PIN_MOSI)    ' -> pinclear(PIN_SD_MOSI)    (writeSector)
wrpin(PIN_MOSI, ...)  ' -> wrpin(PIN_SD_MOSI, ...)  (writeSector)
```

In shared-bus mode these resolve to the same values via the alias mechanism.

### 3.9 Streamer Mode Configuration

The streamer embeds the pin number in its mode word:

```spin2
' readSector (line 9484):
stream_mode := STREAM_RX_BASE | (PIN_MISO << 17) | (SECTOR_SIZE * 8)
'                                 ^^^^^^^^
'                                 -> PIN_SD_MISO

' writeSector (similar):
stream_mode := STREAM_TX_BASE | (PIN_MOSI << 17) | (SECTOR_SIZE * 8)
'                                 ^^^^^^^^
'                                 -> PIN_SD_MOSI
```

This is computed at runtime from CON constants, so the change is just the constant name.

### 3.10 Event Configuration

```spin2
' initSPIPins (line 9009):
spi_event := %01_000000 | PIN_SD_SCK    ' Already device-specific -- no change needed
```

---

## 4. Impact Summary

### 4.1 Files Changed

| File | Nature of Change |
|---|---|
| `dual_sd_fat32_flash_fs.spin2` | All changes below |

### 4.2 Change Categories

| Category | Est. Lines | Complexity | Risk |
|---|---|---|---|
| Pin constant restructuring | ~25 | Low | Low -- pure compile-time |
| `P_PLUSn_B` dynamic computation | ~20 | **Medium** | **Medium** -- P2 hardware constraint |
| PASM pin reference rename (`PIN_MOSI`->`PIN_SD_MOSI` etc.) | ~53 refs | Low | Low -- mechanical rename |
| `switch_to_flash()` conditional | ~15 | Low | Low |
| `switch_to_sd()` conditional | ~15 | Low | Low |
| `reinitCard()` ifdef guard | ~5 | Low | Low |
| `initCard()` pin rename | ~10 | Low | Low |
| `initSPIPins()` B-selector | ~15 | **Medium** | **Medium** |
| Streamer mode pin references | ~4 | Low | Low |
| Spin-level pin references | ~30 | Low | Low -- mechanical rename |
| Worker cog init | ~8 | Low | Low |
| Flash mount init | ~6 | Low | Low |
| **Total** | **~206** | | |

### 4.3 What Does NOT Change

- Flash filesystem logic (block allocation, file operations, CRC, translation tables)
- SD filesystem logic (FAT32 parsing, directory operations, file I/O)
- Worker cog command dispatch architecture
- Handle management system
- Multi-cog locking protocol
- All existing conditional compilation flags (SD_INCLUDE_RAW, etc.)
- Test framework and test suites (pin-agnostic)
- Public API (PUB methods unchanged)

---

## 5. Hardware Constraints

### 5.1 Smart Pin B-Input Range

P2 smart pins can only route B-input from pin+0 through pin+3. For SD SPI:

```
SD_SCK must be within [SD_MOSI .. SD_MOSI+3]  (for P_SYNC_TX clock source)
SD_SCK must be within [SD_MISO .. SD_MISO+3]  (for P_SYNC_RX clock source)
```

**Practical constraint**: All 4 SD pins should be within a contiguous 4-pin group, with SCK as the highest-numbered pin (or at most 3 above the lowest data pin). Example valid groups:

```
Group 1: MISO=24, MOSI=25, CS=26, SCK=27  (SCK = MOSI+2, MISO+3)
Group 2: MISO=40, MOSI=41, CS=42, SCK=43  (SCK = MOSI+2, MISO+3)
Group 3: CS=16, MISO=17, MOSI=18, SCK=19  (SCK = MOSI+1, MISO+2)
```

**Invalid**: MISO=10, MOSI=20, SCK=30 -- pins too far apart.

### 5.2 Flash Pin Freedom

Flash uses GPIO bit-bang (not smart pins), so Flash pins have **no relative-position constraint**. Any 4 GPIO-capable P2 pins will work. The only requirement is that fl_command() can configure P_TRANSITION on FL_SCK and FL_CS (which works on any pin).

### 5.3 Pin Group Separation

With independent buses, the SD and Flash pin groups must not overlap. No pin can appear in both groups.

### 5.4 Streamer Pin Constraint

The P2 streamer samples a single pin specified in the mode word. This pin must be the device's MISO (for reads) or MOSI (for writes). No additional constraint beyond the pin being valid GPIO.

---

## 6. Performance Impact

### 6.1 Device Switching Comparison

| Operation | Shared Bus | Independent Buses |
|---|---|---|
| Flash-to-SD switch | ~50-100ms (reinitCard) | ~0 (state variable update) |
| SD-to-Flash switch | ~10us (PINCLEAR x4) | ~0 (state variable update) |
| Consecutive same-device | 0 (lazy guard) | 0 (same) |

### 6.2 Code Size

| Component | Shared Bus | Independent Buses |
|---|---|---|
| `reinitCard()` | ~2KB | 0 (compiled out) |
| `switch_to_flash()` | ~100 bytes | ~20 bytes |
| `switch_to_sd()` | ~120 bytes | ~20 bytes |
| `computeBSelector()` | 0 | ~60 bytes |
| GPIO flush constants | ~50 bytes | 0 |
| **Net change** | baseline | **~-2.1KB saved** |

### 6.3 Interleaved Access Patterns

With independent buses, the worker cog can switch between devices instantly, making rapid interleaved access patterns more efficient (e.g., read Flash config, write SD log, read Flash config -- all without the shared-bus recovery step between device switches).

---

## 7. Testing Strategy

### 7.1 Compile-Time Verification

```bash
# Shared bus (default -- existing behavior must not regress)
pnut-ts -d dual_sd_fat32_flash_fs.spin2

# Independent buses
# (requires top-level file with #define SPI_INDEPENDENT_BUSES)
pnut-ts -d test_independent_spi.spin2
```

### 7.2 Hardware Testing

All 32 existing regression suites must pass in **both** modes:

1. **Shared-bus mode** (P2 Edge Module): Run full `./run_regression.sh` -- must match current 1,350-test baseline
2. **Independent-bus mode** (custom board): Run same suites with modified pin configuration

### 7.3 New Test Coverage

| Test | Purpose |
|---|---|
| Rapid device alternation | Verify no reinit delay in independent mode |
| Concurrent Flash+SD timing | Measure actual switch overhead vs shared bus |
| Pin constraint validation | Verify compile-time error for invalid SD pin groups |

---

## 8. Implementation Plan (Recommended Order)

### Phase 1: Pin Abstraction (Low Risk)

1. Add `SPI_INDEPENDENT_BUSES` pragma export
2. Restructure pin CON block with `#ifdef`/`#else`
3. Add `PIN_SD_MOSI`, `PIN_SD_MISO`, `PIN_FL_MOSI`, `PIN_FL_MISO` aliases in shared-bus `#else` block
4. Rename all `PIN_MOSI`/`PIN_MISO` references to device-specific names throughout driver
5. **Verify**: Compile both modes. Run full regression in shared-bus mode (must be zero-diff behavior).

### Phase 2: Smart Pin B-Selector (Medium Risk)

1. Add `computeBSelector()` helper method
2. Update `initSPIPins()` to compute `spi_tx_mode`/`spi_rx_mode` dynamically
3. Add compile-time or mount-time validation that SD pins are within B-input range
4. **Verify**: Compile and run shared-bus regression (selector should compute same values as today's hardcoded P_PLUS2_B/P_PLUS3_B).

### Phase 3: Conditional Switching (Major Benefit)

1. Wrap `switch_to_flash()` body in `#ifdef`/`#else`
2. Wrap `switch_to_sd()` body in `#ifdef`/`#else`
3. Wrap `reinitCard()` in `#ifndef SPI_INDEPENDENT_BUSES`
4. Add Flash pin init in `do_flash_mount()` for independent mode
5. Update worker cog init for independent mode
6. **Verify**: Full regression in shared-bus mode. Hardware test in independent mode on custom board.

### Phase 4: Cleanup and Documentation

1. Update `DOCs/DUAL-DRIVER-THEORY.md` with independent bus section
2. Update `DOCs/Analysis/SPI-BUS-STATE-ANALYSIS.md`
3. Add pin selection guidance to tutorial
4. Update EXAMPLES to show independent bus configuration

---

## 9. Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Smart pin B-input range violated by user | **High** (silent malfunction) | Add runtime check in initSPIPins() that aborts with debug message |
| PASM pin reference missed during rename | Medium (compile error likely) | Grep audit: count all #PIN_ refs before and after |
| Shared-bus regression break | **High** | Phase 1 must produce bit-identical binaries via alias mechanism |
| Flash GPIO on distant pins | Low (should work) | Flash bit-bang has no pin-distance constraint |
| Streamer with non-standard MISO pin | Low | Pin number is embedded in mode word at runtime |

---

## 10. Open Questions

1. **OBJ pipe for 8 CON overrides**: Does pnut-ts support overriding 8+ CON values via OBJ pipe in a single declaration? If not, the user may need to `#define` each pin constant before the OBJ import.

2. **Compile-time pin validation**: Can `#error` directives be used conditionally in pnut-ts to flag invalid pin configurations? If so, add guards for the B-input range constraint.

3. **Flash CS polarity**: The current Flash driver uses `drvh` to select CS and `drvl` to deselect. This matches the reference driver. Verify this polarity is correct for the user's Flash chip (most SPI Flash use active-LOW CS, but the P_TRANSITION mode may invert the sense).

4. **Worker cog initial device**: With independent buses, should the worker cog initialize both buses at startup, or still use lazy initialization? Recommendation: initialize both at startup since there's no cost to having both buses ready.
