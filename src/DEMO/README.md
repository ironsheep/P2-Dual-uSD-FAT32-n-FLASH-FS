# Dual Filesystem Demo Shell

An interactive command-line shell for exploring both SD card and Flash filesystem operations on the P2. Supports DOS-style (`dir`, `type`, `del`) and Unix-style (`ls`, `cat`, `rm`) commands. Switch between devices with `dvc sd` / `dvc flash`, or copy across devices with `copy sd:FILE flash:FILE`.

## Files

| File | Description |
|------|-------------|
| `DFS_demo_shell.spin2` | Main shell application (dual-device) |
| `isp_serial_singleton.spin2` | Serial terminal driver (singleton, shared across cogs) |
| `isp_mem_strings.spin2` | In-memory string formatting utilities (includes number-to-string) |

The shell also uses `dual_sd_fat32_flash_fs.spin2` from the parent directory (included via `-I ..`).

## Building and Running

### Prerequisites

- **pnut-ts** and **pnut-term-ts** - See detailed installation instructions for **[macOS](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-macOS.md#installing-pnut-term-ts-on-macos)**, **[Windows](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-win.md#installing-pnut-term-ts-on-windows)**, and **[Linux/RPi](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-RPi.md#installing-pnut-term-ts-on-rpilinux)**
- Parallax P2 Edge Module (P2-EC or P2-EC32MB) connected via USB

### Compile and Run

From this `DEMO/` directory:

```bash
pnut-ts -I .. -I ../UTILS DFS_demo_shell.spin2
pnut-term-ts -r DFS_demo_shell.bin
```

The `-I ..` flag finds `dual_sd_fat32_flash_fs.spin2` in the parent directory. The `-I ../UTILS` flag finds the FSCK/audit and format utility libraries.

**Important:** Do NOT use the `-d` (debug) flag when compiling the demo shell. The debug runtime emits cog-start frames on pin 62 that corrupt the serial output when the SD worker cog starts mid-session (e.g., during `mount`). The demo shell uses `isp_serial_singleton.spin2` for all terminal I/O, not the debug system.

## Terminal Setup

Connect a serial terminal to the P2 programming port:

- **Baud rate:** 2,000,000 (2 Mbit)
- **Data format:** 8N1
- **Terminal type:** PST (Parallax Serial Terminal) compatible
- **Flow control:** None

The shell uses PST control characters for screen clearing (CLS = 16) and cursor control.

## Using the Shell

### Startup

When the shell starts, it clears the screen and displays a welcome banner. The prompt shows the active device, current directory, and mount status:

```
sd:/> _                  (SD mounted, at root)
sd:/MYDIR> _             (SD mounted, in MYDIR)
flash:/> _               (Flash active, mounted)
sd:(unmounted)> _        (SD not mounted)
```

### Device Switching

Use `dvc` to switch between SD and Flash (`fl` and `flash` are interchangeable everywhere):

```
sd:/> dvc fl
flash:/> dir
 ... Flash file listing ...
flash:/> dvc sd
sd:/>
```

### First Steps

Mount the devices before any filesystem operations:

```
sd:(unmounted)> mount
Mounting SD card...
SD mounted successfully
  Volume: [P2FMTER    ]
  Size: 15272 MB (15GB)
sd:/>
```

Switch to Flash and mount it:

```
sd:/> dvc fl
flash:(unmounted)> mount
Mounting Flash...
Flash mounted successfully
  Size: 15872 KB (15MB)
flash:/>
```

Or mount both at once with `mount all`.

### Browsing Files

**SD directory listing:**
```
sd:/> dir
 Directory of /

  Attr      Size  Name
  ----  --------  --------------------------------
  D---    <DIR>  MYDIR
  -A--      1234  README.TXT
  -A--     65536  DATA.BIN

  3 file(s), 66770 bytes

sd:/> cd MYDIR
sd:/MYDIR> dir
```

**Flash directory listing:**
```
flash:/> dir
 Flash Files

      Size  Name
  --------  --------------------------------
       128  sensor.log
        64  config.dat

  2 file(s), 192 bytes
```

### Cross-Device Copy

Copy files between SD and Flash using device prefixes (`fl:` and `flash:` are interchangeable):

```
sd:/> copy README.TXT fl:readme
Copied README.TXT -> readme (cross-device)

flash:/> copy sensor.log sd:SENSOR.LOG
Copied sensor.log -> SENSOR.LOG (cross-device)
```

### File Operations

```
sd:/> type README.TXT

Hello from the P2 SD card driver!

[58 bytes]

sd:/> copy README.TXT BACKUP.TXT
Copied 58 bytes to BACKUP.TXT

sd:/> ren BACKUP.TXT SAVED.TXT
Renamed 'BACKUP.TXT' to 'SAVED.TXT'

sd:/> touch EMPTY.TXT
Created: EMPTY.TXT

sd:/> del EMPTY.TXT
Deleted: EMPTY.TXT
```

### Card Information

```
sd:/> stats
Total:  15272 MB
Free:   15227 MB
Label:  [P2FMTER    ]

sd:/> card
card ready...
PNY SD16G SDHC 15GB [FAT32] SD3.x rev2.0 SN:0BADCAFE 2023/06
OEM: MSWIN4.1
```

### Diagnostics

**Audit** - read-only filesystem integrity check (works on both SD and Flash):
```
sd:/> audit
Unmounted for audit.
  ... (audit output from external utility) ...

Re-mount devices? (Y/N): y

flash:/> audit
Flash Filesystem Audit (Read-Only)

Phase 1: canMount() health check...
  canMount: PASS

Phase 2: Mount and statistics...
  Mount: PASS
  Used blocks:  12
  Free blocks:  1012
  File count:   3
  Total blocks: 1024

Phase 3: File iteration verification...
  [1] hello.txt (26 bytes)
  [2] readme.txt (45 bytes)
  [3] config.dat (64 bytes)
  Iterated files: 3
  Total bytes:    135
  File count: MATCH

AUDIT PASSED - Flash filesystem is healthy
```

**FSCK** - filesystem check and repair (works on both SD and Flash):
```
sd:/> fsck
FSCK requires unmount. Unmount now? (Y/N): y
Unmounted.
  ... (FSCK output from external utility) ...

Re-mount devices? (Y/N): y

flash:/> fsck
Flash Filesystem Check & Repair (FSCK)

Phase 1: Read-only health check (canMount)...
  Health check: PASS (no issues detected)

  Mounting to verify statistics...
  Used blocks:  12
  Free blocks:  1012
  File count:   3

FSCK COMPLETE - No repairs needed
```

**Benchmark** - read throughput measurement (SD only):
```
sd:/> bench

=== Read-Only Throughput Benchmark ===
Card: 15272 MB
Test area: sectors 2048+

Single-sector (100 reads)... 48 ms, 204 KB/s
Multi-sector x8 (100 reads)... 196 ms, 400 KB/s
Multi-sector x32 (25 reads)... 130 ms, 601 KB/s
Multi-sector x64 (16 reads)... 133 ms, 600 KB/s

Benchmark complete.
```

## Complete Command Reference

### Navigation
| Command | Aliases | Description |
|---------|---------|-------------|
| `dvc {sd|fl}` | | Switch active device (`fl` and `flash` both work) |
| `mount [sd|fl|all]` | | Mount active device, or specified |
| `unmount [sd|fl]` | `eject` | Unmount active device, or specified |
| `dir` | `ls` | List directory contents |
| `tree [<path>]` | | Display directory tree |
| `cd [<path>]` | | Change directory (bare `cd` = root) |
| `pwd` | | Print current working directory |
| `mkdir <dir>` | | Create a new directory |
| `rmdir <dir>` | | Remove an empty directory |

### File Operations
| Command | Aliases | Description |
|---------|---------|-------------|
| `type <file>` | `cat` | Display text file contents |
| `hexdump <file>` | `hd` | Display file in hex dump format |
| `copy <src> <dst>` | `cp` | Copy a file (supports `sd:`/`fl:` prefixes) |
| `ren <old> <new>` | | Rename a file or directory |
| `move <src> <dst>` | `mv` | Move file to directory, or rename |
| `del <file>` | `rm` | Delete a file |
| `touch <file>` | | Create an empty file |

### Information
| Command | Aliases | Description |
|---------|---------|-------------|
| `stats` | `info` | Show filesystem statistics |
| `card` | `cid` | Show SD card identification (SD only) |
| `version` | | Show driver version |
| `label [<name>]` | `vol` | Display or set volume label (SD only) |

### Diagnostics
| Command | Aliases | Description |
|---------|---------|-------------|
| `audit` | | Read-only filesystem integrity check (SD and Flash) |
| `fsck` | | Filesystem check and repair (SD and Flash) |
| `bench` | `benchmark`, `perf` | Read throughput benchmark (SD only) |
| `format [sd|fl]` | | Format active device, or specified |

### Utility
| Command | Description |
|---------|-------------|
| `demo` | Create sample files for testing |
| `cls` / `clear` | Clear the terminal screen |
| `alias` | Show all command aliases |
| `help` | Show all available commands |

## Architecture

The demo shell runs as a single-cog application:

1. **Main loop** - reads commands from serial, parses tokens, dispatches to handlers
2. **Dual-FS driver** - runs a worker cog for SPI operations (started on `mount`), manages both SD and Flash on the shared SPI bus
3. **Serial driver** - singleton serial terminal on the programming port (P62/P63)

The shell tracks the active device (SD or Flash) and routes commands accordingly. Both devices support directory navigation (`cd`, `pwd`, `mkdir`). Flash emulates directories using path-prefixed filenames; the driver handles path resolution transparently so callers pass full paths (e.g., `/MYDIR/FILE.TXT`) and the driver navigates internally.

---

*Part of the [P2 Dual SD FAT32 + Flash Filesystem](../../README.md) project — Iron Sheep Productions*
