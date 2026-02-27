# Propeller 2 `debug()` -- User Guide

A study of how `debug()` is used across 7 Iron Sheep production projects, covering message tagging conventions, format specifiers, compile-time and runtime debug control, graphical debug displays, and project-specific patterns.

---

## Table of Contents

1. [The Golden Rule: Underscore Suffix](#the-golden-rule-underscore-_-suffix)
2. [Message Tagging Conventions](#message-tagging-conventions)
3. [Module Prefix Convention](#module-prefix-convention)
4. [Message Structure Patterns](#message-structure-patterns)
5. [Format Specifier Reference](#format-specifier-reference)
6. [Controlling Debug Output](#controlling-debug-output)
7. [Graphical Debug Displays (Backtick Syntax)](#graphical-debug-displays-backtick-syntax)
8. [Project-Specific Conventions](#project-specific-conventions)
9. [Complete Formatter Quick Reference](#complete-formatter-quick-reference)
10. [Tips and Best Practices](#tips-and-best-practices)

---

## The Golden Rule: Underscore (`_`) Suffix

The single most important concept for debug formatters:

| Formatter | Output |
|-----------|--------|
| `udec(myVar)` | `myVar = 42` (includes variable name) |
| `udec_(myVar)` | `42` (value only) |

The underscore suppresses the automatic name label. This applies to **all** numeric and array formatters. Use the underscore version when building custom formatted messages; use the plain version for quick diagnostic dumps.

---

## Message Tagging Conventions

A consistent set of prefix tags is used across all projects to categorize debug output by severity and purpose. These prefixes make it easy to visually scan debug output and filter for specific message types.

### Severity/Purpose Prefixes

| Prefix | Meaning | Example |
|--------|---------|---------|
| `"* "` | General status / action / milestone | `debug("* demo dual motor control via R/C")` |
| `"** "` | Memory dump header | `debug("** ", zstr_(pMessage), ":")` |
| `"*** "` | Completion marker or corruption alert | `debug("***  DONE  ***")` |
| `"++ "` | Milestone achieved | `debug("++ Motors ready, let's drive!")` |
| `"+++ "` | Test pass/fail result | `debug("+++ TEST [", zstr_(pTestId), "] - ", zstr_(pResult))` |
| `"-- "` | Internal operation detail | `debug("-- dqrs:", uhex_long(pRmStr), udec(nQStrCount))` |
| `"--- "` | Board detection / subsection | `debug("--- ", udec(pinSum), ", 64010 Rev A")` |
| `"---- "` | Fatal stop marker | `debug("---- FAIL - stopping here for Analysis of above ^^^")` |
| `"^^^ "` | Stack checking | `debug("^^^ STACK used ", udec(nStkChkUsed), " of ", udec(nStackLongCt))` |
| `"--> "` | Return value / result arrow | `debug("--> read_tca() = ", uhex(tmpC))` |
| `">> "` | Test sequence step | `debug(">> 001 is T/F:", ubin_byte(bStatus))` |
| `"(DBG) "` | Explicit debug-only (usually commented out) | `debug("(DBG) ", udec(nQStrCount))` |

### Error Prefixes

| Prefix | Severity | Example |
|--------|----------|---------|
| `"!! "` | Error (inline) | `debug("!! ERROR filed to start RX-QUE task")` |
| `"EEEE: "` / `"EEE "` | Severe / fatal error | `debug("EEEE: SBUS rcvr not started?!")` |
| `"ERROR"` | Standard error keyword | `debug("* ERROR user configuration NOT valid!")` |
| `"FAIL"` | Assertion / test failure | `debug("  [do_mount] FAIL: initCard() returned false")` |
| `"FATAL"` | Unrecoverable corruption | `debug("FIFO FATAL: freeHead=", udec(freeHead), " CORRUPTED!")` |
| `"WARNING"` | Non-fatal advisory | `debug("    [setSPISpeed] WARNING: Half-period clamped to minimum (4)")` |
| `"TIMEOUT"` | Operation timeout | `debug("  [readSector] TIMEOUT waiting for start token")` |

### Practical Examples

**Status milestone** (P2-OctoSerial, `test_octoExercise_send.spin2`):
```spin2
debug("* -----  TRANSMIT end STARTED  ----- *")
```

**Test result reporting** (P2-OctoSerial, `isp_stack_check.spin2`):
```spin2
debug("+++ ---------")
debug("+++ TEST [", zstr_(pTestId), "] - ", zstr_(pResult))
```

**Stack overflow detection** (P2-OctoSerial, `isp_stack_check.spin2`):
```spin2
debug("^^^ STACK Overflow! Depth greater than ", udec(nStackLongCt), " longs")
```

**Fatal halt** (P2-OctoSerial, `isp_stack_check.spin2`):
```spin2
debug("---- FAIL - stopping here for Analysis of above ^^^")
repeat      ' hold here for analysis
```

---

## Module Prefix Convention

Each object/module uses a short prefix tag to identify the source of debug output. This makes it easy to trace which object produced a given message.

| Prefix | Module | Project |
|--------|--------|---------|
| `"SP8: "` | OctoSerial 8-port driver | P2-OctoSerial |
| `"8S: "` | OctoSerial (abbreviated) | P2-OctoSerial |
| `"TskU: "` | Task utility (offloader) | P2-OctoSerial |
| `"strQ: "` | String queue | P2-OctoSerial |
| `"MOT: "` | BLDC motor driver | P2-BLDC-MotorControl |
| `"TASK[Rx] "` | Serial receive task | P2-BLDC / P2-RPi-ioT-GW |
| `"hrf: "` | Host request format | P2-BLDC / P2-RPi-ioT-GW |
| `"stm: "` | State machine | P2-RPi-ioT-Gateway |
| `"EYEs: "` | Servo eyes mechanism | P2-Multi-servo |
| `"enc: "` | Rotary encoder | P2-Multi-servo |
| `"TIMI: "` | TIMI display module | P2-Multi-servo |
| `"tch- "` | Touch controller | P2-Click-eInk |
| `"ft: "` | Font subsystem | P2-Click-eInk |
| `"i2c: "` | I2C singleton | P2-Click-eInk |
| `"sfmt: "` | String formatter (isp_mem_strings) | Multiple projects |
| `"FIFO: "` / `"FIFO FATAL: "` | Frame FIFO manager | P2-Magnetic-Imaging-Tile |
| `"HDMI Engine: "` | HDMI display engine | P2-Magnetic-Imaging-Tile |
| `"OLED: "` / `"OLED Driver: "` | OLED display driver | P2-Magnetic-Imaging-Tile |
| `"Sensor: "` | Tile sensor driver | P2-Magnetic-Imaging-Tile |
| `"WRITER: "` / `"PRODUCER: "` / `"CONSUMER: "` | Test role identification | P2-Magnetic-Imaging-Tile |

**Examples:**

```spin2
' OctoSerial driver
debug("SP8: ", udec(rxp), udec(txp), udec(baudrate), udec(portHandle))
debug("SP8: ERROR: not starting, no ports specified!")
debug("SP8: rx(", uhex_byte_(nChar), ")")

' Motor driver
debug("MOT: ", udec(fwdDegrees), uhex_long(offset_fwd))
debug("MOT: busy!!")
debug("MOT: WAIT-fault-reset ended still-FAULT!")

' Serial receive task
debug("TASK[Rx] started ", uhex(pRxByteStart), ", ", udec(nRxByteMax))
debug("TASK[Rx] ** Live LOOP rcvg fm RPi **")
debug("TASK[Rx] !! ERROR  char-queue full!!")

' String queue
debug("strQ:pushStr()=[", lstr_(pStr, nStrLen), "](", udec_(nStrLen), ") now ", udec_(nQStrCount+1), " strings")
debug("strQ:push() ERROR Q full!!")
debug("strQ:pop() ERROR Q empty!!")

' Eyes servo mechanism
debug("EYEs: connected to PCA9685")
debug("EYEs: ready...")

' Encoder
debug("enc: pins [", udec_(pinEnc0), ", ", udec_(pinEnc1), "], btn pin [", udec_(pinEncBtn), "]")

' FIFO manager
debug("FIFO: Initialization complete", 13, 10)
debug("FIFO FATAL: freeHead=", udec(freeHead), " CORRUPTED! Resetting pool.", 13, 10)
```

---

## Message Structure Patterns

### Visual Section Separators

```spin2
' Equal-sign bars (P2-Magnetic-Imaging-Tile, P2-uSD-FAT32-FS)
debug("=== PSRAM DRIVER TEST ===", 13, 10)
debug("========================================")

' Dash bars (P2-OctoSerial, P2-BLDC-MotorControl)
debug("* -------------")
debug("---------------")

' Hash bars (P2-uSD-FAT32-FS)
debug("##############################################")

' Asterisk box (P2-Magnetic-Imaging-Tile)
debug("****************************************", 13, 10)
debug("*         CALIBRATION MODE             *", 13, 10)
debug("*    REMOVE ALL MAGNETS FROM SENSOR    *", 13, 10)
debug("****************************************", 13, 10)
```

### Method Entry Tracing

Show the method name and its parameters to trace execution flow.

```spin2
' With parameters displayed (P2-Click-eInk)
debug("start(", udec_(eDisplayType), ", ", udec_(eTouchBasePin), ")")
debug("* fillScreen(", uhex_byte_(eColor), ")")
debug("setOrientation(", udec_(dvcRotation), ") ...")

' With return values (P2-RPi-ioT-Gateway)
debug("--> read_tca() = ", uhex(tmpC))
debug("--> write_scratchpad() SPAD = ", uhex_word_(wrdValue))
```

### Bracketed Method Name Convention (P2-uSD-FAT32-FS)

A distinctive pattern unique to the SD card driver: 2-space or 4-space indentation plus `[methodName]` identifies the calling function, with severity keywords.

```spin2
debug("  [start] Already started (cog ", udec_(cog_id), ")")
debug("  [start] FAIL: Could not allocate lock")
debug("  [do_mount] SUCCESS")
debug("  [do_mount] FAIL: initCard() returned false")
debug("    [initCard] Starting card init...")
debug("    [initCard] Step 1: Power-on delay (100ms)...")
debug("    [initCard] Step 2: SPI config, bit_delay=", udec(bit_delay), " (~50kHz)")
```

The indentation depth reflects call depth -- `"  "` for top-level public methods, `"    "` for private helpers they call.

### Numbered Step Sequences

Trace multi-step initialization processes.

**From P2-uSD-FAT32-FS** (`micro_sd_fat32_fs.spin2`):
```spin2
debug("    [initCard] Step 1: Power-on delay (100ms)...")
debug("    [initCard] Step 2: SPI config, bit_delay=", udec(bit_delay), " (~50kHz)")
' ...
debug("    [initCard] Step 8: Card identification and speed selection...")
```

**From P2-Magnetic-Imaging-Tile** (`isp_oled_driver_bitbang.spin2`):
```spin2
debug("    Init step 1: Unlock (FD 12)", 13, 10)
debug("    Init step 2: Unlock advanced (FD B1)", 13, 10)
' ...
debug("    Init step 19: Display ON", 13, 10)
```

### Command Direction Arrows

**From P2-uSD-FAT32-FS** (`micro_sd_fat32_fs.spin2`):
```spin2
debug("cmd->", udec_(op_cmd))       ' command sent
debug("cmd<-")                       ' response received
```

### Tx/Rx Message Logging with Counts

**From P2-OctoSerial** (`test_octoExercise_send.spin2`):
```spin2
debug("Tx #", udec_(currPortIndex + 1), " msg=[", lstr_(@valBuffer, lenNonCtrl), "]")
debug("Rx #", udec_(currPortIndex + 1), " msg=[", lstr_(pNextString, lenNonCtrl), "] cts [good=(", udec_(passCt[currPortIndex]), "), bad=(", udec_(failCt[currPortIndex]), ")]")
```

### State Transition Messages

**From P2-RPi-ioT-Gateway**:
```spin2
debug("TEST state [", zstr_(pFrom), "] -> [", zstr_(pTo), "]")
```

### Structured Test Framework Output

**From P2-uSD-FAT32-FS** (`isp_rt_utilities.spin2`):
```spin2
debug("* Test Group: ", zstr_(pDescription))
debug("* Test #", udec_(numberTests), ": ", zstr_(pDescription))
debug("   -> ", zstr_(pPassFail))
debug("  Sub-Test: ", zstr_(pMessage))
debug("  Value: ", sdec_long_(result), " (expected ", sdec_long_(expectedResult), ")")
```

---

## Format Specifier Reference

### Decimal Formatters

| Formatter | Size | Signed? | Named | Example |
|-----------|------|---------|-------|---------|
| `udec` / `udec_` | auto | No | yes/no | `debug(udec(loopCt))` |
| `sdec` / `sdec_` | auto | Yes | yes/no | `debug("ofs=", sdec_(offset))` |
| `udec_byte` / `udec_byte_` | byte | No | yes/no | `debug(udec_byte(rotation))` |
| `udec_word` / `udec_word_` | word | No | yes/no | `debug(udec_word(scopeIndex))` |
| `udec_long` / `udec_long_` | long | No | yes/no | `debug(udec_long(dead_gap))` |
| `sdec_long` / `sdec_long_` | long | Yes | yes/no | `debug(sdec_long(limitPwr))` |

### Hexadecimal Formatters

| Formatter | Size | Named | Example |
|-----------|------|-------|---------|
| `uhex` / `uhex_` | auto | yes/no | `debug(uhex(tmpC))` |
| `uhex_byte` / `uhex_byte_` | byte | yes/no | `debug("rx(", uhex_byte_(nChar), ")")` |
| `uhex_word` / `uhex_word_` | word | yes/no | `debug("R2=$", uhex_word_(r2_response))` |
| `uhex_long` / `uhex_long_` | long | yes/no | `debug(uhex_long(pGroupTitles))` |

### Binary Formatters

| Formatter | Size | Named | Example |
|-----------|------|-------|---------|
| `ubin_byte` / `ubin_byte_` | byte | yes/no | `debug("bits=", ubin_byte_(rowBits))` |
| `ubin_long` / `ubin_long_` | long | yes/no | `debug(ubin_long(maskAddr))` |

### Array Formatters

| Formatter | Element | Named | Example |
|-----------|---------|-------|---------|
| `uhex_byte_array` / `uhex_byte_array_` | byte | yes/no | `debug(uhex_byte_array_(@buf + addr, 8))` |
| `uhex_long_array` / `uhex_long_array_` | long | yes/no | `debug(uhex_long_array(@hall, 4))` |
| `sdec_long_array_` | long | no | `debug(sdec_long_array_(@portHndl, MAX_PORTS))` |

### String Formatters

| Formatter | Description | Example |
|-----------|-------------|---------|
| `zstr` / `zstr_` | Zero-terminated string | `debug("[", zstr_(pNextString), "]")` |
| `lstr_` | Length-bounded string | `debug("[", lstr_(@txBuffer, lenNonCtrl), "]")` |

### Control

| Formatter | Description | Example |
|-----------|-------------|---------|
| `if(cond)` | Suppress debug if false | `debug(if(flag), "conditional text")` |
| `13, 10` | Explicit CR+LF | `debug("text", 13, 10)` |

Formatters are **case-insensitive** -- `UHEX_LONG` and `uhex_long` are equivalent.

---

## Controlling Debug Output

### Compile-Time: `DEBUG_DISABLE`

Set `DEBUG_DISABLE` to 0 or 1 in a CON block to control debug compilation **per-file**. Never use the bare form.

- `DEBUG_DISABLE = 0` — no effect, debug() statements compile normally
- `DEBUG_DISABLE = 1` — suppresses debug() compilation in that file only. Zero code generated, zero runtime overhead for that file.

**Note:** Never use bare `DEBUG_DISABLE` (without a value). Always use the valued form.

**Disabling debug** (P2-uSD-FAT32-FS, `micro_sd_fat32_fs.spin2`):
```spin2
CON
    ' V3 driver exceeds 255 debug record limit when debug is fully enabled
    DEBUG_DISABLE = 1
```

**Enabling debug** (P2-uSD-FAT32-FS, `isp_format_utility.spin2`):
```spin2
CON
    DEBUG_DISABLE = 0   ' Enable debug output
```

**Used in:** P2-uSD-FAT32-FS (`micro_sd_fat32_fs.spin2`, `isp_format_utility.spin2`)

### Compile-Time: `DEBUG_MASK` with Channels (v46+)

Requires `{Spin2_v46}` directive. Assign debug statements to numbered channels (0-31). Only channels whose bit is set in `DEBUG_MASK` are compiled; others generate zero code.

```spin2
{Spin2_v46}

CON
    DBG_INIT  = %00000001           ' Channel 0: Initialization
    DBG_MAIN  = %00000010           ' Channel 1: Main loop
    DBG_COMMS = %00000100           ' Channel 2: Communications
    DBG_ERROR = %00001000           ' Channel 3: Errors

    DEBUG_MASK = DBG_INIT | DBG_ERROR   ' Enable only channels 0 and 3

PUB main()
    debug[0]("Initializing...")           ' COMPILED (bit 0 set)
    debug[1]("Main loop started")         ' OMITTED (bit 1 not set -- zero code)
    debug[2]("Comms data received")       ' OMITTED (bit 2 not set)
    debug[3]("Error occurred!")           ' COMPILED (bit 3 set)
    debug("Always compiled")              ' Plain debug ignores the mask
```

**Note:** Not currently used in any of the 7 surveyed projects, but available in PNut v46+ compilers.

### Compile-Time: `DEBUG_BAUD` / `DEBUG_PIN_TX` / `DEBUG_PIN_RX`

Redirect debug serial output to non-default pins and/or change baud rate.

**From P2-BLDC-MotorControl** (commented out, ready for RPi logging):
```spin2
CON
'{
    DEBUG_PIN_TX = 57
    DEBUG_PIN_RX = 56
    DEBUG_BAUD = 2_000_000
'}
```

**From P2-Magnetic-Imaging-Tile** (`test_tile_sensor_adc.spin2`):
```spin2
CON
    DEBUG_BAUD = 2_000_000          ' 2 Mbps debug baud rate
```

### Compile-Time: Preprocessor Conditionals (`#IFDEF`)

Conditionally compile entire debug methods and constants. Only used in P2-uSD-FAT32-FS.

**From P2-uSD-FAT32-FS** (`micro_sd_fat32_fs.spin2`):
```spin2
'' Enable in your top-level file:
''   #PRAGMA EXPORTDEF SD_INCLUDE_DEBUG

#IFDEF SD_INCLUDE_ALL
  #IFNDEF SD_INCLUDE_DEBUG
    #DEFINE SD_INCLUDE_DEBUG
  #ENDIF
#ENDIF

' Guard debug-only command constants
#IFDEF SD_INCLUDE_DEBUG
    CMD_DEBUG_SLOW_READ  = 25
    CMD_DEBUG_CLEAR_ROOT = 26
#ENDIF

' Guard debug-only PUB methods
#IFDEF SD_INCLUDE_DEBUG
PUB debugDumpRootDir()
    ' ...
PUB debugGetRootSec() : result
    ' ...
PUB readSectorSlow(sector, pBuf) : status
    ' ...
#ENDIF
```

### Runtime: `bDbgShoMem` Flag with `showDebug()` Method

A DAT-section boolean toggled via a public method. Used in queue/memory objects across 3 projects.

**Pattern** (P2-OctoSerial, `isp_string_queue.spin2`):
```spin2
DAT
    bDbgShoMem      LONG    FALSE

PUB showDebug(bEnable)
'' Enable/Disable debug messages
    bDbgShoMem := bEnable

PUB pushStr(pStr) | nStrLen
    ' ... logic ...
    if bDbgShoMem
        debug("strQ:pushStr()=[", lstr_(pStr, nStrLen), "](", udec_(nStrLen), ")")

PUB popStr(pUserDest, nUserDestMax, bHadOverrun) : pStr
    ' ... logic ...
    if bDbgShoMem
        debug("strQ:popStr()=[", zstr_(pUserDest), "](", udec_(strsize(pUserDest)), ")")
```

**Used in:** `isp_string_queue.spin2` (P2-OctoSerial), `isp_queue_serial.spin2` (P2-BLDC-MotorControl, P2-RPi-ioT-Gateway)

### Runtime: `bShowDebug` Flag with `enableDebug()` Method

A per-instance debug flag in VAR or DAT, controlled via a public `enableDebug()` method. Used in driver/library objects.

**Basic pattern** (P2-Multi-servo, `isp_i2c_pca9685.spin2`):
```spin2
DAT
    bShowDebug      BYTE    TRUE        ' default on; callers override

PUB enableDebug(bEnable)
'' Turn on/off file internal debug messaging
    bShowDebug := bEnable

PUB init(pinSCL, pinSDA, pinOE)
    enableDebug(FALSE)              ' default off at init

PRI writeRegister(regAddr, value)
    if bShowDebug
        debug("PCA: writeReg(", uhex_byte_(regAddr), ", ", uhex_byte_(value), ")")
```

### Runtime: `enableDebug()` with `saveDebug()` / `restoreDebug()`

A single-level push/pop stack for debug state. Suppresses debug during continuous operations (like servo slews) and restores it when done. Only used in P2-Multi-servo.

**From P2-Multi-servo** (`isp_i2c_pca9685_servo.spin2`):
```spin2
VAR
    BYTE    bShowDebug
    BYTE    bHaveSavedDebug
    BYTE    bPriorShowDebug

PUB enableDebug(bEnable)
'' Turn on/off file internal debug messaging
    bShowDebug := bEnable

PUB saveDebug()
'' Preserve last debug state (push)
    if not bHaveSavedDebug
        bPriorShowDebug := bShowDebug
        bHaveSavedDebug := TRUE
    else
        term.fstr0(string("!!! saveDebug() ERROR - Already SAVED!\r\n"))

PUB restoreDebug()
'' Restore prior debug state (pop)
    if bHaveSavedDebug
        bShowDebug := bPriorShowDebug
        bHaveSavedDebug := FALSE
    else
        term.fstr0(string("!!! restoreDebug() ERROR - Nothing SAVED to restore!\r\n"))

' Usage in servo slew:
PUB writePosition(mode, value)
    if NOT bHaveSavedDebug
        saveDebug()
    bShowDebug := FALSE             ' suppress during slew

PUB continueSlew() : bAtTargetStatus
    if bSlewComplete
        restoreDebug()              ' restore when slew completes
```

### Runtime: Per-Object Debug Control from Callers

Callers can selectively enable debug on specific object instances.

**From P2-Multi-servo** (`isp_6servo_eyes.spin2`):
```spin2
PRI initEyeServos()
    pca9685.enableDebug(FALSE)                      ' quiet the hardware driver
    servos[SERVO_EYE_LT_RT].enableDebug(TRUE)       ' but watch these servos
    servos[SERVO_EYE_UP_DN].enableDebug(TRUE)
    servos[SERVO_LID_TOP_RT].enableDebug(TRUE)
    servos[SERVO_LID_BOT_RT].enableDebug(TRUE)
    servos[SERVO_LID_TOP_LT].enableDebug(TRUE)
    servos[SERVO_LID_BOT_LT].enableDebug(TRUE)
```

**Bracket pattern -- enable around sensitive operation** (P2-BLDC-MotorControl, `demo_dual_motor_rc.spin2`):
```spin2
    remoteCtl.showDebug(bShowDebugStatus)       ' enable before
    bEmerCutoff := remoteCtl.swIsOff(remoteCtl.CTL_SW_D)
    remoteCtl.showDebug(FALSE)                  ' disable after
```

### Runtime: `showHDMIDebug` Flag (BLDC-specific)

Controls verbose HDMI debug display data dumps. Separate from `useDebug` for general motor debug.

**From P2-BLDC-MotorControl** (`isp_bldc_motor.spin2`):
```spin2
VAR
    LONG    useDebug
    LONG    showHDMIDebug

PUB start(...)
    useDebug := FALSE
    showHDMIDebug := FALSE

PUB getDebugData() : nGroups, pGroupTitles, pGroupNames, pGroupVarCts, pGroupVars
    loadDisplayList()
    if showHDMIDebug
        debug("* MOTR DL title: ", uhex_long(@pTitlesAr), uhex_long_array(@pTitlesAr, DBG_GROUPS_CT + 1))
        debug("* MOTR DL VarCt: ", uhex_long(@pVarCtAr), uhex_long_array(@pVarCtAr, DBG_GROUPS_CT))
```

### Debug Throttling

Limit debug output volume in tight loops with a counter.

**From P2-uSD-FAT32-FS** (`micro_sd_fat32_fs.spin2`):
```spin2
DAT
    sp_debug_ctr    LONG    0

PRI sp_transfer_8(data_out) : result
    if sp_debug_ctr < 5
        debug("    [sp_transfer_8] pins: miso=", udec_(_miso), " sck=", udec_(_sck), " raw=", uhex_long_(raw_result), " final=", uhex_byte_(result))
        sp_debug_ctr++
```

### Comment-Toggle

The simplest approach for one-off diagnostics -- comment/uncomment with `'`:
```spin2
    'debug("- PWM frame(", udec_(frameIdx), "), ", uhex_long(pFrameBuffer))
```

This is the most common pattern across all projects.

---

## Graphical Debug Displays (Backtick Syntax)

The P2 debug system supports graphical display windows using backtick syntax. Used in P2-BLDC-MotorControl for real-time motor visualization.

### Logic Analyzer

**From P2-BLDC-MotorControl** (`isp_bldc_motor-REF.spin2`):
```spin2
' Define 3-bit logic analyzer for Hall effect sensors
debug(`logic l title 'Hall Effect' pos 650 500 'Hall' 3)

' Feed data in the motor loop
debug(`l `ubin_byte_(hall))
```

### Terminal Window

```spin2
' Define a live-updating status terminal
debug(`term t title 'Status' pos 650 650 size 30 1 textsize 20 update)

' Update with current duty cycle and position
debug(`t 0 '`sdec(duty, pos)' update)
```

### Oscilloscope

```spin2
' Define dual-channel scope for duty and error signals
debug(`scope r title 'Duty and Error' pos 100 900 size 256 256 samples 256 rate 50)
debug(`r 'Duty' 0 `(PWMLIM<<4) 256 0)
debug(`r 'Error' -128 128 256 0 15)

' Feed data each motor cycle
debug(`r `sdec_(duty, err))
```

### Multi-Channel Scope with Arrays

```spin2
' Define 3-channel voltage scope (U, V, W phases)
debug(`scope s title 'Voltages' pos 100 500 size 512 300 samples 256 rate 256)
debug(`s 'U' 0 `(FRAME) 128 170)
debug(`s 'V' 0 `(FRAME) 128 170)
debug(`s 'W' 0 `(FRAME) 128 170)

' Feed array data for all three phases
debug(`s `sdec_long_array_(@drive_u, 3) `sdec_long_array_(@sense_u, 4))
```

---

## Project-Specific Conventions

### P2-OctoSerial
- Module prefixes: `"SP8: "`, `"8S: "`, `"strQ: "`, `"TskU: "`
- Runtime control: `bDbgShoMem` flag via `showDebug()` method
- Conventions: `"* "` for status, `"+++ "` for test results, `"^^^ "` for stack checks

### P2-BLDC-MotorControl
- Module prefix: `"MOT: "`
- Runtime control: `showDebug()`, `bShowDebug`, `useDebug`, `showHDMIDebug`
- Conventions: Graphical debug displays (logic, scope, term), `"EEEE: "` for severe errors
- HDMI debug infrastructure: `DBG_GROUPS_CT`, `DBG_MAX_VARS_IN_GROUP` CON constants with structured display list data
- `DEBUG_PIN_TX/RX/BAUD` prepared but commented out for RPi logging

### P2-Multi-servo
- Module prefixes: `"EYEs: "`, `"enc: "`, `"TIMI: "`
- Runtime control: `enableDebug()` + `saveDebug()` / `restoreDebug()` push/pop
- Per-object debug control from callers

### P2-RPi-ioT-Gateway
- Module prefixes: `"TASK[Rx] "`, `"hrf: "`, `"stm: "`, `"gnpsr: "`, `"gcs: "`
- Runtime control: `bDbgShoMem` in queue objects
- Conventions: `"--> "` for return values, `">> "` for test steps, `"!! "` for errors

### P2-Click-eInk
- Module prefixes: `"tch- "`, `"ft: "`, `"i2c: "`
- Runtime control: `bShowDebug` in touch and I2C objects
- Conventions: Method entry tracing with parameters, `"  -- "` for detail lines

### P2-uSD-FAT32-FS
- **Unique convention:** `"  [methodName] "` bracketed function name with indentation depth
- Severity keywords inline: `FAIL:`, `SUCCESS`, `WARNING:`, `TIMEOUT`
- Compile-time control: `DEBUG_DISABLE = 0|1` (per-file), `#IFDEF SD_INCLUDE_DEBUG`
- Debug throttling with `sp_debug_ctr`
- Numbered step sequences: `"Step 1: "`, `"Step 2: "`
- `"cmd-> "` / `"cmd<- "` for command direction

### P2-Magnetic-Imaging-Tile
- Module prefixes: `"FIFO: "`, `"FIFO FATAL: "`, `"HDMI Engine: "`, `"OLED: "`, `"Sensor: "`
- Role prefixes in tests: `"WRITER: "`, `"PRODUCER: "`, `"CONSUMER: "`, `"ROUTER: "`
- **Unique convention:** Always appends `, 13, 10` (CR+LF) to every debug call
- No runtime debug gating -- direct debug calls throughout
- `"=== TITLE ==="` section headers, `"****"` banner boxes
- `DEBUG_BAUD = 2_000_000` for high-speed debug output

---

## Ending a Debug Session Programmatically

Requires `{Spin2_v52}` directive. Send `DEBUG_END_SESSION` (value 27) to close the debug window.

```spin2
{Spin2_v52}

PUB shutdown()
    debug("Program complete, closing debug")
    waitms(100)                         ' allow output to display
    DEBUG(DEBUG_END_SESSION)            ' closes debug window
```

---

## Complete Formatter Quick Reference

### Naming Convention

```
u/s     dec/hex/bin     _byte/_word/_long     _array     _
^sign   ^base           ^size (optional)      ^array     ^suppress name
```

### All Formatters Found in Production Code

| Formatter | Example from Codebase |
|-----------|----------------------|
| `udec(x)` | `debug("count: ", udec(loopCt))` |
| `udec_(x)` | `debug("pin ", udec_(pinNum))` |
| `udec_byte(x)` | `debug(udec_byte(rotation))` |
| `udec_byte_(x)` | `debug("fill=", udec_byte_(color))` |
| `udec_word(x)` | `debug(udec_word(scopeIndex))` |
| `udec_long(x)` | `debug(udec_long(dead_gap), udec_long(pwm_limit))` |
| `udec_long_(x)` | `debug("freq=", udec_long_(test_freq / 1_000_000), " MHz")` |
| `sdec(x)` | `debug("pin (", sdec(rxp), ")")` |
| `sdec_(x)` | `debug("ofs=", sdec_(offset))` |
| `sdec_long(x)` | `debug(sdec_long(limitPwr))` |
| `sdec_long_(x)` | `debug("val=(", sdec_long_(LONG[@cmd][idx]), ")")` |
| `uhex(x)` | `debug(uhex(tmpC))` |
| `uhex_(x)` | `debug("addr=", uhex_(@serialRxBffr))` |
| `uhex_byte(x)` | `debug(uhex_byte(byte[@remap][orient]))` |
| `uhex_byte_(x)` | `debug("rx(", uhex_byte_(nChar), ")")` |
| `uhex_word(x)` | `debug(uhex_word(block_address))` |
| `uhex_word_(x)` | `debug("R2=$", uhex_word_(r2_response))` |
| `uhex_long(x)` | `debug(uhex_long(pGroupTitles))` |
| `uhex_long_(x)` | `debug(" ", uhex_long_(pBytes), ": ...")` |
| `ubin_byte(x)` | `debug(ubin_byte(presentStatus))` |
| `ubin_byte_(x)` | `debug("bits=", ubin_byte_(rowBits))` |
| `ubin_long(x)` | `debug(ubin_long(maskAddr))` |
| `uhex_byte_array(p,n)` | `debug(uhex_byte_array(@nameTitle1, dataLen1))` |
| `uhex_byte_array_(p,n)` | `debug(uhex_byte_array_(@buf + addr, 8))` |
| `uhex_long_array(p,n)` | `debug(uhex_long_array(@hall, 4))` |
| `uhex_long_array_(p,n)` | `debug(uhex_long_array_(@currDLEntryIdx, 33))` |
| `sdec_long_array_(p,n)` | `debug(sdec_long_array_(@portHndl, MAX_PORTS))` |
| `zstr(p)` | `debug(zstr(@buffer))` |
| `zstr_(p)` | `debug("[", zstr_(pNextString), "]")` |
| `lstr_(p,n)` | `debug("[", lstr_(@txBuffer, lenNonCtrl), "]")` |

---

## Tips and Best Practices

1. **Use module prefixes consistently.** Every object should tag its debug output with a short prefix (`"MOT: "`, `"SP8: "`, etc.) so you can trace which object produced each line.

2. **Use underscore variants for inline messages.** `udec_(x)` gives you just the value; `udec(x)` adds the variable name. The underscore versions produce cleaner formatted output.

3. **Use `sdec` for values that can be negative.** `udec(-1)` shows `4294967295`; `sdec(-1)` shows `-1`.

4. **Use sized formatters for sized data.** `uhex_byte_` for bytes, `uhex_word_` for words, `uhex_long_` for longs -- this controls how many hex digits are displayed.

5. **`lstr_` is safer than `zstr_`** for untrusted or partially-filled buffers. It limits output to a specified length.

6. **Expose `enableDebug(bEnable)` in library objects.** Let callers control debug output per instance. Use `saveDebug()` / `restoreDebug()` when you need to temporarily suppress debug during continuous operations.

7. **Use `DEBUG_DISABLE = 1` per-file to reduce binary size or avoid the 255 debug record compiler limit.** Debug and serial share pin 62 without conflict. Never use bare `DEBUG_DISABLE`.

8. **Throttle debug in tight loops.** Use a counter (`if debug_ctr < 5`) to limit output volume and avoid timing disruption.

9. **Use severity prefixes consistently.** `"* "` for normal status, `"!! "` / `"EEE "` for errors, `"^^^ "` for stack checks, `"+++ "` for test results, `"---- "` for fatal stops.

10. **Use visual separators** (`"* -------------"`, `"=== TITLE ==="`) to make debug output scannable when there's a lot of it.

---

## Debug Control Infrastructure Summary

| Mechanism | Type | Projects Using It |
|-----------|------|-------------------|
| `DEBUG_DISABLE = 0\|1` | Compile-time (per-file) | P2-uSD-FAT32-FS |
| `DEBUG_BAUD` / `DEBUG_PIN_TX/RX` | Compile-time | P2-BLDC-MotorControl (commented), P2-Magnetic-Imaging-Tile |
| `#IFDEF SD_INCLUDE_DEBUG` | Compile-time preprocessor | P2-uSD-FAT32-FS |
| `DEBUG_MASK` + `debug[N]()` | Compile-time channels (v46+) | (Available but not yet used) |
| `bDbgShoMem` + `showDebug()` | Runtime flag | P2-OctoSerial, P2-BLDC-MotorControl, P2-RPi-ioT-Gateway |
| `bShowDebug` + `enableDebug()` | Runtime flag | P2-Multi-servo, P2-Click-eInk |
| `saveDebug()` / `restoreDebug()` | Runtime push/pop | P2-Multi-servo |
| `showHDMIDebug` / `useDebug` | Runtime flag (HDMI) | P2-BLDC-MotorControl |
| Comment toggle (`'debug(...)`) | Manual | All projects |
| Debug throttle counter | Runtime limiter | P2-uSD-FAT32-FS |
