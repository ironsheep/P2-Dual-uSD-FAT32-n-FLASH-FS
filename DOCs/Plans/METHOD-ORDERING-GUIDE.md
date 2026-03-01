# Method Ordering Guide — dual_sd_fat32_flash_fs.spin2

**Version:** 1.0.0
**Applies to:** `dual_sd_fat32_flash_fs.spin2` (unified dual-FS driver)
**Portable:** This guide can be carried to agents working on any Spin2 driver following the same conventions.

---

## Rationale

The driver has 300+ methods spanning two devices (SD and Flash), multiple conditional compilation blocks, and a mix of PUB API surface and PRI implementation. A canonical ordering makes the file readable top-to-bottom as a narrative:

1. **PUB before PRI** — A reader sees the full public API before any implementation details.
2. **Lifecycle first** — Mount/unmount/init before any file operations.
3. **Common operations early** — File I/O and directory operations before metadata and legacy.
4. **Conditional features last** — `#IFDEF`-gated PUB sections after core API.
5. **PRI sections mirror PUB flow** — Worker infrastructure, then handle management, then device-specific operations, ending with the lowest-level SPI layer.

---

## What Does NOT Move

These regions are anchored at fixed positions in the file and are never reordered:

| Region | Position | Contents |
|--------|----------|----------|
| File header | Lines 1-21 | `{{ }}` doc block with file description |
| `#PRAGMA` / `#IFDEF` preamble | After header | Conditional compilation setup |
| `CON` blocks | After preamble | All constant declarations |
| `STRUCT` blocks | After CON | Structure type definitions |
| `DAT` preamble | After STRUCT | Singleton state, parameter blocks, handle tables, buffers |
| `OBJ` block | Where needed | Object references (if any) |
| LICENSE block | End of file | `CON` + `{{ }}` license text — always last |

Only `PUB` and `PRI` method blocks are reordered.

---

## PUB Sections (1-11)

Methods are listed within each section in the order they should appear. Section dividers use `CON` outline labels for VS Code navigation.

### Section 1: LIFECYCLE

Core driver lifecycle — initialization, teardown, mounting, status queries.

```
null, init, stop, mount, unmount, mounted, canMount, version, format
```

### Section 2: FILE I/O

Opening, reading, writing, seeking, syncing, and closing files.

```
open, open_circular, create_file, close, flush
openFileRead, openFileWrite, createFileNew, closeFileHandle
readHandle, writeHandle
seekHandle, seek, flashSeek, tellHandle, eofHandle, fileSizeHandle
syncHandle, syncAllHandles, copyFile
```

### Section 3: DIRECTORY

Directory navigation and enumeration.

```
openDirectory, readDirectoryHandle, closeDirectoryHandle
readDirectory (legacy), newDirectory, changeDirectory, directory
```

### Section 4: METADATA

File metadata queries and modifications.

```
exists, file_size, file_size_unused, rename, deleteFile, moveFile
freeSpace, stats, setDate, serial_number, TEST_count_file_bytes
```

### Section 5: BYTE/WORD/LONG/STRING I/O

Typed read/write helpers built on top of readHandle/writeHandle.

```
wr_byte, rd_byte, wr_word, rd_word, wr_long, rd_long, wr_str, rd_str
```

### Section 6: LEGACY

Older API methods retained for backward compatibility. These operate on the "current" file/directory state rather than explicit handles.

```
fileName, fileSize, attributes, volumeLabel, setVolumeLabel, syncDirCache
```

### Section 7: ERROR/DIAGNOSTIC

Error reporting and stack guard checking. The `DAT` block containing `error_strings` moves with `string_for_error` into this section.

```
error, string_for_error (+ DAT error_strings), checkStackGuard
```

### Section 8: #IFDEF SD_INCLUDE_RAW

Raw sector access methods — gated behind `SD_INCLUDE_RAW`.

```
#IFDEF SD_INCLUDE_RAW
readSectorRaw, writeSectorRaw, readSectorsRaw, writeSectorsRaw, readVBRRaw
#ENDIF
```

### Section 9: #IFDEF SD_INCLUDE_REGISTERS

Card register access methods — gated behind `SD_INCLUDE_REGISTERS`.

```
#IFDEF SD_INCLUDE_REGISTERS
readCIDRaw, readCSDRaw, readSCRRaw, readSDStatusRaw, getOCR
#ENDIF
```

### Section 10: #IFDEF SD_INCLUDE_SPEED

High-speed mode control — gated behind `SD_INCLUDE_SPEED`. Note: ungated speed getters (getSPIFrequency, getCardMaxSpeed, etc.) appear outside the `#IFDEF` block, immediately after it.

```
#IFDEF SD_INCLUDE_SPEED
attemptHighSpeed, setSPISpeed, checkCMD6Support, checkHighSpeedCapability
#ENDIF

' Ungated speed/register getters (always available)
getSPIFrequency, getCardMaxSpeed, getManufacturerID, getReadTimeout, getWriteTimeout, isHighSpeedActive
```

### Section 11: #IFDEF SD_INCLUDE_DEBUG

Debug and diagnostic methods — gated behind `SD_INCLUDE_DEBUG`.

```
#IFDEF SD_INCLUDE_DEBUG
getWriteDiag, getLastCMD13, getLastCMD13Error
getLastReceivedCRC, getLastCalculatedCRC, getLastSentCRC
getCRCMatchCount, getCRCMismatchCount, getCRCRetryCount
setCRCValidation, setTestForceReadError, setTestForceWriteError
getTestErrorCount, clearTestErrors
debugGetRootSec, debugGetDirSec, debugGetVbrSec, debugGetFatSec, debugGetSecPerFat
debugClearRootDir, debugReadSectorSlow
debugGetReadSectorDiag, debugGetReadSectorDiagExt
debugDumpRootDir, displaySector, displayEntry, displayFAT
#ENDIF
```

---

## PRI Sections (A-M)

Private implementation methods. Ordered from highest-level infrastructure down to lowest-level hardware.

### Section A: Worker Infrastructure

The core worker cog and command dispatch. These are the foundation everything else calls through.

```
set_error, fs_worker, send_command
```

### Section B: Handle Management

Allocation, validation, and buffer access for the shared handle pool.

```
allocateHandle, freeHandle, validateHandle, isFileOpenForWrite
getHandleBuffer, initHandleTable
```

### Section C: Struct Accessors

Overlay accessors for MBR, VBR, FSInfo, and directory entry structures. These are thin wrappers around STRUCT field access.

```
partType, partLbaStart
vbrBytesPerSec, vbrSecPerClus, vbrReservedSec, vbrNumFats, vbrSecPerFat32, vbrFsInfoSec, vbrVolLabelAddr
fsiLeadSig, fsiStructSig, fsiFreeClusters, fsiNextFreeHint, fsiSetFreeClusters, fsiSetNextFreeHint
dirEntAttr, dirEntStartClus, dirEntFileSize
dirEntSetAttr, dirEntSetStartClus, dirEntSetFileSize, dirEntAddFileSize
dirEntSetCreateStamp, dirEntSetModifyStamp
```

### Section D: SD Worker Operations

All `do_*` methods that run inside the worker cog to handle SD filesystem commands. Includes `#IFDEF`-gated `do_*` methods within matching guards.

```
do_mount, do_unmount, do_init_card_only, do_get_card_size
do_open, do_close
do_open_read, do_open_write, do_create
do_close_h, do_read_h, do_write_h
do_seek_h, do_sync_h, do_sync_all
do_open_dir, do_read_dir_h, do_close_dir_h
do_newfile, do_newdir, do_delete, do_sd_file_size_unused
do_chdir, do_freespace, do_sync, do_rename, do_set_vol_label, do_movefile
do_readdir

#IFDEF SD_INCLUDE_RAW
do_read_scr, do_read_cid, do_read_csd, do_read_sd_status
#ENDIF

#IFDEF SD_INCLUDE_SPEED
do_test_cmd13, do_attempt_high_speed, do_check_hs_capability
#ENDIF
```

### Section E: SPI Bus Switching

Methods that manage switching the shared SPI bus between SD and Flash devices.

```
switch_to_flash, switch_to_sd, reinitCard
```

### Section F: Flash SPI Engine

Low-level Flash SPI communication — command send, data transfer, block read/write/erase.

```
fl_command, fl_send, fl_receive, fl_wait
fl_read_block_id, fl_read_block_addr
fl_program_block, fl_activate_block, fl_format
fl_cancel_block, fl_program_bit
fl_next_active_cycle, fl_block_crc
fl_activate_updated_block, fl_check_block_fix_dupe_id
fl_trace_file_set_flags
```

### Section G: Flash Mount

Flash device mounting, capability checking, and serial number retrieval.

```
do_flash_mount, fl_can_mount, fl_check_block_read_only, do_flash_serial_number
```

### Section H: Flash CWD Emulation

Flash current-working-directory path management (emulates SD's chdir).

```
fl_get_cwd, fl_prepend_cwd, fl_change_cwd, fl_cwd_matches
```

### Section I: Flash Handle/Buffer Management

Flash-specific handle allocation, error storage, and buffer pool management.

```
fl_set_error, fl_filename_crc, fl_filename_pointer, fl_buffer_pointer
fl_alloc_buffer, fl_free_buffer, fl_has_free_buffer
fl_ensure_handle_mode, fl_has_free_handle, fl_new_handle, fl_free_handle
```

### Section J: Flash File Operations

All Flash file-level operations — open, close, read, write, seek, delete, rename, stats, directory enumeration, and file creation.

```
fl_build_head_block, fl_is_file_open, fl_exists_no_lock
fl_blocks_free, fl_available_blocks, fl_next_available_block_id
fl_start_write, fl_is_old_format_file_head, fl_get_file_head_signature
fl_TEST_count_file_bytes, fl_count_file_bytes, fl_count_file_bytes_id
fl_locate_file_byte, fl_start_modify, fl_seek_no_locks
fl_next_block_address, fl_write_block, fl_rewrite_block
fl_delete_chain_from_id, fl_froncate_file
fl_rd_byte_no_locks, fl_wr_byte_no_locks, fl_rd_str
fl_file_size_unused, fl_close_no_lock
fl_finish_open_read, fl_finish_open_write, fl_finish_open_append, fl_finish_open_readwrite
fl_open, fl_open_circular, fl_close, fl_flush
fl_read, fl_write, fl_seek, fl_delete, fl_rename
fl_exists, fl_file_size, fl_stats, fl_directory, fl_create_file
```

### Section K: SD Directory/FAT Operations

SD directory search, FAT chain management, cluster allocation, and sector traversal.

```
searchDirectory, firstCluster, readFat, allocateCluster
clearCluster, readNextSector, followFatChain
updateFSInfo, countFreeClusters
```

### Section L: SD Conversion Helpers

Arithmetic conversions between byte addresses, sectors, and clusters.

```
byte2clus, sec2clus, clus2byte, clus2sec
```

### Section M: SD SPI Layer

Lowest-level SD SPI communication — pin initialization, data transfer, card initialization, command send, sector read/write, and response waiting. Includes `#IFDEF`-gated PRI methods within matching guards.

```
initSPIPins, configureEvent, do_set_spi_speed, calcDataCRC
sp_transfer, sp_transfer_8, sp_transfer_32
initCard, cmd
readSector, transfer, readSectors
writeSector, writeSectors
waitR1Response, waitDataToken, waitDataResponse, waitBusyComplete
sendStopTransmission, recoverToIdle, checkCardStatus

' Ungated card identification / register read PRIs (called from ungated initCard and PUB wrappers)
readCSD, readCID, parseTransSpeed, parseMfrId, parseTimeouts, identifyCard, setOptimalSpeed
readSCR, readSDStatus

#IFDEF SD_INCLUDE_SPEED
sendCMD6, queryHighSpeedSupport, switchToHighSpeed
#ENDIF

#IFDEF SD_INCLUDE_DEBUG
readSectorSlow
#ENDIF
```

---

## #IFDEF Block Rules

1. **Each `#IFDEF` block keeps its PUBs and PRIs together** within matching `#IFDEF`/`#ENDIF` guards. A PUB section and its associated PRI section may be in separate `#IFDEF` blocks (e.g., PUB Section 8 and the `do_read_scr`/`do_read_cid` PRIs in Section D).

2. **`fs_worker` has internal `#IFDEF` case blocks** — these dispatch entries do NOT move. The worker's case statement references forward-declared methods, which is fine in Spin2.

3. **Ungated methods must NOT accidentally land inside a conditional block.** Methods like `readCSD`, `readCID`, `identifyCard`, `setOptimalSpeed`, `getSPIFrequency`, `getCardMaxSpeed` etc. that are called from both gated and ungated code must remain outside `#IFDEF` guards, OR must be inside the correct guard that is always active when they are called.

4. **When in doubt, check callers.** If a method is called from ungated code, it must itself be ungated. If it is only called from within one `#IFDEF` block, it belongs in that block.

---

## Section Dividers

Each section boundary uses a `CON` outline label for VS Code navigation:

```spin2
CON ' ═══════════════════════════════════════════════════════════════════════════
    ' SECTION NAME
    ' ═══════════════════════════════════════════════════════════════════════════
```

The first `CON` line appears in the VS Code Outline panel. The indented lines provide context when reading the source.

---

## Applying to Other Drivers

This ordering scheme adapts to any Spin2 driver:

1. Replace device-specific section names (Flash/SD) with the driver's subsystems.
2. Keep the PUB-before-PRI rule and the lifecycle-first ordering.
3. Keep `#IFDEF` blocks self-contained with their PUBs and PRIs.
4. Keep the lowest-level hardware layer (SPI, I2C, etc.) as the last PRI section.
