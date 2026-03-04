# Conditional Compilation Guide

**User's guide to the Dual FS driver pragma system, feature flags, multi-compiler support, and debug output control.**

---

## Overview

The Dual FS driver (`dual_sd_fat32_flash_fs.spin2`) uses a conditional compilation system to let you include only the SD card features your application needs. The core driver compiles to ~59 KB with all standard filesystem operations for both SD and Flash. Enabling all optional SD features brings it to ~62 KB. Since the Propeller 2 has 512 KB of hub RAM this isn't usually a constraint, but the mechanism keeps the driver well-organized and gives you control over what ships in your binary.

Feature flags are declared in your **top-level application file** (the file that contains `_CLKFREQ` and the `OBJ` declaration for the driver). The flags propagate down to the driver at compile time using `#PRAGMA EXPORTDEF` directives.

All feature flags control **SD card** capabilities only. The Flash filesystem is always compiled into the unified driver and has no conditional flags.

---

## Feature Flags

### Available Flags

| Flag | What It Enables |
|------|-----------------|
| `SD_INCLUDE_RAW` | Raw sector read/write, `initCardOnly()`, multi-block reads/writes |
| `SD_INCLUDE_REGISTERS` | Card register access: CID, CSD, SCR, SD Status |
| `SD_INCLUDE_SPEED` | High-speed mode switch via CMD6 (up to 50 MHz SPI) |
| `SD_INCLUDE_DEBUG` | Debug/diagnostic methods, CRC error getters, test hooks |
| `SD_INCLUDE_STACK_CHECK` | Worker cog stack depth measurement (diagnostic) |
| `SD_INCLUDE_ALL` | Convenience: enables RAW + REGISTERS + SPEED + DEBUG |

All optional features combined add approximately 3 KB to the binary (57 additional methods).

### Flag Dependencies

`SD_INCLUDE_SPEED` **automatically includes** `SD_INCLUDE_REGISTERS`. If you enable SPEED without explicitly enabling REGISTERS, the driver silently defines REGISTERS for you. No action is needed on your part.

`SD_INCLUDE_STACK_CHECK` is independent and is **not** included by `SD_INCLUDE_ALL`. It must be enabled separately when needed.

### What the Core Driver Includes (No Flags)

With no feature flags, the driver provides all standard filesystem operations for both SD and Flash:

- `init()` / `stop()`
- `mount()` / `unmount()` / `mounted()` / `canMount()`
- `createFileNew()` / `openFileRead()` / `openFileWrite()`
- `readHandle()` / `writeHandle()` / `seekHandle()` / `tellHandle()`
- `closeFileHandle()` / `syncHandle()` / `syncAllHandles()`
- `deleteFile()` / `rename()` / `moveFile()`
- `makeDirectory()` / `changeDirectory()` / `openDirectory()` / `readDirectory()`
- `exists()` / `file_size()` / `freeSpace()` / `stats()` / `error()`
- `wr_byte()` / `rd_byte()` / `wr_word()` / `rd_word()` / `wr_long()` / `rd_long()`
- `wr_str()` / `rd_str()`

This is sufficient for the vast majority of applications. The example programs (`src/EXAMPLES/`) use no feature flags at all.

---

## How to Enable Features

### Simple Case (pnut-ts only)

If you only need to compile with pnut-ts (the primary compiler for this project), enabling features is straightforward. Place the `#PRAGMA EXPORTDEF` directives **before** your `OBJ` declaration:

```spin2
CON
    _CLKFREQ = 350_000_000
    SD_CS = 60, SD_MOSI = 59, SD_MISO = 58, SD_SCK = 61

' Enable raw sector access and debug diagnostics
#PRAGMA EXPORTDEF SD_INCLUDE_RAW
#PRAGMA EXPORTDEF SD_INCLUDE_DEBUG

OBJ
    dfs : "dual_sd_fat32_flash_fs"
```

Or to enable everything:

```spin2
#PRAGMA EXPORTDEF SD_INCLUDE_ALL

OBJ
    dfs : "dual_sd_fat32_flash_fs"
```

### When Your File Also Needs the Flag Locally

`#PRAGMA EXPORTDEF` propagates a flag to child objects (the driver). It does **not** define the flag in your own file. If your top-level code also has `#IFDEF` blocks that check a flag, you need **both** directives:

```spin2
' Make it available locally AND propagate to the driver
#DEFINE SD_INCLUDE_STACK_CHECK
#PRAGMA EXPORTDEF SD_INCLUDE_STACK_CHECK

OBJ
    dfs : "dual_sd_fat32_flash_fs"

PUB go() | workerCog, depth
    workerCog := dfs.init(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    dfs.mount(dfs.DEV_BOTH)

    ' This #IFDEF needs the local #DEFINE to work:
#IFDEF SD_INCLUDE_STACK_CHECK
    depth := dfs.reportStackDepth()
    debug("Stack depth: ", udec_(depth))
#ENDIF
```

The rule is simple:

| Directive | Scope | Purpose |
|-----------|-------|---------|
| `#DEFINE` | Current file only | Controls `#IFDEF` guards in your file |
| `#PRAGMA EXPORTDEF` | Child objects (OBJ) | Makes the flag visible to the driver |

If your application code doesn't use `#IFDEF` blocks for the flag (the common case), you only need `#PRAGMA EXPORTDEF`.

---

## Multi-Compiler Support

The project supports three Spin2 compilers. Each handles flag propagation differently, so the codebase uses a three-branch conditional pattern to set flags correctly for whichever compiler is building the code.

### The Three Compilers

| Compiler | Built-in Define | Flag Propagation |
|----------|----------------|------------------|
| **Spin Tools IDE** | `__SPINTOOLS__` | `#DEFINE` automatically propagates to child objects |
| **flexspin** | `__FLEXSPIN__` | Requires both `#define` and `#pragma exportdef` (lowercase) |
| **pnut-ts** | *(neither defined)* | Requires `#PRAGMA EXPORTDEF` (case insensitive) |

### Why Three Branches?

The compilers differ in flag propagation semantics:

- **Spin Tools** `#DEFINE` automatically exports to child objects. flexspin and pnut-ts require an explicit `#pragma exportdef` to propagate flags.
- **flexspin** requires lowercase directives (`#define`, `#pragma exportdef`).
- **pnut-ts** preprocessor directives are case insensitive. The project uses uppercase (`#DEFINE`, `#PRAGMA EXPORTDEF`) by convention.

### The Standard Pattern

Here is the three-branch pattern used throughout the project. This example enables `SD_INCLUDE_RAW` and `SD_INCLUDE_DEBUG`:

```spin2
#IFDEF __SPINTOOLS__
#DEFINE SD_INCLUDE_RAW
#DEFINE SD_INCLUDE_DEBUG
#ELSEIFDEF __FLEXSPIN__
#define SD_INCLUDE_RAW
#pragma exportdef SD_INCLUDE_RAW
#define SD_INCLUDE_DEBUG
#pragma exportdef SD_INCLUDE_DEBUG
#ELSE
#PRAGMA EXPORTDEF SD_INCLUDE_RAW
#PRAGMA EXPORTDEF SD_INCLUDE_DEBUG
#ENDIF
```

What each branch does:

- **Spin Tools branch** (`__SPINTOOLS__`): Uses `#DEFINE` only. The IDE automatically propagates defines to child objects, so no explicit export is needed.

- **flexspin branch** (`__FLEXSPIN__`): Uses lowercase `#define` for the local definition plus lowercase `#pragma exportdef` to propagate to child objects. Both are required.

- **pnut-ts branch** (`#ELSE`): The fallback. Uses `#PRAGMA EXPORTDEF` to propagate to the driver (uppercase by convention; pnut-ts is case insensitive). Adds `#DEFINE` only if the current file itself needs to test the flag with `#IFDEF`.

### Pattern Variations in the Codebase

**Selective features** (e.g., speed tests need SPEED + REGISTERS):

```spin2
#IFDEF __SPINTOOLS__
#DEFINE SD_INCLUDE_SPEED
#DEFINE SD_INCLUDE_REGISTERS
#ELSEIFDEF __FLEXSPIN__
#define SD_INCLUDE_SPEED
#pragma exportdef SD_INCLUDE_SPEED
#define SD_INCLUDE_REGISTERS
#pragma exportdef SD_INCLUDE_REGISTERS
#ELSE
#PRAGMA EXPORTDEF SD_INCLUDE_SPEED
#PRAGMA EXPORTDEF SD_INCLUDE_REGISTERS
#ENDIF
```

**All features** (e.g., demo shell, format utility):

```spin2
#IFDEF __SPINTOOLS__
#DEFINE SD_INCLUDE_ALL
#ELSEIFDEF __FLEXSPIN__
#define SD_INCLUDE_ALL
#pragma exportdef SD_INCLUDE_ALL
#ELSE
#PRAGMA EXPORTDEF SD_INCLUDE_ALL
#ENDIF
```

**Stack check only** (e.g., diagnostic tests):

```spin2
#IFDEF __SPINTOOLS__
#DEFINE SD_INCLUDE_STACK_CHECK
#ELSEIFDEF __FLEXSPIN__
#define SD_INCLUDE_STACK_CHECK
#pragma exportdef SD_INCLUDE_STACK_CHECK
#ELSE
#DEFINE SD_INCLUDE_STACK_CHECK
#PRAGMA EXPORTDEF SD_INCLUDE_STACK_CHECK
#ENDIF
```

Note the pnut-ts branch includes `#DEFINE` here because the test file's own code uses `#IFDEF SD_INCLUDE_STACK_CHECK` blocks.

**No flags at all** (e.g., seek tests, directory tests): Most test files and all example programs omit the three-branch block entirely. They compile with the core driver, which is all they need.

### If You Only Use One Compiler

If your project only targets one compiler, you can simplify:

**pnut-ts only:**
```spin2
#PRAGMA EXPORTDEF SD_INCLUDE_RAW
#PRAGMA EXPORTDEF SD_INCLUDE_DEBUG

OBJ
    dfs : "dual_sd_fat32_flash_fs"
```

**flexspin only:**
```spin2
#define SD_INCLUDE_RAW
#pragma exportdef SD_INCLUDE_RAW
#define SD_INCLUDE_DEBUG
#pragma exportdef SD_INCLUDE_DEBUG

OBJ
    dfs : "dual_sd_fat32_flash_fs"
```

**Spin Tools only:**
```spin2
#DEFINE SD_INCLUDE_RAW
#DEFINE SD_INCLUDE_DEBUG

OBJ
    dfs : "dual_sd_fat32_flash_fs"
```

The three-branch pattern is only needed when the same source must compile under multiple compilers.

---

## How the Driver Uses Feature Flags

Inside the driver (`dual_sd_fat32_flash_fs.spin2`), each optional feature is completely enclosed in `#IFDEF` / `#ENDIF` blocks. When a flag is not defined, the compiler removes all related code: public methods, private methods, worker cog command handlers, and command code constants.

### SD_INCLUDE_ALL Expansion

The driver expands `SD_INCLUDE_ALL` into the four individual flags:

```spin2
#IFDEF SD_INCLUDE_ALL
#IFNDEF SD_INCLUDE_RAW
#DEFINE SD_INCLUDE_RAW
#ENDIF
#IFNDEF SD_INCLUDE_REGISTERS
#DEFINE SD_INCLUDE_REGISTERS
#ENDIF
#IFNDEF SD_INCLUDE_SPEED
#DEFINE SD_INCLUDE_SPEED
#ENDIF
#IFNDEF SD_INCLUDE_DEBUG
#DEFINE SD_INCLUDE_DEBUG
#ENDIF
#ENDIF
```

The `#IFNDEF` guards prevent double-definition if you happen to enable both `SD_INCLUDE_ALL` and an individual flag.

### SD_INCLUDE_SPEED Auto-Includes Registers

The driver automatically defines `SD_INCLUDE_REGISTERS` when `SD_INCLUDE_SPEED` is enabled:

```spin2
#IFDEF SD_INCLUDE_SPEED
#IFNDEF SD_INCLUDE_REGISTERS
#DEFINE SD_INCLUDE_REGISTERS
#ENDIF
#ENDIF
```

This means you never need to explicitly enable REGISTERS when using SPEED.

### Gated Sections

The driver is organized so that optional features occupy their own sections:

| Feature | Flag | Public Methods |
|---------|------|----------------|
| Stack Depth | `SD_INCLUDE_STACK_CHECK` | `reportStackDepth()` |
| Raw Sector Access | `SD_INCLUDE_RAW` | `initCardOnly()`, `cardSizeSectors()`, `testCMD13()`, `readSectorRaw()`, `writeSectorRaw()`, `readSectorsRaw()`, `writeSectorsRaw()`, `readVBRRaw()` |
| Card Registers | `SD_INCLUDE_REGISTERS` | `readCIDRaw()`, `readCSDRaw()`, `readSCRRaw()`, `readSDStatus()` |
| Speed Control | `SD_INCLUDE_SPEED` | `attemptHighSpeed()`, `setSPISpeed()`, `checkCMD6Support()`, `checkHighSpeedCapability()` |
| Debug / Diagnostics | `SD_INCLUDE_DEBUG` | `getLastCMD13()`, `getLastCalculatedCRC()`, `getCRCMatchCount()`, `setCRCValidation()`, `debugDumpRootDir()`, `displaySector()`, and 10+ more |

Some related methods are **always present** regardless of flags: `getSPIFrequency()`, `getCardMaxSpeed()`, `getManufacturerID()`, `getReadTimeout()`, `getWriteTimeout()`, `isHighSpeedActive()`.

If a flag is not defined, calling any of its gated methods causes a **linker error** at compile time. There is no silent failure -- you get a clear "method not found" message pointing you to the missing feature flag.

### Worker Cog Command Dispatch

The worker cog's command handler also uses `#IFDEF` blocks around each feature's command cases. Only the command codes for enabled features exist in the dispatch table. Disabled command codes are not compiled, so they cannot be accidentally invoked.

---

## Enabling Debug Output

The driver and its associated files use the Spin2 `DEBUG_DISABLE` constant to control whether `debug()` statements produce output. This is a standard Spin2 mechanism -- when `DEBUG_DISABLE = 1`, the compiler removes all `debug()` calls from the binary.

### Driver Debug Is Disabled by Default

The driver sets `DEBUG_DISABLE = 1`:

```spin2
CON  ' flags
  ' NOTE: V3 driver exceeds 255 debug record limit when debug is fully enabled
  ' pnut-ts error: "DEBUG data is too long: too many records: max 255"
  ' Set to 1 to disable debug in driver and avoid compilation errors
  DEBUG_DISABLE = 1
```

This is **intentional and necessary**. The driver has hundreds of `debug()` statements spread across ~9400 lines of code. The pnut-ts compiler enforces a limit of 255 debug records per compilation unit. With debug enabled, the driver exceeds this limit and fails to compile.

### Debug in Your Application Code

Your top-level application file has its **own** `DEBUG_DISABLE` setting, independent of the driver's. Most application and test files either set `DEBUG_DISABLE = 0` or leave it unset (defaults to enabled):

```spin2
CON
    _CLKFREQ = 350_000_000

OBJ
    dfs : "dual_sd_fat32_flash_fs"   ' Driver still has DEBUG_DISABLE = 1

PUB go() | workerCog
    debug("Starting application")     ' This WILL appear in debug output
    workerCog := dfs.init(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    dfs.mount(dfs.DEV_BOTH)
    ' Internal driver debug() calls are still suppressed
```

Each `.spin2` file controls its own debug output independently. Setting `DEBUG_DISABLE = 0` (or omitting it) in your file enables debug for **your code only**. The driver's internal debug statements remain suppressed regardless.

### Debug Settings Across the Project

The project files use these settings:

| File | `DEBUG_DISABLE` | Reason |
|------|----------------|--------|
| `dual_sd_fat32_flash_fs.spin2` (driver) | `1` | Exceeds 255 debug record limit |
| `DFS_example_*.spin2` (examples) | `0` | Show progress/results to user |
| `DFS_demo_shell.spin2` (demo) | `1` | Uses serial terminal instead of debug |
| `isp_fsck_utility.spin2` | `1` | Uses FIFO strings instead of debug |
| `isp_serial_singleton.spin2` | `1` | Owns pin 62 for serial TX (conflicts with debug) |
| `DFS_SD_RT_*_tests.spin2` (tests) | `0` (default) | Tests use debug for results output |
| `DFS_FL_RT_*_tests.spin2` (tests) | `0` (default) | Tests use debug for results output |

### How to See Driver-Internal Debug Output

If you need to see what the driver is doing internally (for deep debugging), you can temporarily change the driver's `DEBUG_DISABLE` to `0`:

```spin2
' In dual_sd_fat32_flash_fs.spin2:
  DEBUG_DISABLE = 0    ' TEMPORARILY enable for debugging
```

**Important caveats:**

1. The pnut-ts compiler will likely fail with "too many records: max 255." To work around this, you must comment out most of the driver's `debug()` calls and leave only the ones in the area you are investigating.

2. This is a **temporary diagnostic change** -- revert it before committing. The driver cannot ship with `DEBUG_DISABLE = 0`.

3. An alternative approach: use the `SD_INCLUDE_DEBUG` feature flag to access the driver's diagnostic getters (`getLastCMD13()`, `getCRCMatchCount()`, `getLastCalculatedCRC()`, etc.). These methods return internal diagnostic state through the normal API, without needing to enable the driver's debug output. This is the recommended approach for production debugging.

### SD_INCLUDE_DEBUG vs DEBUG_DISABLE

These are two different mechanisms that are easily confused:

| Mechanism | What It Controls | Scope |
|-----------|-----------------|-------|
| `SD_INCLUDE_DEBUG` | Whether debug **API methods** are compiled into the driver | Feature flag (compile-time) |
| `DEBUG_DISABLE` | Whether `debug()` **print statements** produce output | Per-file constant |

You can (and typically do) enable `SD_INCLUDE_DEBUG` while leaving `DEBUG_DISABLE = 1` in the driver. This gives you access to the debug API (diagnostic getters, CRC error injection hooks) without enabling the driver's hundreds of internal `debug()` print statements.

### Future Direction: Debug Mask

A planned improvement is to add debug mask support to the driver. Instead of the current all-or-nothing `DEBUG_DISABLE` switch, the driver will assign each `debug()` call to a category (e.g., SPI transactions, FAT operations, directory walks, handle management). A bitmask will control which categories are active, allowing you to enable debug output for just the subsystem you are investigating without exceeding the 255 debug record limit. This will eliminate the need to manually comment out `debug()` calls when troubleshooting specific areas of the driver.

---

## The Dual-Device Architecture

The unified driver manages two filesystems simultaneously:

| Device | Constant | Filesystem | Storage |
|--------|----------|------------|---------|
| SD card | `DEV_SD` (0) | FAT32 | microSD card via SPI |
| Flash | `DEV_FLASH` (1) | Custom block-based | Onboard 16MB QSPI Flash |
| Both | `DEV_BOTH` (2) | Both of the above | Used with `mount()` / `unmount()` |

All file operations take a `dev` parameter to specify which device to use. The driver shares a single worker cog and up to 6 file/directory handles across both devices, with lazy SPI bus switching between them.

The Flash filesystem has **no conditional compilation flags**. It is always compiled into the unified driver. Only SD card features have optional compile-time flags.

---

## Quick Reference

### Minimal application (core filesystem only)

```spin2
CON
    _CLKFREQ = 350_000_000
    SD_CS = 60, SD_MOSI = 59, SD_MISO = 58, SD_SCK = 61

OBJ
    dfs : "dual_sd_fat32_flash_fs"

PUB go() | workerCog, handle
    workerCog := dfs.init(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    dfs.mount(dfs.DEV_SD)
    handle := dfs.createFileNew(dfs.DEV_SD, @"HELLO.TXT")
    dfs.wr_str(handle, @"Hello, world!")
    dfs.closeFileHandle(handle)
    dfs.unmount(dfs.DEV_SD)
    dfs.stop()
```

No feature flags needed.

### Application using both devices

```spin2
CON
    _CLKFREQ = 350_000_000
    SD_CS = 60, SD_MOSI = 59, SD_MISO = 58, SD_SCK = 61

OBJ
    dfs : "dual_sd_fat32_flash_fs"

PUB go() | workerCog, sdHandle, flHandle
    workerCog := dfs.init(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    dfs.mount(dfs.DEV_BOTH)

    ' Write to SD
    sdHandle := dfs.createFileNew(dfs.DEV_SD, @"LOG.TXT")
    dfs.wr_str(sdHandle, @"SD card data")
    dfs.closeFileHandle(sdHandle)

    ' Write to Flash
    flHandle := dfs.createFileNew(dfs.DEV_FLASH, @"CONFIG.DAT")
    dfs.wr_str(flHandle, @"Flash data")
    dfs.closeFileHandle(flHandle)

    dfs.unmount(dfs.DEV_BOTH)
    dfs.stop()
```

### Application with raw sector access

```spin2
#PRAGMA EXPORTDEF SD_INCLUDE_RAW

OBJ
    dfs : "dual_sd_fat32_flash_fs"
```

### Application with all features (multi-compiler)

```spin2
#IFDEF __SPINTOOLS__
#DEFINE SD_INCLUDE_ALL
#ELSEIFDEF __FLEXSPIN__
#define SD_INCLUDE_ALL
#pragma exportdef SD_INCLUDE_ALL
#ELSE
#PRAGMA EXPORTDEF SD_INCLUDE_ALL
#ENDIF

OBJ
    dfs : "dual_sd_fat32_flash_fs"
```

### Application with debug diagnostics

```spin2
#PRAGMA EXPORTDEF SD_INCLUDE_DEBUG

OBJ
    dfs : "dual_sd_fat32_flash_fs"

PUB go() | workerCog, matchCount, mismatchCount
    workerCog := dfs.init(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    dfs.mount(dfs.DEV_SD)
    ' ... perform operations ...
    matchCount := dfs.getCRCMatchCount()
    mismatchCount := dfs.getCRCMismatchCount()
    debug("CRC match=", udec_(matchCount), " mismatch=", udec_(mismatchCount))
```
