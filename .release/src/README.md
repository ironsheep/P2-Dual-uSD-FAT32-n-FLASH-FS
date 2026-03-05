# Source Files

All Spin2 source code for the P2 Dual SD FAT32 + Flash Filesystem driver, demo application, examples, and utility programs.

## Dual-FS Driver

**dual_sd_fat32_flash_fs.spin2** -- The unified dual-filesystem driver for the Parallax Propeller 2. Provides simultaneous access to a microSD card (FAT32) and the onboard 16MB Flash chip through a single dedicated cog and a shared SPI bus.

Features:
- Dedicated worker cog with hardware lock serialization
- Smart pin SPI engine for SD (Mode 0), GPIO bit-bang for Flash (Mode 3)
- Automatic SPI bus switching between devices
- Multi-file handle system (up to 6 simultaneous file and directory handles)
- Per-cog current working directory for safe multi-cog navigation
- Cross-device file copy with `copyFile()`
- Status-returning API (SUCCESS=0 or negative error codes)

### Using the Driver

Copy `dual_sd_fat32_flash_fs.spin2` into your project directory (or use `-I` to point to it), then:

```spin2
OBJ
    dfs : "dual_sd_fat32_flash_fs"
```

See the [Tutorial](../DOCs/DUAL-DRIVER-TUTORIAL.md) for complete examples covering mount, read, write, seek, directory operations, and cross-device copy.

### Conditional Compilation

The SD subsystem builds in **minimal mode** by default (core file operations only). Enable optional modules with `#PRAGMA EXPORTDEF` in your top-level file before the OBJ declaration:

```spin2
#PRAGMA EXPORTDEF SD_INCLUDE_RAW        ' Raw sector access
#PRAGMA EXPORTDEF SD_INCLUDE_REGISTERS  ' Card register access (CID/CSD/SCR)
#PRAGMA EXPORTDEF SD_INCLUDE_SPEED      ' High-speed mode control
#PRAGMA EXPORTDEF SD_INCLUDE_DEBUG      ' Debug/diagnostic methods & CRC getters

' Or include everything:
#PRAGMA EXPORTDEF SD_INCLUDE_ALL
```

## EXAMPLES/

Compilable, self-contained example programs demonstrating common dual-FS driver patterns.

| File | Description |
|------|-------------|
| `DFS_example_basic.spin2` | Mount both devices, write/read files on each, show stats -- the "hello world" |
| `DFS_example_cross_copy.spin2` | Copy a file from SD to Flash and back, verify round-trip data integrity |
| `DFS_example_data_logger.spin2` | Log sensor data to Flash, then archive the log to SD |
| `DFS_example_sd_manifest.spin2` | Read manifest from SD, copy listed files/folders to Flash |

See [EXAMPLES/README.md](EXAMPLES/README.md) for build instructions and what each example teaches.

## DEMO/

Interactive terminal shell for exploring both SD card and Flash filesystem operations. Supports DOS-style (`dir`, `type`, `del`) and Unix-style (`ls`, `cat`, `rm`) commands. Switch between devices with `dev sd` / `dev flash`, or copy across devices with `copy sd:FILE flash:FILE`.

| File | Description |
|------|-------------|
| `DFS_demo_shell.spin2` | Main shell application (dual-device) |
| `isp_serial_singleton.spin2` | Serial terminal driver (singleton, shared across cogs) |
| `isp_mem_strings.spin2` | In-memory string formatting utilities |

See [DEMO/README.md](DEMO/README.md) for build instructions, command reference, and usage examples.

## UTILS/

Standalone utility programs for preparing SD cards and Flash for embedded use, diagnosing filesystem problems, and characterizing untested cards.

| Utility | Purpose | Destructive? |
|---------|---------|:------------:|
| **DFS_SD_format_card.spin2** | FAT32 card formatter | Yes |
| **DFS_SD_FAT32_audit.spin2** | SD filesystem validator (read-only) | No |
| **DFS_SD_FAT32_fsck.spin2** | SD filesystem check & repair | Yes |
| **DFS_SD_card_characterize.spin2** | SD card register reader | No |
| **DFS_FL_format.spin2** | Flash filesystem formatter | Yes |
| **DFS_FL_audit.spin2** | Flash integrity check (read-only) | No |
| **DFS_FL_fsck.spin2** | Flash check & repair | Yes* |

*Repair is performed by remounting, which automatically resolves duplicates, orphans, and bad CRC blocks.

Support libraries used by the utilities:

| File | Used By |
|------|---------|
| `isp_format_utility.spin2` | SD format card, demo shell |
| `isp_fsck_utility.spin2` | SD FSCK, SD audit, demo shell |
| `isp_mem_strings.spin2` | String utilities (shared by format and FSCK libraries) |
| `isp_string_fifo.spin2` | Lock-free inter-cog string FIFO (used by format and FSCK libraries) |

See [UTILS/README.md](UTILS/README.md) for build instructions and detailed documentation for each utility.

## Building

See [Prerequisites](../README.md#prerequisites) for toolchain and hardware requirements.

### Compile and Run

Programs in DEMO/ and UTILS/ use `-I ..` to find the driver in this directory:

```bash
# Driver standalone
pnut-ts -d dual_sd_fat32_flash_fs.spin2

# Demo shell (from DEMO/ directory)
pnut-ts -I .. -I ../UTILS DFS_demo_shell.spin2
pnut-term-ts -r DFS_demo_shell.bin

# Utility (from UTILS/ directory)
pnut-ts -d -I .. DFS_SD_card_characterize.spin2
pnut-term-ts -r DFS_SD_card_characterize.bin
```

---

*Part of the [P2 Dual SD FAT32 + Flash Filesystem](../README.md) package -- Iron Sheep Productions*
