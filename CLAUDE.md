# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dual filesystem project for the Parallax Propeller 2 (P2) microcontroller combining a Flash filesystem (onboard 16MB FLASH chip) and a microSD FAT32 filesystem for simultaneous use on a P2 Edge Module. The top-level `src/` is reserved for the future unified dual-FS driver; current implementations live under `REF-FLASH-uSD/`.

## Language and Toolchain

All source is **Spin2** (`.spin2`), the Propeller 2's native language combining high-level Spin code with inline PASM2 assembly.

- **Compiler**: `pnut-ts` (Parallax Spin2 compiler, v45+)
- **Downloader/Terminal**: `pnut-term-ts` (serial terminal for P2 hardware)
- No Makefile; files compile directly.

## Build Commands

```bash
# Compile a Spin2 file (use -I to set include search path)
pnut-ts -d -I ../src <filename>.spin2

# Download and run on P2 hardware
pnut-term-ts -r <filename>.bin
```

The `-I` flag is critical — most source files reference the driver via relative include paths (e.g., `-I ../src` or `-I ../../src`).

## Running Tests

Tests execute on **real P2 hardware** with a physical SD card (no simulator). The SD tests use a runner script in `REF-FLASH-uSD/uSD-FAT32/tools/`:

```bash
cd REF-FLASH-uSD/uSD-FAT32/tools/

# Run a single test suite
./run_test.sh ../regression-tests/SD_RT_mount_tests.spin2

# With custom timeout (seconds, default 60)
./run_test.sh ../regression-tests/SD_RT_multicog_tests.spin2 -t 120

# WARNING: format tests erase the SD card
./run_test.sh ../regression-tests/SD_RT_format_tests.spin2 -t 300
```

Logs are saved to `tools/logs/`. Flash tests are under `REF-FLASH-uSD/FLASH/RegresssionTests/`.

Test framework: `isp_rt_utilities.spin2` (SD) / `RT_utilities.spin2` (Flash) — provides `startTestGroup()`, `startTest()`, `evaluateBool()`, `evaluateSingleValue()`, and `ShowTestEndCounts()`.

## Repository Structure

```
REF-FLASH-uSD/
├── FLASH/                          # Flash filesystem (onboard 16MB chip)
│   ├── flash_fs.spin2                  # Core driver (~4KB per open file)
│   ├── flash_fs_demo.spin2             # Demo application
│   └── RegresssionTests/              # 900+ tests
│
└── uSD-FAT32/                      # microSD FAT32 filesystem
    ├── src/
    │   ├── micro_sd_fat32_fs.spin2     # Core SD driver
    │   ├── DEMO/                       # Interactive terminal shell
    │   ├── EXAMPLES/                   # 4 compilable example programs
    │   └── UTILS/                      # 7 standalone utilities + 3 support libs
    ├── regression-tests/              # 345+ tests across 19 suites
    └── tools/                         # Test runner script and logs

src/                                # Reserved for future unified dual-FS driver
```

## Architecture

### Reference Driver Architectures (REF-FLASH-uSD/)

**SD Driver** — Worker cog pattern:
- Dedicated worker cog runs a command loop, polling `pb_cmd` for commands
- Caller cogs send commands via parameter block (pb_cmd, pb_param0-3), wait via `WAITATN()`
- Worker signals completion via `COGATN(1 << pb_caller)`
- Hardware lock (`locktry`/`lockrel`) serializes multi-cog access
- Smart pin SPI engine (Mode 0): P_TRANSITION clock, P_SYNC_TX/RX data, SE1 event waiting
- ~46 command codes dispatched via case statement
- Up to 6 file/directory handles, each with dedicated 512-byte buffer

**Flash Driver** — No worker cog (synchronous):
- All operations run in the **caller's cog** with inline PASM2
- SPI via smart pin clock + manual bit-bang for data (Mode 3 — inverted clock)
- Multi-cog safety via election-based lock allocation (first cog to call `mount()` wins)
- 4KB block size, wear-leveling via random block allocation + make-before-break replacement
- Default 2 open files, ~4KB buffer per handle
- Per-cog error storage (`errorCode[8]`)

### Unified Driver Plan (src/)

The unified driver will use the SD driver's worker cog architecture as its base and integrate Flash operations within the same cog. Key integration points:

- **SPI mode switching**: SD uses Mode 0 (clock idles LOW), Flash uses Mode 3 (clock idles HIGH). Worker must reconfigure smart pin clock polarity when switching devices.
- **Bus arbitration**: Worker cog is sole SPI bus owner. CS management ensures only one device active. See `DOCs/Analysis/SPI-BUS-STATE-ANALYSIS.md`.
- **Command dispatch**: Extend the case statement with Flash-specific command codes.
- **Handle pool**: Shared handles across both devices; each handle tracks which device it belongs to.
- **Mount sequence**: Single `mount()` initializes both devices (separate CS pins).

### SD Driver Conditional Compilation
The SD driver supports minimal/full builds via pragma exports in the top-level file:

```spin2
#PRAGMA EXPORTDEF SD_INCLUDE_RAW        ' Raw sector access
#PRAGMA EXPORTDEF SD_INCLUDE_REGISTERS  ' Card register access
#PRAGMA EXPORTDEF SD_INCLUDE_SPEED      ' High-speed mode control
#PRAGMA EXPORTDEF SD_INCLUDE_DEBUG      ' Debug/diagnostic methods
```

### Hardware Configuration
Default SD pins for P2 Edge Module: CS=P60, MOSI=P59, MISO=P58, SCK=P61 (base pin 56, 8-pin header group). The Flash chip shares MOSI/MISO/SCK with a separate CS line. Pins are configurable at mount time.

## File Naming Conventions

- `SD_<operation>.spin2` — SD utilities (e.g., `SD_format_card`, `SD_FAT32_audit`)
- `SD_example_<topic>.spin2` — compilable example programs
- `SD_demo_<app>.spin2` — interactive demos
- `SD_RT_<feature>_tests.spin2` — regression test suites
- `isp_<function>.spin2` — Iron Sheep Productions support libraries (serial, strings, FIFO, test utils, format/fsck libs)

## Key Limitations

- 8.3 filenames only (no LFN support)
- SPI mode only, 25 MHz maximum SPI clock
- SDXC cards (>32GB) must be reformatted as FAT32 using the included format utility
- FSCK cluster-chain validation limited to ~64GB cards (P2 hub RAM constraint)
