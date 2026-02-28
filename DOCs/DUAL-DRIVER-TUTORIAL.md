# SD Card Driver — Tutorial

*micro_sd_fat32_fs.spin2*

**A practical guide to FAT32 file operations on the Parallax Propeller 2**

This tutorial shows how to perform common filesystem operations using the SD card driver. If you're familiar with standard FAT32 APIs (FatFs, POSIX file I/O), this guide maps those concepts to our driver's interface.

> **Reference:** For background on FAT32 internals and standard API concepts, see [FAT32-API-CONCEPTS-REFERENCE.md](Reference/FAT32-API-CONCEPTS-REFERENCE.md)

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Handle-Based File API](#handle-based-file-api)
3. [Mounting the Card](#mounting-the-card)
4. [Working with Directories](#working-with-directories)
5. [Searching for Files](#searching-for-files)
6. [Reading Files](#reading-files)
7. [Writing Files](#writing-files)
8. [Seeking and Random Access](#seeking-and-random-access)
9. [File Information](#file-information)
10. [File Management](#file-management)
11. [Multi-Cog Access](#multi-cog-access)
12. [Error Handling](#error-handling)
13. [Complete Examples](#complete-examples)
14. [Example Programs](#example-programs)
15. [Architecture Notes](#architecture-notes)
16. [API Quick Reference](#api-quick-reference)
17. [Conditional API Modules](#conditional-api-modules)

---

## Quick Start

```spin2
OBJ
  sd : "micro_sd_fat32_fs"

CON
  ' SD card pins - offsets from 8-pin header base pin
  SD_BASE = 56                        ' P2 Edge Module default
  SD_SCK  = SD_BASE + 5              ' Serial Clock
  SD_CS   = SD_BASE + 4              ' Chip Select
  SD_MOSI = SD_BASE + 3              ' Master Out, Slave In
  SD_MISO = SD_BASE + 2              ' Master In, Slave Out

PUB main() | handle, buf[128], bytes_read
  ' Mount the card
  if not sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    debug("Mount failed!")
    return

  ' Open file for reading (handle-based API)
  handle := sd.openFileRead(string("TEST.TXT"))
  if handle >= 0
    bytes_read := sd.readHandle(handle, @buf, 512)
    sd.closeFileHandle(handle)
    debug("Read ", udec(bytes_read), " bytes")

  ' Clean shutdown
  sd.unmount()
```

---

## Handle-Based File API

The driver uses a handle-based file API that supports **multiple files and directories open simultaneously** (default 6 handles, user-configurable via `MAX_OPEN_FILES`). This enables use cases like:
- Reading a configuration file while writing a log
- Copying data between files
- Comparing file contents

### Key Concepts

**File Handles:** Each open file returns a handle (0-5, with the default 6 handles). Use this handle for all subsequent operations on that file.

**Single-Writer Policy:** Only ONE file can be open for writing at a time. This prevents data corruption from concurrent writes.

**Handle Type Enforcement:** `writeHandle()` on a read-only handle returns `E_INVALID_HANDLE` — you must open the file with `openFileWrite()` or `createFileNew()` to write. Reading from a write handle is permitted (useful for verify-after-write patterns).

**Singleton Architecture:** The driver uses a singleton pattern - all OBJ instances share the same worker cog. Calling `stop()` from any instance affects all instances.

### Filename Format

The driver uses **8.3 short filenames** (up to 8 characters, a dot, and a 3-character extension). Names are case-insensitive — `"DATA.TXT"`, `"data.txt"`, and `"Data.Txt"` all refer to the same file. Long filenames (LFN) are not supported.

### Opening Files

```spin2
' Open for reading (returns handle or negative error code)
handle := sd.openFileRead(string("DATA.TXT"))
if handle < 0
  debug("Open failed, error: ", sdec(handle))

' Open for writing (existing file, appends — positions at end of file)
handle := sd.openFileWrite(string("OUTPUT.TXT"))

' Create new file for writing (fails if file already exists)
handle := sd.createFileNew(string("NEWFILE.TXT"))
```

### Reading/Writing with Handles

```spin2
' Read using handle
bytes_read := sd.readHandle(handle, @buffer, count)

' Write using handle
bytes_written := sd.writeHandle(handle, @buffer, count)
```

### Closing Files

```spin2
' Close specific handle
sd.closeFileHandle(handle)

' Sync all open handles without closing
sd.syncAllHandles()
```

### File Operations with Handles

```spin2
' Get file size
size := sd.fileSizeHandle(handle)

' Get current position
pos := sd.tellHandle(handle)

' Check for end of file
if sd.eofHandle(handle)
  debug("At end of file")

' Seek to position
sd.seekHandle(handle, position)

' Flush writes without closing
sd.syncHandle(handle)
```

### Multi-File Example

```spin2
PUB copyFile(src_name, dest_name) | src_h, dest_h, buf[128], bytes
  ' Open source for reading
  src_h := sd.openFileRead(src_name)
  if src_h < 0
    return false

  ' Create destination for writing
  dest_h := sd.createFileNew(dest_name)
  if dest_h < 0
    sd.closeFileHandle(src_h)
    return false

  ' Copy in chunks
  repeat
    bytes := sd.readHandle(src_h, @buf, 512)
    if bytes == 0
      quit
    sd.writeHandle(dest_h, @buf, bytes)

  ' Clean up both files
  sd.closeFileHandle(src_h)
  sd.closeFileHandle(dest_h)
  return true
```

### Handle Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| -90 | `E_TOO_MANY_FILES` | All file handles in use |
| -91 | `E_INVALID_HANDLE` | Handle not valid or not open |
| -92 | `E_FILE_ALREADY_OPEN` | File already open (same path) |
| -93 | `E_NOT_A_DIR_HANDLE` | Expected directory handle, got file handle |

---

## Mounting the Card

### Concept

Before any filesystem operations, you must mount the card. This initializes the SPI interface, reads the boot sector, and locates the FAT and root directory.

### API

```spin2
PUB mount(_cs, _mosi, _miso, _sck) : result
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `_cs` | pin number | Chip Select (directly wired to SD card CS) |
| `_mosi` | pin number | Master Out, Slave In (data to card) |
| `_miso` | pin number | Master In, Slave Out (data from card) |
| `_sck` | pin number | Serial Clock |

**Returns:** `true` on success, `false` on failure

**Example:**
```spin2
CON
  SD_BASE = 56                        ' P2 Edge Module default
  SD_SCK  = SD_BASE + 5
  SD_CS   = SD_BASE + 4
  SD_MOSI = SD_BASE + 3
  SD_MISO = SD_BASE + 2

PUB setup()
  if sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    debug("Card mounted successfully")
    debug("Volume: ", zstr(sd.volumeLabel()))
  else
    debug("Mount failed, error: ", sdec(sd.error()))
```

### Using a Different 8-Pin Header Group

The microSD add-on board works on any P2 8-pin header group — not just the default P2 Edge Module pins. Simply change `SD_BASE` to match your wiring:

| Header Group | SD_BASE | CS | MOSI | MISO | SCK |
|---|---|---|---|---|---|
| P0–P7 | 0 | P4 | P3 | P2 | P5 |
| P8–P15 | 8 | P12 | P11 | P10 | P13 |
| P16–P23 | 16 | P20 | P19 | P18 | P21 |
| P24–P31 | 24 | P28 | P27 | P26 | P29 |
| P32–P39 | 32 | P36 | P35 | P34 | P37 |
| P40–P47 | 40 | P44 | P43 | P42 | P45 |
| P48–P55 | 48 | P52 | P51 | P50 | P53 |

**Example — External Header on P16–P23:**

```spin2
CON
  SD_BASE = 16                        ' External header (P16-P23 group)
  SD_SCK  = SD_BASE + 5              ' P21
  SD_CS   = SD_BASE + 4              ' P20
  SD_MOSI = SD_BASE + 3              ' P19
  SD_MISO = SD_BASE + 2              ' P18
```

> **Note:** The P2 Edge Module's built-in SD slot is hard-wired to the P56–P63 group.
> External headers use longer PCB traces, which may limit maximum reliable SPI speed
> compared to the on-board slot. The driver defaults to 25 MHz SPI which works on all
> tested configurations.

### Unmounting

Always unmount cleanly to ensure data integrity:

```spin2
sd.unmount()
```

This flushes any pending writes and updates the FSInfo sector with the correct free cluster count.

---

## Working with Directories

### Concept

The driver maintains a "current working directory" (CWD) **per cog** -- each P2 cog has its own independent CWD. This means cog A can navigate to `/LOGS` while cog B works in `/DATA` without interference. You navigate the directory tree by changing directories, and can use absolute paths (starting with `/`) or relative paths.

### Changing the Current Directory

```spin2
PUB changeDirectory(name_ptr) : result
```

**Examples:**
```spin2
' Navigate to a subdirectory
sd.changeDirectory(string("LOGS"))

' Navigate to root
sd.changeDirectory(string("/"))

' Navigate using absolute path
sd.changeDirectory(string("/DATA/2026/JAN"))

' Navigate up one level (to parent)
sd.changeDirectory(string(".."))
```

### Creating a New Directory

```spin2
PUB newDirectory(name_ptr) : result
```

**Example:**
```spin2
' Create a new directory in current location
if sd.newDirectory(string("BACKUP"))
  debug("Directory created")
else
  debug("Failed - may already exist")
```

### Enumerating Directory Contents

```spin2
PUB readDirectory(entry) : result
```

This function iterates through entries in the current directory. Call it with entry index 0, 1, 2, etc. to get successive entries. Returns a pointer to the internal entry buffer, or 0 when no more entries exist.

**Getting Entry Information:**

After `readDirectory()` returns successfully, use these methods:

| Method | Returns | Description |
|--------|---------|-------------|
| `fileName()` | string pointer | 8.3 formatted filename |
| `fileSize()` | long | Size in bytes (0 for directories) |
| `attributes()` | byte | Attribute flags (see below) |

> **Important:** The pointers returned by `fileName()` and the data from `attributes()` / `fileSize()` are only valid until the next call to `readDirectory()` or `readDirectoryHandle()`. If you need to keep a filename, copy it with `bytemove()` before reading the next entry.

**Attribute Flags:**
| Value | Meaning |
|-------|---------|
| `$01` | Read-only |
| `$02` | Hidden |
| `$04` | System |
| `$08` | Volume label |
| `$10` | Directory |
| `$20` | Archive |

**Example - List All Files in Current Directory:**
```spin2
PUB listDirectory() | entry_num, p_entry
  entry_num := 0
  repeat
    p_entry := sd.readDirectory(entry_num)
    if p_entry == 0
      quit                                    ' No more entries

    ' Check if it's a directory or file
    if sd.attributes() & $10
      debug("[DIR]  ", zstr(sd.fileName()))
    else
      debug("[FILE] ", zstr(sd.fileName()), " (", udec(sd.fileSize()), " bytes)")

    entry_num++
```

### Handle-Based Directory Enumeration

For more advanced use cases, the driver provides handle-based directory enumeration. This lets you enumerate a specific directory **without changing your CWD**, and supports concurrent enumeration from multiple cogs since each handle has its own state.

```spin2
PUB openDirectory(p_path) : handle
PUB readDirectoryHandle(handle) : p_entry
PUB closeDirectoryHandle(handle)
```

Directory handles share the same pool as file handles (`MAX_OPEN_FILES` total). Pass `"."` or `""` to enumerate the calling cog's CWD, or any path to enumerate a specific directory.

**Example - List a Specific Directory Without Changing CWD:**
```spin2
PUB listPath(p_path) | dh, p_entry
  dh := sd.openDirectory(p_path)
  if dh < 0
    debug("Cannot open directory: error ", sdec(dh))
    return

  repeat
    p_entry := sd.readDirectoryHandle(dh)
    if p_entry == 0
      quit                                    ' End of directory

    if sd.attributes() & $10
      debug("[DIR]  ", zstr(sd.fileName()))
    else
      debug("[FILE] ", zstr(sd.fileName()), " (", udec(sd.fileSize()), " bytes)")

  sd.closeDirectoryHandle(dh)
```

**When to use which:**
| Approach | Use when... |
|----------|-------------|
| `readDirectory(index)` | Simple enumeration of current directory |
| `openDirectory()` + `readDirectoryHandle()` | Enumerating a different directory without changing CWD, or concurrent enumeration from multiple cogs |

---

## Searching for Files

### Concept

Unlike some APIs that provide a separate search function, our driver combines searching with opening. When you call `openFileRead()` with a path, the driver walks the directory tree to find the file.

### Search for a File in Current Directory

```spin2
handle := sd.openFileRead(string("CONFIG.TXT"))
if handle >= 0
  ' File found and opened
  sd.closeFileHandle(handle)
else
  debug("File not found")
```

### Search Using Full Path

The driver supports absolute paths starting with `/`:

```spin2
' Search from root, regardless of current directory
handle := sd.openFileRead(string("/SETTINGS/USER.CFG"))
if handle >= 0
  ' Found it
  sd.closeFileHandle(handle)
```

### Check if Directory Exists

```spin2
if sd.changeDirectory(string("LOGS"))
  debug("LOGS directory exists")
  sd.changeDirectory(string(".."))          ' Go back up
else
  debug("LOGS directory not found")
```

---

## Reading Files

### Concept

File reading is byte-oriented. You provide a buffer and a count, and the driver returns however many bytes were actually read. The driver handles all the cluster chain following, sector boundary crossing, and buffering internally.

### Opening a File for Reading

```spin2
handle := sd.openFileRead(string("DATA.TXT"))
if handle < 0
  debug("Open failed")
  return
```

### Reading Data

```spin2
PUB readHandle(handle, p_buffer, count) : bytes_read
```

**Parameters:**
| Parameter | Description |
|-----------|-------------|
| `handle` | File handle from openFileRead() |
| `p_buffer` | Pointer to your receive buffer |
| `count` | Maximum bytes to read |

**Returns:** Actual number of bytes read (may be less than requested at end of file)

### Reading Examples

**Read Entire Small File:**
```spin2
VAR
  byte buffer[512]

PUB readSmallFile() | handle, size
  handle := sd.openFileRead(string("MESSAGE.TXT"))
  if handle < 0
    return

  size := sd.fileSizeHandle(handle)
  sd.readHandle(handle, @buffer, size)
  buffer[size] := 0                           ' Null-terminate for string use
  debug(zstr(@buffer))
  sd.closeFileHandle(handle)
```

**Read Large File in Chunks:**
```spin2
CON
  CHUNK_SIZE = 512

VAR
  byte chunk[CHUNK_SIZE]

PUB readLargeFile() | handle, total_read, bytes_this_read
  handle := sd.openFileRead(string("BIGFILE.DAT"))
  if handle < 0
    return

  total_read := 0
  repeat
    bytes_this_read := sd.readHandle(handle, @chunk, CHUNK_SIZE)
    if bytes_this_read == 0
      quit                                    ' End of file

    ' Process chunk here...
    processData(@chunk, bytes_this_read)

    total_read += bytes_this_read

  debug("Total bytes read: ", udec(total_read))
  sd.closeFileHandle(handle)
```

---

## Writing Files

### Concept

Writing works similarly to reading. For new files, use `createFileNew()` which creates the file and returns a handle for writing. For existing files, use `openFileWrite()`.

### Creating a New File

```spin2
handle := sd.createFileNew(string("NEWFILE.TXT"))
if handle < 0
  debug("Could not create file")
  return
```

### Writing Data

```spin2
PUB writeHandle(handle, p_buffer, count) : bytes_written
```

**Parameters:**
| Parameter | Description |
|-----------|-------------|
| `handle` | File handle from createFileNew() or openFileWrite() |
| `p_buffer` | Pointer to data to write |
| `count` | Number of bytes to write |

### Writing Examples

**Create and Write a Small File:**
```spin2
PUB createTextFile() | handle
  handle := sd.createFileNew(string("HELLO.TXT"))
  if handle >= 0
    sd.writeHandle(handle, string("Hello, World!"), 13)
    sd.closeFileHandle(handle)
    debug("File created successfully")
  else
    debug("Could not create file")
```

**Write Binary Data:**
```spin2
VAR
  long sensor_data[100]

PUB saveSensorData() | handle
  handle := sd.createFileNew(string("SENSOR.DAT"))
  if handle >= 0
    sd.writeHandle(handle, @sensor_data, 100 * 4)   ' 100 longs = 400 bytes
    sd.closeFileHandle(handle)
```

**Write Large Data in Chunks:**
```spin2
PUB writeLargeData(p_data, total_bytes) | handle, offset, chunk_size
  handle := sd.createFileNew(string("DUMP.BIN"))
  if handle < 0
    return false

  offset := 0
  repeat while offset < total_bytes
    chunk_size := (total_bytes - offset) <# 512
    sd.writeHandle(handle, p_data + offset, chunk_size)
    offset += chunk_size

  sd.closeFileHandle(handle)
  return true
```

### Flushing Data Without Closing

Use `syncHandle()` to flush pending writes without closing the file:

```spin2
PUB longRunningWrite() | handle, i
  handle := sd.createFileNew(string("DATA.LOG"))
  if handle < 0
    return

  repeat i from 0 to 999
    sd.writeHandle(handle, @data_point, DATA_SIZE)

    ' Checkpoint every 100 entries
    if i // 100 == 99
      sd.syncHandle(handle)

  sd.closeFileHandle(handle)
```

---

## Seeking and Random Access

### Concept

The driver maintains a file position that advances automatically with each read/write. You can change this position with `seekHandle()`.

### Seek to Position

```spin2
PUB seekHandle(handle, pos) : result
```

**Parameters:**
| Parameter | Description |
|-----------|-------------|
| `handle` | File handle |
| `pos` | Byte offset from start of file |

**Returns:** `SUCCESS` (0) on success, or a negative error code if position is beyond end of file

### Seeking Examples

**Read from Middle of File:**
```spin2
VAR
  byte header[64]

PUB readFileHeader() | handle
  handle := sd.openFileRead(string("DATA.BIN"))
  if handle < 0
    return

  sd.seekHandle(handle, 256)                  ' Skip first 256 bytes
  sd.readHandle(handle, @header, 64)          ' Read 64-byte header
  sd.closeFileHandle(handle)
```

**Random Access Read:**
```spin2
PUB readRecordAt(record_num) | handle, record[16]
  ' Assuming 64-byte records
  handle := sd.openFileRead(string("DATABASE.DAT"))
  if handle >= 0
    sd.seekHandle(handle, record_num * 64)
    sd.readHandle(handle, @record, 64)
    sd.closeFileHandle(handle)
  return @record
```

---

## File Information

### Getting File Size

```spin2
size := sd.fileSizeHandle(handle)
```

Returns the size of the file in bytes.

### Getting Current Position

```spin2
pos := sd.tellHandle(handle)
```

Returns the current read/write position.

### Checking for End of File

```spin2
if sd.eofHandle(handle)
  debug("Reached end of file")
```

### Volume Information

```spin2
' Get volume label
debug("Volume: ", zstr(sd.volumeLabel()))

' Get free space (returns sectors, not bytes)
free_sectors := sd.freeSpace()
debug("Free space: ", udec(free_sectors >> 11), " MB")  ' sectors / 2048 = MB
```

### Setting Timestamps

Set the date/time that will be applied to new files:

```spin2
PUB setDate(year, month, day, hour, minute, second)
```

```spin2
' Set timestamp before creating files
sd.setDate(2026, 2, 3, 14, 30, 0)
handle := sd.createFileNew(string("TIMESTAMPED.TXT"))
sd.closeFileHandle(handle)
```

---

## File Management

### Deleting Files

```spin2
PUB deleteFile(name_ptr) : result
```

Deletes the named file from the current directory. Returns `SUCCESS` (0) on success, or a negative error code. The file must not be open.

```spin2
if sd.deleteFile(@"OLD_DATA.TXT") == sd.SUCCESS
    debug("File deleted")
else
    debug("Delete failed, error: ", sdec(sd.error()))
```

### Renaming Files and Directories

```spin2
PUB rename(old_name, new_name) : result
```

Renames a file or directory within the current directory. Both names are simple filenames (not paths). Returns `true` on success, `false` on failure. Fails with `E_FILE_NOT_FOUND` if the source doesn't exist, or `E_FILE_EXISTS` if the destination name is already in use.

```spin2
if not sd.rename(@"DRAFT.TXT", @"FINAL.TXT")
  debug("Rename failed: ", sdec(sd.error()))
```

### Moving Files Between Directories

```spin2
PUB moveFile(name_ptr, dest_folder) : result
```

Moves a file from the current directory into a different directory. The destination must be an existing directory name or path.

```spin2
' Move LOG.TXT from current directory into the ARCHIVE directory
sd.moveFile(@"LOG.TXT", @"ARCHIVE")
```

---

## Multi-Cog Access

### Concept

The P2 has 8 cogs, and the SD driver is designed for safe concurrent access from any of them. The driver runs a dedicated worker cog that serializes all SPI operations through a hardware lock — your application cogs never touch the SPI bus directly.

### What Each Cog Gets

- **Its own current working directory (CWD)** — cog A can navigate to `/LOGS` while cog B works in `/DATA`
- **Its own error slot** — `error()` returns the last error for the calling cog only
- **Shared file handles** — handles are allocated from a common pool and can be used from any cog

### Singleton Pattern

All OBJ instances of the driver share the same worker cog. This means you don't need to pass a driver reference between cogs — just declare the OBJ in each cog's top-level object:

```spin2
OBJ
    sd : "micro_sd_fat32_fs"

PUB readerTask() | handle, buf[128], bytes_read
    ' This cog can use sd.* immediately — it shares the already-mounted driver
    handle := sd.openFileRead(@"SENSOR.DAT")
    if handle >= 0
        repeat
            bytes_read := sd.readHandle(handle, @buf, 512)
            if bytes_read == 0
                quit
            processData(@buf, bytes_read)
        sd.closeFileHandle(handle)
```

### Rules for Multi-Cog Access

1. **Mount from one cog only.** Call `mount()` before starting other cogs that use the driver.
2. **One writer at a time.** Only one file can be open for writing across all cogs. Multiple files can be open for reading simultaneously.
3. **Close handles when done.** Handles are a shared resource (default 6 total).
4. **Don't call `stop()` or `unmount()` while other cogs are using the driver.**

> **See also:** [SD_example_multicog.spin2](../src/EXAMPLES/SD_example_multicog.spin2) for a complete working example.

---

## Error Handling

### Checking for Errors

```spin2
PUB error() : status
```

Returns the error code from the most recent operation. Thread-safe (each cog has its own error slot).

### Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 0 | `SUCCESS` | No error |
| -1 | `E_TIMEOUT` | Card didn't respond in time |
| -2 | `E_NO_RESPONSE` | Card not responding |
| -3 | `E_BAD_RESPONSE` | Unexpected response from card |
| -4 | `E_CRC_ERROR` | Data CRC mismatch |
| -5 | `E_WRITE_REJECTED` | Card rejected write operation |
| -6 | `E_CARD_BUSY` | Card busy |
| -20 | `E_NOT_MOUNTED` | Filesystem not mounted |
| -21 | `E_INIT_FAILED` | Card initialization failed |
| -22 | `E_NOT_FAT32` | Card not formatted as FAT32 |
| -23 | `E_BAD_SECTOR_SIZE` | Sector size not 512 bytes |
| -40 | `E_FILE_NOT_FOUND` | File doesn't exist |
| -41 | `E_FILE_EXISTS` | File already exists |
| -42 | `E_NOT_A_FILE` | Expected file, found directory |
| -43 | `E_NOT_A_DIR` | Expected directory, found file |
| -45 | `E_FILE_NOT_OPEN` | File not open |
| -46 | `E_END_OF_FILE` | Read past end of file |
| -60 | `E_DISK_FULL` | No free clusters |
| -64 | `E_NO_LOCK` | Couldn't allocate hardware lock |
| -7 | `E_IO_ERROR` | I/O error during read or write |
| -90 | `E_TOO_MANY_FILES` | All file handles in use |
| -91 | `E_INVALID_HANDLE` | Handle not valid or not open |
| -92 | `E_FILE_ALREADY_OPEN` | File already open (same path) |
| -93 | `E_NOT_A_DIR_HANDLE` | Expected directory handle, got file handle |

### Error Handling Pattern

```spin2
PUB safeFileOperation() | handle
  if not sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    case sd.error()
      sd.E_TIMEOUT:
        debug("Card not inserted or not responding")
      sd.E_NOT_FAT32:
        debug("Card not formatted as FAT32")
      other:
        debug("Mount failed, error: ", sdec(sd.error()))
    return

  handle := sd.openFileRead(string("DATA.TXT"))
  if handle < 0
    if sd.error() == sd.E_FILE_NOT_FOUND
      ' Create the file
      handle := sd.createFileNew(string("DATA.TXT"))

  if handle >= 0
    ' ... perform operations ...
    sd.closeFileHandle(handle)

  sd.unmount()
```

---

## Complete Examples

### Example 1: Configuration File Reader

```spin2
CON
  SD_BASE = 56, SD_SCK = SD_BASE + 5, SD_CS = SD_BASE + 4, SD_MOSI = SD_BASE + 3, SD_MISO = SD_BASE + 2
  MAX_LINE = 80

OBJ
  sd : "micro_sd_fat32_fs"

VAR
  byte line_buffer[MAX_LINE]

PUB readConfig() | handle, i, ch
  if not sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    return false

  handle := sd.openFileRead(string("CONFIG.INI"))
  if handle < 0
    sd.unmount()
    return false

  ' Read file line by line
  repeat
    i := 0
    repeat
      if sd.readHandle(handle, @ch, 1) == 0   ' End of file
        quit
      if ch == 10                             ' Newline
        quit
      if ch <> 13 and i < MAX_LINE - 1        ' Skip CR, check buffer
        line_buffer[i++] := ch

    line_buffer[i] := 0                       ' Null terminate

    if i > 0
      processConfigLine(@line_buffer)

    if sd.eofHandle(handle)
      quit

  sd.closeFileHandle(handle)
  sd.unmount()
  return true
```

### Example 2: Data Logger

```spin2
CON
  SD_BASE = 56, SD_SCK = SD_BASE + 5, SD_CS = SD_BASE + 4, SD_MOSI = SD_BASE + 3, SD_MISO = SD_BASE + 2

OBJ
  sd : "micro_sd_fat32_fs"

VAR
  byte log_name[13]
  long log_handle

PUB startLogging() | handle
  if not sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    return false

  ' Set timestamp
  sd.setDate(2026, 2, 3, 12, 0, 0)

  ' Create logs directory if needed
  if not sd.changeDirectory(string("LOGS"))
    sd.newDirectory(string("LOGS"))
    sd.changeDirectory(string("LOGS"))

  ' Find next available log number
  findNextLogName()

  ' Create the new log file
  log_handle := sd.createFileNew(@log_name)
  if log_handle < 0
    sd.unmount()
    return false

  sd.writeHandle(log_handle, string("=== Log Started ===", 13, 10), 21)
  return true

PUB logEntry(message) | len
  len := strsize(message)
  sd.writeHandle(log_handle, message, len)
  sd.writeHandle(log_handle, string(13, 10), 2)
  sd.syncHandle(log_handle)                   ' Ensure data is saved

PUB stopLogging()
  sd.writeHandle(log_handle, string("=== Log Ended ===", 13, 10), 19)
  sd.closeFileHandle(log_handle)
  sd.changeDirectory(string("/"))
  sd.unmount()

PRI findNextLogName() | num, handle
  num := 0
  repeat
    formatLogName(num)
    handle := sd.openFileRead(@log_name)
    if handle < 0
      quit                                    ' Found unused name
    sd.closeFileHandle(handle)
    num++

PRI formatLogName(num) | tens, ones
  ' Format as "LOG00.TXT" through "LOG99.TXT"
  tens := num / 10
  ones := num // 10
  bytemove(@log_name, string("LOG00.TXT"), 10)
  log_name[3] := "0" + tens
  log_name[4] := "0" + ones
```

### Example 3: Binary Record File

```spin2
CON
  SD_BASE = 56, SD_SCK = SD_BASE + 5, SD_CS = SD_BASE + 4, SD_MOSI = SD_BASE + 3, SD_MISO = SD_BASE + 2
  RECORD_SIZE = 32

OBJ
  sd : "micro_sd_fat32_fs"

PUB readRecord(filename, record_num, p_dest) : success | handle
  if not sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    return false

  handle := sd.openFileRead(filename)
  if handle < 0
    sd.unmount()
    return false

  ' Check if record exists
  if (record_num + 1) * RECORD_SIZE > sd.fileSizeHandle(handle)
    sd.closeFileHandle(handle)
    sd.unmount()
    return false

  ' Seek to record position and read
  sd.seekHandle(handle, record_num * RECORD_SIZE)
  sd.readHandle(handle, p_dest, RECORD_SIZE)

  sd.closeFileHandle(handle)
  sd.unmount()
  return true

PUB appendRecord(filename, p_src) : success | handle
  if not sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    return false

  ' Try to open existing (appends), or create new
  handle := sd.openFileWrite(filename)
  if handle < 0
    handle := sd.createFileNew(filename)
    if handle < 0
      sd.unmount()
      return false

  sd.writeHandle(handle, p_src, RECORD_SIZE)

  sd.closeFileHandle(handle)
  sd.unmount()
  return true
```

---

## Example Programs

The `src/EXAMPLES/` directory contains compilable, self-contained programs you can run directly on P2 hardware. Each demonstrates a common usage pattern:

| Program | What It Teaches |
|---------|-----------------|
| [SD_example_read_write.spin2](../src/EXAMPLES/SD_example_read_write.spin2) | Complete file lifecycle: create, write, close, re-open, read back |
| [SD_example_data_logger.spin2](../src/EXAMPLES/SD_example_data_logger.spin2) | Append-mode logging with `syncHandle()` for power-fail safety |
| [SD_example_directory_walk.spin2](../src/EXAMPLES/SD_example_directory_walk.spin2) | Directory listing (both APIs), file delete, rename, subdirectory creation |
| [SD_example_multicog.spin2](../src/EXAMPLES/SD_example_multicog.spin2) | Two cogs accessing different files concurrently |

See the [Examples README](../src/EXAMPLES/README.md) for build instructions and detailed descriptions.

---

## Architecture Notes

### Singleton Pattern

The driver uses a singleton pattern: all object instances share the same worker cog and state. This has important implications:

```spin2
OBJ
  sd1 : "micro_sd_fat32_fs"    ' First instance
  sd2 : "micro_sd_fat32_fs"    ' Second instance - shares same driver!

PUB example()
  sd1.mount(CS, MOSI, MISO, SCK)
  ' sd2 can now use the mounted card too - same driver instance
  handle := sd2.openFileRead(string("TEST.TXT"))

  ' WARNING: stop() from ANY instance affects ALL instances
  sd1.stop()   ' This will also stop sd2's access!
```

### Worker Cog

All SPI operations are performed by a dedicated worker cog. This:
- Isolates timing-sensitive SPI operations from your application code
- Provides multi-cog safety through a hardware lock
- Allows the main cog to continue other work during SD operations

### Memory Usage

| Resource | Usage |
|----------|-------|
| Cogs | 1 (worker) |
| Locks | 1 |
| Hub RAM | ~4KB (handles + worker stack + sector buffers) |

---

## API Quick Reference

These methods are always available in the core driver (no feature flags required).

### Lifecycle
| Method | Description |
|--------|-------------|
| `mount(cs, mosi, miso, sck)` | Mount card, returns true/false |
| `unmount()` | Unmount card cleanly |
| `stop()` | Stop worker cog |
| `error()` | Last error code for calling cog |

### Handle-Based File Operations
| Method | Description |
|--------|-------------|
| `openFileRead(path)` | Open for reading, returns handle |
| `openFileWrite(path)` | Open for append writing, returns handle |
| `createFileNew(path)` | Create new file for writing, returns handle |
| `closeFileHandle(handle)` | Close file handle, flush writes |
| `readHandle(handle, buffer, count)` | Read bytes, returns count read |
| `writeHandle(handle, buffer, count)` | Write bytes, returns count written |
| `seekHandle(handle, pos)` | Set file position, returns SUCCESS (0) or error |
| `tellHandle(handle)` | Get current position |
| `eofHandle(handle)` | Check if at end of file |
| `fileSizeHandle(handle)` | Get file size by handle |
| `syncHandle(handle)` | Flush writes on handle |
| `syncAllHandles()` | Flush all open handles |

### File Management
| Method | Description |
|--------|-------------|
| `deleteFile(name)` | Delete file |
| `rename(old, new)` | Rename file or directory |
| `moveFile(name, dest)` | Move file to directory |

### Directories
| Method | Description |
|--------|-------------|
| `changeDirectory(name)` | Change current directory (per-cog CWD) |
| `newDirectory(name)` | Create new directory |
| `readDirectory(index)` | Get CWD entry at index |
| `openDirectory(path)` | Open directory for enumeration, returns handle |
| `readDirectoryHandle(handle)` | Read next entry from directory handle |
| `closeDirectoryHandle(handle)` | Close directory handle |

### Information
| Method | Description |
|--------|-------------|
| `fileName()` | Name of last directory entry |
| `attributes()` | Attributes of last directory entry |
| `volumeLabel()` | Card volume label |
| `setVolumeLabel(label)` | Set volume label |
| `freeSpace()` | Free sectors on card |
| `setDate(y,m,d,h,mi,s)` | Set date/time for new files |
| `getSPIFrequency()` | Current SPI clock in Hz |
| `getCardMaxSpeed()` | Card's reported max speed in Hz |
| `getManufacturerID()` | Card manufacturer ID byte |
| `getReadTimeout()` | Read timeout in ms |
| `getWriteTimeout()` | Write timeout in ms |
| `isHighSpeedActive()` | True if running at 50 MHz |

### Utilities
| Method | Description |
|--------|-------------|
| `setSPISpeed(freq)` | Set SPI clock frequency in Hz |
| `syncDirCache()` | Force directory cache re-read |
| `sync()` | Flush all pending writes |

### Legacy File API (deprecated)

The driver contains older single-file methods (`openFile`, `read`, `write`, `seek`, `closeFile`) from before the handle-based API was added. These still work but are **not recommended for new code** — they operate on an implicit "current file" with no handle, support only one file at a time, and silently return 0 or no-op when called without an open file (instead of reporting an error). Use the handle-based API above for all new development.

---

## Conditional API Modules

The driver supports optional feature modules enabled via `#PRAGMA EXPORTDEF` in your top-level file. This keeps the core driver small (24 KB) for applications that only need standard file operations.

To enable a module, add the pragma **before** the OBJ declaration:

```spin2
#PRAGMA EXPORTDEF SD_INCLUDE_RAW
#PRAGMA EXPORTDEF SD_INCLUDE_REGISTERS

OBJ
  sd : "micro_sd_fat32_fs"
```

To enable all modules at once:

```spin2
#PRAGMA EXPORTDEF SD_INCLUDE_ALL

OBJ
  sd : "micro_sd_fat32_fs"
```

### SD_INCLUDE_RAW - Raw Sector Access

For low-level operations like formatting, partitioning, or direct sector manipulation. Bypasses the filesystem layer entirely.

| Method | Description |
|--------|-------------|
| `initCardOnly(cs, mosi, miso, sck)` | Initialize card without mounting filesystem |
| `cardSizeSectors()` | Total 512-byte sectors on card |
| `readSectorRaw(sector, buffer)` | Read sector at absolute LBA |
| `writeSectorRaw(sector, buffer)` | Write sector at absolute LBA |
| `readSectorsRaw(start, count, buffer)` | Multi-block read (CMD18) |
| `writeSectorsRaw(start, count, buffer)` | Multi-block write (CMD25) |
| `testCMD13()` | Send CMD13, return raw R2 response |

### SD_INCLUDE_REGISTERS - Card Register Access

For card characterization and identification. Provides raw access to CID, CSD, SCR, and OCR registers.

| Method | Description |
|--------|-------------|
| `readCIDRaw(buffer)` | Read 16-byte CID register (manufacturer, serial, etc.) |
| `readCSDRaw(buffer)` | Read 16-byte CSD register (capacity, speed, features) |
| `readSCRRaw(buffer)` | Read 8-byte SCR register (SD spec version, bus widths) |
| `getOCR()` | Get cached OCR value (voltage range, capacity status) |
| `readSDStatusRaw(buffer)` | Read 64-byte SD Status register (ACMD13) |
| `readVBRRaw(buffer)` | Read 512-byte Volume Boot Record |

### SD_INCLUDE_SPEED - High-Speed Mode Control

For testing and enabling 50 MHz high-speed mode via CMD6.

| Method | Description |
|--------|-------------|
| `attemptHighSpeed()` | Switch to 50 MHz with verification, falls back on failure |
| `checkCMD6Support()` | Check if card supports CMD6 (SD 2.0+) |
| `checkHighSpeedCapability()` | Query if card reports high-speed capability |

### SD_INCLUDE_DEBUG - Diagnostic Methods

For driver development, debugging, and regression testing. Includes CRC diagnostic getters, internal state inspection, and display utilities.

| Method | Description |
|--------|-------------|
| `getLastCMD13()` | Last CMD13 R2 response word |
| `getLastCMD13Error()` | Last non-zero CMD13 result |
| `getLastReceivedCRC()` | CRC-16 received from card on last read |
| `getLastCalculatedCRC()` | CRC-16 calculated from received data |
| `getLastSentCRC()` | CRC-16 sent with last write |
| `getCRCMatchCount()` | Count of reads where CRC matched |
| `getCRCMismatchCount()` | Count of reads where CRC did not match |
| `getCRCRetryCount()` | Count of CRC retries on reads |
| `setCRCValidation(enabled)` | Enable/disable CRC checking |
| `debugGetRootSec()` | Root directory sector number |
| `debugGetDirSec()` | Current directory sector for calling cog |
| `debugGetVbrSec()` | VBR sector number |
| `debugGetFatSec()` | FAT start sector number |
| `debugGetSecPerFat()` | Sectors per FAT |
| `debugDumpRootDir()` | Print root directory entries to debug |
| `debugClearRootDir()` | Zero root directory sector (destructive!) |
| `debugReadSectorSlow(sector, buffer)` | Byte-by-byte read without streamer |
| `getWriteDiag(...)` | Last writeSector diagnostic (4 return values) |
| `setTestForceReadError(count)` | Inject N forced CRC mismatches on reads (test hook) |
| `setTestForceWriteError(enabled)` | Inject one-shot write CRC corruption (test hook) |
| `getTestErrorCount()` | Count of injected test errors triggered |
| `clearTestErrors()` | Reset all test error injection state |
| `debugGetReadSectorDiag(...)` | Last readSector diagnostic data (8 params) |
| `debugGetReadSectorDiagExt(...)` | Extended diagnostic data (5 params) |
| `displaySector()` | Hex dump of sector buffer |
| `displayEntry()` | Hex dump of directory entry buffer |
| `displayFAT(cluster)` | Hex dump of FAT sector for cluster |

---

## What The Driver Handles For You

The driver abstracts away all FAT32 complexity:

- **Cluster chains:** Following and allocating clusters automatically
- **FAT updates:** Maintaining both FAT copies
- **Sector buffering:** Managing the 512-byte sector buffer
- **Directory parsing:** Converting 8.3 names and navigating entries
- **Path resolution:** Walking the directory tree for absolute paths
- **Multi-cog safety:** Serializing access through a worker cog
- **Multiple file handles:** Track up to 6 open files/directories simultaneously (configurable)
- **Single-writer enforcement:** Prevent data corruption from concurrent writes
- **CRC validation:** Hardware-accelerated CRC-16 on all data transfers

You just work with files and bytes; the driver handles the rest.
