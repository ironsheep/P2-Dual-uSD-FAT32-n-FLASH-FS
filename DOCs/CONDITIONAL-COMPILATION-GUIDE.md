# Conditional Compilation Guide

**User's guide to the Dual FS driver pragma system, feature flags, multi-compiler support, and debug output control.**

---

## Overview

The Dual FS driver (`dual_sd_fat32_flash_fs.spin2`) uses a conditional compilation system to let you include only the SD card features your application needs. The core driver compiles to ~59 KB with all standard filesystem operations for both SD and Flash. Enabling all optional SD features brings it to ~62 KB. Since the Propeller 2 has 512 KB of hub RAM this isn't usually a constraint, but the mechanism keeps the driver well-organized and gives you control over what ships in your binary.

Feature flags are declared in your **top-level application file** (the file that contains `_CLKFREQ` and the `OBJ` declaration for the driver). The flags propagate down to the driver at compile time using `#pragma exportdef` directives.

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
| `SD_INCLUDE_DEFRAG` | Defragmentation: `fileFragments()`, `compactFile()`, `createFileContiguous()` |
| `SD_INCLUDE_STACK_CHECK` | Worker cog stack depth measurement (diagnostic) |
| `SD_INCLUDE_ALL` | Convenience: enables RAW + REGISTERS + SPEED + DEBUG + DEFRAG |

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

If you only need to compile with pnut-ts (the primary compiler for this project), enabling features is straightforward. Place the `#pragma exportdef` directives **before** your `OBJ` declaration:

```spin2
CON
    _CLKFREQ = 350_000_000

' Enable raw sector access and debug diagnostics
#pragma exportdef SD_INCLUDE_RAW
#pragma exportdef SD_INCLUDE_DEBUG

OBJ
    dfs : "dual_sd_fat32_flash_fs"
```

Or to enable everything:

```spin2
#pragma exportdef SD_INCLUDE_ALL

OBJ
    dfs : "dual_sd_fat32_flash_fs"
```

### When Your File Also Needs the Flag Locally

`#pragma exportdef` propagates a flag to child objects (the driver). It does **not** define the flag in your own file. If your top-level code also has `#ifdef` blocks that check a flag, you need **both** directives:

```spin2
' Make it available locally AND propagate to the driver
#define SD_INCLUDE_STACK_CHECK
#pragma exportdef SD_INCLUDE_STACK_CHECK

OBJ
    dfs : "dual_sd_fat32_flash_fs"

PUB go() | workerCog, depth
    workerCog := dfs.init()
    dfs.mount(dfs.DEV_BOTH)

    ' This #ifdef needs the local #define to work:
#ifdef SD_INCLUDE_STACK_CHECK
    depth := dfs.reportStackDepth()
    debug("Stack depth: ", udec_(depth))
#endif
```

The rule is simple:

| Directive | Scope | Purpose |
|-----------|-------|---------|
| `#define` | Current file only | Controls `#ifdef` guards in your file |
| `#pragma exportdef` | Child objects (OBJ) | Makes the flag visible to the driver |

If your application code doesn't use `#ifdef` blocks for the flag (the common case), you only need `#pragma exportdef`.

---

## Multi-Compiler Support

The project supports three Spin2 compilers. Each handles flag propagation differently, so the codebase uses a three-branch conditional pattern to set flags correctly for whichever compiler is building the code.

### The Three Compilers

| Compiler | Built-in Define | Flag Propagation |
|----------|----------------|------------------|
| **Spin Tools IDE** | `__SPINTOOLS__` | `#define` automatically propagates to child objects |
| **flexspin** | `__FLEXSPIN__` | Requires both `#define` and `#pragma exportdef` (lowercase) |
| **pnut-ts** | *(neither defined)* | Requires `#pragma exportdef` (case insensitive) |

### Why Three Branches?

The compilers differ in flag propagation semantics:

- **Spin Tools** `#define` automatically exports to child objects. flexspin and pnut-ts require an explicit `#pragma exportdef` to propagate flags.
- **flexspin** requires lowercase directives (`#define`, `#pragma exportdef`).
- **pnut-ts** preprocessor directives are case insensitive. The project uses uppercase (`#define`, `#pragma exportdef`) by convention.

### The Standard Pattern

Here is the three-branch pattern used throughout the project. This example enables `SD_INCLUDE_RAW` and `SD_INCLUDE_DEBUG`:

```spin2
#ifdef __SPINTOOLS__
#define SD_INCLUDE_RAW
#define SD_INCLUDE_DEBUG
#elseifdef __FLEXSPIN__
#define SD_INCLUDE_RAW
#pragma exportdef SD_INCLUDE_RAW
#define SD_INCLUDE_DEBUG
#pragma exportdef SD_INCLUDE_DEBUG
#else
#pragma exportdef SD_INCLUDE_RAW
#pragma exportdef SD_INCLUDE_DEBUG
#endif
```

What each branch does:

- **Spin Tools branch** (`__SPINTOOLS__`): Uses `#define` only. The IDE automatically propagates defines to child objects, so no explicit export is needed.

- **flexspin branch** (`__FLEXSPIN__`): Uses lowercase `#define` for the local definition plus lowercase `#pragma exportdef` to propagate to child objects. Both are required.

- **pnut-ts branch** (`#else`): The fallback. Uses `#pragma exportdef` to propagate to the driver (uppercase by convention; pnut-ts is case insensitive). Adds `#define` only if the current file itself needs to test the flag with `#ifdef`.

### Pattern Variations in the Codebase

**Selective features** (e.g., speed tests need SPEED + REGISTERS):

```spin2
#ifdef __SPINTOOLS__
#define SD_INCLUDE_SPEED
#define SD_INCLUDE_REGISTERS
#elseifdef __FLEXSPIN__
#define SD_INCLUDE_SPEED
#pragma exportdef SD_INCLUDE_SPEED
#define SD_INCLUDE_REGISTERS
#pragma exportdef SD_INCLUDE_REGISTERS
#else
#pragma exportdef SD_INCLUDE_SPEED
#pragma exportdef SD_INCLUDE_REGISTERS
#endif
```

**All features** (e.g., demo shell, format utility):

```spin2
#ifdef __SPINTOOLS__
#define SD_INCLUDE_ALL
#elseifdef __FLEXSPIN__
#define SD_INCLUDE_ALL
#pragma exportdef SD_INCLUDE_ALL
#else
#pragma exportdef SD_INCLUDE_ALL
#endif
```

**Stack check only** (e.g., diagnostic tests):

```spin2
#ifdef __SPINTOOLS__
#define SD_INCLUDE_STACK_CHECK
#elseifdef __FLEXSPIN__
#define SD_INCLUDE_STACK_CHECK
#pragma exportdef SD_INCLUDE_STACK_CHECK
#else
#define SD_INCLUDE_STACK_CHECK
#pragma exportdef SD_INCLUDE_STACK_CHECK
#endif
```

Note the pnut-ts branch includes `#define` here because the test file's own code uses `#ifdef SD_INCLUDE_STACK_CHECK` blocks.

**No flags at all** (e.g., seek tests, directory tests): Most test files and all example programs omit the three-branch block entirely. They compile with the core driver, which is all they need.

### If You Only Use One Compiler

If your project only targets one compiler, you can simplify:

**pnut-ts only:**
```spin2
#pragma exportdef SD_INCLUDE_RAW
#pragma exportdef SD_INCLUDE_DEBUG

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
#define SD_INCLUDE_RAW
#define SD_INCLUDE_DEBUG

OBJ
    dfs : "dual_sd_fat32_flash_fs"
```

The three-branch pattern is only needed when the same source must compile under multiple compilers.

---

## How the Driver Uses Feature Flags

Inside the driver (`dual_sd_fat32_flash_fs.spin2`), each optional feature is completely enclosed in `#ifdef` / `#endif` blocks. When a flag is not defined, the compiler removes all related code: public methods, private methods, worker cog command handlers, and command code constants.

### SD_INCLUDE_ALL Expansion

The driver expands `SD_INCLUDE_ALL` into the five individual flags:

```spin2
#ifdef SD_INCLUDE_ALL
#ifndef SD_INCLUDE_RAW
#define SD_INCLUDE_RAW
#endif
#ifndef SD_INCLUDE_REGISTERS
#define SD_INCLUDE_REGISTERS
#endif
#ifndef SD_INCLUDE_SPEED
#define SD_INCLUDE_SPEED
#endif
#ifndef SD_INCLUDE_DEBUG
#define SD_INCLUDE_DEBUG
#endif
#ifndef SD_INCLUDE_DEFRAG
#define SD_INCLUDE_DEFRAG
#endif
#endif
```

The `#ifndef` guards prevent double-definition if you happen to enable both `SD_INCLUDE_ALL` and an individual flag.

### SD_INCLUDE_SPEED Auto-Includes Registers

The driver automatically defines `SD_INCLUDE_REGISTERS` when `SD_INCLUDE_SPEED` is enabled:

```spin2
#ifdef SD_INCLUDE_SPEED
#ifndef SD_INCLUDE_REGISTERS
#define SD_INCLUDE_REGISTERS
#endif
#endif
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

The worker cog's command handler also uses `#ifdef` blocks around each feature's command cases. Only the command codes for enabled features exist in the dispatch table. Disabled command codes are not compiled, so they cannot be accidentally invoked.

---

## Enabling Debug Output

The driver uses selective debug channels controlled by `DEBUG_MASK`. Each `debug()` statement is assigned to a numbered channel via `debug[CH_xxx]()` syntax. Only channels whose bit is set in `DEBUG_MASK` are compiled -- all others are removed from the binary with zero overhead.

### How DEBUG_MASK Works

```spin2
CON ' debug channel assignments for selective debug output
  CH_INIT    = 0              ' Card/device initialization, pin setup, speed config
  CH_MOUNT   = 1              ' Mount/unmount, filesystem geometry, FSInfo
  CH_FILE    = 2              ' File handle operations: open, close, read, write, seek, sync
  CH_DIR     = 3              ' Directory operations: search, create, rename, move, CWD
  CH_SECTOR  = 4              ' Sector I/O, FAT chain walking, cluster allocation
  CH_STATUS  = 5              ' CMD13/CMD23 probe and runtime status checks
  CH_IDENT   = 6              ' Card/device identity: CID/CSD/SCR, Flash serial number
  CH_HSPEED  = 7              ' High-speed mode: CMD6 query, switch, verification
  CH_API     = 8              ' Public API entry points, worker cog dispatch, stack guard
  CH_RECOVER = 9              ' Error recovery: CMD12, bus recovery, SPI bus switching
  CH_FL_BLOCK = 10            ' Flash block-level I/O: read/write/erase 4KB blocks
  CH_FL_CIRC  = 11            ' Flash circular files: froncate, wrap, old-format detection

  DEBUG_MASK = (1 << CH_INIT) | (1 << CH_MOUNT)   ' Default: init + mount channels
```

The driver has ~448 debug statements across 12 channels. The P2 compiler limits debug records to 255 per compilation unit. Enable 2-3 channels at a time to stay under the limit. Any 3 channels combined stay under 255 records.

### Production Builds

Set `DEBUG_MASK = 0` for production builds. This suppresses all driver debug output with zero binary overhead -- equivalent to the old `DEBUG_DISABLE = 1` approach.

### Debug in Your Application Code

Your top-level application file has its own debug settings, independent of the driver's `DEBUG_MASK`. Application and test files use standard `debug()` statements (without channel numbers) and their own `DEBUG_DISABLE` constant:

```spin2
CON
    _CLKFREQ = 350_000_000

OBJ
    dfs : "dual_sd_fat32_flash_fs"   ' Driver debug controlled by its own DEBUG_MASK

PUB go() | workerCog
    debug("Starting application")     ' This WILL appear in debug output
    workerCog := dfs.init()
    dfs.mount(dfs.DEV_BOTH)
    ' Driver debug() calls only appear if their channel is enabled in DEBUG_MASK
```

Each `.spin2` file controls its own debug output independently. The driver's `DEBUG_MASK` and your application's `DEBUG_DISABLE` are separate mechanisms with separate record budgets.

### Debug Settings Across the Project

| File | Debug Setting | Reason |
|------|--------------|--------|
| `dual_sd_fat32_flash_fs.spin2` (driver) | `DEBUG_MASK = 0` (production) | Selective channels via `DEBUG_MASK` |
| `DFS_example_*.spin2` (examples) | `DEBUG_DISABLE = 0` | Show progress/results to user |
| `DFS_demo_shell.spin2` (demo) | `DEBUG_DISABLE = 1` | Uses serial terminal instead of debug |
| `isp_fsck_utility.spin2` | `DEBUG_DISABLE = 1` | Uses FIFO strings instead of debug |
| `isp_serial_singleton.spin2` | `DEBUG_DISABLE = 1` | Owns pin 62 for serial TX (conflicts with debug) |
| `DFS_SD_RT_*_tests.spin2` (tests) | `DEBUG_DISABLE = 0` (default) | Tests use debug for results output |
| `DFS_FL_RT_*_tests.spin2` (tests) | `DEBUG_DISABLE = 0` (default) | Tests use debug for results output |

### How to See Driver-Internal Debug Output

To investigate a specific driver subsystem, enable the relevant channels:

```spin2
' In dual_sd_fat32_flash_fs.spin2 -- temporarily change DEBUG_MASK:
  DEBUG_MASK = (1 << CH_FILE) | (1 << CH_DIR)   ' Investigate file + directory ops
```

**Guidelines:**

1. Enable at most 3 channels simultaneously. The largest 3 channels total ~221 records, safely under the 255 limit.
2. This is a **temporary diagnostic change** -- set `DEBUG_MASK = 0` before committing.
3. The `-d` flag is required when compiling: `pnut-ts -d dual_sd_fat32_flash_fs.spin2`

**Alternative:** Use the `SD_INCLUDE_DEBUG` feature flag to access the driver's diagnostic getters (`getLastCMD13()`, `getCRCMatchCount()`, `getLastCalculatedCRC()`, etc.) without enabling debug output. This is the recommended approach for production debugging.

### SD_INCLUDE_DEBUG vs DEBUG_MASK

These are two different mechanisms that are easily confused:

| Mechanism | What It Controls | Scope |
|-----------|-----------------|-------|
| `SD_INCLUDE_DEBUG` | Whether debug **API methods** are compiled into the driver | Feature flag (compile-time) |
| `DEBUG_MASK` | Which `debug[CH_xxx]()` **print statements** compile | Per-channel bitmask |

You can (and typically do) enable `SD_INCLUDE_DEBUG` while leaving `DEBUG_MASK = 0` in the driver. This gives you access to the debug API (diagnostic getters, CRC error injection hooks) without enabling the driver's internal `debug()` print statements.

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

OBJ
    dfs : "dual_sd_fat32_flash_fs"

PUB go() | workerCog, handle
    workerCog := dfs.init()
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

OBJ
    dfs : "dual_sd_fat32_flash_fs"

PUB go() | workerCog, sdHandle, flHandle
    workerCog := dfs.init()
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
#pragma exportdef SD_INCLUDE_RAW

OBJ
    dfs : "dual_sd_fat32_flash_fs"
```

### Application with all features (multi-compiler)

```spin2
#ifdef __SPINTOOLS__
#define SD_INCLUDE_ALL
#elseifdef __FLEXSPIN__
#define SD_INCLUDE_ALL
#pragma exportdef SD_INCLUDE_ALL
#else
#pragma exportdef SD_INCLUDE_ALL
#endif

OBJ
    dfs : "dual_sd_fat32_flash_fs"
```

### Application with debug diagnostics

```spin2
#pragma exportdef SD_INCLUDE_DEBUG

OBJ
    dfs : "dual_sd_fat32_flash_fs"

PUB go() | workerCog, matchCount, mismatchCount
    workerCog := dfs.init()
    dfs.mount(dfs.DEV_SD)
    ' ... perform operations ...
    matchCount := dfs.getCRCMatchCount()
    mismatchCount := dfs.getCRCMismatchCount()
    debug("CRC match=", udec_(matchCount), " mismatch=", udec_(mismatchCount))
```

### Application with defragmentation

```spin2
#pragma exportdef SD_INCLUDE_DEFRAG

OBJ
    dfs : "dual_sd_fat32_flash_fs"

PUB go() | workerCog, handle, frags, result
    workerCog := dfs.init()
    dfs.mount(dfs.DEV_SD)

    ' Check fragmentation
    frags := dfs.fileFragments(dfs.DEV_SD, @"BIGFILE.DAT")
    if frags > 1
        ' Compact the file (file must be closed)
        result := dfs.compactFile(dfs.DEV_SD, @"BIGFILE.DAT")

    ' Or create a file pre-allocated for contiguous writes
    handle := dfs.createFileContiguous(dfs.DEV_SD, @"STREAM.BIN", 1_000_000)
    ' ... write up to 1 MB of data — guaranteed contiguous ...
    dfs.closeFileHandle(handle)

    dfs.unmount(dfs.DEV_SD)
    dfs.stop()
```

**SD_INCLUDE_DEFRAG methods:**

| Method | Purpose |
|--------|---------|
| `fileFragments(dev, path)` | Count non-contiguous fragments (1 = contiguous, 0 = empty) |
| `isFileContiguous(dev, path)` | TRUE if file has exactly 1 fragment |
| `createFileContiguous(dev, path, size)` | Create file with pre-allocated contiguous cluster chain |
| `compactFile(dev, path)` | Relocate fragmented file to contiguous clusters |

**SD_INCLUDE_DEFRAG error codes:**

| Error Code | Value | Meaning |
|-----------|-------|---------|
| `E_NO_CONTIGUOUS_SPACE` | -131 | No contiguous run of sufficient length exists |
| `E_FILE_OPEN_FOR_COMPACT` | -132 | File is open (cannot compact while open) |
| `E_VERIFY_FAILED` | -133 | Read-back verification failed after compact |

---

## DEBUG_MASK: Selective Debug Channels

The driver uses `DEBUG_MASK` with 12 named debug channels to solve the P2 compiler's 255 debug record limit. All 448 debug statements in the driver use the `debug[CH_xxx]()` form, so only channels with their bit set in `DEBUG_MASK` compile into the binary. Disabled channels produce zero code and zero overhead.

Channels 0-9 use the same names and meanings as the standalone SD driver (`micro_sd_fat32_fs.spin2`), so developers familiar with either driver use the same channel values.

### Channel Assignments

| Channel | Constant | Purpose |
|---------|----------|---------|
| 0 | `CH_INIT` | Card/device initialization, SPI pin setup, speed config |
| 1 | `CH_MOUNT` | Mount/unmount, filesystem geometry, FSInfo, Flash block scan |
| 2 | `CH_FILE` | File handle operations: open, close, read, write, seek, sync |
| 3 | `CH_DIR` | Directory operations: search, create, rename, move, CWD |
| 4 | `CH_SECTOR` | Sector I/O, FAT chain walking, cluster allocation |
| 5 | `CH_STATUS` | CMD13/CMD23 probe and runtime status checks |
| 6 | `CH_IDENT` | Card/device identity: CID/CSD/SCR, Flash serial number |
| 7 | `CH_HSPEED` | High-speed mode: CMD6 query, switch, verification |
| 8 | `CH_API` | Public API entry points, worker cog dispatch, stack guard |
| 9 | `CH_RECOVER` | Error recovery: CMD12, bus recovery, SPI bus switching |
| 10 | `CH_FL_BLOCK` | Flash block-level I/O: read/write/erase 4KB blocks |
| 11 | `CH_FL_CIRC` | Flash circular files: froncate, wrap, old-format detection |

### How to Use

`DEBUG_MASK` is a CON constant inside the driver. To change which channels are active, edit the `DEBUG_MASK` line in `dual_sd_fat32_flash_fs.spin2`:

```spin2
  ' Default: init + mount channels only
  DEBUG_MASK = (1 << CH_INIT) | (1 << CH_MOUNT)

  ' Debug file operations and directory operations
  DEBUG_MASK = (1 << CH_FILE) | (1 << CH_DIR)

  ' Production: zero debug overhead
  DEBUG_MASK = 0
```

Enable 2-3 channels at a time to stay under the 255 debug record limit. The largest channels have ~76 statements each, so any 3 channels combined stay well under 255.

### Interaction with Feature Gates

A debug statement inside an `#ifdef SD_INCLUDE_*` block must pass both gates to compile:

1. The `#ifdef` flag must be defined (the method exists)
2. The channel's bit must be set in `DEBUG_MASK` (the debug statement compiles)

For example, a `debug[CH_HSPEED](...)` inside `#ifdef SD_INCLUDE_SPEED` only compiles if both `SD_INCLUDE_SPEED` is defined AND bit 7 is set in `DEBUG_MASK`.

### Consumer Impact

`DEBUG_MASK` and the channel constants are internal to the driver object. Consumer files (test suites, demo shell, examples, utilities) use their own regular `debug()` statements with a separate record budget. Consumers do not need to define `DEBUG_MASK`.
