# Dual Filesystem Demo Shell

An interactive command-line shell for exploring both SD card and Flash filesystem operations on the P2. Supports DOS-style (`dir`, `type`, `del`) and Unix-style (`ls`, `cat`, `rm`) commands. Switch between devices with `dev sd` / `dev flash`, or copy across devices with `copy sd:FILE flash:FILE`.

Beyond exercising driver features, the shell is a practical all-in-one management tool: format a device, check filesystem integrity with `audit`, repair corruption with `fsck`, and measure performance with `bench` -- all without leaving the terminal session.

## Files

| File | Description |
|------|-------------|
| `DFS_demo_shell.spin2` | Main shell application (dual-device) |
| `isp_serial_singleton.spin2` | Serial terminal driver (singleton, shared across cogs) |
| `isp_mem_strings.spin2` | In-memory string formatting utilities |

The shell also uses these files from other directories (included via `-I` flags):

| File | Location | Description |
|------|----------|-------------|
| `dual_sd_fat32_flash_fs.spin2` | `src/` | Unified dual-FS driver |
| `isp_fsck_utility.spin2` | `src/UTILS/` | FSCK/audit library (powers `audit` and `fsck` commands) |
| `isp_format_utility.spin2` | `src/UTILS/` | Format library (powers `format` command) |
| `isp_string_fifo.spin2` | `src/UTILS/` | Inter-cog string FIFO (used by fsck and format libraries) |

## Building and Running

See [Prerequisites](../../README.md#prerequisites) for toolchain and hardware requirements.

### Compile and Run

From this `DEMO/` directory:

```bash
pnut-ts -I .. -I ../UTILS DFS_demo_shell.spin2
pnut-term-ts -r DFS_demo_shell.bin
```

The `-I ..` flag tells the compiler to find the dual-FS driver in the parent directory. The `-I ../UTILS` flag is needed for the fsck, audit, and format libraries used by the shell's diagnostic commands.

**Important:** Do NOT use the `-d` (debug) flag when compiling the demo shell. The debug runtime emits cog-start frames on pin 62 that corrupt the serial output when the driver's worker cog starts mid-session (e.g., during `mount`). The demo shell uses `isp_serial_singleton.spin2` for all terminal I/O, not the debug system.

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

Use `dev` to switch between SD and Flash:

```
sd:/> dev flash
flash:/> dir
 ... Flash file listing ...
flash:/> dev sd
sd:/>
```

### First Steps

Mount the devices before any filesystem operations:

```
sd:(unmounted)> mount
Mounting SD card...
SD mounted successfully
  Card: PNY SD16G (16 GB)
  SPI:  25000000 Hz
  Free: 15.9 GB
sd:/>
```

Switch to Flash and mount it:

```
sd:/> dev flash
flash:(unmounted)> mount
Mounting Flash...
Flash mounted successfully
flash:/>
```

Or mount both at once with `mount both`.

### Browsing Files

**SD directory listing:**
```
sd:/> dir
 Directory of /

  Attr    Name          Size
  ----    --------      ----------
  D---    MYDIR/
  -A--    README.TXT    1,234
  -A--    DATA.BIN      65,536

       2 File(s)     66,770 bytes
       1 Dir(s)

sd:/> cd MYDIR
sd:/MYDIR> dir
```

**Flash directory listing:**
```
flash:/> dir
  Name           Size
  ----------     -----
  sensor.log     128
  config.dat     64

  2 files
```

### Cross-Device Copy

Copy files between SD and Flash using device prefixes:

```
sd:/> copy README.TXT flash:readme
Copied 1,234 bytes (SD -> Flash)

flash:/> copy sensor.log sd:SENSOR.LOG
Copied 128 bytes (Flash -> SD)
```

### File Operations

```
sd:/> type README.TXT
Hello from the P2 dual filesystem driver!
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
  Volume label: P2FMTER
  Free space:   15.9 GB (31199056 sectors)
  Cluster size: 16 sectors (8192 bytes)

sd:/> card
  Manufacturer: PNY (0x27)
  Product:      SD16G
  Revision:     2.0
  Serial:       0x0BADCAFE
  Date:         06/2023
```

### Diagnostics

**Audit** - read-only filesystem integrity check (works on both SD and Flash):
```
sd:/> audit
  [PASS] MBR signature valid ($AA55)
  ...
  All checks passed

flash:/> audit
  Phase 1: canMount() health check...
    canMount: PASS
  Phase 2: Mount and statistics...
    Used blocks:  12  Free blocks:  1012  File count:  3
  Phase 3: File iteration verification...
    File count: MATCH
  AUDIT PASSED - Flash filesystem is healthy
```

**FSCK** - filesystem check and repair (works on both SD and Flash):
```
sd:/> fsck
  WARNING: FSCK will modify the SD card to fix errors.
  Continue? (Y/N): y
  ...
  Filesystem check complete

flash:/> fsck
  Phase 1: Read-only health check (canMount)...
    Health check: PASS (no issues detected)
  FSCK COMPLETE - No repairs needed
```

**Benchmark** - read throughput measurement (SD only):
```
sd:/> bench
  Single sector read:  285 KB/s
  Multi-sector read:   412 KB/s
```

## Complete Command Reference

### Navigation
| Command | Aliases | Description |
|---------|---------|-------------|
| `dev sd` / `dev flash` | | Switch active device |
| `mount` | | Mount the active device (or `mount both`) |
| `unmount` | `eject` | Safely unmount the active device |
| `dir` | `ls` | List directory contents |
| `tree` | | Display directory tree (SD only) |
| `cd <path>` | | Change directory (SD only) |
| `pwd` | | Print current working directory (SD only) |

### File Operations
| Command | Aliases | Description |
|---------|---------|-------------|
| `type <file>` | `cat` | Display text file contents |
| `hexdump <file>` | `hd` | Display file in hex dump format |
| `copy <src> <dst>` | `cp` | Copy a file (supports `sd:`/`flash:` prefixes) |
| `ren <old> <new>` | | Rename a file or directory |
| `move <src> <dst>` | `mv` | Move a file or directory |
| `del <file>` | `rm` | Delete a file |
| `touch <file>` | | Create an empty file |
| `mkdir <dir>` | | Create a new directory (SD only) |
| `rmdir <dir>` | | Remove an empty directory (SD only) |

### Information
| Command | Aliases | Description |
|---------|---------|-------------|
| `stats` | `info` | Show filesystem statistics |
| `label` | `vol` | Show or set volume label (SD only) |
| `date` | | Set or display real-time clock (`date Y M D H M S` or `date`) |
| `card` | `cid` | Show SD card identification |
| `version` | | Show driver version and SPI frequency |
| `alias` | | Show all command aliases |

### Diagnostics
| Command | Aliases | Description |
|---------|---------|-------------|
| `audit` | | Read-only filesystem integrity check (SD and Flash) |
| `fsck` | | Filesystem check and repair (SD and Flash) |
| `format` | | Format the active device (prompts before erasing) |
| `bench` | `benchmark`, `perf` | Read throughput benchmark (SD only) |

### Utility
| Command | Description |
|---------|-------------|
| `demo` | Create sample files for testing |
| `cls` / `clear` | Clear the terminal screen |
| `help` | Show all available commands |

### Cross-Device Copy

Copy files between SD and Flash by prefixing the filename with `sd:` or `flash:`:

```
copy sd:FILE flash:FILE
copy flash:FILE sd:FILE
```

## Architecture

The demo shell runs as a single-cog application:

1. **Main loop** - reads commands from serial, parses tokens, dispatches to handlers
2. **Dual-FS driver** - runs a worker cog for SPI operations (started on `mount`), manages both SD and Flash on the shared SPI bus
3. **Serial driver** - singleton serial terminal on the programming port (P62/P63)

The shell tracks the active device (SD or Flash) and routes commands accordingly. SD supports full directory navigation (`cd`, `pwd`, `mkdir`); Flash uses a flat namespace.

---

*Part of the [P2 Dual SD FAT32 + Flash Filesystem](../../README.md) package -- Iron Sheep Productions*
