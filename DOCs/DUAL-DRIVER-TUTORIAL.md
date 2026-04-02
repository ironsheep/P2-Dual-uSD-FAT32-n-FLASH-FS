# Dual Filesystem Driver — Tutorial

*dual_sd_fat32_flash_fs.spin2*

**A practical guide to SD + Flash file operations on the Parallax Propeller 2**

This tutorial shows how to perform common filesystem operations using the unified dual-FS driver. The driver manages both a microSD card (FAT32) and the onboard 16MB Flash chip through a single API.

> **Reference:** For architecture, command protocols, and internal details, see [DUAL-DRIVER-THEORY.md](DUAL-DRIVER-THEORY.md).

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Initialization and Mounting](#initialization-and-mounting)
3. [Two Devices, One API](#two-devices-one-api)
4. [SD File Operations](#sd-file-operations)
5. [Flash File Operations](#flash-file-operations)
6. [Cross-Device Operations](#cross-device-operations)
7. [Working with Directories](#working-with-directories)
8. [Seeking and Random Access](#seeking-and-random-access)
9. [File Information](#file-information)
10. [File Management](#file-management)
11. [Non-Blocking File I/O](#non-blocking-file-io)
12. [Multi-Cog Access](#multi-cog-access)
13. [Error Handling](#error-handling)
14. [Complete Examples](#complete-examples)
15. [Example Programs](#example-programs)
16. [Conditional Compilation](#conditional-compilation)
17. [API Quick Reference](#api-quick-reference)

---

## Quick Start

```spin2
OBJ
  fs : "dual_sd_fat32_flash_fs"

CON  ' Application constants
  ' P2 Edge Module default pins
DAT
  testFile    BYTE  "TEST.TXT", 0
  sensorLog   BYTE  "sensor-log.dat", 0
  flashMsg    BYTE  "Hello from Flash!", 0

PUB main() | workerCog, status, handle, buf[128], bytesRead
  ' Step 1: Initialize driver (starts worker cog)
  workerCog := fs.init()
  if workerCog >= 0
    ' Step 2: Mount one or both devices
    status := fs.mount(fs.DEV_BOTH)
    if status == fs.SUCCESS
      ' Step 3: Use SD (FAT32 -- directories, 8.3 filenames)
      handle := fs.openFileRead(fs.DEV_SD, @testFile)
      if handle >= 0
        bytesRead := fs.readHandle(handle, @buf, 512)
        fs.closeFileHandle(handle)
        debug("SD: read ", udec(bytesRead), " bytes")

      ' Step 4: Use Flash (block-based -- directory emulation, long filenames)
      handle := fs.open(fs.DEV_FLASH, @sensorLog, fs.FILEMODE_WRITE)
      if handle >= 0
        fs.wr_str(handle, @flashMsg)
        fs.close(handle)

      ' Step 5: Clean shutdown
      fs.unmount(fs.DEV_BOTH)
    fs.stop()
```

Key differences from the SD-only reference driver:

| SD-only driver | Unified driver |
|----------------|----------------|
| `sd : "micro_sd_fat32_fs"` | `fs : "dual_sd_fat32_flash_fs"` |
| `sd.mount(CS, MOSI, MISO, SCK)` | `fs.init()` then `fs.mount(dev)` |
| `sd.openFileRead(@"FILE")` | `fs.openFileRead(fs.DEV_SD, @"FILE")` |
| (no Flash support) | `fs.open(fs.DEV_FLASH, @"file", mode)` |

---

## Initialization and Mounting

Initialization and mounting are separate steps in the unified driver. This allows you to start the worker cog once and then mount/unmount devices independently during the application's lifetime.

### Step 1: Initialize

```spin2
PUB init() : workerCog
```

`init()` allocates a hardware lock, starts the worker cog, and returns the worker's cog ID (0-7). Pin assignments are fixed CON constants for the P2 Edge Module (CS=P60, MOSI=P59, MISO=P58, SCK=P61). Call it once at startup. If it returns a negative value, initialization failed.

```spin2
workerCog := fs.init()
if workerCog < 0
  debug("Init failed!")
  return
```

### Step 2: Mount

```spin2
PUB mount(dev) : status
```

Mount one or both devices. The `dev` parameter selects the target:

| Argument | Effect |
|----------|--------|
| `fs.DEV_SD` | Mount SD card only |
| `fs.DEV_FLASH` | Mount Flash chip only |
| `fs.DEV_BOTH` | Mount both devices |

```spin2
' Mount both devices
status := fs.mount(fs.DEV_BOTH)

' Or mount individually
fs.mount(fs.DEV_SD)
fs.mount(fs.DEV_FLASH)
```

`mount()` returns `SUCCESS` (0) on success, or a negative error code on failure. After mounting, you can check the status:

```spin2
status := fs.mount(fs.DEV_SD)
if status < 0
  debug("SD mount failed: ", zstr(fs.string_for_error(status)))
else
  debug("SD mounted, volume: ", zstr(fs.volumeLabel(fs.DEV_SD)))
```

### Checking Mount Status

```spin2
if fs.mounted(fs.DEV_SD)
  debug("SD is mounted")
if fs.mounted(fs.DEV_FLASH)
  debug("Flash is mounted")
```

`mounted()` is lock-free — it reads a hub RAM flag directly, so it's safe and fast to call from any cog at any time.

### Unmounting

Always unmount cleanly to ensure data integrity:

```spin2
fs.unmount(fs.DEV_BOTH)   ' Flush and unmount both
fs.stop()                  ' Stop worker cog, release lock
```

For SD, unmounting flushes pending writes and updates the FSInfo sector. For Flash, it flushes any open file block buffers.

### Pin Assignments

The P2 Edge Module uses a fixed pin mapping where MISO and MOSI are shared between both devices, while CS and SCK swap roles:

| Pin | SD Function | Flash Function |
|-----|-------------|----------------|
| P58 | MISO | MISO |
| P59 | MOSI | MOSI |
| P60 | CS | SCK |
| P61 | SCK | CS |

The pin assignments are fixed CON constants in the driver. The Flash pins are the SD pins with P60/P61 swapped (CS and SCK exchange roles).

---

## Two Devices, One API

The driver manages two very different storage devices through a unified interface:

| Feature | SD Card (FAT32) | Flash Chip (Block-Based) |
|---------|-----------------|--------------------------|
| Capacity | Card-dependent (up to 2 TB, SDHC/SDXC) | 16 MB (3968 x 4KB blocks) |
| Filenames | 8.3 format (case-insensitive) | Up to 127 characters |
| Directories | Full hierarchy (cd, mkdir, tree) | Emulated via path-segmented filenames |
| Sector/block size | 512 bytes | 4096 bytes |
| File I/O style | Handle-based (readHandle/writeHandle) | Byte/word/long/string-level (wr_byte/rd_str) |
| Removable | Yes | No (soldered on board) |

### Device Constants

Most path-based methods take a `dev` parameter as the first argument:

```spin2
fs.DEV_SD      ' microSD card
fs.DEV_FLASH   ' Onboard Flash chip
fs.DEV_BOTH    ' Both (mount/unmount only)
```

Handle-based methods (readHandle, writeHandle, closeFileHandle, etc.) do **not** need a device parameter — the driver remembers which device each handle belongs to.

### Choosing the Right Device

| Use Case | Best Device | Why |
|----------|-------------|-----|
| Large data files | SD | More capacity, removable for PC access |
| Configuration storage | Flash | Always present, survives card removal |
| High-frequency logging | Flash | No SD latency, fast small writes |
| Long-term archival | SD | Removable, standard FAT32, large capacity |
| Data exchange with PC | SD | Standard FAT32, USB card reader |
| Sensor buffering | Flash | Fast writes, then archive to SD |

---

## SD File Operations

SD file operations use the handle-based API familiar from standard file I/O: open a file, get a handle, read/write through it, close when done.

### Filename Format

SD uses **8.3 short filenames**: up to 8 characters, a dot, and a 3-character extension. Names are case-insensitive — `"DATA.TXT"`, `"data.txt"`, and `"Data.Txt"` all refer to the same file. Long filenames (LFN) are not supported.

### Opening Files

```spin2
' Open for reading (returns handle or negative error code)
handle := fs.openFileRead(fs.DEV_SD, @"DATA.TXT")
if handle < 0
  debug("Open failed, error: ", sdec(handle))

' Open for writing/append (existing file, positions at end)
handle := fs.openFileWrite(fs.DEV_SD, @"OUTPUT.TXT")

' Create new file for writing (fails if file already exists)
handle := fs.createFileNew(fs.DEV_SD, @"NEWFILE.TXT")
```

### Reading and Writing

```spin2
' Read using handle
bytes_read := fs.readHandle(handle, @buffer, count)

' Write using handle
bytes_written := fs.writeHandle(handle, @buffer, count)
```

### Closing and Flushing

```spin2
' Close handle (flushes pending writes, updates directory entry)
fs.closeFileHandle(handle)

' Flush without closing (checkpoint for power-fail safety)
fs.syncHandle(handle)

' Flush all open write handles
fs.syncAllHandles()
```

### Handle Concepts

**Handle pool:** File and directory handles share a single pool of `MAX_OPEN_FILES` slots (default 6, configurable). Both SD and Flash handles come from this same pool.

**Single-writer policy:** Only one handle can have a given SD file open for writing at a time. Multiple read handles to the same file are allowed.

**Handle type guards:** File operations reject directory handles and vice versa.

---

## Flash File Operations

Flash uses a different I/O style than SD. Instead of bulk buffer reads/writes, Flash provides byte, word, long, and string-level operations.

### Filename Format

Flash supports filenames up to **127 characters** (128 bytes including null terminator). Names are stored as-is — there is no 8.3 restriction and no case folding.

### Open Modes

```spin2
fs.FILEMODE_READ             ' "r" — read existing file
fs.FILEMODE_WRITE            ' "w" — write new file (truncates if exists)
fs.FILEMODE_APPEND           ' "a" — append to existing file
fs.FILEMODE_READ_EXTENDED    ' "r+" — read/write existing file
fs.FILEMODE_WRITE_EXTENDED   ' "w+" — read/write, truncates if exists
```

### Opening and Closing

```spin2
' Open for reading
handle := fs.open(fs.DEV_FLASH, @"sensor-log.dat", fs.FILEMODE_READ)
if handle < 0
  debug("Open failed: ", sdec(handle))

' Open for writing (creates new or truncates)
handle := fs.open(fs.DEV_FLASH, @"config.dat", fs.FILEMODE_WRITE)

' Close when done
fs.close(handle)

' Flush without closing
fs.flush(handle)
```

### Writing Data

```spin2
' Write individual values
fs.wr_byte(handle, $42)              ' Single byte
fs.wr_word(handle, 1234)             ' 16-bit (little-endian)
fs.wr_long(handle, 1_000_000)        ' 32-bit (little-endian)

' Write string (includes null terminator in the file)
fs.wr_str(handle, @"Temperature: 23.5C")
```

### Reading Data

```spin2
' Read individual values
byteVal := fs.rd_byte(handle)       ' Single byte
wordVal := fs.rd_word(handle)       ' 16-bit
longVal := fs.rd_long(handle)       ' 32-bit

' Read string (reads until null terminator or maxLen)
bytesRead := fs.rd_str(handle, @strBuf, STR_BUF_SIZE)
```

> **Note:** `wr_str()` writes the null terminator into the file. `rd_str()` reads until it finds that terminator (or hits the buffer limit). The return value from `rd_str()` is the string length **without** the terminator.

### Pre-Allocating Files

For Flash files that will be written incrementally, you can pre-allocate space:

```spin2
' Create a 4000-byte file filled with zeros
fs.create_file(fs.DEV_FLASH, @"buffer.dat", 0, 4000)
```

### Circular Files

Flash supports circular (ring-buffer) files that wrap around at a fixed size:

```spin2
handle := fs.open_circular(fs.DEV_FLASH, @"ringlog.dat", fs.FILEMODE_WRITE, 8000)
' Writes beyond 8000 bytes wrap to the beginning
```

### Flash Example: Write and Read Back

```spin2
DAT
  flTestFile  BYTE  "test.dat", 0
  flTestStr   BYTE  "hello", 0

PUB flashReadWrite() | handle, value, nameBuf[8]
  ' Write some values
  handle := fs.open(fs.DEV_FLASH, @flTestFile, fs.FILEMODE_WRITE)
  if handle >= 0
    fs.wr_long(handle, 42)
    fs.wr_str(handle, @flTestStr)
    fs.close(handle)

  ' Read them back
  handle := fs.open(fs.DEV_FLASH, @flTestFile, fs.FILEMODE_READ)
  if handle >= 0
    value := fs.rd_long(handle)
    debug("Value: ", udec(value))          ' 42

    fs.rd_str(handle, @nameBuf, 32)
    debug("String: ", zstr(@nameBuf))      ' hello

    fs.close(handle)
```

---

## Cross-Device Operations

The driver provides a built-in `copyFile()` that copies data between any combination of devices:

```spin2
PUB copyFile(srcDev, pSrc, dstDev, pDst) : status
```

### Copying Between Devices

```spin2
' Copy from SD to Flash
fs.copyFile(fs.DEV_SD, @"DATA.TXT", fs.DEV_FLASH, @"data-backup.txt")

' Copy from Flash to SD
fs.copyFile(fs.DEV_FLASH, @"sensor.dat", fs.DEV_SD, @"SENSOR.DAT")

' Same-device copy also works
fs.copyFile(fs.DEV_SD, @"FILE.TXT", fs.DEV_SD, @"COPY.TXT")
```

`copyFile()` opens both files, transfers data in 512-byte chunks, and closes both handles. It handles the SPI bus switching internally.

### Manual Cross-Device Copy

For more control (e.g., data transformation during copy), you can do it manually:

```spin2
DAT
  srcLogFile  BYTE  "log.dat", 0
  dstLogFile  BYTE  "LOG.TXT", 0

PUB manualCopy() | srcHandle, dstHandle, buf[128], bytesRead
  ' Read from Flash
  srcHandle := fs.open(fs.DEV_FLASH, @srcLogFile, fs.FILEMODE_READ)
  if srcHandle >= 0
    ' Write to SD
    dstHandle := fs.createFileNew(fs.DEV_SD, @dstLogFile)
    if dstHandle >= 0
      ' Copy loop -- driver handles SPI switching per command
      repeat
        bytesRead := fs.readHandle(srcHandle, @buf, 512)
        if bytesRead == 0
          quit
        fs.writeHandle(dstHandle, @buf, bytesRead)
      fs.closeFileHandle(dstHandle)
    fs.close(srcHandle)
```

---

## Working with Directories

Both SD and Flash support directory navigation. SD uses the native FAT32 directory hierarchy. Flash emulates directories using path-segmented filenames — the driver prepends the current working directory prefix to filenames transparently.

### Changing the Current Directory (SD)

Each P2 cog maintains its own current working directory (CWD):

```spin2
' Navigate to a subdirectory
fs.changeDirectory(fs.DEV_SD, @"LOGS")

' Navigate to root
fs.changeDirectory(fs.DEV_SD, @"/")

' Navigate using absolute path
fs.changeDirectory(fs.DEV_SD, @"/DATA/2026/FEB")

' Navigate up one level
fs.changeDirectory(fs.DEV_SD, @"..")
```

### Creating Directories (SD)

```spin2
if fs.newDirectory(fs.DEV_SD, @"BACKUP") == fs.SUCCESS
  debug("Directory created")
else
  debug("Failed - may already exist")
```

### Enumerating SD Directory Contents

**Index-based (simple, from CWD):**

```spin2
CON
  ATTR_DIRECTORY = $10        ' FAT32 directory attribute flag

PUB listSDDirectory() | entryIdx, pEntry
  entryIdx := 0
  repeat
    pEntry := fs.readDirectory(entryIdx)
    if pEntry == 0
      quit

    if fs.attributes() & ATTR_DIRECTORY
      debug("[DIR]  ", zstr(fs.fileName()))
    else
      debug("[FILE] ", zstr(fs.fileName()), " (", udec(fs.fileSize()), " bytes)")

    entryIdx++
```

**Handle-based (enumerate a specific path without changing CWD):**

```spin2
PUB listPath(pPath) | dirHandle, pEntry
  dirHandle := fs.openDirectory(fs.DEV_SD, pPath)
  if dirHandle >= 0
    repeat
      pEntry := fs.readDirectoryHandle(dirHandle)
      if pEntry == 0
        quit

      if fs.attributes() & ATTR_DIRECTORY
        debug("[DIR]  ", zstr(fs.fileName()))
      else
        debug("[FILE] ", zstr(fs.fileName()))

    fs.closeDirectoryHandle(dirHandle)
  else
    debug("Cannot open: ", sdec(dirHandle))
```

### Flash Directory Emulation

Flash emulates directories using path-segmented filenames. The driver maintains a per-cog CWD prefix string that is transparently prepended to filenames during file operations.

```spin2
' Navigate Flash directories (same API as SD)
fs.changeDirectory(fs.DEV_FLASH, @"logs")      ' CWD prefix becomes "logs/"
fs.changeDirectory(fs.DEV_FLASH, @"2026")       ' CWD prefix becomes "logs/2026/"
fs.changeDirectory(fs.DEV_FLASH, @"/")           ' Back to root (empty prefix)
fs.changeDirectory(fs.DEV_FLASH, @"..")          ' Up one level

' Create a directory (validates path, stores nothing on Flash)
fs.newDirectory(fs.DEV_FLASH, @"sensors")

' Open a file — CWD prefix is prepended automatically
fs.changeDirectory(fs.DEV_FLASH, @"sensors")
handle := fs.open(fs.DEV_FLASH, @"temp.dat", fs.FILEMODE_WRITE)
' File is stored as "sensors/temp.dat" on Flash
```

**Key differences from SD directories:**
- Empty directories vanish when their last file is deleted (directories exist only because files with those path segments exist)
- `newDirectory()` on Flash is a validation-only operation — it doesn't write anything to Flash
- Flash filenames support "/" characters naturally (up to 127 chars total including path segments)

### Enumerating Flash Directory Contents

**Handle-based (filtered by CWD):**

```spin2
DAT
  sensorsDir  BYTE  "/sensors", 0

PUB listFlashDir() | dirHandle, pEntry
  dirHandle := fs.openDirectory(fs.DEV_FLASH, @sensorsDir)
  if dirHandle >= 0
    repeat
      pEntry := fs.readDirectoryHandle(dirHandle)
      if pEntry == 0
        quit
      debug("[FILE] ", zstr(fs.fileName()))
    fs.closeDirectoryHandle(dirHandle)
```

**Low-level iteration (all files, unfiltered):**

```spin2
PUB listAllFlashFiles() | blockId, status, nameBuf[32], fileBytes
  blockId := 0
  repeat
    status := fs.directory(fs.DEV_FLASH, @blockId, @nameBuf, @fileBytes)
    if status <> fs.SUCCESS
      quit
    debug(zstr(@nameBuf), " (", udec(fileBytes), " bytes)")
```

Call `directory()` with `block_id` initialized to 0. Each call updates `block_id` to point to the next file. When there are no more files, it returns a non-zero status. This shows all files with their full path-segmented names.

### SD Attribute Flags

| Value | Meaning |
|-------|---------|
| `$01` | Read-only |
| `$02` | Hidden |
| `$04` | System |
| `$08` | Volume label |
| `$10` | Directory |
| `$20` | Archive |

---

## Seeking and Random Access

### SD Seeking

```spin2
' Seek to absolute byte position
fs.seekHandle(handle, position)

' Get current position
pos := fs.tellHandle(handle)
```

### Flash Seeking

Flash provides a richer seek API with a `whence` parameter:

```spin2
' Seek from start of file
end_pos := fs.flashSeek(handle, 100, fs.SK_FILE_START)

' Seek relative to current position
end_pos := fs.flashSeek(handle, 50, fs.SK_CURRENT_POSN)
```

### Random Access Example (SD)

```spin2
CON
  RECORD_SIZE = 64            ' bytes per record

DAT
  dbFile      BYTE  "DATABASE.DAT", 0

PUB readRecordAt(recordNum, pRecordBuf) : status | handle
  status := fs.E_FILE_NOT_FOUND
  handle := fs.openFileRead(fs.DEV_SD, @dbFile)
  if handle >= 0
    fs.seekHandle(handle, recordNum * RECORD_SIZE)
    fs.readHandle(handle, pRecordBuf, RECORD_SIZE)
    fs.closeFileHandle(handle)
    status := fs.SUCCESS
```

---

## File Information

### File Size

```spin2
' By handle (SD or Flash)
size := fs.fileSizeHandle(handle)

' By name (without opening)
size := fs.file_size(fs.DEV_SD, @"DATA.TXT")
size := fs.file_size(fs.DEV_FLASH, @"sensor.dat")
```

### End of File

```spin2
if fs.eofHandle(handle)
  debug("At end of file")
```

### Current Position

```spin2
pos := fs.tellHandle(handle)
```

### Volume and Device Information

```spin2
' SD volume label
debug("Volume: ", zstr(fs.volumeLabel(fs.DEV_SD)))

' Free space
sd_free := fs.freeSpace(fs.DEV_SD)         ' Returns sectors (x512 = bytes)
fl_free := fs.freeSpace(fs.DEV_FLASH)      ' Returns free blocks (x4096 = bytes)

' Device statistics (Flash)
used, free_ct, file_count := fs.stats(fs.DEV_FLASH)
debug("Flash: ", udec(file_count), " files, ", udec(free_ct), " blocks free")

' Serial number (Flash)
sn_hi, sn_lo := fs.serial_number(fs.DEV_FLASH)

' Driver version
ver := fs.version(fs.DEV_SD)    ' 10500 (= v1.5.0)
ver := fs.version(fs.DEV_FLASH) ' 20000 (= v2.0.0)
```

### Setting Timestamps (SD Only)

Set the date/time applied to newly created files and directories. `setDate()` also activates a live 2-second clock that ticks automatically in the worker loop, so timestamps stay current without repeated calls.

```spin2
PUB setDate(year, month, day, hour, minute, second) : status
```

Returns `SUCCESS` (0) or `E_INVALID_PARAM` if any field is out of range. Input validation enforces: year 1980-2107, month 1-12, day 1-N (validated against the month), hour 0-23, minute 0-59, second 0-59.

```spin2
status := fs.setDate(2026, 3, 18, 14, 30, 0)  ' Set clock and activate ticking
handle := fs.createFileNew(fs.DEV_SD, @"STAMPED.TXT")
fs.closeFileHandle(handle)
```

### Reading the Live Clock

Once `setDate()` has been called, the clock ticks in the background. Read the current date/time with `getDate()`:

```spin2
PUB getDate() : year, month, day, hour, minute, second
```

```spin2
status := fs.setDate(2026, 3, 18, 14, 30, 0)  ' Set clock and activate ticking
' ... later ...
yr, mon, dy, hr, mn, sc := fs.getDate()        ' Read live clock
```

### Auto-Flush (Data Safety)

After 200ms of idle time (no API calls), the driver automatically flushes all dirty file handles and updates the FSInfo sector. This protects against data loss when an SD card is removed without calling `closeFileHandle()` or `unmount()`.

No API call is needed -- auto-flush is always active once the worker cog is running.

The 200ms threshold is fast enough for human card removal (typically 1-2 seconds) yet slow enough to never interrupt burst writes. For explicit flush control, continue to use `syncHandle(handle)` or `syncAllHandles()`.

### Checking File Existence

```spin2
if fs.exists(fs.DEV_SD, @"CONFIG.TXT")
  debug("Config file found on SD")

if fs.exists(fs.DEV_FLASH, @"calibration.dat")
  debug("Calibration data found on Flash")
```

---

## File Management

### Deleting Files

```spin2
' Delete from SD (current directory)
status := fs.deleteFile(fs.DEV_SD, @"OLD_DATA.TXT")

' Delete from Flash
status := fs.deleteFile(fs.DEV_FLASH, @"temp-log.dat")
```

Returns `SUCCESS` (0) on success, or a negative error code. The file must not be open.

### Renaming Files

```spin2
' Rename on SD (within current directory)
status := fs.rename(fs.DEV_SD, @"DRAFT.TXT", @"FINAL.TXT")

' Rename on Flash
status := fs.rename(fs.DEV_FLASH, @"old-name.dat", @"new-name.dat")
```

### Moving Files Between Directories (SD Only)

```spin2
' Move LOG.TXT into the ARCHIVE directory
fs.moveFile(fs.DEV_SD, @"LOG.TXT", @"ARCHIVE")
```

`moveFile()` is currently SD-only (moves a file to another directory on the SD card). Calling it with `DEV_FLASH` returns `E_NOT_SUPPORTED`. On Flash, rename with a different path prefix to achieve the same effect.

---

## Non-Blocking File I/O

Enable with `#pragma exportdef SD_INCLUDE_ASYNC` (or `SD_INCLUDE_ALL`) before the OBJ declaration. The async API lets the caller cog do useful work while the worker cog handles a read or write in the background.

### Async Methods

| Method | Description |
|--------|-------------|
| `startReadHandle(handle, pBuf, count) : status` | Begin async read, returns `PENDING` (1) |
| `startWriteHandle(handle, pBuf, count) : status` | Begin async write, returns `PENDING` (1) |
| `isComplete() : done` | Non-blocking poll, TRUE when operation finished |
| `getResult() : status` | Block if needed, returns bytes read/written, releases lock |
| `cancelAsync() : status` | Discard result, release lock |

### Usage Pattern

```spin2
#pragma exportdef SD_INCLUDE_ASYNC

OBJ
  dfs : "dual_sd_fat32_flash_fs"

PUB logAndSample() | handle, bytesWritten
  handle := dfs.openFileWrite(dfs.DEV_SD, @"SENSOR.DAT")
  if handle >= 0
    dfs.startWriteHandle(handle, @sensorData, 512)
    repeat
      sample_sensors()              ' Do real work at full 350 MHz
      if dfs.isComplete()
        bytesWritten := dfs.getResult()
        quit
    dfs.closeFileHandle(handle)
```

The caller cog fires off the I/O with `startReadHandle()` or `startWriteHandle()`, then polls with `isComplete()` between real-time tasks. When the operation is done, `getResult()` returns the byte count (or a negative error code) and releases the internal lock so the next operation can proceed.

### Error Codes

| Code | Constant | Meaning |
|------|----------|---------|
| -95 | `E_ASYNC_BUSY` | An async operation is already in progress |
| -96 | `E_NO_ASYNC_OP` | `getResult()` or `cancelAsync()` called with no pending operation |

### Cancellation

If the caller decides it no longer needs the result (e.g., a timeout or mode change), call `cancelAsync()` to discard the pending result and release the lock:

```spin2
dfs.startReadHandle(handle, @buf, 512)
' ... decide to abort ...
dfs.cancelAsync()
```

---

## Multi-Cog Access

### What Each Cog Gets

- **Its own CWD** — Cog A can navigate to `/LOGS` while Cog B works in `/DATA` (both SD and Flash maintain per-cog CWD)
- **Its own error slot** — `error()` returns the last error for the calling cog only
- **Shared handle pool** — handles are allocated from a common pool and can be used from any cog

### Singleton Pattern

All OBJ instances of `dual_sd_fat32_flash_fs` share the same worker cog and state. You don't need to pass a driver reference between cogs:

```spin2
OBJ
  fs : "dual_sd_fat32_flash_fs"

PUB readerTask() | handle, buf[128], bytes_read
  ' This cog can use fs.* immediately — shares the already-initialized driver
  handle := fs.openFileRead(fs.DEV_SD, @"SENSOR.DAT")
  if handle >= 0
    repeat
      bytes_read := fs.readHandle(handle, @buf, 512)
      if bytes_read == 0
        quit
      processData(@buf, bytes_read)
    fs.closeFileHandle(handle)
```

### Multi-Cog Lifecycle Patterns

#### Startup Pattern

The main cog owns the driver lifecycle. It initializes the worker cog and mounts the devices that the application needs, **before** spawning any worker cogs:

```spin2
PUB go() | workerCog
    workerCog := fs.init()

    fs.mount(fs.DEV_BOTH)       ' or DEV_SD / DEV_FLASH if only one is needed

    cogspin(NEWCOG, dataLogger(), @loggerStack)
    cogspin(NEWCOG, archiveTask(), @archiveStack)
```

Worker cogs arrive in a world where the filesystem is ready. They do **not** need to call `init()` — the worker cog is already running and the API lock handles multi-cog serialization automatically.

#### Checking Mount Status: `mounted()`

`mounted()` is a zero-cost check — it reads a shared DAT flag with no SPI bus activity and no command sent to the worker cog. Use it for:

**Gating a code path based on device availability:**

```spin2
PRI archiveTask()
    ' Only archive if SD was mounted at startup
    if fs.mounted(fs.DEV_SD)
        copyLogsToSD()
    else
        debug("SD not available, skipping archive")
```

**Verifying a prerequisite at worker startup:**

```spin2
PRI sensorLogger()
    if fs.mounted(fs.DEV_FLASH)
        ' proceed with logging...
    else
        debug("FATAL: Flash not mounted")
```

#### Late-Discovered Need: Just Call `mount()`

`mount()` is idempotent — if the device is already mounted, it returns SUCCESS immediately with negligible cost. A worker cog that discovers it needs a device the main cog didn't mount can mount it directly:

```spin2
PRI handleAlarm()
    ' Alarm triggered — need to write report to SD
    ' Main cog only mounted Flash at startup
    if fs.mount(fs.DEV_SD) <> fs.SUCCESS
        debug("SD unavailable, can't write alarm report")
        return
    ' SD is now mounted, write the report...
```

This is safe because:
- `mount()` is idempotent (no harm if already mounted)
- The hardware lock serializes the mount with any concurrent filesystem operations
- In an embedded system, the SD card and Flash chip are physically present and don't change

#### Shutdown Pattern

`unmount()` is exclusively a main-cog operation. The main cog must coordinate worker shutdown **before** unmounting:

```spin2
PUB shutdown()
    ' Signal workers to stop (application-specific mechanism)
    shutdownFlag := TRUE
    waitms(1000)                   ' allow workers to close files and exit

    fs.unmount(fs.DEV_BOTH)
    fs.stop()
```

A worker cog should **never** call `unmount()`. If it did, other cogs with open file handles would encounter errors.

### Rules for Multi-Cog Access

| Operation | Who calls it | When |
|-----------|-------------|------|
| `init()` | Main cog only | Once, at application start |
| `mount()` | Main cog at startup; any cog if late need arises | Before first filesystem use |
| `mounted()` | Any cog | To check availability (zero-cost) |
| `unmount()` | Main cog only | After all workers have stopped |
| `stop()` | Main cog only | Final cleanup, stops worker cog |

Additional rules:
- **One writer per SD file.** Multiple read handles are fine; only one write handle per file.
- **Close handles when done.** Handles are a shared resource (default 6 total for both devices).
- **`mount()` is cheap when already mounted.** Don't fear calling it as a precaution.
- **`mounted()` is zero-cost.** It reads a shared variable — no SPI traffic, no worker command.
- **The hardware lock handles everything.** Multiple cogs can call `open()`, `read()`, `write()`, etc. concurrently. The API lock serializes access to the worker cog automatically.

### Configuring Handle Count

Override `MAX_OPEN_FILES` if the default 6 isn't enough:

```spin2
OBJ
  fs : "dual_sd_fat32_flash_fs" | MAX_OPEN_FILES = 8   ' 3 cogs doing file copy + headroom
```

Each additional handle costs ~688 bytes (SD 512-byte sector buffer + 28-byte SD state + ~148-byte Flash state). Flash block buffers are pooled separately (`MAX_FLASH_BUFFERS`, default 3 x 4 KB = 12 KB shared).

---

## Error Handling

### Checking for Errors

```spin2
status := fs.error()          ' Last error for calling cog
```

Each cog has its own error slot, so errors from one cog don't affect another.

### Human-Readable Error Strings

```spin2
debug("Error: ", zstr(fs.string_for_error(status)))
```

### Error Code Ranges

| Range | Category |
|-------|----------|
| 0 | `SUCCESS` |
| -1 to -96 | SD/FAT32 errors |
| -100 to -115 | Flash errors |
| -120 to -122 | Unified device errors |
| -130 to -133 | Stack/defrag errors |

### Common SD Errors

| Code | Constant | Meaning |
|------|----------|---------|
| -1 | `E_TIMEOUT` | Card didn't respond |
| -8 | `E_NO_CARD` | No card detected in slot |
| -20 | `E_NOT_MOUNTED` | Filesystem not mounted |
| -40 | `E_FILE_NOT_FOUND` | File doesn't exist |
| -41 | `E_FILE_EXISTS` | File already exists |
| -60 | `E_DISK_FULL` | No free clusters |
| -90 | `E_TOO_MANY_FILES` | All handle slots in use |
| -91 | `E_INVALID_HANDLE` | Handle not valid or not open |
| -92 | `E_FILE_ALREADY_OPEN` | File already open for writing |
| -93 | `E_NOT_A_DIR_HANDLE` | Handle is not a directory handle (or vice versa) |
| -94 | `E_INVALID_PARAM` | Invalid parameter (e.g., bad date field) |
| -95 | `E_ASYNC_BUSY` | Async operation already in progress |
| -96 | `E_NO_ASYNC_OP` | No pending async operation |

### Common Flash Errors

| Code | Constant | Meaning |
|------|----------|---------|
| -100 | `E_FLASH_BAD_HANDLE` | Flash handle is invalid |
| -101 | `E_FLASH_NO_HANDLE` | Out of available handles |
| -102 | `E_FLASH_DRIVE_FULL` | Flash chip is full |
| -106 | `E_FLASH_FILE_MODE` | Wrong open mode for operation |
| -107 | `E_FLASH_FILE_SEEK` | Seek past end of file |
| -114 | `E_FLASH_FILE_EXISTS` | File already exists |
| -115 | `E_FLASH_NO_BUFFER` | No Flash buffer available (all in use) |

### Unified Device Errors

| Code | Constant | Meaning |
|------|----------|---------|
| -120 | `E_BAD_DEVICE` | Invalid device parameter |
| -121 | `E_DEVICE_NOT_MOUNTED` | Device not mounted |
| -122 | `E_NOT_SUPPORTED` | Operation not supported on this device |

### Error Handling Pattern

```spin2
DAT
  configFile  BYTE  "CONFIG.TXT", 0

PUB safeOperation() | workerCog, handle, status
  workerCog := fs.init()
  if workerCog >= 0
    status := fs.mount(fs.DEV_BOTH)
    if status == fs.SUCCESS
      ' Try to open a file on SD
      handle := fs.openFileRead(fs.DEV_SD, @configFile)
      if handle >= 0
        ' ... use handle ...
        fs.closeFileHandle(handle)
      else
        case fs.error()
          fs.E_FILE_NOT_FOUND:
            debug("Config not found, using defaults")
          fs.E_NOT_MOUNTED:
            debug("SD card not mounted")
          other:
            debug("Error: ", zstr(fs.string_for_error(fs.error())))

      fs.unmount(fs.DEV_BOTH)
    elseif status == fs.E_NO_CARD
      debug("No SD card detected - check slot")
    else
      debug("Mount failed: ", zstr(fs.string_for_error(status)))
    fs.stop()
  else
    debug("Init failed")
```

---

## Complete Examples

### Example 1: Sensor Logger (Flash + SD Archival)

A common pattern: write high-frequency data to Flash for speed, then archive to SD for long-term storage.

```spin2
CON
  NUM_READINGS = 100

OBJ
  fs : "dual_sd_fat32_flash_fs"

DAT
  flReadings  BYTE  "readings.dat", 0
  sdReadings  BYTE  "READINGS.DAT", 0

PUB main() | status, handle, readingIdx, value
  fs.init()
  status := fs.mount(fs.DEV_BOTH)
  if status == fs.SUCCESS
    ' --- Phase 1: Fast logging to Flash ---
    handle := fs.open(fs.DEV_FLASH, @flReadings, fs.FILEMODE_WRITE)
    if handle >= 0
      repeat readingIdx from 0 to NUM_READINGS - 1
        value := readSensor()
        fs.wr_long(handle, value)
      fs.close(handle)
      debug("Logged 100 readings to Flash")

    ' --- Phase 2: Archive to SD ---
    fs.copyFile(fs.DEV_FLASH, @flReadings, fs.DEV_SD, @sdReadings)
    debug("Archived to SD card")

    ' --- Phase 3: Verify and clean up ---
    if fs.exists(fs.DEV_SD, @sdReadings)
      fs.deleteFile(fs.DEV_FLASH, @flReadings)
      debug("Flash copy deleted after successful archive")

    fs.unmount(fs.DEV_BOTH)
  fs.stop()

PRI readSensor() : value
  value := getrnd() & $FFFF              ' Simulated sensor reading
```

### Example 2: Configuration File Reader (SD)

```spin2
CON
  MAX_LINE = 80
  LF = 10
  CR = 13

OBJ
  fs : "dual_sd_fat32_flash_fs"

DAT
  configIni   BYTE  "CONFIG.INI", 0

VAR
  byte lineBuffer[MAX_LINE]

PUB readConfig() : status | handle, charIdx, charVal
  status := fs.E_NOT_MOUNTED
  fs.init()
  status := fs.mount(fs.DEV_SD)
  if status == fs.SUCCESS
    handle := fs.openFileRead(fs.DEV_SD, @configIni)
    if handle >= 0
      ' Read line by line
      repeat
        charIdx := 0
        repeat
          if fs.readHandle(handle, @charVal, 1) == 0
            quit
          if charVal == LF
            quit
          if charVal <> CR and charIdx < MAX_LINE - 1
            lineBuffer[charIdx++] := charVal

        lineBuffer[charIdx] := 0
        if charIdx > 0
          processConfigLine(@lineBuffer)

        if fs.eofHandle(handle)
          quit

      fs.closeFileHandle(handle)
    else
      status := handle
    fs.unmount(fs.DEV_SD)
  fs.stop()
```

### Example 3: Data Logger with Periodic SD Checkpoints

```spin2
CON
  LOG_HEADER_LEN = 19
  LOG_FOOTER_LEN = 17
  CRLF_LEN = 2

OBJ
  fs : "dual_sd_fat32_flash_fs"

DAT
  logsDir     BYTE  "LOGS", 0
  dataLog     BYTE  "DATA.LOG", 0
  logHeader   BYTE  "=== Log Started ===", 0
  logFooter   BYTE  "=== Log Ended ===", 0
  crLf        BYTE  13, 10
  rootDir     BYTE  "/", 0

VAR
  long logHandle

PUB startLogging() | status
  fs.init()
  status := fs.mount(fs.DEV_SD)
  if status == fs.SUCCESS
    ' Set timestamp (activates live clock)
    fs.setDate(2026, 2, 28, 12, 0, 0)

    ' Create logs directory if needed
    if fs.changeDirectory(fs.DEV_SD, @logsDir) < 0
      fs.newDirectory(fs.DEV_SD, @logsDir)
      fs.changeDirectory(fs.DEV_SD, @logsDir)

    ' Create log file
    logHandle := fs.createFileNew(fs.DEV_SD, @dataLog)
    if logHandle >= 0
      fs.writeHandle(logHandle, @logHeader, LOG_HEADER_LEN)

PUB logEntry(pMessage) | messageLen
  messageLen := strsize(pMessage)
  fs.writeHandle(logHandle, pMessage, messageLen)
  fs.writeHandle(logHandle, @crLf, CRLF_LEN)
  fs.syncHandle(logHandle)               ' Checkpoint for power-fail safety

PUB stopLogging()
  fs.writeHandle(logHandle, @logFooter, LOG_FOOTER_LEN)
  fs.closeFileHandle(logHandle)
  fs.changeDirectory(fs.DEV_SD, @rootDir)
  fs.unmount(fs.DEV_SD)
  fs.stop()
```

### Example 4: Flash Key-Value Store

```spin2
PUB saveConfig(key, value) | handle
  ' Flash filenames can be descriptive
  handle := fs.open(fs.DEV_FLASH, key, fs.FILEMODE_WRITE)
  if handle >= 0
    fs.wr_long(handle, value)
    fs.close(handle)

PUB loadConfig(key) : value | handle
  handle := fs.open(fs.DEV_FLASH, key, fs.FILEMODE_READ)
  if handle >= 0
    value := fs.rd_long(handle)
    fs.close(handle)
  else
    value := -1                            ' Default if not found

' Usage:
'   saveConfig(@"calibration-offset", 1234)
'   offset := loadConfig(@"calibration-offset")
```

---

## Example Programs

The `src/` directory contains compilable, hardware-verified example programs:

| Program | What It Teaches |
|---------|-----------------|
| [DFS_example_basic.spin2](../src/EXAMPLES/DFS_example_basic.spin2) | Init both devices, write/read on SD and Flash, device stats |
| [DFS_example_cross_copy.spin2](../src/EXAMPLES/DFS_example_cross_copy.spin2) | Cross-device copy (SD → Flash → SD round-trip with verification) |
| [DFS_example_data_logger.spin2](../src/EXAMPLES/DFS_example_data_logger.spin2) | Fast logging to Flash, periodic archival to SD |
| [DFS_example_sd_manifest.spin2](../src/EXAMPLES/DFS_example_sd_manifest.spin2) | Read manifest from SD, copy listed files to Flash |
| [DFS_demo_shell.spin2](../src/DEMO/DFS_demo_shell.spin2) | Interactive shell: `dev sd`/`dev flash`, `dir`, `type`, `copy sd:FILE flash:FILE` |

Build any example with:

```bash
cd src/EXAMPLES/
pnut-ts -d -I .. DFS_example_basic.spin2
pnut-term-ts -r DFS_example_basic.bin
```

---

## Conditional Compilation

Eight feature flags control optional SD features. Flash features are always compiled.

**Hardware Access flags:**

| Flag | What It Adds |
|------|-------------|
| `SD_INCLUDE_RAW` | Raw sector read/write, `initCardOnly()`, multi-block CMD18/CMD25 |
| `SD_INCLUDE_REGISTERS` | CID, CSD, SCR, SD Status register access |
| `SD_INCLUDE_SPEED` | CMD6 high-speed mode (50 MHz) |
| `SD_INCLUDE_DEBUG` | CRC diagnostics, test hooks, hex dump utilities |

**User-Selectable Features:**

| Flag | What It Adds |
|------|-------------|
| `SD_INCLUDE_ASYNC` | Non-blocking file I/O: startReadHandle, startWriteHandle, isComplete, getResult, cancelAsync |
| `SD_INCLUDE_DEFRAG` | Defragmentation: fileFragments, compactFile, createFileContiguous, isFileContiguous |
| `SD_INCLUDE_STACK_CHECK` | Worker cog stack depth measurement (not included by `SD_INCLUDE_ALL`) |
| `SD_INCLUDE_ALL` | All of the above flags except `SD_INCLUDE_STACK_CHECK` |

Enable flags with `#pragma exportdef` **before** the OBJ declaration:

```spin2
#pragma exportdef SD_INCLUDE_RAW
#pragma exportdef SD_INCLUDE_REGISTERS

OBJ
  fs : "dual_sd_fat32_flash_fs"
```

Or enable everything:

```spin2
#pragma exportdef SD_INCLUDE_ALL

OBJ
  fs : "dual_sd_fat32_flash_fs"
```

### Raw Sector Access (SD_INCLUDE_RAW)

For formatting, partitioning, or direct sector manipulation:

```spin2
' Initialize card without filesystem (raw mode)
fs.initCardOnly()

' Read/write at absolute LBA addresses
fs.readSectorRaw(sector, @buf)
fs.writeSectorRaw(sector, @buf)

' Multi-block operations (faster for sequential access)
fs.readSectorsRaw(start, count, @buf)
fs.writeSectorsRaw(start, count, @buf)

' Card capacity
total := fs.cardSizeSectors()
```

### Card Registers (SD_INCLUDE_REGISTERS)

```spin2
VAR
  byte cid_buf[16], csd_buf[16]

fs.readCIDRaw(@cid_buf)                   ' Manufacturer, serial number, etc.
fs.readCSDRaw(@csd_buf)                   ' Capacity, speed class, etc.
ocr := fs.getOCR()                        ' Operating conditions
```

### High-Speed Mode (SD_INCLUDE_SPEED)

```spin2
if fs.checkCMD6Support()
  if fs.checkHighSpeedCapability()
    if fs.attemptHighSpeed()
      debug("Running at 50 MHz!")
```

---

## API Quick Reference

### Lifecycle

| Method | Description |
|--------|-------------|
| `init()` | Start worker cog, returns cog ID |
| `stop()` | Stop worker cog, release lock |
| `mount(dev)` | Mount one or both devices |
| `unmount(dev)` | Flush and unmount |
| `mounted(dev)` | Check mount status (lock-free) |
| `version(dev)` | Driver version as integer |
| `versionStr(dev)` | Driver version as string (e.g., "1.3.1") |
| `checkStackGuard()` | Verify worker stack integrity |
| `error()` | Last error for calling cog |
| `string_for_error(code)` | Human-readable error string |

### SD File Operations (Handle-Based)

| Method | Description |
|--------|-------------|
| `openFileRead(dev, path)` | Open for reading → handle |
| `openFileWrite(dev, path)` | Open for append → handle |
| `createFileNew(dev, path)` | Create new file → handle |
| `readHandle(handle, buf, count)` | Read bytes → bytes_read |
| `writeHandle(handle, buf, count)` | Write bytes → bytes_written |
| `seekHandle(handle, pos)` | Seek to position |
| `tellHandle(handle)` | Get position |
| `eofHandle(handle)` | Check end-of-file |
| `fileSizeHandle(handle)` | Get file size |
| `syncHandle(handle)` | Flush writes |
| `syncAllHandles()` | Flush all handles |
| `closeFileHandle(handle)` | Close handle |

### Flash File Operations

| Method | Description |
|--------|-------------|
| `open(dev, name, mode)` | Open with mode → handle |
| `open_circular(dev, name, mode, maxLen)` | Open circular file → handle |
| `create_file(dev, name, fill, count)` | Pre-allocate file |
| `close(handle)` | Close handle |
| `flush(handle)` | Flush without closing |
| `wr_byte(handle, val)` | Write byte |
| `rd_byte(handle)` | Read byte |
| `wr_word(handle, val)` | Write 16-bit word |
| `rd_word(handle)` | Read 16-bit word |
| `wr_long(handle, val)` | Write 32-bit long |
| `rd_long(handle)` | Read 32-bit long |
| `wr_str(handle, pStr)` | Write string + null terminator |
| `rd_str(handle, pStr, maxLen)` | Read string → length (excl. null) |
| `flashSeek(handle, pos, whence)` | Seek with SK_FILE_START or SK_CURRENT_POSN |

### File Management

| Method | Description |
|--------|-------------|
| `deleteFile(dev, name)` | Delete file |
| `rename(dev, old, new)` | Rename file or directory |
| `moveFile(dev, name, dest)` | Move to directory (SD only) |
| `exists(dev, name)` | Check if file exists |
| `file_size(dev, name)` | Size without opening |
| `file_size_unused(dev, name)` | Unused bytes in last Flash block |

### Directories

| Method | Description |
|--------|-------------|
| `changeDirectory(dev, path)` | Change CWD (SD or Flash, per-cog) |
| `getFlashCwd()` | Current Flash working directory path |
| `newDirectory(dev, name)` | Create directory (SD native, Flash emulated) |
| `readDirectory(index)` | Enumerate CWD by index (SD) |
| `openDirectory(dev, path)` | Open for enumeration (SD or Flash) → handle |
| `readDirectoryHandle(handle)` | Next entry → pEntry |
| `closeDirectoryHandle(handle)` | Close directory handle |
| `directory(dev, pBlockId, pName, pSize)` | Iterate Flash files |

### Device Information

| Method | Description |
|--------|-------------|
| `freeSpace(dev)` | Free space (SD: sectors, Flash: blocks) |
| `volumeLabel(dev)` | Volume label (SD only) |
| `setVolumeLabel(dev, label)` | Set volume label (SD) |
| `serial_number(dev)` | Device serial number |
| `stats(dev)` | Statistics (used, free, files) |
| `canMount(dev)` | Non-destructive mount check |
| `cardWarnings()` | SD card warning flags after mount |
| `format(dev)` | Format device (destructive!) |
| `setDate(y,m,d,h,mi,s) : status` | Set clock and activate live ticking (SD) |
| `getDate() : y,m,d,h,mi,s` | Read live clock (SD) |

### Cross-Device

| Method | Description |
|--------|-------------|
| `copyFile(srcDev, src, dstDev, dst)` | Copy between devices |

### Non-Blocking I/O (SD_INCLUDE_ASYNC)

| Method | Description |
|--------|-------------|
| `startReadHandle(handle, pBuf, count)` | Begin async read, returns PENDING |
| `startWriteHandle(handle, pBuf, count)` | Begin async write, returns PENDING |
| `isComplete()` | Poll async completion (non-blocking) |
| `getResult()` | Get async result (blocks if needed), releases lock |
| `cancelAsync()` | Cancel async operation, releases lock |

### Defragmentation (SD_INCLUDE_DEFRAG)

| Method | Description |
|--------|-------------|
| `fileFragments(dev, path)` | Count non-contiguous fragments (1 = contiguous, 0 = empty) |
| `isFileContiguous(dev, path)` | TRUE if file has exactly 1 fragment |
| `createFileContiguous(dev, path, size)` | Create file with pre-allocated contiguous chain |
| `compactFile(dev, path)` | Relocate fragmented file to contiguous clusters |

**Check and compact a file:**

```spin2
  frags := dfs.fileFragments(dfs.DEV_SD, @"DATA.BIN")
  if frags > 1
    result := dfs.compactFile(dfs.DEV_SD, @"DATA.BIN")
    ' File must be CLOSED before compacting — returns E_FILE_OPEN_FOR_COMPACT if open
```

**Create a pre-allocated contiguous file:**

```spin2
  ' Pre-allocate 100 KB of contiguous clusters — writes never fragment
  handle := dfs.createFileContiguous(dfs.DEV_SD, @"STREAM.BIN", 100_000)
  if handle >= 0
    repeat 200
      dfs.writeHandle(handle, @sensorData, 512)
    dfs.closeFileHandle(handle)
    ' File is guaranteed contiguous — optimal for multi-block reads
```

### Utilities

| Method | Description |
|--------|-------------|
| `setSPISpeed(freq)` | Set SPI clock in Hz (requires `SD_INCLUDE_SPEED`) |
| `syncDirCache()` | Invalidate SD directory cache |
| `sync()` | Flush all pending writes |
| `fileName()` | Last directory entry name (SD) |
| `attributes()` | Last directory entry attributes (SD) |

### Card Information (Always Available)

| Method | Description |
|--------|-------------|
| `getSPIFrequency()` | Current SPI clock in Hz |
| `getCardMaxSpeed()` | Card's max speed from CSD |
| `getManufacturerID()` | Card manufacturer ID |
| `getReadTimeout()` | Read timeout in ms |
| `getWriteTimeout()` | Write timeout in ms |
| `isHighSpeedActive()` | TRUE if at 50 MHz |

---

## What The Driver Handles For You

The driver abstracts away the complexity of managing two devices over a shared SPI bus:

- **SPI bus switching:** Automatic smart pin teardown and SD card re-initialization when switching between devices
- **FAT32 internals:** Cluster chains, FAT updates, directory parsing, path resolution
- **Flash block management:** Translation tables, wear leveling, block allocation
- **Multi-cog safety:** Hardware lock serialization, per-cog CWD, per-cog errors
- **Multiple file handles:** Up to 6 (configurable) open files/directories across both devices
- **CRC validation:** Hardware-accelerated CRC-16 on all SD data transfers
- **Cross-device copy:** Built-in `copyFile()` handles all the plumbing

You work with files and bytes; the driver handles the rest.

---

*Part of the [P2 Dual Filesystem](../README.md) project — Iron Sheep Productions*
