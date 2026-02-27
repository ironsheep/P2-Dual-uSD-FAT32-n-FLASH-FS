# isp_mem_strings - User Guide

A `sprintf()`-like string formatting object for Spin2 on the Parallax Propeller 2. Formats strings with escape sequences and embedded values into a caller-supplied byte buffer in memory.

- **Author:** Stephen M. Moraco (leveraged from `jm_serial.spin2` by Jon McPhalen)
- **License:** MIT
- **Dependency:** None (number-to-string conversions are inlined)

---

## Quick Start

### 1. Declare the object and a buffer

```spin2
OBJ
    strFmt : "isp_mem_strings"

VAR
    BYTE    buffer[128]
```

### 2. Format a string

```spin2
PUB example() | nLen
    nLen := strFmt.sFormatStr1(@buffer, string("Temperature: %d F"), 72)
    ' buffer now contains: "Temperature: 72 F" (zero-terminated)
```

---

## Public API Reference

| Method | Signature | Description |
|--------|-----------|-------------|
| `sFormatStr0` | `(pUserBuff, p_str) : nPlaced` | Format string with **no** arguments |
| `sFormatStr1` | `(pUserBuff, p_str, arg1) : nPlaced` | Format string with **1** argument |
| `sFormatStr2` | `(pUserBuff, p_str, arg1, arg2) : nPlaced` | Format string with **2** arguments |
| `sFormatStr3` | `(pUserBuff, p_str, arg1, arg2, arg3) : nPlaced` | Format string with **3** arguments |
| `sFormatStr4` | `(pUserBuff, p_str, ..., arg4) : nPlaced` | Format string with **4** arguments |
| `sFormatStr5` | `(pUserBuff, p_str, ..., arg5) : nPlaced` | Format string with **5** arguments |
| `sFormatStr6` | `(pUserBuff, p_str, ..., arg6) : nPlaced` | Format string with **6** arguments |
| `sFormatStr7` | `(pUserBuff, p_str, ..., arg7) : nPlaced` | Format string with **7** arguments |
| `sFormatStr8` | `(pUserBuff, p_str, ..., arg8) : nPlaced` | Format string with **8** arguments |
| `sFormat` | `(pUserBuff, p_str, p_args) : nPlaced` | Low-level: takes a pointer to an array of longs |

**Parameters (all methods):**

- **pUserBuff** -- Pointer to the destination byte buffer (must be pre-allocated and large enough)
- **p_str** -- Pointer to the format control string
- **arg1...argN** -- Values to substitute into `%` format specifiers
- **Returns `nPlaced`** -- Count of characters written (excluding the zero terminator)

---

## Format Specifiers

### Escape Characters

| Escape | Output |
|--------|--------|
| `\\` | Literal backslash `\` |
| `\%` | Literal percent `%` |
| `\q` | Double quote `"` |
| `\b` | Backspace |
| `\t` | Tab (horizontal) |
| `\n` | New line (line feed) |
| `\r` | Carriage return |
| `\nnn` | Arbitrary ASCII value (nnn is decimal, e.g., `\065` = `A`) |

### Value Format Specifiers

| Specifier | Meaning | Example |
|-----------|---------|---------|
| `%d` | Decimal integer | `%d` with 42 &rarr; `42` |
| `%x` | Hexadecimal | `%x` with 255 &rarr; `FF` |
| `%o` | Octal | `%o` with 8 &rarr; `10` |
| `%q` | Quaternary (base 4) | `%q` with 5 &rarr; `11` |
| `%b` | Binary | `%b` with 5 &rarr; `101` |
| `%s` | String (pointer) | `%s` with @"hi" &rarr; `hi` |
| `%c` | Character (repeated) | `%c` with `"*"` &rarr; `*` |
| `%w.pf` | Fixed-point decimal | `%6.2f` with 1234 &rarr; ` 12.34` |

### Width and Precision Modifiers

Format: `%[w[.p]]X` where:

- **w** (width) -- Minimum field width. Positive = right-aligned, negative = left-aligned.
- **p** (precision) -- For numerics: minimum digits (zero-padded). For `%f`: digits after the decimal point.

| Format | Value | Output | Notes |
|--------|-------|--------|-------|
| `%d` | 42 | `42` | No padding |
| `%6d` | 42 | `    42` | Right-aligned, width 6 |
| `%-6d` | 42 | `42    ` | Left-aligned, width 6 |
| `%6.4d` | 42 | `  0042` | Width 6, 4-digit minimum |
| `%06x` | 255 | `0000FF` | 6-digit hex with leading zeros |
| `%4d` | 7 | `   7` | Right-aligned, width 4 |
| `%6.2f` | 1234 | ` 12.34` | Fixed-point: 2 digits after decimal |

---

## Real-World Usage Patterns

The following patterns are drawn from 6 production projects across 13 consumer files.

### Pattern 1: Simple Value Formatting

The most common pattern -- format one or two values into a buffer, then pass the buffer to a display or serial routine.

**Formatting display dimensions for an eInk screen** (from P2-Click-eInk):

```spin2
OBJ
    eInkDisplay : "isp_eInk_click"
    strFmt      : "isp_mem_strings"

VAR
    BYTE    strBuffer[20+1]

PRI drawOrientationDisplay(rotation) | dsplyWidthInPix, dsplyHeightInPix, ...
    dsplyWidthInPix, dsplyHeightInPix := eInkDisplay.displaySize()

    ' Format display dimensions as "w296, h128"
    strFmt.sFormatStr2(@strBuffer, string("w%d, h%d"), dsplyWidthInPix, dsplyHeightInPix)

    ' Use the formatted string on the display
    eInkDisplay.setTextAtXY(startX, startY + 15, @strBuffer)
```

**Formatting a temperature reading as fixed-point decimal** (from P2-RPi-ioT-Gateway):

```spin2
VAR
    byte    fmtBuffer[FMT_BFFR_LEN+1]

    ' Format temperature as fixed-point decimal: "  72.50 F"
    strFmt.sFormatStr1(@fmtBuffer, string("%6.2f F"), (tempF + 50)/100)
    debug("* main: 1-wire says [", zstr_(@fmtBuffer), "]")
```

---

### Pattern 2: Incremental String Building (Buffer Cursor Advancement)

Use the return value `nPlaced` to build up a long string from multiple formatted segments. Each call appends after the previous one by advancing the buffer pointer.

**Building a multi-line email body** (from P2-RPi-ioT-Gateway):

```spin2
DAT
    emailBody   byte    0[1024]         ' 1k buffer for email text

PUB main() | nLen, ...
    ' First call assigns the initial length
    nLen := strFmt.sFormatStr0(@emailBody, string("hi,\n"))

    ' Subsequent calls ADD to the running length to advance the write position
    nLen += strFmt.sFormatStr0(@BYTE[@emailBody][nLen], string("  This is being sent from the P2 via the RPi gateway\n"))
    nLen += strFmt.sFormatStr0(@BYTE[@emailBody][nLen], string("\n"))

    ' Mix in formatted values
    nLen += strFmt.sFormatStr1(@BYTE[@emailBody][nLen], string("  Sample Temperature reading: %s\n"), @sampleStrVar)
    nLen += strFmt.sFormatStr1(@BYTE[@emailBody][nLen], string("  Sample data value: %d\n"), sampleIntVar)

    nLen += strFmt.sFormatStr0(@BYTE[@emailBody][nLen], string("\n"))
    nLen += strFmt.sFormatStr0(@BYTE[@emailBody][nLen], string("Regards,\n"))
    nLen += strFmt.sFormatStr0(@BYTE[@emailBody][nLen], string("Your friendly P2!\n"))

    ' emailBody now contains the complete multi-line email text
    IoT_GW.sendEmail(@emailTo, @emailSubj, @emailBody)
```

**Key insight:** `@BYTE[@emailBody][nLen]` computes the pointer to position `nLen` in the buffer, so each new formatted segment appends right after the previous one.

---

### Pattern 3: Error Message Construction

Format runtime values into descriptive error messages for serial communication.

**Validation error reporting** (from P2-BLDC-MotorControl):

```spin2
DAT
    msgWork     BYTE    0[256]          ' 256-byte message work buffer

PRI handleDriveDirection(drvPwr1, drvDir) | ...
    if not isInRange(drvPwr1, -100, 100)
        strFmt.sFormatStr1(@msgWork, @"Power (%d) out of range [-100, 100]", drvPwr1)
        serialQueue.sendError(@msgWork)
        return

    if not isInRange(drvDir, -100, 100)
        strFmt.sFormatStr1(@msgWork, @"Direction (%d) out of range [-100, 100]", drvDir)
        serialQueue.sendError(@msgWork)
        return
```

**Sending query responses back to a host** (from P2-BLDC-MotorControl):

```spin2
    ltValue, rtValue := wheels.getDistance(nDistUnits)
    strFmt.sFormatStr2(@msgWork, @"dist %d %d\n", ltValue, rtValue)
    serialQueue.sendResponse(@msgWork)

    ltValue, rtValue := wheels.getPower()
    strFmt.sFormatStr2(@msgWork, @"pwr %d %d\n", ltValue, rtValue)
    serialQueue.sendResponse(@msgWork)
```

---

### Pattern 4: Hex Formatting with Post-Processing

Format a value as hex and then massage the result.

**Color value to hex string** (from P2-RPi-ioT-Gateway):

```spin2
PRI colorAsHexString(nColor, pWorkBffr, nBffrLenMax) : pBffr | nIdx
    ' Format as 6-digit hex: "0x00FF80"
    strFmt.sFormatStr1(pWorkBffr, string("0x%06x"), nColor >> 8)

    ' Replace any leading spaces with '0' characters
    repeat nIdx from 2 to strsize(pWorkBffr) - 1
        if BYTE[pWorkBffr][nIdx] == $20
            BYTE[pWorkBffr][nIdx] := $30
        else
            quit
```

---

### Pattern 5: Two-Stage Dynamic Format Strings

Build a format string dynamically at runtime, then use it to format actual values. This enables configurable field widths.

**Right-aligning values and strings to a variable width** (from P2-Multi-servo):

```spin2
OBJ
    memstr : "isp_mem_strings"

DAT
    rateMsg     byte    0[20]

PRI rightAlignValue(value, width) : pMessage | lenBytes, BYTE fmtStr[20]
    ' Step 1: Build format string "%<width>d" (e.g., width=6 produces "%6d")
    lenBytes := memstr.sFormatStr1(@fmtStr, @"\%%dd", width)

    ' Step 2: Use the dynamic format string to format the actual value
    lenBytes := memstr.sFormatStr1(@rateMsg, @fmtStr, value)
    pMessage := @rateMsg

PRI rightAlignString(pStr, width) : pMessage | lenBytes, BYTE fmtStr[20]
    ' Same technique for strings: build "%<width>s", then apply it
    lenBytes := memstr.sFormatStr1(@fmtStr, @"\%%ds", width)
    lenBytes := memstr.sFormatStr1(@rateMsg, @fmtStr, pStr)
    pMessage := @rateMsg
```

**How it works:** The format string `@"\%%dd"` contains `\%` (escaped percent &rarr; literal `%`), then `%d` (substitute the width value), then `d` (literal). So `sFormatStr1(@fmtStr, @"\%%dd", 6)` produces the string `%6d`, which is then used as the format string in the second call.

---

### Pattern 6: Serial Protocol Message Construction

Format structured protocol messages with port numbers and sequence counters.

**Building test messages with sequence numbers** (from P2-OctoSerial):

```spin2
PUB getMessageForCount(pBuffer, portIndex, nCount, eMsgState)
    if eMsgState == MSG_ACKD
        strFmt.sFormatStr2(pBuffer, string("%d:Test Message #%4d ACK?\r\n"), portIndex + 1, nCount)
    elseif eMsgState == MSG_RAW
        strFmt.sFormatStr2(pBuffer, string("%d:Test Message #%4d ---?\r\n"), portIndex + 1, nCount)
    elseif eMsgState == MSG_NAKD
        strFmt.sFormatStr2(pBuffer, string("%d:Test Message #%4d NAK?\r\n"), portIndex + 1, nCount)
    replaceMarkerWithCRC(pBuffer, @"?")
```

**Composite label generation** (from P2-Multi-servo):

```spin2
PRI genStateMsg(nServo, nState) : pMessage | lenBytes, pStateMsg
    pStateMsg := (nState == 0) ? @msgLOW : @msgHIGH
    lenBytes := memstr.sFormatStr2(@Title1, @"SRVO-%d %s", nServo, pStateMsg)
    pMessage := @Title1
```

---

## Buffer Sizing Guidelines

| Use Case | Recommended Size | Example Declaration |
|----------|-----------------|---------------------|
| Short labels / single values | 20-32 bytes | `BYTE strBuffer[21]` |
| Error messages | 128-256 bytes | `BYTE msgWork[256]` |
| Multi-line text (emails, logs) | 512-1024 bytes | `BYTE emailBody[1024]` |

Buffers can be declared in either `VAR` (instance-specific) or `DAT` (shared/global) sections.

---

## Tips and Best Practices

1. **Always allocate enough buffer space.** There is no overflow protection -- if the formatted string exceeds the buffer, it will silently overwrite adjacent memory.

2. **Use the return value** (`nPlaced`) when building strings incrementally. It tells you exactly how many characters were written, so you can advance your write pointer for the next append.

3. **String literal syntax matters:**
   - `string("text")` -- Creates an inline string constant (common in OBJ method calls)
   - `@"text"` -- Pointer to a string literal in DAT context

4. **The `\%` escape** lets you include a literal `%` in output. This is essential for the two-stage dynamic format string technique (Pattern 5).

5. **Common object prefixes** seen across production code:
   - `strFmt` -- most common (used in 5 of 6 projects)
   - `memstr` -- used in the Multi-servo project

6. **Only include what you need.** In practice, `sFormatStr0`, `sFormatStr1`, and `sFormatStr2` cover the vast majority of real-world use cases. The higher-arity methods (`sFormatStr3` through `sFormatStr8`) and the low-level `sFormat` are available for complex formatting needs.

---

## PST Formatting Constants

The object exposes these constants for use with PST-compatible terminals:

| Constant | Value | Meaning |
|----------|-------|---------|
| `HOME` | 1 | Cursor home |
| `CRSR_XY` | 2 | Set cursor X,Y |
| `CRSR_LF` | 3 | Cursor left |
| `CRSR_RT` | 4 | Cursor right |
| `CRSR_UP` | 5 | Cursor up |
| `CRSR_DN` | 6 | Cursor down |
| `BELL` | 7 | Bell |
| `BKSP` | 8 | Backspace |
| `TAB` | 9 | Tab |
| `LF` | 10 | Line feed |
| `CLR_EOL` | 11 | Clear to end of line |
| `CLR_DN` | 12 | Clear down |
| `CR` | 13 | Carriage return |
| `CRSR_X` | 14 | Set cursor X |
| `CRSR_Y` | 15 | Set cursor Y |
| `CLS` | 16 | Clear screen |

---

## Projects Using This Object

| Project | Consumer Files | Call Sites | Primary Use Case |
|---------|---------------|------------|-----------------|
| P2-BLDC-MotorControl | 1 | 22 | Error messages and serial protocol responses |
| P2-Multi-servo | 4 | 20 | Display labels and right-aligned values on TIMI display |
| P2-RPi-ioT-Gateway | 3 | ~12 | Email body, hex colors, temperature display |
| P2-OctoSerial | 4 | ~8 | Serial port test message construction |
| P2-Click-eInk | 1 | 1 | eInk display dimension text |
| P2-uSD-FAT32-FS | 0 | 0 | Present in project but no active callers |
