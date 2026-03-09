# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Unified dual filesystem driver for the Parallax Propeller 2 (P2) microcontroller combining a Flash filesystem (onboard 16MB FLASH chip) and a microSD FAT32 filesystem for simultaneous use on a P2 Edge Module. The driver source lives in `src/dual_sd_fat32_flash_fs.spin2`. Reference (read-only) standalone drivers are preserved under `REF-FLASH-uSD/`.

## Language and Toolchain

All source is **Spin2** (`.spin2`), the Propeller 2's native language combining high-level Spin code with inline PASM2 assembly.

- **Compiler**: `pnut-ts` (Parallax Spin2 compiler, v45+)
- **Alternative compiler**: `flexspin.mac` (FlexSpin for macOS; the executable is `flexspin.mac`, NOT `flexspin`)
- **Downloader/Terminal**: `pnut-term-ts` (serial terminal for P2 hardware)
- No Makefile; files compile directly.

## Build Commands

```bash
# From src/ — compile the driver standalone
pnut-ts -d dual_sd_fat32_flash_fs.spin2

# From a subdirectory (EXAMPLES/, regression-tests/, UTILS/)
pnut-ts -d -I .. <filename>.spin2

# From DEMO/ (needs UTILS include path too)
pnut-ts -I .. -I ../UTILS DFS_demo_shell.spin2

# Download and run on P2 hardware
pnut-term-ts -r <filename>.bin
```

The `-I` flag is critical — most source files reference the driver via relative include paths (e.g., `-I ..`).

```bash
# FlexSpin compile check (macOS) — from src/
flexspin.mac -2 -q -I . -I UTILS <filename>.spin2
```

## Running Tests

Tests execute on **real P2 hardware** with a physical SD card and onboard Flash chip (no simulator). Runner scripts are in `tools/`:

```bash
cd tools/

# Run a single test suite
./run_test.sh ../src/regression-tests/DFS_SD_RT_mount_tests.spin2

# With custom timeout (seconds, default 60)
./run_test.sh ../src/regression-tests/DFS_SD_RT_multicog_tests.spin2 -t 120

# Full unified regression (stop on first fail)
./run_regression.sh

# Resume from a specific suite (substring match)
./run_regression.sh --from cwd_tests

# Compile check only (no hardware)
./run_regression.sh --compile-only

# Include 8-cog stress test
./run_regression.sh --include-8cog

# Include format test (WARNING: erases SD card!)
./run_regression.sh --include-format
```

Logs are saved to `tools/logs/`.

Test framework: `DFS_RT_utilities.spin2` (unified, used by all test suites) — provides `startTestGroup()`, `startTest()`, `evaluateBool()`, `evaluateSingleValue()`, sub-test variants, Flash helpers, and `ShowTestEndCounts()`.

## Repository Structure

```
src/
├── dual_sd_fat32_flash_fs.spin2       # Unified dual-FS driver (~9400 lines)
├── DEMO/                              # Interactive dual-device shell
│   └── DFS_demo_shell.spin2
├── EXAMPLES/                          # 3 compilable example programs
├── UTILS/                             # 7 standalone utilities + 4 support libs
└── regression-tests/                  # 32 standard suites, 1,300+ tests

tools/                                 # Test runner scripts and logs
DOCs/                                  # Technical documentation

REF-FLASH-uSD/                         # Read-only reference drivers (development baseline)
├── FLASH/                             # Flash FS reference (Chip Gracey / Jon McPhalen)
└── uSD-FAT32/                         # microSD FAT32 reference (Chris Gadd / Stephen Moraco)
```

## Architecture

**Unified Driver** (`dual_sd_fat32_flash_fs.spin2`) — Worker cog pattern:
- Dedicated worker cog runs a command loop, polling `pb_cmd` for commands
- Caller cogs send commands via parameter block (pb_cmd, pb_param0-3), wait via `WAITATN()`
- Worker signals completion via `COGATN(1 << pb_caller)`
- Hardware lock (`locktry`/`lockrel`) serializes multi-cog access
- SD: smart pin SPI engine (Mode 0) with P_TRANSITION clock, P_SYNC_TX/RX data, SE1 event waiting
- Flash: GPIO bit-bang SPI (Mode 3 — inverted clock polarity)
- Lazy SPI bus switching between devices (only reconfigures on device change)
- Up to 6 shared file/directory handles across both devices; each handle tracks its device
- SD card re-initialization after Flash operations (P60 doubles as Flash SCK)
- Per-cog current working directory for SD navigation and Flash directory emulation
- See `DOCs/Analysis/SPI-BUS-STATE-ANALYSIS.md` for bus sharing details

### SD Driver Conditional Compilation
The SD driver supports minimal/full builds via pragma exports in the top-level file:

```spin2
#pragma exportdef SD_INCLUDE_RAW        ' Raw sector access
#pragma exportdef SD_INCLUDE_REGISTERS  ' Card register access
#pragma exportdef SD_INCLUDE_SPEED      ' High-speed mode control
#pragma exportdef SD_INCLUDE_DEBUG      ' Debug/diagnostic methods
```

### Hardware Configuration
Default SD pins for P2 Edge Module: CS=P60, MOSI=P59, MISO=P58, SCK=P61 (base pin 56, 8-pin header group). The Flash chip shares MOSI/MISO/SCK with a separate CS line. Pins are configurable at mount time.

## File Naming Conventions

- `DFS_SD_<operation>.spin2` — SD utilities (e.g., `DFS_SD_format_card`, `DFS_SD_FAT32_audit`)
- `DFS_FL_<operation>.spin2` — Flash utilities (e.g., `DFS_FL_format`, `DFS_FL_audit`)
- `DFS_example_<topic>.spin2` — compilable example programs
- `DFS_demo_<app>.spin2` — interactive demos
- `DFS_SD_RT_<feature>_tests.spin2` — SD regression test suites
- `DFS_FL_RT_<feature>_tests.spin2` — Flash regression test suites
- `DFS_RT_<feature>_tests.spin2` — Cross-device and dual-device test suites
- `isp_<function>.spin2` — Iron Sheep Productions support libraries (serial, strings, FIFO, test utils, format/fsck libs)

## Output Rules -- Regression Test Reporting

- After running regression tests, report **every test file on its own line** with pass/fail counts, plus totals at the end. Example:
  ```
  DFS_RT_dual_device_tests:        36 pass, 0 fail
  DFS_SD_RT_mount_tests:           21 pass, 0 fail
  DFS_SD_RT_error_handling_tests:  17 pass, 0 fail
  ...
  Total: 1,378 tests, 0 failures
  ```
- Do NOT summarize or group results by suite group (e.g., "SD: 424 pass"). Each file has a different purpose and must be reported individually.
- Do NOT skip files or abbreviate with "All N suites pass". The user watches output live and wants per-file confirmation.

## Key Limitations

- 8.3 filenames only (no LFN support)
- SPI mode only, 25 MHz maximum SPI clock
- SDXC cards (>32GB) must be reformatted as FAT32 using the included format utility
- FSCK cluster-chain validation limited to ~64GB cards (P2 hub RAM constraint)

---

## Todo MCP Mastery Operations

### Quick Recovery Commands
```bash
mcp__todo-mcp__context_resume     # "WHERE WAS I?" - primary recovery
mcp__todo-mcp__todo_next          # Smart task recommendation
mcp__todo-mcp__todo_archive       # Clean completed tasks
mcp__todo-mcp__context_stats      # Context health check
```

### Core Parameter Patterns
```bash
# PREFER task_id (permanent) over position_id (ephemeral)
mcp__todo-mcp__todo_start task_id:"#49"    # Reliable - ID never changes
mcp__todo-mcp__todo_pause task_id:"#49" reason:"Blocked"
mcp__todo-mcp__todo_complete task_id:"#49"

# Critical data types
estimate_minutes:60        # Number, never string
priority:"high"           # lowercase: critical/high/medium/low/backlog
force:true               # Boolean, never string
task_id:"#49"            # String with # prefix
```

### Context Hygiene (40-Key Target)
```bash
# Persistent context (KEEP)
lesson_*, workaround_*, recovery_*, friction_*

# Temporary context (DELETE after use)
temp_*, current_*, session_*, task_#N_*

# Regular cleanup
mcp__todo-mcp__context_delete pattern:"temp_*"
mcp__todo-mcp__context_delete pattern:"task_#N_*"  # After task completion
```

### Data Safety (ALWAYS)
```bash
# SAFE archiving (preserves backup)
mcp__todo-mcp__todo_archive

# Complete backup before risky operations
mcp__todo-mcp__project_dump include_context:true

# Recovery
mcp__todo-mcp__project_restore file:"filename.json" mode:"replace"
```

### Task Lifecycle (ENFORCED)
1. **Start** before work: `todo_start task_id:"#N"`
2. **Complete** after work: `todo_complete task_id:"#N"`
3. **Archive** when done: `todo_archive`
4. Only ONE task `in_progress` at a time (auto-enforced)

## CRITICAL: Mastery Folder is Read-Only

**NEVER create, modify, or store files in `.todo-mcp/mastery/`** — this folder is replaced during upgrades.

Store notes in: project root, `docs/`, `.todo-mcp/notes/`, or context system.
