# Dual Filesystem Driver — Theory of Operations

*dual_sd_fat32_flash_fs.spin2*

## Overview

The dual filesystem driver provides simultaneous access to two storage devices on the Parallax P2 Edge Module: a microSD card (FAT32) and the onboard 16MB Flash chip (block-based). A single Spin2 source file replaces what were previously two separate drivers, unifying them behind one API, one worker cog, and one shared SPI bus.

Key architectural features:

- **One worker cog, two devices** — a dedicated cog owns all SPI I/O for both SD and Flash, eliminating bus contention
- **Smart pin SPI + GPIO bit-bang** — SD uses Mode 0 via smart pins with streamer DMA; Flash uses Mode 3 via software bit-bang
- **Lazy SPI bus switching** — bus reconfiguration happens only when the target device changes
- **Unified handle pool** — SD and Flash files share a single pool of `MAX_OPEN_FILES` handles (default 6, configurable)
- **Per-cog current working directory** — each P2 cog maintains its own CWD for SD navigation and Flash directory emulation
- **Device-aware API** — path-based methods take a `dev` parameter (`DEV_SD`, `DEV_FLASH`); handle-based methods auto-route by stored device tag
- **Cross-device copyFile** — copy files between SD and Flash in a single call
- **Conditional compilation** — 7 feature flags control optional SD features for minimal or full builds

## Architecture

```
  Calling Cog(s) (up to 7 — one cog reserved for worker)
  ┌──────────┐ ┌──────────┐ ┌──────────┐
  │ Cog 0    │ │ Cog 1    │ │ Cog N    │
  │ CWD: /   │ │ CWD: /A  │ │ CWD: /B  │   Each cog has its own SD CWD
  └────┬─────┘ └────┬─────┘ └────┬─────┘
       │            │            │
       └────────────┼────────────┘
                    │ send_command()
              ┌─────▼──────┐
              │  Mailbox    │  pb_cmd, pb_param0..3
              │  (Hub RAM)  │  pb_status, pb_data0..2
              └─────┬──────┘
                    │
              ┌─────▼──────────────────────────┐
              │  Worker Cog (fs_worker)         │
              │  - Owns all SPI pins            │
              │  - SD FAT32 operations          │
              │  - Flash block operations       │
              │  - Lazy SPI bus switching        │
              └─────┬──────────┬───────────────┘
                    │          │
          ┌─────────┘          └─────────┐
          │ Mode 0 (smart pins)          │ Mode 3 (GPIO bit-bang)
          │                              │
    ┌─────▼─────┐                  ┌─────▼─────┐
    │  SD Card  │                  │  Flash    │
    │  (FAT32)  │                  │  (16 MB)  │
    └───────────┘                  └───────────┘
```

The worker cog is the sole owner of the SPI bus. Calling cogs never touch the bus pins directly — they write parameters into the shared mailbox, issue a command, and sleep until the worker signals completion via `COGATN`. A hardware lock serializes access so only one caller can issue a command at a time.

## Hardware: The Shared SPI Bus

Both devices share the same four physical pins on the P2 Edge Module, but with a critical role swap for two of them:

| Pin | SD Function | Flash Function |
|-----|-------------|----------------|
| P58 | MISO (data in) | MISO (data in) |
| P59 | MOSI (data out) | MOSI (data out) |
| P60 | CS (chip select) | SCK (clock) |
| P61 | SCK (clock) | CS (chip select) |

P58 (MISO) and P59 (MOSI) are shared as-is. P60 and P61 swap roles: what is the SD chip select becomes the Flash clock, and what is the SD clock becomes the Flash chip select.

This works because only one device is selected at a time. The worker cog is the sole bus owner, so there is no risk of simultaneous access. When the SD card is active, Flash CS (P61) is held high (deselected). When Flash is active, SD CS (P60) is left floating after smart pin teardown.

Pin assignments are stored once at `init()` time:

```spin2
cs   := sd_cs        ' P60 — SD chip select, doubles as Flash SCK
mosi := _mosi        ' P59 — shared
miso := _miso        ' P58 — shared
sck  := sd_sck       ' P61 — SD clock, doubles as Flash CS
flash_cs_pin  := sck  ' P61
flash_sck_pin := cs   ' P60
```

## SPI Bus Switching

The SD card uses SPI Mode 0 (CPOL=0, CPHA=0) driven by P2 smart pins. The Flash chip uses SPI Mode 3 (CPOL=1, CPHA=1) driven by software GPIO bit-bang. These are fundamentally incompatible configurations, so the worker must reconfigure the bus when switching between devices.

### SD Mode: Smart Pin SPI

| Pin | Smart Pin Mode | Purpose |
|-----|---------------|---------|
| SCK (P61) | `P_TRANSITION | P_OE` | Clock generation, idle LOW |
| MOSI (P59) | `P_SYNC_TX | P_OE` | Synchronized transmit, clocked by SCK |
| MISO (P58) | `P_SYNC_RX` | Synchronized receive, clocked by SCK |

The streamer engine provides DMA-accelerated 512-byte sector transfers at the full SPI clock rate without per-byte cog intervention.

### Flash Mode: GPIO Bit-Bang

Flash SPI uses `drvc`/`drvh`/`drvl` for MOSI and `testp` for MISO — direct GPIO pin manipulation. The Flash clock (P60) and Flash CS (P61) are driven as standard outputs. This is slower than smart pins but reliable for the Flash chip's Mode 3 protocol.

### Switching: SD to Flash

`switch_to_flash()` performs a clean teardown of the SD smart pin configuration:

1. Deselect SD CS (HIGH)
2. **PINCLEAR** all four pins — this clears both the DIR bit *and* the WRPIN mode register
3. Set `current_spi_device := DEV_FLASH`

Flash SPI methods then configure their own GPIO state per-command.

### Switching: Flash to SD

`switch_to_sd()` must perform a full SD card re-initialization because P60 (SD CS) doubles as the Flash clock. During Flash operations, the SD card sees its CS line rapidly toggling, which corrupts the card's internal SPI state machine. A simple smart pin reconfiguration is not enough — the card needs a complete reset:

1. Float Flash pins
2. `reinitCard()` performs a minimal recovery sequence:
   - PINCLEAR all pins, then set up as GPIO for a 4096-clock flush (with CS HIGH)
   - Reconfigure smart pins at 400 kHz
   - CMD0 (GO_IDLE) → CMD8 (SEND_IF_COND) → ACMD41 (SD_SEND_OP_COND) → CMD58 (READ_OCR)
   - Restore the saved SPI frequency
3. Invalidate all sector caches (dir_buf, fat_buf, buf)
4. Set `current_spi_device := DEV_SD`

The ACMD41 argument is cached from the initial mount (`saved_acmd41_arg`) so reinitCard() doesn't repeat the full identification sequence.

### Lazy Switching

The worker cog tracks the current bus configuration in `current_spi_device` (-1 = none, 0 = SD, 1 = Flash). Before dispatching any command, it checks the target device:

```
if cur_cmd >= CMD_FLASH_MOUNT and cur_cmd <= CMD_FL_CAN_MOUNT
  switch_to_flash()    ' no-op if already on Flash
else
  switch_to_sd()       ' no-op if already on SD
```

Consecutive same-device operations incur zero switching overhead. Only the first command after a device change pays the cost — and for Flash-to-SD, that cost includes the full `reinitCard()` sequence.

### PINCLEAR vs PINFLOAT

A critical P2 smart pin detail: `PINFLOAT(pin)` only clears the DIR bit (output enable). The WRPIN mode register survives — so a pin configured as `P_SYNC_TX` remains in that mode even after PINFLOAT, and subsequent GPIO operations (`drvc`, `testp`) produce unexpected smart pin behavior instead of clean GPIO transitions.

`PINCLEAR(pin)` clears both DIR and WRPIN, fully stopping the smart pin. This is the correct way to tear down smart pin configuration before switching to GPIO mode.

## Two Filesystem Models

### SD: FAT32

The SD card uses the standard FAT32 filesystem:

- **Sector-based**: 512-byte sectors organized into clusters (typically 8-64 sectors per cluster)
- **FAT chain**: each cluster points to the next via the File Allocation Table (MBR → VBR → FAT → data area)
- **Directory hierarchy**: subdirectories, per-cog CWD, `cd`/`mkdir`/`rmdir` support
- **8.3 filenames**: 8-character name + 3-character extension (no long filename support)
- **Timestamps**: creation, modification, and access dates on directory entries
- **SPI mode**: 25 MHz maximum clock, with optional CMD6 high-speed (50 MHz) if supported by the card

### Flash: Block-Based

The 16MB onboard Flash chip uses a custom block-based filesystem:

- **4KB blocks**: the chip's erase unit (first 512KB reserved for the P2 boot image, leaving blocks $080–$FFF)
- **3968 usable blocks** in the filesystem region
- **Directory emulation**: path-segmented filenames simulate directories (see below)
- **Long filenames**: up to 127 characters (128 bytes including null terminator)

#### Flash Directory Emulation

Flash filenames support "/" characters (up to 127 chars, no filtering), making path-segmented filenames natural. The driver uses this to emulate a directory hierarchy on Flash's flat block store:

- **Per-cog CWD prefix**: the driver maintains a per-cog current working directory string in `fl_cog_cwd` (DAT array, 128 bytes per cog, 8 cogs = 1 KB total). The CWD prefix is prepended to filenames on Flash file operations, making the emulation transparent to callers.
- **`changeDirectory(DEV_FLASH, @path)`**: updates the CWD prefix for the calling cog. "/" navigates to root (empty prefix), ".." strips the last path segment, and relative paths append to the current prefix with "/" separators.
- **`newDirectory(DEV_FLASH, @name)`**: validates the path but stores nothing on Flash. Directories exist implicitly because files with those path segments exist. Empty directories vanish when their last file is deleted.
- **`openDirectory(DEV_FLASH, ...)`**: iterates all Flash files via `directory()` but filters by CWD prefix — only returns filenames whose stored name starts with the current CWD prefix, stripping the prefix from the returned name.
- **File creation**: `open()` and `createFileNew()` prepend the CWD prefix to the filename before storing it on Flash.

**Limitation**: Empty directories cannot exist on Flash. A directory only "exists" because files with that path prefix exist. Deleting the last file in a directory removes the directory.

#### Block Layout

**Head block** (first block of a file, 4096 bytes total):

| Offset | Size | Content |
|--------|------|---------|
| $000 | 4 | Block header (ID + lifecycle) |
| $004 | 4 | Filename CRC |
| $008 | 128 | Filename (null-terminated) |
| $088 | 3956 | File data (first 3956 bytes) |

**Body block** (continuation block, 4096 bytes total):

| Offset | Size | Content |
|--------|------|---------|
| $000 | 4 | Block header (ID + lifecycle) |
| $004 | 4 | Chain pointer |
| $008 | 4088 | File data |

#### Translation Tables

Three in-memory tables track block state (~7.2 KB total):

| Table | Per-Block | Total Size | Purpose |
|-------|-----------|------------|---------|
| `fl_IDToBlocks` | 12 bits | ~5968 bytes | Maps file ID to physical block address |
| `fl_IDValids` | 1 bit | ~496 bytes | Marks which file IDs are in use |
| `fl_BlockStates` | 2 bits | ~992 bytes | Block state: FREE, TEMP, HEAD, or BODY |

These tables are rebuilt from the physical Flash contents during `mount(DEV_FLASH)` by scanning all blocks.

#### Wear Leveling

Flash blocks have a limited number of erase cycles. The driver uses two strategies to distribute wear:

1. **Random block allocation**: new blocks are chosen randomly from the free pool rather than sequentially
2. **Make-before-break replacement**: when modifying a file, the new data is written to a fresh block before the old block is released — preventing data loss if power fails mid-write

## Driver Modes and Mount State

### Operating Modes

The driver tracks an overall mode that governs which SD commands are allowed:

| Mode | Value | Set By | Allowed Operations |
|------|-------|--------|--------------------|
| `MODE_NONE` | 0 | Initial state | Only `mount()` or `initCardOnly()` |
| `MODE_RAW` | 1 | `initCardOnly()` | Raw sector read/write (SD only) |
| `MODE_FILESYSTEM` | 2 | `mount()` | Full filesystem + raw access |

### Independent Device Mount Tracking

Each device has its own mount flag:

| Flag | Meaning |
|------|---------|
| `sd_mounted` | TRUE after successful `mount(DEV_SD)` |
| `flash_mounted` | TRUE after successful `mount(DEV_FLASH)` |

The `mount()` method accepts three device arguments:

| Argument | Effect |
|----------|--------|
| `DEV_SD` | Mount SD card only |
| `DEV_FLASH` | Mount Flash chip only |
| `DEV_BOTH` | Mount both devices |

`mounted(dev)` is a zero-cost check — it reads the shared DAT flag directly from hub RAM without acquiring the lock or sending a command to the worker cog. Safe to call from any cog at any time.

## Worker Cog and Command Protocol

### Mailbox Registers

All cog-to-worker communication flows through shared hub RAM variables:

| Register | Direction | Purpose |
|----------|-----------|---------|
| `pb_cmd` | Caller → Worker | Command opcode (0 = idle) |
| `pb_param0..3` | Caller → Worker | Up to 4 command parameters |
| `pb_caller` | Caller → Worker | Calling cog's ID (for COGATN wakeup) |
| `pb_status` | Worker → Caller | Result status code |
| `pb_data0..2` | Worker → Caller | Up to 3 result values (handle, count, pointer, etc.) |

Per-cog snapshots (`saved_data0..2[8]`) are captured before releasing the lock, so each cog sees its own results even if another cog issues a command immediately after.

### Command Flow

1. **Acquire lock** — `repeat until locktry(api_lock)` serializes multi-cog access
2. **Write parameters** — `pb_caller := COGID()`, `pb_param0..3`, then `pb_cmd := opcode` (write cmd last — it triggers the worker)
3. **Sleep** — `WAITATN()` (efficient hardware sleep until worker signals)
4. **Worker dispatches** — polls `pb_cmd`, executes the operation, writes `pb_status` and `pb_data0..2`
5. **Worker signals** — `COGATN(1 << pb_caller)`, then `pb_cmd := CMD_NONE`
6. **Caller reads results** — snapshots `pb_data0..2` into per-cog saved arrays
7. **Release lock** — `lockrel(api_lock)`

### Command Opcode Tables

**Core SD Commands:**

| Command | Value | Purpose |
|---------|-------|---------|
| `CMD_MOUNT` | 1 | Mount SD filesystem |
| `CMD_UNMOUNT` | 2 | Unmount SD filesystem |
| `CMD_NEWDIR` | 9 | Create new directory |
| `CMD_DELETE` | 10 | Delete file or empty directory |
| `CMD_RENAME` | 11 | Rename file or directory |
| `CMD_CHDIR` | 12 | Change current directory |
| `CMD_READDIR` | 13 | Read directory entry by index |
| `CMD_FILESIZE` | 14 | Get file size (legacy API) |
| `CMD_FREESPACE` | 15 | Get free space in sectors |
| `CMD_SYNC` | 16 | Flush pending writes |
| `CMD_MOVEFILE` | 17 | Move file to another directory |

**Handle-Based File Commands:**

| Command | Value | Purpose |
|---------|-------|---------|
| `CMD_OPEN_READ` | 30 | Open file for reading → handle |
| `CMD_OPEN_WRITE` | 31 | Open file for append writing → handle |
| `CMD_CREATE` | 32 | Create new file → handle |
| `CMD_CLOSE_H` | 33 | Close file handle |
| `CMD_READ_H` | 34 | Read bytes from handle |
| `CMD_WRITE_H` | 35 | Write bytes to handle |
| `CMD_SEEK_H` | 36 | Seek to position |
| `CMD_TELL_H` | 37 | Get current position |
| `CMD_FILESIZE_H` | 38 | Get file size by handle |
| `CMD_SYNC_H` | 39 | Flush handle to disk |
| `CMD_SYNC_ALL` | 40 | Flush all open handles |
| `CMD_EOF_H` | 41 | Check end-of-file |
| `CMD_OPEN_DIR` | 43 | Open directory → handle |
| `CMD_READ_DIR_H` | 44 | Read next directory entry |
| `CMD_CLOSE_DIR_H` | 45 | Close directory handle |
| `CMD_SET_VOL_LABEL` | 46 | Set SD volume label |
| `CMD_SD_EXISTS` | 47 | Check if SD file exists |
| `CMD_SD_FILE_SIZE` | 48 | Get SD file size by name |
| `CMD_SD_FILE_SIZE_UNUSED` | 49 | Get SD file slack space |

**Flash Commands:**

| Command | Value | Purpose |
|---------|-------|---------|
| `CMD_FLASH_MOUNT` | 50 | Mount Flash filesystem |
| `CMD_FLASH_FORMAT` | 51 | Format Flash filesystem |
| `CMD_FLASH_OPEN` | 52 | Open Flash file with mode |
| `CMD_FLASH_OPEN_CIRC` | 53 | Open Flash circular file |
| `CMD_FLASH_CLOSE` | 54 | Close Flash file handle |
| `CMD_FLASH_READ` | 55 | Read from Flash handle |
| `CMD_FLASH_WRITE` | 56 | Write to Flash handle |
| `CMD_FLASH_SEEK` | 57 | Seek in Flash file |
| `CMD_FLASH_FLUSH` | 58 | Flush Flash handle |
| `CMD_FLASH_DELETE` | 59 | Delete Flash file |
| `CMD_FLASH_RENAME` | 60 | Rename Flash file |
| `CMD_FLASH_EXISTS` | 61 | Check if Flash file exists |
| `CMD_FLASH_CREATE_FILE` | 62 | Pre-allocate Flash file |
| `CMD_FLASH_FILE_SIZE` | 63 | Get Flash file size |
| `CMD_FLASH_STATS` | 64 | Get Flash device stats |
| `CMD_FLASH_DIRECTORY` | 65 | Iterate Flash directory |
| `CMD_SERIAL_NUMBER` | 67 | Get device serial number |
| `CMD_FL_WR_BYTE` | 71 | Write single byte to Flash |
| `CMD_FL_RD_BYTE` | 72 | Read single byte from Flash |
| `CMD_FL_RD_STR` | 73 | Read string from Flash |
| `CMD_FL_FILE_SIZE_UNUSED` | 79 | Unused bytes in last block |
| `CMD_FL_COUNT_BYTES` | 80 | Diagnostic: count file bytes |
| `CMD_FL_CAN_MOUNT` | 81 | Flash mount capability check |

**Conditional SD Commands:**

| Command | Value | Guard | Purpose |
|---------|-------|-------|---------|
| `CMD_READ_SECTORS` | 18 | `SD_INCLUDE_RAW` | Multi-block read (CMD18) |
| `CMD_WRITE_SECTORS` | 19 | `SD_INCLUDE_RAW` | Multi-block write (CMD25) |
| `CMD_READ_SECTOR_RAW` | 20 | (always) | Single sector read |
| `CMD_WRITE_SECTOR_RAW` | 21 | `SD_INCLUDE_RAW` | Single sector write |
| `CMD_INIT_CARD_ONLY` | 22 | `SD_INCLUDE_RAW` | Raw mode init (no FS) |
| `CMD_GET_CARD_SIZE` | 23 | `SD_INCLUDE_RAW` | Card capacity in sectors |
| `CMD_READ_SCR` | 24 | `SD_INCLUDE_REGISTERS` | Read SCR register |
| `CMD_DEBUG_SLOW_READ` | 25 | `SD_INCLUDE_DEBUG` | Byte-by-byte sector read |
| `CMD_DEBUG_CLEAR_ROOT` | 26 | `SD_INCLUDE_DEBUG` | Clear root directory |
| `CMD_READ_CID` | 27 | `SD_INCLUDE_REGISTERS` | Read CID register |
| `CMD_READ_CSD` | 28 | `SD_INCLUDE_REGISTERS` | Read CSD register |
| `CMD_READ_SD_STATUS` | 29 | `SD_INCLUDE_REGISTERS` | Read SD Status (ACMD13) |
| `CMD_TEST_CMD13` | 82 | `SD_INCLUDE_RAW` | Test CMD13: returns R2 response |
| `CMD_ATTEMPT_HIGH_SPEED` | 83 | `SD_INCLUDE_SPEED` | Attempt 50 MHz high-speed mode |
| `CMD_CHECK_HS_CAPABILITY` | 84 | `SD_INCLUDE_SPEED` | Check CMD6 high-speed support |
| `CMD_SET_SPI_SPEED` | 85 | `SD_INCLUDE_SPEED` | Set SPI clock frequency |
| `CMD_STACK_DEPTH` | 86 | `SD_INCLUDE_STACK_CHECK` | Report stack depth high-water mark |
| `CMD_CREATE_CONTIGUOUS` | 87 | `SD_INCLUDE_DEFRAG` | Create file with contiguous chain |
| `CMD_COMPACT_FILE` | 88 | `SD_INCLUDE_DEFRAG` | Defragment a single file |
| `CMD_FILE_FRAGMENTS` | 89 | `SD_INCLUDE_DEFRAG` | Count file fragmentation |

### Worker Loop Architecture

The worker cog runs a structured main loop with three functional slots, executed on every iteration:

1. **Clock tick** -- Every 2 seconds, increments `date_stamp` using FIELD operators on the FAT32-packed date/time fields (seconds, minutes, hours, day, month, year). The clock is activated by the first call to `setDate()` and runs continuously thereafter, providing automatic timestamps for file creation and modification without further caller intervention.

2. **Command dispatch** -- The existing filesystem command processing. When `pb_cmd <> CMD_NONE`, the worker dispatches to the appropriate handler, writes results to `pb_status` and `pb_data0..2`, signals the caller via `COGATN`, and resets `pb_cmd` to `CMD_NONE`.

3. **Auto-flush** -- After 200ms of idle time (no commands received), the worker flushes all dirty file handles and the FSInfo sector to disk. This protects against data loss from unexpected card removal. The auto-flush checks `pb_cmd` between each handle sync, aborting immediately if a new command arrives so there is zero latency impact on normal operations.

The inner polling loop (`repeat until pb_cmd <> CMD_NONE`) is where the idle-time work fires. While waiting for the next command, the worker performs clock ticks and auto-flush checks on each iteration, keeping both subsystems responsive without dedicated timers.

## Unified Handle System

### Shared Handle Pool

File handles and directory handles for both devices share a single pool of `MAX_OPEN_FILES` slots (default 6, user-configurable). Each slot is tagged with the device it belongs to via `h_device[handle]`.

When a path-based method opens a file, it allocates a handle, sets `h_device` to the target device, and populates the appropriate state arrays. Handle-based methods (read, write, seek, close) check `h_device` to route to the correct device's implementation — the caller doesn't need to specify the device again.

### SD Handle State

| Array | Type | Purpose |
|-------|------|---------|
| `h_device` | BYTE | Device tag: `DEV_SD` |
| `h_flags` | BYTE | `HF_READ`, `HF_WRITE`, or `HF_DIR` (OR'd with `HF_DIRTY` for pending writes) |
| `h_attr` | BYTE | FAT directory entry attributes |
| `h_position` | LONG | Current byte position in file |
| `h_sector` | LONG | Current data sector |
| `h_cluster` | LONG | Current cluster in FAT chain |
| `h_start_clus` | LONG | First cluster (from directory entry) |
| `h_size` | LONG | File size in bytes |
| `h_dir_sector` | LONG | Sector containing the file's directory entry |
| `h_dir_offset` | WORD | Offset within that sector (0–511) |
| `h_buf[512]` | BYTE | Per-handle sector buffer |
| `h_buf_sector` | LONG | Which sector is cached (-1 = none) |

### Flash Handle State

| Array | Type | Purpose |
|-------|------|---------|
| `h_device` | BYTE | Device tag: `DEV_FLASH` |
| `fl_hStatus` | BYTE | `FL_H_READ`, `FL_H_WRITE`, `FL_H_FORK`, `FL_H_MODIFY` |
| `fl_hHeadBlockID` | WORD | Block ID of file header (-30 = uninitialized) |
| `fl_hChainBlockID` | WORD | Current block in linked chain |
| `fl_hChainBlockAddr` | WORD | Physical address of current chain block |
| `fl_hChainLifeCycle` | BYTE | Life cycle state of chain block |
| `fl_hModified` | BYTE | TRUE if data has been modified |
| `fl_hEndPtr` | WORD | Offset to end of data in current block |
| `fl_hSeekPtr` | LONG | Seek position (-1 = not enabled) |
| `fl_hSeekFileOffset` | LONG | File byte offset from seek position |
| `fl_hCircularLength` | LONG | Length of circular file (0 = normal file) |
| `fl_hFilename[128]` | BYTE | Cached filename (128 bytes per handle) |
| `fl_hBufIndex` | BYTE | Buffer pool index for this handle (`$FF` = none) |
| `fl_hBlockBuff[4096]` | BYTE | 4KB block buffer (from buffer pool, not per-handle) |

### Handle Lifecycle

```
allocateHandle()      Find free slot (h_flags == HF_FREE)
       |
       v
  Set h_device        Tag as DEV_SD or DEV_FLASH
       |
       v
  [Flash only]        fl_alloc_buffer() — attach buffer from pool
                      If pool exhausted: freeHandle(), return E_FLASH_NO_BUFFER
       |
       v
  Populate state      SD: h_flags, h_start_clus, h_sector, etc.
                      Flash: fl_hStatus, fl_hHeadBlockID, etc.
       |
       v
  Use handle          readHandle / writeHandle / rd_byte / wr_str / ...
       |
       v
  Close               SD: flush dirty buffer, update directory entry
                      Flash: flush block buffer, finalize chain
       |
       v
  [Flash only]        fl_free_buffer() — release buffer back to pool
       |
       v
  freeHandle()        Clear all state, h_flags := HF_FREE
```

### Single-Writer Policy (SD)

The SD driver prevents two handles from writing the same file simultaneously:

1. Each file is uniquely identified by its `(h_dir_sector, h_dir_offset)` pair
2. `isFileOpenForWrite()` scans all handles for a matching pair with `HF_WRITE` set
3. Opening for write when already open returns `E_FILE_ALREADY_OPEN` (-92)
4. Multiple read handles to the same file are allowed

### Handle Type Guards

File operations reject directory handles and vice versa:

- `readHandle()`, `writeHandle()`, `seekHandle()`, etc. return `E_NOT_A_DIR_HANDLE` if the handle has `HF_DIR` set
- `readDirectoryHandle()` returns `E_INVALID_HANDLE` if the handle is not a directory handle

## Buffer Management and Memory Cost

### SD Buffers

Three shared 512-byte buffers serve the worker cog's internal operations:

| Buffer | Cache Variable | Purpose |
|--------|---------------|---------|
| `buf` (512 bytes) | `sec_in_buf` | General data sector I/O |
| `dir_buf` (512 bytes) | `dir_sec_in_buf` | Directory sector reads |
| `fat_buf` (512 bytes) | `fat_sec_in_buf` | FAT table reads/writes |

Additionally:

- `entry_buffer` (32 bytes) — holds the most recently read directory entry (typed as `dir_entry_t`)
- `vol_label` (12 bytes) — volume label string (11 chars + null)

Each SD handle also has its own 512-byte sector buffer (`h_buf`), eliminating thrashing when alternating between multiple open files.

### Flash Buffers

Flash block buffers are managed as a **pool** sized by `MAX_FLASH_BUFFERS` (default 3), independent of `MAX_OPEN_FILES`:

- **Buffer pool** (`fl_hBlockBuff`) — `MAX_FLASH_BUFFERS` x 4,096 bytes. Buffers are assigned to handles on `open()` and released on `close()`. Pool tracking uses `fl_buf_owner[MAX_FLASH_BUFFERS]` (which handle owns each buffer) and `fl_hBufIndex[MAX_OPEN_FILES]` (which buffer is assigned to each handle).
- **Temporary block buffer** (`fl_tmpBlockBuff`) — 4,096 bytes. Used during mount scanning, block moves, directory listing, exists, file_size, delete, rename, and format operations. Independent of the handle buffer pool.

Operations that use **no handle buffer**: mount, directory, exists, file_size, file_size_unused, stats, deleteFile, rename, changeDirectory, freeSpace, serial_number, format. These use `fl_tmpBlockBuff` or in-memory translation tables.

Operations that **require a handle buffer**: open (read or write), rd_byte/rd_str/rd_long, wr_byte/wr_str/wr_long, seek, flush, close. The buffer is attached at `open()` and detached at `close()`.

### Copy Buffer

- `copy_buf` (512 bytes) — scratch buffer used by `copyFile()` for chunked cross-device copies

### Memory Budget

| Component | Size | Notes |
|-----------|------|-------|
| Shared SD buffers (buf + dir_buf + fat_buf) | 1,536 bytes | 3 x 512 |
| Entry buffer + volume label | 44 bytes | 32 + 12 |
| Copy buffer | 512 bytes | For copyFile() |
| Per-handle SD state (33 bytes x 6) | 198 bytes | Flags, position, cluster, etc. |
| Per-handle SD buffers (512 bytes x 6) | 3,072 bytes | Sector cache per handle |
| Per-handle Flash state (~148 bytes x 6) | 888 bytes | Status, IDs, seek, filename |
| Flash buffer pool (4096 bytes x 3) | 12,288 bytes | `MAX_FLASH_BUFFERS` block buffers |
| Flash buffer pool tracking | 9 bytes | `fl_buf_owner[3]` + `fl_hBufIndex[6]` |
| Flash translation tables | ~7,456 bytes | IDToBlocks + IDValids + BlockStates |
| Temporary Flash block buffer | 4,096 bytes | Mount scanning |
| Per-cog SD CWD (8 LONGs) | 32 bytes | SD directory sector per cog |
| Per-cog Flash CWD (8 x 128 B) | 1,024 bytes | Flash CWD emulation |
| Per-cog errors (8 LONGs) | 32 bytes | last_error[8] |
| Per-cog saved data (3 x 8 LONGs) | 96 bytes | saved_data0..2 |
| Mailbox registers | 40 bytes | pb_cmd through pb_data2 |
| Worker cog stack | 640 bytes | 160 LONGs (peak measured: 127) |
| Stack guard | 16 bytes | 4 LONGs sentinel |
| **Total (6 handles, 3 buffers)** | **~31,979 bytes** | ~31.2 KB |

Flash buffer pool sizing is independent of handle count. Reducing `MAX_FLASH_BUFFERS` from 6 to 3 (default) saves 12,288 bytes compared to previous releases. SD-only applications can set `MAX_FLASH_BUFFERS = 0` to eliminate Flash buffers entirely.

### Choosing Handle and Buffer Counts

Two independent constants control memory allocation:

- **`MAX_OPEN_FILES`** — Total handles shared between SD and Flash. Drives SD sector buffers (512 B each) and Flash handle state arrays (~148 B each). Default 6. SD needs handles for files AND directories (a dir listing + a file read = 2 handles). Flash uses zero handles for directory operations.
- **`MAX_FLASH_BUFFERS`** — How many Flash files can be open simultaneously. Drives Flash block buffers (4,096 B each). Default 3. Independent of handle count. A system with 6 handles may only ever have 2-3 Flash files open at once.

Override both in the OBJ declaration:

```spin2
OBJ
  fs : "dual_sd_fat32_flash_fs" | MAX_OPEN_FILES = 4, MAX_FLASH_BUFFERS = 2
```

**Cost per additional unit**:

| Resource | Per-Unit Cost | What It Enables |
|----------|---------------|-----------------|
| Handle (`MAX_OPEN_FILES`) | ~693 B | 33 B SD state + 512 B SD buffer + 148 B Flash state |
| Flash buffer (`MAX_FLASH_BUFFERS`) | 4,097 B | 4,096 B block buffer + 1 B owner tracking |

**How to choose `MAX_FLASH_BUFFERS`**:
- **2** = enough for read + write (or cross-device copy)
- **3** = Flash-to-Flash copy + one additional file (default, recommended)
- **0** = SD-only build (Flash mount still works, but `open()` fails with `E_FLASH_NO_BUFFER`)

**How to choose `MAX_OPEN_FILES`**: Count max simultaneous open files + directory enumerations across all cogs.
- **4** = typical single-cog app
- **6** = 2-3 cogs doing file access (default)
- **8** = maximum practical (limited by hub RAM)

| Usage Pattern | Handles | Flash Buffers |
|---------------|---------|---------------|
| Read or write a single file | 1 | 1 |
| Copy operation (source + destination) | 2 | 0-2 |
| Single file + directory enumeration | 2 | 0-1 |
| Cross-device copy + directory browsing | 3 | 1 |
| Flash-to-Flash copy | 2 | 2 |

### Flash Buffer Pool — Deferred Allocation

Flash handle buffers are allocated from a fixed pool at runtime, not statically per handle. This decouples Flash memory cost from the total handle count.

**Algorithm**:
1. `open(DEV_FLASH, ...)` calls `fl_alloc_buffer(handle)` — scans `fl_buf_owner[]` for a free slot (`$FF`)
2. If found: assigns the buffer to the handle and proceeds normally
3. If pool exhausted: frees the handle and returns `E_FLASH_NO_BUFFER`
4. `close(handle)` calls `fl_free_buffer(handle)` — returns the buffer to the pool

Operations that consume **zero buffers** from the pool: mount, directory listing, exists, file_size, stats, deleteFile, rename, changeDirectory, freeSpace, serial_number, format. These use `fl_tmpBlockBuff` or in-memory translation tables.

The pool is reset to all-free on `mount(DEV_FLASH)` and `unmount(DEV_FLASH)`.

| Scenario | Behavior |
|----------|----------|
| All buffers in use | `open()` returns `E_FLASH_NO_BUFFER`, handle freed |
| Close then reopen | Buffer released on close, available for next open |
| `MAX_FLASH_BUFFERS = 0` | SD-only build. Flash open fails. Flash mount/stats/delete still work |
| `MAX_FLASH_BUFFERS = MAX_OPEN_FILES` | Equivalent to pre-pool behavior (every handle can get a buffer) |

## Conditional Compilation

Seven feature flags control optional SD features. Flash features are always compiled.

**Hardware Access:**

| Flag | Features Included |
|------|-------------------|
| `SD_INCLUDE_RAW` | Raw sector read/write, `initCardOnly()`, multi-block (CMD18/CMD25) |
| `SD_INCLUDE_REGISTERS` | CID, CSD, SCR, SD Status register access, OCR, VBR read |
| `SD_INCLUDE_SPEED` | CMD6 high-speed mode query and switch (50 MHz) |
| `SD_INCLUDE_DEBUG` | Debug getters, CRC diagnostic methods, test error injection hooks |

**User-Selectable Features:**

| Flag | Features Included |
|------|-------------------|
| `SD_INCLUDE_ASYNC` | Async (non-blocking) read/write with polling completion |
| `SD_INCLUDE_DEFRAG` | Defragmentation: `fileFragments()`, `compactFile()`, `createFileContiguous()` |

**Diagnostic:**

| Flag | Features Included |
|------|-------------------|
| `SD_INCLUDE_STACK_CHECK` | Worker cog stack depth measurement (`stackDepth()`) |

**Convenience:**

| Flag | Features Included |
|------|-------------------|
| `SD_INCLUDE_ALL` | Enables all six flags above (RAW + REGISTERS + SPEED + DEBUG + ASYNC + DEFRAG; not STACK_CHECK) |

### Enabling Flags

Flags are exported from the top-level file using `#pragma exportdef` before the `OBJ` declaration:

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

## Debug Channel Scheme (DEBUG_MASK)

The driver contains ~455 debug statements, which exceeds the P2 compiler's 255 debug record limit. All debug statements use the `debug[CH_xxx]()` selective channel form with a `DEBUG_MASK` constant that controls which channels compile. This replaces the previous `DEBUG_DISABLE` constant.

Channels 0-9 use the same names and meanings as the standalone SD driver for cross-project consistency:

| Channel | Constant | Purpose | Both Devices? |
|---------|----------|---------|---------------|
| 0 | `CH_INIT` | Initialization, SPI pin setup, speed config | Yes |
| 1 | `CH_MOUNT` | Mount/unmount, filesystem geometry | Yes |
| 2 | `CH_FILE` | File handle lifecycle | Yes |
| 3 | `CH_DIR` | Directory operations, CWD | Yes |
| 4 | `CH_SECTOR` | Sector I/O, FAT chains, cluster allocation | SD only |
| 5 | `CH_STATUS` | CMD13/CMD23 probes, card status | SD only |
| 6 | `CH_IDENT` | CID/CSD/SCR, Flash serial number | Yes |
| 7 | `CH_HSPEED` | CMD6 high-speed mode | SD only |
| 8 | `CH_API` | PUB wrappers, worker cog dispatch | Yes |
| 9 | `CH_RECOVER` | Error recovery, SPI bus switching | Yes |
| 10 | `CH_FL_BLOCK` | Flash block I/O, wear leveling | Flash only |
| 11 | `CH_FL_CIRC` | Flash circular files | Flash only |

Enable 2-3 channels at a time. Set `DEBUG_MASK = 0` for production builds. See [Conditional Compilation Guide](CONDITIONAL-COMPILATION-GUIDE.md) for details.

## Multi-Cog Support

### Per-Cog Current Working Directory

Each P2 cog maintains its own current working directory for SD navigation:

```spin2
DAT
  cog_dir_sec   LONG    0[8]    ' Per-cog CWD sector (one per P2 cog)
```

- Indexed by `pb_caller` (the calling cog's ID)
- Initialized to `root_sec` for all 8 cogs at mount time
- `changeDirectory()` only modifies `cog_dir_sec[pb_caller]`
- Directory searches and enumerations start from `cog_dir_sec[pb_caller]`

This ensures Cog 0 can `cd /LOGS` while Cog 2 works in `/DATA` without interference.

### Per-Cog Flash CWD

Flash directory emulation also maintains a per-cog current working directory:

```spin2
DAT
  fl_cog_cwd   BYTE    0[8 * 128]    ' Per-cog Flash CWD prefix (128 bytes per cog)
```

- Indexed by `COGID() * 128`
- Initialized to empty string (root) at mount time
- `changeDirectory(DEV_FLASH, @path)` modifies only the calling cog's prefix
- File opens and directory listings use the calling cog's prefix for filtering

This allows each cog to navigate Flash's emulated directory tree independently, just as with SD.

### Hardware Lock

A hardware lock (`api_lock`) serializes all API calls. Every `send_command()` acquires the lock before writing to the mailbox and releases it after reading results. The lock prevents command interleaving when multiple cogs call the driver simultaneously.

### Per-Cog Error Storage

```spin2
DAT
  last_error   LONG    0[8]     ' One error slot per cog
```

Each cog's last error is stored independently, so `error()` returns the calling cog's most recent error without interference from other cogs.

### Lock-Free Status Checks

`mounted(dev)` reads the `sd_mounted` / `flash_mounted` DAT flags directly — no lock, no command to the worker. Safe to poll from any cog at any time.

## CRC-16 Validation (SD)

The driver validates data integrity on every SD sector transfer using CRC-16-CCITT, computed in hardware:

```spin2
PRI calcDataCRC(pData, len) : crc | raw
  raw := GETCRC(pData, CRC_POLY_REFLECTED, len)
  crc := ((raw ^ CRC_BASE_512) REV 31) >> 16
```

- `GETCRC` — P2 hardware instruction (no lookup table needed)
- `CRC_POLY_REFLECTED` ($8408) — CRC-16-CCITT in LSB-first form
- `CRC_BASE_512` ($2C68) — compensates for GETCRC initialization differences
- `REV 31` + `>> 16` — converts from reflected to standard bit order

**Read flow:** Card sends CRC after 512 data bytes. Driver calculates CRC from received data and compares. On mismatch, retries up to `MAX_READ_CRC_RETRIES` (3) times.

**Write flow:** Driver calculates CRC from data and appends it after the 512 data bytes.

Diagnostic counters (match/mismatch/retry counts) and the `setCRCValidation()` toggle are available via `SD_INCLUDE_DEBUG`. Test error injection hooks (`setTestForceReadError`, `setTestForceWriteError`) allow regression tests to verify CRC retry behavior.

## Cross-Device Operations

`copyFile(srcDev, pSrc, dstDev, pDst)` copies a file between any combination of devices:

1. Opens the source file for reading on `srcDev`
2. Creates (or opens for write) the destination file on `dstDev`
3. Reads in 512-byte chunks through `copy_buf`, writing each chunk to the destination
4. Closes both handles

This works for SD→Flash, Flash→SD, or same-device copies. The worker cog handles all SPI switching internally — the caller just provides device constants and filenames.

## Exported STRUCT Types (SD)

The driver defines and exports packed struct types (requires `{Spin2_v45}` or later; the driver uses `{Spin2_v46}`) for named access to SD card registers and FAT32 on-disk structures.

### SD Card Register Structs

| Struct | Size | Purpose |
|--------|------|---------|
| `cid_t` | 16 bytes | CID register: manufacturer ID, product name, serial number, manufacturing date |
| `csd_t` | 16 bytes | CSD register: card capacity, speed class, timing parameters |
| `scr_t` | 8 bytes | SCR register: SD spec version, bus widths, security features |

### FAT32 On-Disk Structure Structs

| Struct | Size | Purpose |
|--------|------|---------|
| `dir_entry_t` | 32 bytes | Directory entry: name, ext, attributes, timestamps, cluster, file size |
| `mbr_partition_t` | 16 bytes | MBR partition table entry: boot flag, type, LBA start/size |
| `vbr_t` | 512 bytes | Volume Boot Record (BPB): bytes/sector, clusters, FAT layout, volume label |
| `fsinfo_t` | 512 bytes | FSInfo sector: free cluster count, next free hint, signatures |

### Usage Pattern

Structs are overlaid onto buffers via typed pointers:

```spin2
OBJ
  fs : "dual_sd_fat32_flash_fs"

PRI parseCID(p_buf)
  fs.cid_t pCid := @p_buf
  debug("Manufacturer: ", uhex_byte_(pCid.mid))
  debug("Product: ", lstr_(@pCid.pnm, 5))
```

All structs are packed (Spin2 default) with offsets matching their respective hardware or on-disk layouts exactly. SD card register structs are big-endian (as received from card); FAT32 structs are little-endian (native P2 byte order).

## Error Codes

### SD Errors

| Error | Value | Meaning |
|-------|-------|---------|
| `E_TIMEOUT` | -1 | Card didn't respond in time |
| `E_NO_RESPONSE` | -2 | Card not responding |
| `E_BAD_RESPONSE` | -3 | Unexpected response from card |
| `E_CRC_ERROR` | -4 | Data CRC mismatch |
| `E_WRITE_REJECTED` | -5 | Card rejected write operation |
| `E_CARD_BUSY` | -6 | Card busy timeout |
| `E_IO_ERROR` | -7 | General I/O error during read/write |
| `E_NO_CARD` | -8 | No card detected in slot (MISO idle during CMD0 probe) |
| `E_NOT_MOUNTED` | -20 | Filesystem not mounted |
| `E_INIT_FAILED` | -21 | Card initialization failed |
| `E_NOT_FAT32` | -22 | Card not formatted as FAT32 |
| `E_BAD_SECTOR_SIZE` | -23 | Sector size not 512 bytes |
| `E_FILE_NOT_FOUND` | -40 | File doesn't exist |
| `E_FILE_EXISTS` | -41 | File already exists |
| `E_NOT_A_FILE` | -42 | Expected file, found directory |
| `E_NOT_A_DIR` | -43 | Expected directory, found file |
| `E_FILE_NOT_OPEN` | -45 | File not open |
| `E_END_OF_FILE` | -46 | Read past end of file |
| `E_DISK_FULL` | -60 | No free clusters available |
| `E_NO_LOCK` | -64 | Could not acquire hardware lock |
| `E_TOO_MANY_FILES` | -90 | All handle slots in use |
| `E_INVALID_HANDLE` | -91 | Handle out of range or not open |
| `E_FILE_ALREADY_OPEN` | -92 | File already open for writing |
| `E_NOT_A_DIR_HANDLE` | -93 | Wrong handle type for operation |

### Flash Errors

| Error | Value | Meaning |
|-------|-------|---------|
| `E_FLASH_BAD_HANDLE` | -100 | Flash handle is invalid |
| `E_FLASH_NO_HANDLE` | -101 | Out of available Flash handles |
| `E_FLASH_DRIVE_FULL` | -102 | Out of space on Flash chip |
| `E_FLASH_FILE_WRITING` | -103 | Flash file is open for writing |
| `E_FLASH_FILE_READING` | -104 | Flash file is open for reading |
| `E_FLASH_FILE_OPEN` | -105 | Flash file is open |
| `E_FLASH_FILE_MODE` | -106 | Flash file not opened in desired mode |
| `E_FLASH_FILE_SEEK` | -107 | Seek past either end of Flash file |
| `E_FLASH_BAD_BLOCKS` | -108 | Block bit failure, bad blocks removed |
| `E_FLASH_TRUNCATED_STR` | -109 | Buffer full before string terminator |
| `E_FLASH_INCOMPLETE_STR` | -110 | EOF reached before string terminator |
| `E_FLASH_SHORT_TRANSFER` | -111 | Too few bytes read or written |
| `E_FLASH_BAD_FILE_LENGTH` | -112 | File length is negative or zero |
| `E_FLASH_BAD_SEEK_ARG` | -113 | Invalid seek argument |
| `E_FLASH_FILE_EXISTS` | -114 | Flash file already exists |
| `E_FLASH_NO_BUFFER` | -115 | No Flash buffer available (all in use) |

### Unified Device Errors

| Error | Value | Meaning |
|-------|-------|---------|
| `E_BAD_DEVICE` | -120 | Invalid device parameter |
| `E_DEVICE_NOT_MOUNTED` | -121 | Requested device not mounted |
| `E_NOT_SUPPORTED` | -122 | Operation not supported on this device |
| `E_STACK_OVERFLOW` | -130 | Worker cog stack overflow detected |

### Validation and Async Errors

| Error | Value | Meaning |
|-------|-------|---------|
| `E_INVALID_PARAM` | -94 | Parameter value out of valid range |
| `E_ASYNC_BUSY` | -95 | An async operation is already in flight |
| `E_NO_ASYNC_OP` | -96 | No async operation to get result from |

The `string_for_error(code)` method returns a human-readable string for any error code.

## Public API Summary

### Lifecycle

| Method | Description |
|--------|-------------|
| `init()` | Start worker cog, allocate lock (pins are fixed CON constants) |
| `stop()` | Stop worker cog, release lock |
| `mount(dev)` | Mount one or both filesystems |
| `unmount(dev)` | Flush and unmount one or both filesystems |
| `mounted(dev)` | Check if device is mounted (lock-free) |
| `version(dev)` | Driver version as integer (e.g., DEV_BOTH → 1_03_00, DEV_SD → 1_05_00, DEV_FLASH → 2_00_00) |
| `versionStr(dev)` | Driver version as string (e.g., "1.3.0", "1.5.0", "2.0.0") |
| `checkStackGuard()` | Verify worker cog stack guard is intact |
| `error()` | Last error code for calling cog |

### SD File Operations (Handle-Based)

| Method | Description |
|--------|-------------|
| `openFileRead(dev, pPath)` | Open existing file for reading → handle |
| `openFileWrite(dev, pPath)` | Open existing file for append writing → handle |
| `createFileNew(dev, pPath)` | Create new file for writing → handle |
| `readHandle(handle, pBuf, count)` | Read up to count bytes → bytes_read |
| `writeHandle(handle, pBuf, count)` | Write count bytes → bytes_written |
| `seekHandle(handle, position)` | Seek to absolute byte position |
| `tellHandle(handle)` | Get current byte position |
| `eofHandle(handle)` | Check if at end of file |
| `fileSizeHandle(handle)` | Get file size in bytes |
| `syncHandle(handle)` | Flush pending writes to disk |
| `syncAllHandles()` | Flush all open write handles |
| `closeFileHandle(handle)` | Close handle, flush writes |

### Flash File Operations

| Method | Description |
|--------|-------------|
| `open(dev, pFilename, mode)` | Open file with mode (FILEMODE_READ, _WRITE, _APPEND, etc.) → handle |
| `open_circular(dev, pFilename, mode, maxLen)` | Open circular file → handle |
| `create_file(dev, pFilename, fillValue, byteCount)` | Pre-allocate Flash file |
| `close(handle)` | Close file handle (Flash API) |
| `flush(handle)` | Flush without closing (Flash API) |
| `wr_byte(handle, value)` | Write single byte |
| `rd_byte(handle)` | Read next byte |
| `wr_word(handle, value)` | Write 16-bit word (little-endian) |
| `rd_word(handle)` | Read 16-bit word |
| `wr_long(handle, value)` | Write 32-bit long (little-endian) |
| `rd_long(handle)` | Read 32-bit long |
| `wr_str(handle, pStr)` | Write string including null terminator |
| `rd_str(handle, pStr, maxLen)` | Read null-terminated string → bytes_read (excluding terminator) |
| `flashSeek(handle, position, whence)` | Seek with whence (SK_FILE_START or SK_CURRENT_POSN) |

### File Management

| Method | Description |
|--------|-------------|
| `deleteFile(dev, pName)` | Delete file or empty directory |
| `rename(dev, pOld, pNew)` | Rename file or directory |
| `moveFile(dev, pName, pDest)` | Move file to another directory (SD only) |
| `exists(dev, pFilename)` | Check if file exists on device |
| `file_size(dev, pFilename)` | Get file size by name (without opening) |
| `file_size_unused(dev, pFilename)` | Unused bytes in last Flash block |

### Directory Operations

| Method | Description |
|--------|-------------|
| `changeDirectory(dev, pPath)` | Change calling cog's CWD (SD directories, Flash CWD emulation) |
| `newDirectory(dev, pName)` | Create new directory (SD directories, Flash CWD emulation) |
| `readDirectory(entry)` | Enumerate CWD by index (SD legacy API) |
| `openDirectory(dev, pPath)` | Open directory for handle-based enumeration (SD directories, Flash CWD emulation) → handle |
| `readDirectoryHandle(handle)` | Read next directory entry → pEntry |
| `closeDirectoryHandle(handle)` | Close directory handle |
| `directory(dev, pBlockId, pFilename, pFileSize)` | Iterate Flash directory (set blockId=0 to start) |
| `getFlashCwd()` | Get current Flash CWD prefix string for calling cog |

### Device Information

| Method | Description |
|--------|-------------|
| `freeSpace(dev)` | Free space (SD: sectors, Flash: blocks) |
| `volumeLabel(dev)` | Pointer to volume label string (SD only) |
| `setVolumeLabel(dev, pLabel)` | Set SD volume label |
| `serial_number(dev)` | Device serial number (sn_hi, sn_lo) |
| `cardWarnings()` | SD card warning flags from last operation |
| `stats(dev)` | Device statistics (used, free, file_count) |
| `canMount(dev)` | Non-destructive mount check |
| `format(dev)` | Format device (destructive!) |

### Cross-Device

| Method | Description |
|--------|-------------|
| `copyFile(srcDev, pSrc, dstDev, pDst)` | Copy file between devices (512-byte chunked) |

### Date/Time

| Method | Description |
|--------|-------------|
| `setDate(year, month, day, hour, minute, second) : status` | Validate and set date/time, activate live 2-second clock |
| `getDate() : year, month, day, hour, minute, second` | Read live clock values from hub RAM |

### Utilities

| Method | Description |
|--------|-------------|
| `setSPISpeed(freq)` | Set SPI clock frequency in Hz |
| `syncDirCache()` | Invalidate directory sector cache |
| `sync()` | Flush all pending writes |
| `string_for_error(code)` | Human-readable string for any error code |
| `fileName()` | 8.3 filename from last directory read (SD legacy) |
| `attributes()` | Attribute byte from last directory read (SD legacy) |

### Card Information

| Method | Description |
|--------|-------------|
| `getSPIFrequency()` | Current SPI clock frequency in Hz |
| `getCardMaxSpeed()` | Card's reported max speed from CSD |
| `getManufacturerID()` | Card manufacturer ID byte |
| `getReadTimeout()` | Read timeout from CSD in milliseconds |
| `getWriteTimeout()` | Write timeout from CSD in milliseconds |
| `isHighSpeedActive()` | TRUE if running at 50 MHz |

### SD_INCLUDE_RAW

| Method | Description |
|--------|-------------|
| `initCardOnly()` | Initialize card without mounting filesystem |
| `cardSizeSectors()` | Total 512-byte sectors on card |
| `readSectorRaw(sector, pBuf)` | Read sector at absolute LBA |
| `writeSectorRaw(sector, pBuf)` | Write sector at absolute LBA |
| `readSectorsRaw(start, count, pBuf)` | Multi-block read (CMD18) |
| `writeSectorsRaw(start, count, pBuf)` | Multi-block write (CMD25) |
| `testCMD13()` | Send CMD13, return raw R2 response |

### SD_INCLUDE_REGISTERS

| Method | Description |
|--------|-------------|
| `readCIDRaw(pBuf)` | Read 16-byte CID register |
| `readCSDRaw(pBuf)` | Read 16-byte CSD register |
| `readSCRRaw(pBuf)` | Read 8-byte SCR register |
| `readSDStatusRaw(pBuf)` | Read 64-byte SD Status register (ACMD13) |
| `getOCR()` | Get cached OCR value |
| `readVBRRaw(pBuf)` | Read 512-byte Volume Boot Record |

### SD_INCLUDE_SPEED

| Method | Description |
|--------|-------------|
| `attemptHighSpeed()` | Switch to 50 MHz with verification |
| `checkCMD6Support()` | Check if card supports CMD6 |
| `checkHighSpeedCapability()` | Query high-speed capability |

### SD_INCLUDE_DEBUG

| Method | Description |
|--------|-------------|
| `getLastCMD13()` | Last CMD13 R2 response |
| `getLastCMD13Error()` | Last non-zero CMD13 result |
| `getLastReceivedCRC()` | CRC-16 received from card |
| `getLastCalculatedCRC()` | CRC-16 calculated from data |
| `getLastSentCRC()` | CRC-16 sent with last write |
| `getCRCMatchCount()` | CRC match count |
| `getCRCMismatchCount()` | CRC mismatch count |
| `getCRCRetryCount()` | CRC retry count |
| `setCRCValidation(enabled)` | Enable/disable CRC checking |
| `getWriteDiag()` | Last write diagnostic data |
| `setTestForceReadError(count)` | Inject forced CRC mismatches on reads |
| `setTestForceWriteError(enabled)` | Inject one-shot write CRC corruption |
| `getTestErrorCount()` | Count of injected test errors triggered |
| `clearTestErrors()` | Reset all test error injection state |
| `debugGetRootSec()` | Root directory sector |
| `debugGetDirSec()` | Calling cog's directory sector |
| `debugGetVbrSec()` | VBR sector |
| `debugGetFatSec()` | FAT start sector |
| `debugGetSecPerFat()` | Sectors per FAT |
| `debugDumpRootDir()` | Print root entries to debug |
| `debugClearRootDir()` | Zero root directory (destructive) |
| `debugReadSectorSlow(sector, pBuf)` | Byte-by-byte read (no streamer) |
| `debugGetReadSectorDiag(...)` | Last readSector diagnostic data |
| `debugGetReadSectorDiagExt(...)` | Extended diagnostic data |
| `displaySector()` | Hex dump of sector buffer |
| `displayEntry()` | Hex dump of directory entry |
| `displayFAT(cluster)` | Hex dump of FAT sector containing cluster |

### SD_INCLUDE_ASYNC

| Method | Description |
|--------|-------------|
| `startReadHandle(handle, p_buffer, count) : status` | Begin async read, returns PENDING |
| `startWriteHandle(handle, p_buffer, count) : status` | Begin async write, returns PENDING |
| `isComplete() : done` | Non-blocking poll for async completion |
| `getResult() : status` | Get result and release lock |
| `cancelAsync() : status` | Cancel in-flight async operation and release lock |

### SD_INCLUDE_DEFRAG

| Method | Description |
|--------|-------------|
| `fileFragments(dev, p_path) : fragment_count` | Count non-contiguous fragments (1 = contiguous, 0 = empty) |
| `isFileContiguous(dev, p_path) : result` | TRUE if file has exactly 1 fragment |
| `createFileContiguous(dev, p_path, expected_size) : handle` | Create file with pre-allocated contiguous cluster chain |
| `compactFile(dev, p_path) : result` | Relocate fragmented file to contiguous clusters |

## Allocation and Defragmentation

### Next-Fit Allocator

The SD allocator uses a **next-fit** strategy: `allocateCluster()` begins scanning from the previously allocated cluster + 1, rather than always starting at cluster 2 (first-fit). This reduces fragmentation by avoiding filling gaps left by deleted files.

The `fsi_nxt_free` hint from the FSInfo sector seeds the starting position for new chains. On success, the hint is updated to `allocated_cluster + 1` and persists across mount/unmount cycles. At end-of-FAT, the scan wraps to cluster 2 and stops when it returns to the starting position (returning `E_DISK_FULL`).

### Compaction Algorithm (compactFile)

`compactFile()` uses a 12-step **copy-then-free** process:

1. Find the file via `searchDirectory()`
2. Verify the file is not open (`isFileOpenAny()`)
3. Check for empty file (no-op)
4. Count fragments — if already contiguous, return SUCCESS
5. Find a contiguous free run via `findContiguousRun()`
6. Copy each cluster from old chain to new contiguous location
7. Read-back verify every copied cluster (`verifyClusterCopy()`)
8. Build new FAT chain (`allocateContiguousChain()`)
9. Update directory entry to point to new first cluster
10. Free old cluster chain (`freeClusterChain()`)
11. Invalidate all sector caches
12. Return SUCCESS

Steps 8-10 form the **critical window**: if power fails after step 8 but before step 10, both chains exist. FSCK can detect this via cross-link detection.

### Pre-Allocated Contiguous Files

`createFileContiguous()` allocates a contiguous cluster chain upfront. The `h_prealloc_end` handle state tracks the last pre-allocated cluster. During writes, `do_write_h()` advances clusters by simple `+1` instead of calling `allocateCluster()`, guaranteeing zero fragmentation and avoiding FAT lookups on cluster boundaries.

---

*Part of the [P2 Dual Filesystem](../README.md) project — Iron Sheep Productions*
