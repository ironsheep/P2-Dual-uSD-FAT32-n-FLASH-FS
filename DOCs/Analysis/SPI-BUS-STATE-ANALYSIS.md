# SPI Bus State Analysis for Multi-Device Sharing

**Purpose**: Analyze whether the SD card driver leaves the SPI bus in a safe state for sharing with other devices (e.g., flash chip)
**Driver**: OB4269 FAT32 SD Card Driver (modified)
**Date**: 2026-01-16

---

## Executive Summary

**Finding**: The SD card driver **does** leave the SPI bus in a safe state after all public operations. The key safety mechanism is that CS (Chip Select) is always returned HIGH (deselected) at the end of every public method, causing the SD card to release the MISO line and ignore all bus traffic.

**Recommendation**: Multi-device SPI bus sharing is feasible, provided:
1. Each device has its own CS line
2. Only one device is selected (CS LOW) at a time
3. The other driver also returns CS HIGH after operations

---

## SPI Bus Sharing Architecture

### Multi-Device Configuration

```
                                    ┌─────────────┐
                              ┌────►│  SD Card    │
                              │     │  CS=HIGH    │ (deselected, ignores bus)
P2 Pins                       │     │  releases   │
────────────────────────────────────│  MISO       │
                              │     └─────────────┘
MOSI (P59) ───────────────────┼─────────────────────────────────►
                              │     ┌─────────────┐
MISO (P58) ◄──────────────────┼─────│  Flash Chip │
                              │     │  CS=LOW     │ (selected, active)
SCK  (P61) ───────────────────┼─────│  drives     │
                              │     │  MISO       │
SD_CS  (P60) ─────────────────┘     └─────────────┘
                                          │
FLASH_CS (Pxx) ───────────────────────────┘
```

### The CS (Chip Select) Rule

**When CS is HIGH (deselected):**
- The SD card ignores all MOSI and SCK activity
- The SD card releases MISO (high-impedance state)
- Any other device can safely use the bus

**When CS is LOW (selected):**
- The SD card responds to commands
- The SD card drives MISO
- No other device should be active

---

## Pin State Analysis by Function

### Pin State Table

| Function | Entry CS | Exit CS | Exit MOSI | Exit SCK | Safe? |
|----------|----------|---------|-----------|----------|-------|
| `mount()` | - | HIGH | HIGH | LOW | ✓ |
| `unmount()` | HIGH | HIGH | HIGH | varies | ✓ |
| `openFile()` | HIGH | HIGH | HIGH | varies | ✓ |
| `closeFile()` | HIGH | HIGH | HIGH | varies | ✓ |
| `newFile()` | HIGH | HIGH | HIGH | varies | ✓ |
| `deleteFile()` | HIGH | HIGH | HIGH | varies | ✓ |
| `read()` | HIGH | HIGH | HIGH | varies | ✓ |
| `write()` | HIGH | HIGH | HIGH | varies | ✓ |
| `sync()` | HIGH | HIGH | HIGH | varies | ✓ |
| `readDirectory()` | HIGH | HIGH | HIGH | varies | ✓ |
| `changeDirectory()` | HIGH | HIGH | HIGH | varies | ✓ |
| `freeSpace()` | HIGH | HIGH | HIGH | varies | ✓ |

**All public methods leave CS HIGH** ✓

---

## Detailed Code Path Analysis

### 1. `mount()` Function

```spin2
PUB mount(_cs,_mosi,_miso,_sck) : result
  pinh(cs)                    ' ◄── CS HIGH at start
  pinh(mosi)                  ' ◄── MOSI HIGH
  pinh(sck)                   ' Note: This is probably wrong, should be pinl for Mode 0
  ...
  if initCard()               ' initCard() returns with CS HIGH
    readSector(vbr_sec)       ' readSector() ends with CS HIGH
    ...
```

**`initCard()` CS handling:**
- Line 600: `pinh(cs)` - starts HIGH
- Line 611-615: Clock pulses with CS HIGH (correct for init)
- Calls `cmd()` multiple times
- `cmd()` always ends with `pinh(cs)` for non-sector commands

**Exit state**: CS=HIGH, MOSI=HIGH, SCK=LOW ✓

---

### 2. `readSector()` Function

```spin2
PRI readSector(sector)
  ...
  cmd(17, sector << hcs)      ' CS goes LOW inside cmd(), stays LOW
  ' PASM block reads data...
  pinh(cs)                    ' ◄── Line 792: CS HIGH at end
```

**Exit state**: CS=HIGH ✓

---

### 3. `writeSector()` Function

```spin2
PRI writeSector(sector)
  ...
  cmd(24, sector << hcs)      ' CS goes LOW, stays LOW
  transfer($FE, 8)            ' Start token
  ' PASM block writes data...
  repeat until (result := transfer(-1,8)) <> $FF
    if getct() - t > 0
      pinh(cs)                ' ◄── Line 820: CS HIGH on timeout
      return
  if result & $1F <> $05
    pinh(cs)                  ' ◄── Line 824: CS HIGH on error
    return
  repeat until transfer(-1,8)
    if getct() - t > 0
      pinh(cs)                ' ◄── Line 827: CS HIGH on timeout
      return
  pinh(cs)                    ' ◄── Line 829: CS HIGH on success
  return true
```

**All exit paths set CS HIGH** ✓

---

### 4. `cmd()` Function

```spin2
PRI cmd(op, parm) : result | t
  transfer(-1, 8)             ' Dummy byte
  pinl(cs)                    ' ◄── CS LOW (select card)
  transfer(-1, 8)             ' Dummy byte
  transfer($40 | op, 8)       ' Command
  transfer(parm, 32)          ' Argument
  transfer(crc, 8)            ' CRC
  ' Wait for response...
  if getct() - t > 0
    pinh(cs)                  ' ◄── CS HIGH on timeout
    return false
  if op == 8 or op == 58
    result := transfer(-1, 32)
  if op <> 17 and op <> 24 and op <> 55
    pinh(cs)                  ' ◄── CS HIGH for non-sector commands
```

**CS behavior**:
- For CMD17 (read) and CMD24 (write): CS stays LOW (caller will set HIGH)
- For CMD55 (APP_CMD prefix): CS stays LOW (ACMD follows immediately)
- For all other commands: CS goes HIGH before return

---

### 5. `transfer()` Function

```spin2
PRI transfer(data, bits) : result
  ' PASM block for SPI transfer
  ' Does NOT touch CS - relies on caller
```

The `transfer()` function is a pure data mover. It does not control CS, which is handled by the calling function.

---

## MISO Line Behavior

### SD Card MISO States

| CS State | MISO State |
|----------|------------|
| HIGH (deselected) | High-impedance (released) |
| LOW (selected) | Driven by card |

**Critical**: When CS goes HIGH, the SD card **immediately** releases MISO. This is required by the SD specification and enables bus sharing.

### Verification Points

1. After `readSector()`: CS=HIGH → MISO released ✓
2. After `writeSector()`: CS=HIGH → MISO released ✓
3. After `cmd()` (non-sector): CS=HIGH → MISO released ✓
4. After `mount()`: CS=HIGH → MISO released ✓

---

## SCK (Clock) Line State

### Observed Behavior

The SCK line state after operations is **not strictly controlled**:

| Function | SCK Exit State |
|----------|---------------|
| `transfer()` | HIGH (after final `drvh _sck`) |
| `readSector()` | HIGH (CRC clock-out ends high) |
| `writeSector()` | varies |
| `initCard()` | LOW (explicit `pinl(sck)` at start) |

### Impact on Bus Sharing

**For SPI Mode 0** (CPOL=0, CPHA=0):
- Idle clock should be LOW
- However, with CS HIGH, the SD card ignores clock edges
- The other device's driver should set its expected clock state before selecting

**Recommendation**: If the flash driver expects SCK=LOW at start, it should explicitly set it before lowering its CS.

---

## MOSI Line State

### Observed Behavior

MOSI is consistently left HIGH:

- `transfer()` ends with `drvh _mosi` (line 846)
- `writeSector()` ends with `drvh _mosi` (line 813)

### Impact

MOSI=HIGH is a safe idle state. The other device will only interpret MOSI when its CS is LOW.

---

## Bus Sharing Protocol Recommendations

### 1. Sequential Access Pattern

```spin2
' Use SD card
sd.mount(SD_CS, MOSI, MISO, SCK)
sd.openFile(string("DATA.TXT"))
sd.read(@buffer, 512)
sd.closeFile()
' Bus now safe: SD_CS=HIGH, MISO released

' Use Flash chip
pinl(SCK)                      ' Ensure SCK is in expected state
flash.read($1000, @buffer, 256)
' Bus now safe (if flash driver also releases)

' Back to SD card
sd.openFile(string("OTHER.TXT"))
...
```

### 2. Explicit Bus Release (Optional Enhancement)

Consider adding a method to ensure known bus state:

```spin2
PUB releaseBus()
  pinh(cs)      ' Ensure SD card deselected
  pinh(mosi)    ' MOSI HIGH (idle)
  pinl(sck)     ' SCK LOW (Mode 0 idle)
  ' MISO is now high-Z from SD card
```

### 3. Mutex for Multi-Cog Access

If multiple cogs might access the bus:

```spin2
VAR
  long bus_lock

PUB acquireBus()
  repeat until bus_lock == 0
  bus_lock := cogid() + 1

PUB releaseBus()
  pinh(cs)
  bus_lock := 0
```

---

## Flash Driver Requirements

For successful bus sharing, the flash driver must:

1. **Have its own CS pin** (different from SD_CS)
2. **Set CS HIGH after all operations**
3. **Release MISO when deselected** (this is a hardware requirement, not software)
4. **Optionally set SCK to expected idle state** before starting operations

### Analysis Checklist for Flash Driver

| Item | Requirement |
|------|-------------|
| Separate CS line | Yes |
| CS=HIGH after operations | Verify |
| SCK idle state expectation | Document |
| MOSI state expectation | Document |
| Compatible SPI mode (0, 1, 2, 3) | Verify match |

---

## Conclusion

### Safety Assessment: ✓ SAFE FOR BUS SHARING

The SD card driver correctly:
1. Returns CS=HIGH after every public method
2. Causes the SD card to release MISO (high-Z) when deselected
3. Leaves MOSI in a benign state (HIGH)

### Remaining Considerations

1. **SCK state**: Not guaranteed LOW. Other driver should set as needed.
2. **SPI mode compatibility**: Both devices must support the same mode (Mode 0 for this driver)
3. **Timing**: Allow a few microseconds between device switches for bus settling

### Next Steps

1. Analyze the flash driver for the same bus release behavior
2. Document both drivers' SPI mode requirements
3. Create a test that alternates between devices
4. Consider adding explicit `releaseBus()` methods to both drivers

---

*SPI Bus State Analysis for P2 microSD FAT32 Filesystem project*
