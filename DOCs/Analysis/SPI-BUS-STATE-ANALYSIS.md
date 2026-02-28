# SPI Bus State Analysis for Dual-Device Sharing

**Purpose**: Document how the unified dual-FS driver (`dual_sd_fat32_flash_fs.spin2`) manages the shared SPI bus between the SD card and onboard Flash chip, including device switching, pin reconfiguration, and recovery sequences.
**Driver**: `src/dual_sd_fat32_flash_fs.spin2` (unified dual-FS driver v1.0.0)
**Date**: 2026-02-28

---

## Executive Summary

**Finding**: The unified driver successfully shares a single 4-pin SPI bus between an SD card (FAT32) and a 16MB Flash chip. The two devices use **different SPI modes** (SD = Mode 0, Flash = Mode 3), **different pin configurations** (smart pins vs. GPIO bit-bang), and critically, **share P60/P61 in a cross-wired arrangement** where the SD card's CS pin doubles as the Flash chip's SCK pin. This cross-wiring means Flash operations inherently corrupt the SD card's SPI state, requiring a full re-initialization sequence (CMD0/CMD8/ACMD41/CMD58) on every switch back to SD.

**Conclusion**: Bus sharing works correctly in production. The driver has been hardware-verified with 1,200+ regression tests across both devices. The key safety mechanisms are:

1. **Worker cog exclusivity** -- a single worker cog owns all SPI pins; no contention possible
2. **Lazy device switching** -- consecutive operations on the same device incur no switching overhead
3. **PINCLEAR-based teardown** -- fully quiesces the smart pin mode before switching to Flash GPIO
4. **7-step SD recovery** -- reinitCard() reliably restores SD card state after Flash operations

---

## SPI Bus Architecture

### Pin Assignments (P2 Edge Module)

The P2 Edge Module's SPI header uses a 4-pin group with P58-P61. The SD card and Flash chip share MOSI (P59) and MISO (P58) but **cross-wire** the CS and SCK pins:

| Signal    | SD Card | Flash Chip | Physical Pin |
|-----------|---------|------------|-------------|
| CS        | P60     | P61        | P60 = SD CS, P61 = Flash CS |
| SCK       | P61     | P60        | P61 = SD SCK, P60 = Flash SCK |
| MOSI      | P59     | P59        | Shared |
| MISO      | P58     | P58        | Shared |

This is configured at lines ~673-680 of `dual_sd_fat32_flash_fs.spin2`:

```spin2
  cs := sd_cs                ' P60 - SD chip select
  mosi := _mosi              ' P59 - shared
  miso := _miso              ' P58 - shared
  sck := sd_sck              ' P61 - SD serial clock
  flash_cs_pin := sd_sck     ' P61 - Flash CS = SD's SCK pin
  flash_sck_pin := sd_cs     ' P60 - Flash SCK = SD's CS pin
```

### The P60/P61 Pin Swap Problem

The cross-wiring creates a fundamental issue: **Flash SCK (P60) is the same physical pin as SD CS (P60)**. When the Flash driver clocks data, it rapidly toggles P60 -- but from the SD card's perspective, its CS line is toggling rapidly. This drives the SD card's internal state machine through unpredictable states, corrupting its SPI interface.

This means switching from Flash back to SD requires a complete card re-initialization, not merely a CS deselect. The driver handles this transparently via `reinitCard()`.

```
  SD Operations:                    Flash Operations:
  ┌──────────┐                     ┌──────────┐
  │ P60 = CS │ (stable HIGH/LOW)   │ P60 = SCK│ (toggling rapidly!)
  │ P61 = SCK│ (clock)             │ P61 = CS │ (stable)
  │ P59 = TX │ (smart pin)         │ P59 = TX │ (GPIO bit-bang)
  │ P58 = RX │ (smart pin)         │ P58 = RX │ (GPIO bit-bang)
  └──────────┘                     └──────────┘
       │                                │
       │  SD card sees P60              │  Flash chip sees P61
       │  as its CS line                │  as its CS line
       └────────────────────────────────┘
            P60 toggling during Flash ops
            corrupts SD card SPI state!
```

---

## Worker Cog Command Dispatch and Lazy Switching

### Single-Owner Architecture

All SPI bus operations run in a **dedicated worker cog** launched by `init()`. Caller cogs send commands via a parameter block (`pb_cmd`, `pb_param0-3`) and wait via `WAITATN()`. The worker signals completion via `COGATN(1 << pb_caller)`. A hardware lock (`api_lock`) serializes multi-cog API access to prevent parameter block corruption.

This means only one cog ever touches the SPI pins, eliminating bus contention entirely.

### Lazy Device Switching (Line ~937)

The worker cog tracks which device currently owns the SPI bus via the DAT variable `current_spi_device` (line 606), which takes values `-1` (none), `0` (DEV_SD), or `1` (DEV_FLASH).

Before dispatching each command, the worker checks the command code range to determine the target device:

```spin2
    ' Lines 941-944: Lazy SPI bus switching
    if cur_cmd >= CMD_FLASH_MOUNT and cur_cmd <= CMD_FL_CAN_MOUNT
      switch_to_flash()
    else
      switch_to_sd()
```

Both `switch_to_flash()` and `switch_to_sd()` contain early-exit guards:

```spin2
    if current_spi_device == DEV_FLASH    ' Already on Flash? No-op.
      return
```

This means consecutive Flash operations (e.g., open + write + write + close) only incur the switching cost once. The expensive `reinitCard()` in `switch_to_sd()` only runs when actually transitioning from Flash back to SD.

### Command Code Ranges

SD commands occupy codes 1-46, Flash commands occupy codes 50-81. The dispatch boundary at `CMD_FLASH_MOUNT` (50) cleanly separates the two devices:

| Range | Device | Examples |
|-------|--------|---------|
| 1-46  | SD     | CMD_MOUNT(1), CMD_OPEN_READ(30), CMD_SET_VOL_LABEL(46) |
| 50-81 | Flash  | CMD_FLASH_MOUNT(50), CMD_FL_WR_BYTE(71), CMD_FL_CAN_MOUNT(81) |

---

## SD SPI Configuration: Smart Pins

### Smart Pin Mode Setup (initSPIPins(), Line ~7469)

The SD card uses the P2's smart pin hardware for high-speed SPI. Three smart pin modes are configured:

| Pin  | Smart Pin Mode | Configuration | Purpose |
|------|---------------|---------------|---------|
| SCK (P61)  | `P_TRANSITION | P_OE` | X = half-period, Y = transition count | Clock generation |
| MOSI (P59) | `P_SYNC_TX | P_OE | P_PLUS2_B` | X = `%1_00111` (8-bit start-stop) | Synchronized transmit |
| MISO (P58) | `P_SYNC_RX | P_PLUS3_B` | X = `%1_00111` (on-edge sample, 8-bit) | Synchronized receive |
| CS (P60)   | Standard GPIO | `pinh(cs)` / `pinl(cs)` | Manual chip select |

The `P_PLUS2_B` and `P_PLUS3_B` selectors route the SCK pin as the B-input clock source for MOSI and MISO respectively (SCK is 2 pins above MOSI and 3 pins above MISO in the P58-P61 group).

### SE1 Event Configuration (Line ~7542)

An SE1 event is configured for efficient waiting on SCK completion, avoiding polling loops:

```spin2
  spi_event := %01_000000 | sck     ' Positive edge on SCK IN
  configureEvent(spi_event)          ' setse1 in inline PASM
```

### Clock Speed Control (setSPISpeed(), Line ~7565)

SPI clock frequency is set by computing the half-period for P_TRANSITION mode:

```
half_period = ceil(clkfreq / (freq * 2))
```

With a minimum half-period of 4 sysclk cycles (ManAtWork convention). For a 320 MHz system clock:
- 400 kHz init: half_period = 400 clocks
- 25 MHz operational: half_period = 6 clocks (actual ~26.7 MHz)

The WXPIN register sets the period, and DRVL enables the smart pin:

```spin2
  wxpin(sck, half_period)    ' Set transition period
  pinl(sck)                  ' DRVL enables smart pin
```

---

## Flash SPI Configuration: GPIO Bit-Bang (Mode 3)

### Flash SPI Engine (fl_command(), Line ~3130)

The Flash chip uses SPI Mode 3 (CPOL=1, CPHA=1 -- clock idles HIGH). Instead of smart pins, the Flash engine uses **P_TRANSITION with inversion** for SCK and raw **GPIO bit-bang** (`drvc`/`testp`) for MOSI/MISO:

```spin2
  ' Line 3144: Flash SCK setup (Mode 3 -- inverted P_TRANSITION, clock idles HIGH)
  wrpin  ##%001000000_01_00101_0, _sclk    ' P_TRANSITION inverted
  wxpin  #4, _sclk                          ' 4 clocks per transition
```

The Flash CS pin has an inverted sense compared to SD (active-HIGH select in the original flash_fs.spin2 convention):

```spin2
  drvl  _cs          ' CS deselect
  waitx #14          ' Guard time (~50ns)
  drvh  _cs          ' CS select
```

### Flash Data Transfer (fl_send() / fl_receive(), Lines ~3154-3215)

Flash data is transferred via inline PASM bit-bang loops, not smart pins:

**Transmit (fl_send)**: Uses `rdfast` to stream from hub, then for each byte: `drvc` outputs each bit on MOSI while smart-pin SCK provides clocking via `wypin #16` (16 transitions = 8 bits).

**Receive (fl_receive)**: Uses `wrfast` to stream to hub, then for each byte: `testp` samples MISO into C flag, `rcl` accumulates bits, while SCK provides clocking. The command is terminated by driving CS LOW (deselect):

```spin2
  drvl  _cs          ' CS deselect (terminates command)
  fltl  _sclk        ' Reset smart pin
```

---

## Device Switching: switch_to_flash() (Line ~2941)

When switching from SD to Flash, the driver must remove all smart pin configurations from the SPI pins. Flash uses raw GPIO (`drvc`/`testp`), and residual smart pin modes would interfere.

### The Sequence

```spin2
PRI switch_to_flash()
  if current_spi_device == DEV_FLASH
    return                          ' Already on Flash -- no-op

  pinh(cs)                          ' Deselect SD CS (HIGH)

  ' Fully clear all SD smart pin modes
  pinclear(cs)                      ' P60: remove smart pin config
  pinclear(sck)                     ' P61: remove P_TRANSITION
  pinclear(mosi)                    ' P59: remove P_SYNC_TX
  pinclear(miso)                    ' P58: remove P_SYNC_RX

  current_spi_device := DEV_FLASH
```

### Why PINCLEAR, Not PINFLOAT

This is a critical implementation detail. The P2 has two different pin release operations:

| Operation | Effect | Safe for switching? |
|-----------|--------|-------------------|
| `PINFLOAT(pin)` | Sets DIR=0 (pin floats) but **WRPIN mode register survives** | **NO** -- residual P_SYNC_TX/P_SYNC_RX modes interfere with GPIO |
| `PINCLEAR(pin)` | Sets DIR=0 **AND** WRPIN(pin, 0) (fully stops smart pin) | **YES** -- clean slate for GPIO |

If `PINFLOAT` were used instead of `PINCLEAR`, the WRPIN register would retain its P_SYNC_TX or P_SYNC_RX configuration. When Flash code later tries to use `drvc` (drive-conditional) or `testp` (test pin) on those pins, the residual smart pin mode would intercept the GPIO operations, producing corrupt data.

This was discovered empirically during Phase 2 development and is documented as a critical lesson in the project memory. The fix was applied in both `switch_to_flash()` (line 2955-2958) and Step 1 of `reinitCard()` (lines 3023-3026).

---

## Device Switching: switch_to_sd() and reinitCard() (Lines ~2963-3128)

### switch_to_sd() (Line ~2963)

```spin2
PRI switch_to_sd() : ok
  if current_spi_device == DEV_SD
    ok := TRUE
    return                          ' Already on SD -- no-op

  ' Float Flash pins to release smart pin state
  pinfloat(flash_cs_pin)            ' P61 (Flash CS)
  pinfloat(flash_sck_pin)           ' P60 (Flash SCK)

  ' Re-initialize the SD card (recovery from corrupted SPI state)
  ok := reinitCard()
  if ok
    current_spi_device := DEV_SD
```

Note that `PINFLOAT` is sufficient here for the Flash pins because Flash uses `P_TRANSITION` on its SCK (which needs to stop clocking) and standard GPIO on CS. The WRPIN mode remaining on Flash pins is harmless because those pins will not be used for SD smart pin operations (Flash uses P60/P61; SD smart pins are on P58-P61 in different roles).

### reinitCard() -- 7-Step SD Recovery (Line ~2989)

This is the core recovery sequence that restores the SD card after Flash operations have corrupted its SPI state via the P60 toggling. It performs a minimal re-initialization, skipping redundant steps from the initial `mount()`:

**Skipped** (values cached from first mount): power-on delay, `identifyCard()`, `setOptimalSpeed()`

**Step 1: PINCLEAR + GPIO Recovery Flush** (Lines 3023-3038)

All four SPI pins are fully cleared with `PINCLEAR`, then configured as basic GPIO. A 4096-clock flush is performed at ~50 kHz using manual `pinh(sck)`/`pinl(sck)` toggling with `waitus(10)` delays:

```spin2
  pinclear(cs)    ' Remove any residual smart pin modes
  pinclear(sck)
  pinclear(mosi)
  pinclear(miso)

  pinh(cs)        ' CS HIGH (deselected)
  pinh(mosi)      ' MOSI HIGH (idle)
  pinl(sck)       ' SCK LOW (Mode 0 idle)
  pinf(miso)      ' MISO floating input

  repeat 4096     ' 512 bytes worth of clocks
    pinh(sck)
    waitus(10)
    pinl(sck)
    waitus(10)
```

The 4096 clocks serve to flush any partial transfer the SD card may have been in. If the card was mid-sector (stuck waiting for more clocks), these clocks allow it to complete and release MISO.

**Step 2: Smart Pin Initialization at 400 kHz** (Lines 3043-3050)

Reconfigures the smart pins and sets slow clock speed for the initialization command sequence:

```spin2
  initSPIPins()
  setSPISpeed(400_000)
  waitus(100)
  repeat 10
    sp_transfer_8($FF)    ' Dummy clocks via smart pins
```

**Step 3: CMD0 -- GO_IDLE_STATE** (Lines 3055-3064)

Sends CMD0 up to 5 times with 10ms delays, expecting response `$01` (idle state):

```spin2
  repeat 5
    resp := cmd(0, 0)
    if resp == $01
      quit
    waitms(10)
```

**Step 4: CMD8 -- SEND_IF_COND** (Lines 3071-3078)

Sends CMD8 with check pattern `$000001AA` to determine card version and set the ACMD41 argument:

```spin2
  resp := cmd(8, $000001AA)
  if (resp & $FFF) == $1AA
    saved_acmd41_arg := $40000000   ' SDHC/SDXC: set HCS bit
```

**Step 5: ACMD41 -- SD_SEND_OP_COND** (Lines 3083-3098)

Loops CMD55+CMD41 with a 2-second timeout until the card signals ready (`$00`):

```spin2
  t := getct() + clkfreq * 2     ' 2 second timeout
  repeat
    resp := cmd(55, 0)
    if resp <= $01
      resp := cmd(41, saved_acmd41_arg)
      if resp == $00
        quit
    if getct() - t > 0
      return false                ' Timeout
    waitms(10)
```

**Step 6: CMD58 -- READ_OCR** (Lines 3104-3112)

Reads the OCR register to restore the HCS (High Capacity Support) addressing mode:

```spin2
  resp := cmd(58, 0)
  if (resp >> 30) & 1
    hcs := 0      ' SDHC/SDXC: block addressing
  else
    hcs := 9      ' SDSC: byte addressing (shift sector << 9)
```

**Step 7: Restore Operational SPI Speed** (Lines 3117-3128)

Restores the fast SPI clock (saved before reinit), sends stabilization clocks, and invalidates all sector caches:

```spin2
  setSPISpeed(saved_freq)    ' Restore original speed (typically 25 MHz)
  pinh(cs)
  repeat 8
    sp_transfer_8($FF)       ' Stabilization clocks at new speed
```

Cache invalidation happens at the top of `reinitCard()` (lines 3007-3009):

```spin2
  sec_in_buf := -1           ' Invalidate data sector cache
  dir_sec_in_buf := -1       ' Invalidate directory sector cache
  fat_sec_in_buf := -1       ' Invalidate FAT sector cache
```

---

## Streamer DMA for Bulk Sector Transfers

### readSector() with Streamer (Line ~7952)

The SD driver uses the P2's streamer coprocessor for high-speed 512-byte DMA transfers, avoiding per-byte overhead. The streamer captures MISO data directly into hub RAM.

**Key setup** (lines 7998-8005):

```spin2
  stream_mode := STREAM_RX_BASE | (_miso << 17) | (512 * 8)   ' $C081_0000 + pin + 4096 bits
  clk_count := 512 * 8 * 2                                     ' 8192 clock transitions
  xfrq := $4000_0000 / spi_period                              ' NCO rate: 1 sample per clock period
  init_phase := $4000_0000                                      ' Sample mid-bit
```

**Critical step**: Before the streamer can capture from MISO, the MISO smart pin must be disabled. The streamer reads the raw pin state; a smart pin would intercept the data:

```spin2
  pinclear(_miso)    ' Clear smart pin mode
  pinf(_miso)        ' Float pin (input mode)
```

**Streamer sequence** (inline PASM, lines 8058-8067):

```pasm
  dirl    _sck           ' Reset SCK counter
  drvl    _sck           ' Re-enable with fresh phase
  setxfrq xfrq           ' Set streamer NCO rate
  wrfast  #0, p_buf      ' Target: hub buffer
  wypin   clk_count, _sck' Start 8192 clock transitions
  waitx   align_delay    ' Align to first rising edge
  xinit   stream_mode, init_phase  ' Start streamer
  waitxfi                ' Wait for completion
```

After the streamer completes, the MISO smart pin is rebuilt for CRC reads:

```spin2
  wrpin(_miso, spi_rx_mode)    ' P_SYNC_RX | P_PLUS3_B
  wxpin(_miso, %1_00111)       ' 8-bit, on-edge sample
  pinh(_miso)                  ' DIRH - enable
```

### writeSector() with Streamer (Line ~8273)

Similar pattern but in reverse -- the MOSI smart pin is disabled, data streams from hub to MOSI via the streamer, then MOSI is rebuilt for CRC transmission:

```spin2
  pinclear(_mosi)              ' Clear MOSI smart pin
  pinl(_mosi)                  ' Drive low for streamer control

  ' Inline PASM streamer TX
  dirl    _sck
  drvl    _sck
  setxfrq xfrq
  rdfast  #0, p_buf            ' Source: hub buffer
  xinit   stream_mode, #0      ' Start streamer (phase=0 for TX)
  waitx   align_delay          ' Wait for NCO to output first bit
  wypin   clk_count, _sck      ' Start clock
  waitxfi                      ' Wait for completion
```

After the streamer, MOSI is rebuilt:

```spin2
  wrpin(_mosi, spi_tx_mode)    ' P_SYNC_TX | P_OE | P_PLUS2_B
  wxpin(_mosi, %1_00111)       ' 8-bit start-stop
  pinh(_mosi)                  ' DIRH - enable
```

### Streamer Constants (Lines 270-271)

```spin2
  STREAM_RX_BASE = $C081_0000   ' 1-pin input to hub (WFBYTE), MSB-first
  STREAM_TX_BASE = $8081_0000   ' hub (RFBYTE) to 1-pin output, MSB-first
```

---

## CRC-16 Validation and Card Status Checks

### CRC-16-CCITT Calculation (calcDataCRC(), Line ~7603)

The driver uses hardware-accelerated CRC via the P2's `GETCRC` instruction, eliminating the need for a 512-byte lookup table:

```spin2
  raw := GETCRC(pData, CRC_POLY_REFLECTED, len)   ' Poly = $8408 (reflected)
  crc := ((raw ^ CRC_BASE_512) REV 31) >> 16      ' Transform to match SD card's CRC
```

Constants (lines 276-277):
- `CRC_POLY_REFLECTED = $8408` -- CRC-16-CCITT in LSB-first form
- `CRC_BASE_512 = $2C68` -- GETCRC of 512 zero bytes (compensation value)

### Read CRC Validation with Retry (Lines 8084-8110)

After every sector read, the driver compares the calculated CRC against the 2-byte CRC received from the card. On mismatch, it retries up to `MAX_READ_CRC_RETRIES` (3) times:

```spin2
  diag_calc_crc := calcDataCRC(p_buf, 512)
  if diag_calc_crc == diag_recv_crc
    pinh(cs)          ' Success -- deselect card
    quit
  else
    pinh(cs)          ' Deselect before retry
    sp_transfer_8($FF)' 8 NCS recovery clocks
    ' ... retry loop
```

### Write CRC Transmission (Lines 8390-8399)

Before transmitting write CRC, the driver calculates CRC-16 of the buffer and sends high byte first:

```spin2
  diag_sent_crc := calcDataCRC(p_buf, 512)
  sp_transfer_8(diag_sent_crc >> 8)    ' CRC high byte
  sp_transfer_8(diag_sent_crc & $FF)   ' CRC low byte
```

The card responds with a data-response token; `$05` (bits [3:1] = `010`) means accepted, `$0B` means CRC error, `$0D` means write error.

### checkCardStatus() -- CMD13 Post-Operation Verification (Line ~8706)

After every `readSector()` and `writeSector()`, the driver sends CMD13 (SEND_STATUS) to verify the card's internal state. This catches errors that CRC cannot detect (ECC failures, address errors, internal write failures):

```spin2
  ' CMD13 returns R2 response: R1 byte + status byte
  r1 := waitR1Response()
  status := sp_transfer_8($FF)
  pinh(cs)
  if r1 <> $00 or status <> $00
    return -1    ' Card error detected
```

Diagnostic variables `last_cmd13_r1`, `last_cmd13_status`, and `last_cmd13_error` preserve the last CMD13 results for test inspection.

---

## Summary of SPI Modes

| Property | SD Card | Flash Chip |
|----------|---------|------------|
| SPI Mode | Mode 0 (CPOL=0, CPHA=0) | Mode 3 (CPOL=1, CPHA=1) |
| Clock Idle | LOW | HIGH |
| Pin Engine | P2 smart pins | P_TRANSITION + GPIO bit-bang |
| SCK Config | `P_TRANSITION | P_OE` (line 7488) | `P_TRANSITION` inverted (line 3144) |
| MOSI Config | `P_SYNC_TX | P_OE | P_PLUS2_B` | `drvc` in inline PASM |
| MISO Config | `P_SYNC_RX | P_PLUS3_B` | `testp` in inline PASM |
| CS Control | GPIO `pinh`/`pinl` on P60 | GPIO `drvh`/`drvl` on P61 |
| Bulk Transfer | Streamer DMA (XINIT) | Inline PASM byte loops |
| Max Clock | 25 MHz (configurable) | ~10 MHz (fixed 4-clock period) |

---

## Conclusion

### Safety Assessment: VERIFIED SAFE

The unified driver correctly manages the shared SPI bus through:

1. **Worker cog exclusivity**: Only one cog touches SPI pins -- no contention possible
2. **Lazy switching**: `current_spi_device` tracking ensures no redundant device switches
3. **PINCLEAR teardown**: Smart pin modes are fully removed before Flash GPIO operations
4. **7-step SD recovery**: `reinitCard()` reliably restores the SD card after Flash corrupts its state via the P60/P61 cross-wiring
5. **CRC validation**: Every sector transfer is CRC-16 verified; reads retry up to 3 times on mismatch
6. **CMD13 verification**: Card internal state is checked after every read/write operation
7. **Cache invalidation**: All sector caches are invalidated on device switches to prevent stale data

### Hardware Verification

This bus-sharing implementation has been validated on real P2 hardware with:
- 25 Phase 1 SD basic tests
- 27 Phase 2 dual-device mount tests
- 43 Phase 3 Flash file operation tests
- 301 Phase 4 SD regression tests (16 suites)
- 849 Phase 5 Flash regression tests (9 suites)
- 17 Phase 6 cross-device copy tests
- 3 Phase 7 example programs

**Total: 1,265 tests, 0 failures across all phases.**

---

*SPI Bus State Analysis for the P2 Dual uSD FAT32 + Flash Filesystem Project*
*Source: `src/dual_sd_fat32_flash_fs.spin2` -- Unified dual-FS driver v1.0.0*
