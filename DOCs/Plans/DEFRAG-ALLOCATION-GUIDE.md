# Engineering Guide: Defragmentation & Next-Fit Allocation

**Source commits**: `a58fee0` (v1.4.1) and `f83ea92` (v1.4.2)
**Applies to**: micro_sd_fat32_fs.spin2 (or sister driver equivalent)
**Prerequisite**: Working FAT32 driver with allocateCluster(), readFat(), writeSector(), readSector(), searchDirectory(), firstCluster(), and the handle system

---

## What Changed and Why

Two problems existed in the allocator and no defrag support existed at all:

1. **First-fit allocation wasted free space**: `allocateCluster()` always started scanning at cluster 2, filling gaps left by deleted files and creating fragmentation. Files written after deletions would scatter across the disk even when large contiguous runs existed further out.

2. **No defrag capability**: Once files were fragmented, there was no way to compact them. Fragmented files can't use CMD18/CMD25 multi-block transfers (the fast path), falling back to single-sector operations (~30% slower).

The fix has two independent parts:
- **Next-fit allocator** (unconditional, benefits all users): `allocateCluster()` starts scanning after the previously allocated cluster, wraps around to cluster 2 at end-of-FAT, and persists the `fsi_nxt_free` hint across mount/unmount cycles.
- **Defrag API** (gated by `SD_INCLUDE_DEFRAG`): Four new public methods — `fileFragments()`, `isFileContiguous()`, `compactFile()`, `createFileContiguous()` — plus seven new internal helpers.

---

## Part 1: Next-Fit Allocator (Unconditional)

This change is **not gated by any feature flag** — it improves allocation for every user.

### 1.1 Concept

Old behavior: scan FAT from cluster 2 every time (first-fit).
New behavior: scan from `previous_cluster + 1` (or `fsi_nxt_free` for new chains), wrap to cluster 2 if end-of-FAT is reached, stop when back at start (next-fit with wrap-around).

### 1.2 Changes to allocateCluster()

**Signature change** — add new locals:

```spin2
PRI allocateCluster(cluster) : result | fat_idx, buf_idx, high_bits, start_fat_idx, fat_limit, wrapped
```

The three new locals are:
- `start_fat_idx` — byte index where scan began (for wrap-around termination)
- `fat_limit` — end of FAT in bytes (`sec_per_fat << SECTOR_SHIFT`)
- `wrapped` — boolean, TRUE after scan wraps from end-of-FAT back to cluster 2

**Starting position logic** — replaces the old `fat_idx := 8`:

```spin2
  ' Next-fit: choose starting scan position
  if cluster > 0
    fat_idx := (cluster + 1) << 2                  ' Start after previous cluster
  elseif fsi_nxt_free <> $FFFF_FFFF and fsi_nxt_free >= ROOT_CLUSTER
    fat_idx := fsi_nxt_free << 2                   ' Use FSInfo hint for new chains
  else
    fat_idx := 8                                   ' Default: cluster 2

  fat_limit := sec_per_fat << SECTOR_SHIFT         ' End of FAT in bytes
  if fat_idx >= fat_limit                           ' Guard: if start is past end, wrap to cluster 2
    fat_idx := 8
  if test_max_clusters > 0 and (fat_idx >> 2) >= test_max_clusters
    fat_idx := 8                                   ' Guard: if start is past test limit, wrap
  start_fat_idx := fat_idx                         ' Remember where we started
  wrapped := false
```

**Pre-load sector at starting position** — the old code always loaded the first FAT sector. New code loads the sector that contains the starting cluster:

```spin2
  if readSector(fat_sec + (fat_idx >> SECTOR_SHIFT), BUF_FAT) < 0
    debug[CH_SECTOR]("  [allocateCluster] FAT pre-load FAILED")
    result := E_IO_ERROR
```

**Wrap-around at sector boundary** — at each sector boundary check, add end-of-FAT and wrap detection:

```spin2
      if fat_idx & SECTOR_OFFSET_MASK == 0 and fat_idx > 0
        if fat_idx >= fat_limit                     ' past end of FAT?
          if wrapped                                '   already wrapped — entire FAT scanned
            result := E_DISK_FULL
            quit
          fat_idx := 8                             '   wrap to cluster 2
          wrapped := true
        if wrapped and fat_idx >= start_fat_idx     ' wrapped and reached starting point?
          result := E_DISK_FULL
          quit
        if readSector(fat_sec + fat_idx >> SECTOR_SHIFT, BUF_FAT) < 0
          ...
```

**Wrap-around at entry boundary** — after `fat_idx += 4` (advancing to next cluster cell), add a second wrap check:

```spin2
      fat_idx += 4
      if fat_idx >= fat_limit and not wrapped       ' past end of FAT? wrap around
        fat_idx := 8
        wrapped := true
        if readSector(fat_sec, BUF_FAT) < 0        '   pre-load first FAT sector after wrap
          debug[CH_SECTOR]("  [allocateCluster] FAT wrap pre-load FAILED")
          result := E_IO_ERROR
          quit
      elseif wrapped and fat_idx >= start_fat_idx   ' wrapped and back to start?
        result := E_DISK_FULL
        quit
```

**Update fsi_nxt_free on success** — when a free cluster is found and allocated, add this line before the `quit`:

```spin2
        fsi_nxt_free := result + 1                  ' update next-free hint
        quit
```

### 1.3 v1.4.2 Bug Fix: test_max_clusters Wrap-Around

The original v1.4.1 code had `result := E_IO_ERROR; quit` when `test_max_clusters` was hit mid-scan. This was wrong — it should wrap instead of failing. The fix (from commit `f83ea92`):

**Replace** the test_max_clusters block inside the scan loop:

```spin2
      ' OLD (v1.4.1 — BUG):
      if test_max_clusters > 0 and (fat_idx >> 2) >= test_max_clusters
        result := E_IO_ERROR
        quit

      ' NEW (v1.4.2 — CORRECT):
      if test_max_clusters > 0 and (fat_idx >> 2) >= test_max_clusters
        if wrapped                                  ' already wrapped — all visible clusters scanned
          result := E_DISK_FULL
          quit
        fat_idx := 8                               ' wrap to cluster 2
        buf_idx := 8
        wrapped := true
        if fat_idx >= start_fat_idx                 ' started at cluster 2? nowhere left to scan
          result := E_DISK_FULL
          quit
```

**Key difference**: the error code changes from `E_IO_ERROR` to `E_DISK_FULL` (correct — this is a full-disk condition, not an I/O error), and the behavior changes from failing to wrapping.

---

## Part 2: Feature Flag and Constants (SD_INCLUDE_DEFRAG)

### 2.1 Conditional Compilation

Add `SD_INCLUDE_DEFRAG` to the feature flag block:

```spin2
' In the header comment block listing available flags:
'   #pragma exportdef SD_INCLUDE_DEFRAG     ' Defragmentation: fileFragments, compactFile, createFileContiguous

' Inside the SD_INCLUDE_ALL umbrella:
#ifdef SD_INCLUDE_ALL
  ...existing flags...
  #ifndef SD_INCLUDE_DEFRAG
  #define SD_INCLUDE_DEFRAG
  #endif
#endif
```

### 2.2 New Command Codes

Add inside the existing command codes CON block, gated by `SD_INCLUDE_DEFRAG`:

```spin2
#ifdef SD_INCLUDE_DEFRAG
  CMD_CREATE_CONTIGUOUS = 47  ' Create file with pre-allocated contiguous chain: param0=path ptr, param1=file_size, returns data0=handle
  CMD_COMPACT_FILE      = 48  ' Defragment a single file: param0=path ptr
  CMD_FILE_FRAGMENTS    = 49  ' Count file fragmentation: param0=path ptr, returns data0=fragment_count
#endif
```

**IMPORTANT**: Adjust the command code numbers to be sequential after whatever the last existing command code is in the target driver. The numbers 47/48/49 are specific to the uSD driver where CMD_SET_VOL_LABEL = 46.

### 2.3 New Error Codes

Add inside the error codes CON block, gated by `SD_INCLUDE_DEFRAG`:

```spin2
#ifdef SD_INCLUDE_DEFRAG
  E_NO_CONTIGUOUS_SPACE  = -61  ' No contiguous run of sufficient length
  E_FILE_OPEN_FOR_COMPACT = -62 ' File is open (cannot compact while open)
  E_VERIFY_FAILED        = -63  ' Read-back verification failed after compact
#endif
```

**IMPORTANT**: Adjust numeric values to avoid collisions with existing error codes in the target driver.

### 2.4 New DAT State

Add after `h_buf_sector` in the handle state section:

```spin2
#ifdef SD_INCLUDE_DEFRAG
  h_prealloc_end LONG   0[MAX_OPEN_FILES]  ' Last pre-allocated cluster (0 = normal handle)
#endif
```

This tracks the last cluster in a pre-allocated contiguous chain. When non-zero, `do_write_h()` advances clusters by simple `+1` instead of calling `allocateCluster()`.

---

## Part 3: Public API Methods (4 methods)

All four methods follow the standard public API pattern: `send_command()` → check `pb_status` → `set_error()` on failure → return result. Place them in a new section gated by `#ifdef SD_INCLUDE_DEFRAG`.

### 3.1 fileFragments(p_path) : fragment_count

```spin2
PUB fileFragments(p_path) : fragment_count
'' Count the number of non-contiguous fragments in a file's cluster chain.
'' A contiguous file returns 1. An empty file returns 0.
''
'' @param p_path - Pointer to null-terminated filename string
'' @returns fragment_count - Fragment count (1 = contiguous), 0 if empty, or negative error code

  fragment_count := send_command(CMD_FILE_FRAGMENTS, p_path, 0, 0, 0)
  if pb_status < 0
    set_error(pb_status)
    fragment_count := pb_status
  else
    fragment_count := pb_data0
```

### 3.2 isFileContiguous(p_path) : result

```spin2
PUB isFileContiguous(p_path) : result
'' Check if a file's clusters are stored contiguously on disk.
'' Convenience wrapper around fileFragments().
''
'' @param p_path - Pointer to null-terminated filename string
'' @returns result - TRUE if contiguous (fragment_count == 1), FALSE otherwise, or negative error code

  result := fileFragments(p_path)
  if result >= 0
    result := (result == 1)
```

### 3.3 createFileContiguous(p_path, file_size) : handle

```spin2
PUB createFileContiguous(p_path, file_size) : handle
'' Create a new file with a pre-allocated contiguous cluster chain.
'' The file's clusters are allocated upfront so writeHandle() never fragments.
'' If insufficient contiguous space exists, returns E_NO_CONTIGUOUS_SPACE.
''
'' @param p_path - Pointer to null-terminated filename string
'' @param file_size - Expected file size in bytes (determines cluster count)
'' @returns handle - Handle (0 to MAX_OPEN_FILES-1) on success, or negative error code

  handle := send_command(CMD_CREATE_CONTIGUOUS, p_path, file_size, 0, 0)
  if pb_status < 0
    set_error(pb_status)
    handle := pb_status
  else
    handle := pb_data0
```

### 3.4 compactFile(p_path) : result

```spin2
PUB compactFile(p_path) : result
'' Relocate a file's clusters into a contiguous chain on disk.
'' The file must not be open (no active handles). If already contiguous, returns SUCCESS (no-op).
'' Uses copy-then-free strategy: file is always readable during compaction.
'' Read-back verification is performed after every copy.
''
'' @param p_path - Pointer to null-terminated filename string
'' @returns result - SUCCESS, E_FILE_NOT_FOUND, E_FILE_OPEN_FOR_COMPACT, E_NO_CONTIGUOUS_SPACE, E_VERIFY_FAILED, E_IO_ERROR

  result := send_command(CMD_COMPACT_FILE, p_path, 0, 0, 0)
  if pb_status < 0
    set_error(pb_status)
    result := pb_status
  else
    result := pb_status
```

---

## Part 4: Worker Dispatch

### 4.1 Mode Gate Update

The filesystem mode check in `fs_worker()` must include the new command range:

```spin2
#ifdef SD_INCLUDE_DEFRAG
    if (cur_cmd >= CMD_NEWDIR and cur_cmd <= CMD_MOVEFILE) or (cur_cmd >= CMD_OPEN_READ and cur_cmd <= CMD_SET_VOL_LABEL) or (cur_cmd >= CMD_CREATE_CONTIGUOUS and cur_cmd <= CMD_FILE_FRAGMENTS)
#else
    if (cur_cmd >= CMD_NEWDIR and cur_cmd <= CMD_MOVEFILE) or (cur_cmd >= CMD_OPEN_READ and cur_cmd <= CMD_SET_VOL_LABEL)
#endif
```

**Adapt the command ranges** to match whatever CMD_xxx constants exist in the target driver.

### 4.2 Dispatch Cases

Add inside the `case` block in `fs_worker()`, gated by `#ifdef SD_INCLUDE_DEFRAG`:

```spin2
#ifdef SD_INCLUDE_DEFRAG
      CMD_FILE_FRAGMENTS:
        pb_data0 := do_file_fragments(pb_param0)
        pb_status := pb_data0 < 0 ? pb_data0 : SUCCESS

      CMD_COMPACT_FILE:
        pb_status := do_compact_file(pb_param0)

      CMD_CREATE_CONTIGUOUS:
        pb_data0 := do_create_contiguous(pb_param0, pb_param1)
        pb_status := pb_data0 < 0 ? pb_data0 : SUCCESS
#endif
```

---

## Part 5: Internal Helpers — Unconditional (1 method)

### 5.1 freeClusterChain(first_cluster) : result

This was extracted from the inline code in `do_delete()`. It is **not gated by SD_INCLUDE_DEFRAG** because `do_delete()` uses it unconditionally.

```spin2
PRI freeClusterChain(first_cluster) : result | clus, next_clus, last_clus, fat_sector, loop_count
' Walk a FAT chain and mark every cluster as free (zero entry).
' Writes both FAT1 and FAT2 (mirror) at sector boundaries and at end.
' Used by do_delete() and compactFile().
'
' @param first_cluster - First cluster of the chain to free
' @returns result - SUCCESS or E_IO_ERROR on safety limit

  result := SUCCESS
  clus := first_cluster
  last_clus := first_cluster
  loop_count := 0
  if clus >= ROOT_CLUSTER
    repeat
      next_clus := long[readFat(clus)]
      long[@fat_buf + ((clus << 2) & SECTOR_OFFSET_MASK)] := 0    ' zero the FAT entry
      if fsi_free_count <> $FFFF_FFFF                              ' track free count
        fsi_free_count++
      last_clus := clus
      if (next_clus >> 7) - (clus >> 7) <> 0                      ' different FAT sector?
        fat_sector := clus >> 7
        writeSector(fat_sector + fat_sec, BUF_FAT)
        writeSector(fat_sector + fat2_sec, BUF_FAT)
      clus := next_clus
      loop_count++
      if loop_count > 100000                                       ' safety limit
        result := E_IO_ERROR
        quit
    until next_clus +>= FAT32_EOC_MIN
    ' Always write the FAT sector containing the last freed cluster
    if result == SUCCESS
      fat_sector := last_clus >> 7
      writeSector(fat_sector + fat_sec, BUF_FAT)
      writeSector(fat_sector + fat2_sec, BUF_FAT)
```

### 5.2 Update do_delete() to Use freeClusterChain()

Replace the inline cluster-freeing loop in `do_delete()` with a single call:

```spin2
    ' Only deallocate clusters if file has data (cluster >= 2)
    result := freeClusterChain(firstCluster())
```

This replaces ~18 lines of inline FAT walking with one call. The behavior is identical.

---

## Part 6: Internal Helpers — Gated by SD_INCLUDE_DEFRAG (7 methods)

All methods in this section are gated by `#ifdef SD_INCLUDE_DEFRAG`.

### 6.1 do_file_fragments(p_path) : count

```spin2
PRI do_file_fragments(p_path) : count | start_cluster
' Worker-side handler for CMD_FILE_FRAGMENTS.
'
' @param p_path - Pointer to null-terminated filename string
' @returns count - Fragment count (1 = contiguous), 0 if empty, or negative error code

  if searchDirectory(p_path) == 0
    count := E_FILE_NOT_FOUND
  else
    start_cluster := firstCluster()
    if start_cluster < ROOT_CLUSTER
      count := 0                                    ' empty file (no clusters)
    else
      count := countFileFragments(start_cluster)
```

### 6.2 countFileFragments(first_cluster) : count

```spin2
PRI countFileFragments(first_cluster) : count | clus, next_clus, loop_count
' Count non-contiguous fragments in a FAT chain.
' A contiguous file = 1 fragment. Each gap (next != current+1) adds one.
'
' @param first_cluster - First cluster of the file's chain
' @returns count - Fragment count (1 = contiguous), 0 if empty chain

  if first_cluster < ROOT_CLUSTER
    count := 0
    return
  count := 1
  clus := first_cluster
  loop_count := 0
  repeat
    next_clus := long[readFat(clus)] & FAT32_ENTRY_MASK
    if next_clus >= FAT32_EOC_MIN
      quit                                          ' end of chain
    if next_clus < ROOT_CLUSTER                     ' bad reference
      quit
    if next_clus <> clus + 1                        ' non-contiguous?
      count++
    clus := next_clus
    loop_count++
    if loop_count > 100000                          ' safety limit
      quit
```

### 6.3 findContiguousRun(cluster_count) : first_cluster

```spin2
PRI findContiguousRun(cluster_count) : first_cluster | fat_idx, entry, run_start, run_length
' Scan FAT for a contiguous run of N free clusters.
' Linear scan from cluster 2 through end of FAT.
'
' @param cluster_count - Number of consecutive free clusters needed
' @returns first_cluster - First cluster of the run, or E_NO_CONTIGUOUS_SPACE

  run_start := ROOT_CLUSTER
  run_length := 0
  fat_idx := ROOT_CLUSTER * 4                       ' start at cluster 2
  repeat
    if fat_idx & SECTOR_OFFSET_MASK == 0            ' at sector boundary?
      if fat_idx >> SECTOR_SHIFT >= sec_per_fat     '   past end of FAT?
        quit
      if readSector(fat_sec + fat_idx >> SECTOR_SHIFT, BUF_FAT) < 0
        debug[CH_SECTOR]("  [findContiguousRun] FAT read FAILED")
        first_cluster := E_IO_ERROR
        fat_sec_in_buf := -1
        return
    if test_max_clusters > 0 and (fat_idx >> 2) >= test_max_clusters
      quit                                          ' test hook: artificial limit
    entry := long[@fat_buf + (fat_idx & SECTOR_OFFSET_MASK)]
    if (entry & FAT32_ENTRY_MASK) == 0              ' free cluster?
      if run_length == 0
        run_start := fat_idx >> 2                   '   start new run
      run_length++
      if run_length >= cluster_count                ' found enough?
        first_cluster := run_start
        fat_sec_in_buf := -1
        return
    else
      run_length := 0                               ' reset run
    fat_idx += 4
  first_cluster := E_NO_CONTIGUOUS_SPACE
  fat_sec_in_buf := -1
```

**Note**: `fat_sec_in_buf := -1` invalidates the FAT buffer cache before returning. This is essential because `findContiguousRun` reads FAT sectors directly into `fat_buf`, and subsequent FAT operations must not assume the buffer still holds a valid sector.

### 6.4 allocateContiguousChain(first_cluster, count) : result

```spin2
PRI allocateContiguousChain(first_cluster, count) : result | clus, fat_idx, buf_idx, high_bits, prev_fat_sector
' Mark N consecutive clusters as a linked sequential chain in FAT.
' Writes both FAT1 and FAT2 (mirror). Preserves high 4 reserved bits.
'
' @param first_cluster - First cluster of the contiguous run
' @param count - Number of clusters to link
' @returns result - SUCCESS or E_IO_ERROR

  result := SUCCESS
  prev_fat_sector := -1
  repeat clus from first_cluster to first_cluster + count - 1
    fat_idx := clus << 2
    buf_idx := fat_idx & SECTOR_OFFSET_MASK
    ' Load FAT sector if needed
    if (fat_idx >> SECTOR_SHIFT) <> prev_fat_sector
      if prev_fat_sector >= 0                       ' write previous sector before loading new one
        writeSector(fat_sec + prev_fat_sector, BUF_FAT)
        writeSector(fat2_sec + prev_fat_sector, BUF_FAT)
      prev_fat_sector := fat_idx >> SECTOR_SHIFT
      if readSector(fat_sec + prev_fat_sector, BUF_FAT) < 0
        debug[CH_SECTOR]("  [allocateContiguousChain] FAT read FAILED at cluster ", udec_(clus))
        result := E_IO_ERROR
        quit
    ' Write chain link or EOC
    high_bits := long[@fat_buf + buf_idx] & FAT32_RESERVED_MASK    ' preserve high 4 bits
    if clus < first_cluster + count - 1
      long[@fat_buf + buf_idx] := high_bits | ((clus + 1) & FAT32_ENTRY_MASK)  ' link to next
    else
      long[@fat_buf + buf_idx] := high_bits | FAT32_EOC_MARK       ' end of chain
  ' Write final FAT sector
  if prev_fat_sector >= 0 and result == SUCCESS
    writeSector(fat_sec + prev_fat_sector, BUF_FAT)
    writeSector(fat2_sec + prev_fat_sector, BUF_FAT)
  ' Update free cluster tracking
  if result == SUCCESS
    if fsi_free_count <> $FFFF_FFFF
      fsi_free_count -= count
    fsi_nxt_free := first_cluster + count           ' update next-free hint
```

### 6.5 do_create_contiguous(p_path, file_size) : handle

This is the most complex worker handler. It combines contiguous chain allocation with directory entry creation.

```spin2
PRI do_create_contiguous(p_path, file_size) : handle | cluster_count, new_first, temp, first_cluster
' Worker-side handler for CMD_CREATE_CONTIGUOUS.
' Creates a new file with a pre-allocated contiguous cluster chain.
'
' @param p_path - Pointer to null-terminated filename string
' @param file_size - Expected file size in bytes
' @returns handle - Handle on success, negative error code on failure

  ' Calculate clusters needed
  cluster_count := (file_size + (sec_per_clus << SECTOR_SHIFT) - 1) / (sec_per_clus << SECTOR_SHIFT)
  if cluster_count < 1
    cluster_count := 1                              ' minimum 1 cluster

  ' Find contiguous run
  new_first := findContiguousRun(cluster_count)
  if new_first < 0
    handle := new_first                             ' E_NO_CONTIGUOUS_SPACE or E_IO_ERROR
    return

  ' Allocate the contiguous chain in FAT
  temp := allocateContiguousChain(new_first, cluster_count)
  if temp < 0
    handle := temp
    return

  ' Allocate a handle slot
  handle := allocateHandle()
  if handle < 0
    debug[CH_FILE]("  [do_create_contiguous] No free handles")
    return

  ' Check file doesn't already exist
  if searchDirectory(p_path)
    debug[CH_FILE]("  [do_create_contiguous] File already exists: ", zstr_(p_path))
    freeHandle(handle)
    handle := E_FILE_EXISTS
    return
  if entry_address == 0
    debug[CH_FILE]("  [do_create_contiguous] entry_address=0 -- path not valid")
    freeHandle(handle)
    handle := E_FILE_NOT_FOUND
    return

  ' Check if directory needs a new cluster for the entry
  temp := (entry_address + cluster_offset << SECTOR_SHIFT) & (sec_per_clus << SECTOR_SHIFT - 1)
  if temp == (sec_per_clus << SECTOR_SHIFT - DIR_ENTRY_SIZE)
    if dir_buf[LAST_DIR_ENTRY_OFFSET] == $00
      temp := allocateCluster(byte2clus(entry_address))
      if temp < 0
        debug[CH_FILE]("  [do_create_contiguous] Failed to allocate dir cluster")
        freeHandle(handle)
        handle := E_DISK_FULL
        return
      else
        clearCluster(temp)

  ' Set up directory entry
  first_cluster := new_first
  dirEntSetAttr(@entry_buffer, ATTR_ARCHIVE)
  dirEntSetCreateStamp(@entry_buffer, date_stamp)
  dirEntSetStartClus(@entry_buffer, first_cluster)
  dirEntSetModifyStamp(@entry_buffer, date_stamp)
  dirEntSetFileSize(@entry_buffer, 0)

  ' Write directory entry to disk
  if readSector(entry_address >> SECTOR_SHIFT, BUF_DIR) < 0
    debug[CH_FILE]("  [do_create_contiguous] Directory read FAILED")
    freeHandle(handle)
    handle := E_IO_ERROR
    return
  bytemove(@dir_buf + (entry_address & SECTOR_OFFSET_MASK), @entry_buffer, DIR_ENTRY_SIZE)
  if writeSector(entry_address >> SECTOR_SHIFT, BUF_DIR) < 0
    debug[CH_FILE]("  [do_create_contiguous] Directory write FAILED")
    freeHandle(handle)
    handle := E_IO_ERROR
    return

  ' Populate handle state
  h_start_clus[handle] := first_cluster
  h_size[handle] := 0
  h_attr[handle] := ATTR_ARCHIVE
  h_dir_sector[handle] := entry_address >> SECTOR_SHIFT
  h_dir_offset[handle] := entry_address & SECTOR_OFFSET_MASK
  h_cluster[handle] := first_cluster
  h_sector[handle] := clus2sec(first_cluster)
  h_position[handle] := 0
  h_buf_sector[handle] := -1
  h_flags[handle] := HF_WRITE
  h_prealloc_end[handle] := new_first + cluster_count - 1
```

**IMPORTANT**: `do_create_contiguous()` closely mirrors the existing `do_create()` (for `createFileNew()`). The key differences are:
1. It allocates the contiguous chain *before* creating the directory entry
2. It sets `h_prealloc_end[handle]` so writes skip `allocateCluster()`
3. The file size in the directory entry starts at 0 (grows as data is written)

### 6.6 do_compact_file(p_path) : result — 12-Step Process

```spin2
PRI do_compact_file(p_path) : result | dir_sec, dir_off, start_cluster, file_size, cluster_count, new_first, clus, next_clus, idx, frag_count
' Worker-side handler for CMD_COMPACT_FILE.
' Relocates a file's clusters into a contiguous chain using copy-then-free.
' 12-step process with mandatory read-back verification.

  ' Step 1: Find the file
  if searchDirectory(p_path) == 0
    result := E_FILE_NOT_FOUND
    return
  dir_sec := entry_address >> SECTOR_SHIFT
  dir_off := entry_address & SECTOR_OFFSET_MASK
  start_cluster := firstCluster()
  file_size := dirEntFileSize(@entry_buffer)

  ' Step 2: Check file is not open
  if isFileOpenAny(dir_sec, dir_off)
    result := E_FILE_OPEN_FOR_COMPACT
    return

  ' Step 3: Empty file — nothing to compact
  if file_size == 0
    result := SUCCESS
    return

  ' Step 4: Count clusters and check fragmentation
  frag_count := countFileFragments(start_cluster)
  if frag_count == 1
    result := SUCCESS                               ' already contiguous
    return
  ' Count clusters by walking the chain
  cluster_count := 0
  clus := start_cluster
  repeat
    cluster_count++
    next_clus := long[readFat(clus)] & FAT32_ENTRY_MASK
    if next_clus >= FAT32_EOC_MIN
      quit
    if next_clus < ROOT_CLUSTER
      quit
    clus := next_clus

  ' Step 5: Find contiguous free space
  new_first := findContiguousRun(cluster_count)
  if new_first < 0
    result := new_first                             ' E_NO_CONTIGUOUS_SPACE or E_IO_ERROR
    return

  ' Step 6: Copy phase — walk old chain, copy each cluster to new location
  clus := start_cluster
  idx := 0
  repeat
    result := copyClusterData(clus, new_first + idx)
    if result < 0
      return                                        ' E_IO_ERROR
    idx++
    next_clus := long[readFat(clus)] & FAT32_ENTRY_MASK
    if next_clus >= FAT32_EOC_MIN
      quit
    if next_clus < ROOT_CLUSTER
      quit
    clus := next_clus

  ' Step 7: Verify phase — read-back compare every cluster
  clus := start_cluster
  idx := 0
  repeat
    result := verifyClusterCopy(clus, new_first + idx)
    if result < 0
      return                                        ' E_VERIFY_FAILED
    idx++
    next_clus := long[readFat(clus)] & FAT32_ENTRY_MASK
    if next_clus >= FAT32_EOC_MIN
      quit
    if next_clus < ROOT_CLUSTER
      quit
    clus := next_clus

  ' Step 8: Build new FAT chain
  result := allocateContiguousChain(new_first, cluster_count)
  if result < 0
    return

  ' Step 9: Update directory entry to point to new first cluster
  if readSector(dir_sec, BUF_DIR) < 0
    result := E_IO_ERROR
    return
  bytemove(@entry_buffer, @dir_buf + dir_off, DIR_ENTRY_SIZE)
  dirEntSetStartClus(@entry_buffer, new_first)
  bytemove(@dir_buf + dir_off, @entry_buffer, DIR_ENTRY_SIZE)
  writeSector(dir_sec, BUF_DIR)

  ' Step 10: Free old clusters
  freeClusterChain(start_cluster)

  ' Step 11: Invalidate all caches
  invalidateAllCaches()

  ' Step 12: Success
  result := SUCCESS
```

**Atomicity note**: Steps 8-10 form the critical window. If power fails after step 8 but before step 10, both old and new chains exist in the FAT (old data is duplicated, new chain is populated). FSCK can detect this via cross-link detection and recover.

### 6.7 copyClusterData(src_cluster, dst_cluster) : result

```spin2
PRI copyClusterData(src_cluster, dst_cluster) : result | idx
' Copy all sectors of one cluster from source to destination.

  result := SUCCESS
  repeat idx from 0 to sec_per_clus - 1
    if readSector(clus2sec(src_cluster) + idx, BUF_DATA) < 0
      result := E_IO_ERROR
      quit
    if writeSector(clus2sec(dst_cluster) + idx, BUF_DATA) < 0
      result := E_IO_ERROR
      quit
```

### 6.8 verifyClusterCopy(src_cluster, dst_cluster) : result

```spin2
PRI verifyClusterCopy(src_cluster, dst_cluster) : result | idx, byte_idx
' Verify that all sectors in a cluster were copied correctly.
' Repurposes dir_buf for destination reads (safe when file is closed).

  result := SUCCESS
  repeat idx from 0 to sec_per_clus - 1
    if readSector(clus2sec(src_cluster) + idx, BUF_DATA) < 0
      result := E_IO_ERROR
      quit
    if readSector(clus2sec(dst_cluster) + idx, BUF_DIR) < 0
      result := E_IO_ERROR
      quit
    repeat byte_idx from 0 to SECTOR_SIZE - 1
      if byte[@buf][byte_idx] <> byte[@dir_buf][byte_idx]
        debug[CH_FILE]("  [verifyClusterCopy] Mismatch at sector ", udec_(idx), " byte ", udec_(byte_idx))
        result := E_VERIFY_FAILED
        return
```

**Key design**: Uses `BUF_DIR` (`dir_buf`) for the destination read and `BUF_DATA` (`buf`) for the source read. This is safe because `compactFile()` requires the file to be closed, so `dir_buf` is not in active use.

### 6.9 invalidateAllCaches()

```spin2
PRI invalidateAllCaches()
' Reset all three sector cache tracking variables to force re-reads.
' Called after compactFile() to prevent stale cached sectors.

  dir_sec_in_buf := -1
  fat_sec_in_buf := -1
  sec_in_buf := -1
```

### 6.10 isFileOpenAny(dir_sector, dir_offset) : result

```spin2
PRI isFileOpenAny(dir_sector, dir_offset) : result | handle
' Check if a file is open in any mode (read, write, or directory).
' Used by compactFile() to reject compaction on open files.

  result := FALSE
  repeat handle from 0 to MAX_OPEN_FILES - 1
    if h_flags[handle] <> HF_FREE
      if h_dir_sector[handle] == dir_sector and h_dir_offset[handle] == dir_offset
        result := TRUE
        quit
```

---

## Part 7: Modify do_write_h() for Pre-Allocated Chains

At every point in `do_write_h()` where a cluster boundary crossing triggers `allocateCluster()`, add a pre-allocation check. There are **two such sites** — both the initial seek-to-end path and the main write loop.

The pattern is identical at both sites:

```spin2
      if ((h_sector[handle] - cluster_offset) & (sec_per_clus - 1)) == 0
#ifdef SD_INCLUDE_DEFRAG
        if h_prealloc_end[handle] > 0
          new_cluster := h_cluster[handle] + 1
          if new_cluster > h_prealloc_end[handle]
            debug[CH_FILE]("  [do_write_h] Pre-allocated space exhausted")
            count := 0                              ' or quit (in write loop)
          else
            h_cluster[handle] := new_cluster
            h_sector[handle] := clus2sec(new_cluster)
        else
#endif
          new_cluster := allocateCluster(h_cluster[handle])
          if new_cluster < 0
            ...existing error handling...
          else
            h_cluster[handle] := new_cluster
            h_sector[handle] := clus2sec(new_cluster)
```

**Key**: When `h_prealloc_end[handle] > 0`, the file was created with `createFileContiguous()`. Cluster advancement is a simple `+1` — no FAT lookup, no allocation, no fragmentation possible. When the pre-allocated range is exhausted, the write stops.

### Clear Pre-Allocation on Close

In `do_close_h()`, add before `freeHandle(handle)`:

```spin2
#ifdef SD_INCLUDE_DEFRAG
    ' Clear pre-allocation tracking
    h_prealloc_end[handle] := 0
#endif
```

---

## Part 8: FSCK/Audit Fragmentation Reporting

### 8.1 New VAR Declarations (in isp_fsck_utility.spin2)

```spin2
  LONG    v_fragmentedFileCount   ' files with fragment_count > 1
  LONG    v_totalFragments        ' sum of all fragment counts
```

### 8.2 Initialize in runAudit() and runFsck()

Add near the other counter initialization:

```spin2
    v_fragmentedFileCount := 0
    v_totalFragments := 0
```

### 8.3 Track in fsckValidateChain()

Add a `fragCount` local variable to `fsckValidateChain()`.

Initialize to 1 at chain start:

```spin2
    fragCount := 1
```

Detect fragment transitions inside the chain walk loop, after the next cluster is known but before `clus := nextClus`:

```spin2
        ' Detect fragment transitions (non-contiguous cluster)
        if nextClus <> clus + 1
            fragCount++
```

After the chain walk loop, report stats (window 0 only, files only):

```spin2
    ' Track fragmentation statistics (window 0 only, files only)
    if currentWindow == 0
        if not isDir
            if chainLen > 0 and fragCount > 1
                v_fragmentedFileCount++
                v_totalFragments += fragCount
```

### 8.4 Report in Summary Output

In both `runAudit()` and `runFsck()` summary sections, add after the existing counters:

```spin2
        if v_fragmentedFileCount > 0
            fifo.putFmt2(@"Fragmented files: %d (%d fragments total)", v_fragmentedFileCount, v_totalFragments)
```

---

## Part 9: v1.4.2 Audit Fix (auditRootDir volume label scan)

This fix is in `isp_fsck_utility.spin2` and is independent of defrag, but was part of the same release pair.

**Problem**: `auditRootDir()` only checked offset 0 of the root directory for a volume label entry. Some formatters place the volume label at a later position, or only store it in the VBR (Volume Boot Record), not in the root directory at all.

**Fix**: Scan all entries in the first root directory sector. Accept VBR-only labels as valid.

Replace the old `auditRootDir()` with:

```spin2
PRI auditRootDir() | result, idx, p_entry, found_label
' Verify root directory structure.
' FAT32 spec: volume label entry can be anywhere in root directory.

    fifo.put(@"Checking Root Directory...")
    sd.readSectorRaw(dataStart, @buf)

    ' Scan all entries in first root dir sector for volume label
    found_label := false
    repeat idx from 0 to (sd.SECTOR_SIZE / sd.DIR_ENTRY_SIZE) - 1
      p_entry := @buf + (idx * sd.DIR_ENTRY_SIZE)
      if byte[p_entry] == DIR_END_MARKER
        quit
      if byte[p_entry] <> sd.DIR_ENTRY_DELETED and byte[p_entry + sd.DE_ATTR_OFFSET] == sd.ATTR_VOLUME_ID
        found_label := true
        result := byte[p_entry]
        quit
    auditRunTest(@"Volume label entry (attr=$08)", found_label)

    if found_label
      auditRunTest(@"Valid volume label chars", result >= $20 AND result <= $7E)
    else
      auditRunTest(@"Valid volume label chars", true)  ' VBR-only label is acceptable

    result := buf[sd.DIR_ENTRY_SIZE]
    auditRunTest(@"Second entry valid or end", result == DIR_END_MARKER OR result == sd.DIR_ENTRY_DELETED OR (result >= $20 AND result <= $7E))
```

---

## Implementation Order

1. **freeClusterChain() + do_delete() refactor** — standalone, no flag dependency, no API change. Simplest to verify.
2. **allocateCluster() next-fit rewrite** — unconditional, improves all allocation. Test by creating/deleting files and verifying sequential allocation.
3. **Feature flag, constants, error codes, DAT** — scaffolding for the gated code.
4. **countFileFragments() + do_file_fragments() + fileFragments() + isFileContiguous()** — read-only query, safe to test immediately.
5. **findContiguousRun() + allocateContiguousChain()** — FAT manipulation helpers used by both create and compact.
6. **do_create_contiguous() + createFileContiguous() + do_write_h() pre-alloc + do_close_h() cleanup** — contiguous file creation path.
7. **copyClusterData() + verifyClusterCopy() + invalidateAllCaches() + isFileOpenAny() + do_compact_file() + compactFile()** — the full compaction pipeline.
8. **Worker dispatch** — wire all three commands into fs_worker().
9. **FSCK/Audit fragmentation reporting** — independent of the driver changes.
10. **auditRootDir() fix** — independent, can be done at any point.

---

## Test Coverage

The reference test suite (`SD_RT_defrag_tests.spin2`) covers 12 tests across 4 groups:

| Group | Test | What It Verifies |
|-------|------|-----------------|
| Fragment Query | fileFragments() on fresh file returns 1 | Single-fragment detection |
| Fragment Query | isFileContiguous() on fresh file returns TRUE | Convenience wrapper |
| Fragment Query | Fragmented file has fragment count > 1 | Creates interleaved files (A, spacer, append A), verifies >= 2 fragments |
| compactFile | Makes fragmented file contiguous | Compact + verify isFileContiguous == TRUE |
| compactFile | Data integrity preserved after compact | Read-back verify pattern bytes survive compaction |
| compactFile | Contiguous file returns SUCCESS (no-op) | Idempotent behavior |
| compactFile | Open file returns E_FILE_OPEN_FOR_COMPACT | Safety check on open handle |
| compactFile | Nonexistent file returns E_FILE_NOT_FOUND | Error path |
| compactFile | Empty file returns SUCCESS | Edge case |
| createFileContiguous | Creates contiguous file | Allocate, write, close, verify isFileContiguous |
| createFileContiguous | Returns E_NO_CONTIGUOUS_SPACE when constrained | Uses setTestMaxClusters(20) to artificially limit FAT |
| Next-Fit | Sequential file creates are contiguous | Three files created in sequence all have 1 fragment |

**Fragmentation creation strategy**: Create file A (64 KB), create spacer (64 KB), append to file A (64 KB). File A's clusters must skip over spacer's clusters, creating at least 2 fragments.

---

## Key Constants Referenced

These constants must exist (or be mapped to equivalents) in the target driver:

| Constant | Value | Meaning |
|----------|-------|---------|
| `ROOT_CLUSTER` | 2 | First usable cluster in FAT32 |
| `FAT32_ENTRY_MASK` | `$0FFF_FFFF` | Low 28 bits of a FAT entry |
| `FAT32_RESERVED_MASK` | `$F000_0000` | High 4 reserved bits |
| `FAT32_EOC_MIN` | `$0FFF_FFF8` | Minimum end-of-chain marker |
| `FAT32_EOC_MARK` | `$0FFF_FFFF` | Standard EOC value written |
| `FAT_BAD` | `$0FFF_FFF7` | Bad cluster marker |
| `SECTOR_SHIFT` | 9 | log2(512) |
| `SECTOR_OFFSET_MASK` | `$1FF` | 512-1, masks byte offset within sector |
| `SECTOR_SIZE` | 512 | Bytes per sector |
| `DIR_ENTRY_SIZE` | 32 | Bytes per directory entry |
| `HF_FREE` | 0 | Handle flag: not in use |
| `HF_WRITE` | 2 | Handle flag: open for writing |
| `HF_DIRTY` | `$80` | Handle flag: buffer has unwritten data |
| `ATTR_ARCHIVE` | `$20` | Directory entry attribute: archive |
| `ATTR_VOLUME_ID` | `$08` | Directory entry attribute: volume label |
| `SUCCESS` | 0 | Success return code |
| `BUF_DIR` | 0 | Buffer type: directory |
| `BUF_FAT` | 1 | Buffer type: FAT |
| `BUF_DATA` | 2 | Buffer type: data |

---

## Key DAT Variables Referenced

| Variable | Type | Meaning |
|----------|------|---------|
| `fsi_nxt_free` | LONG | FSInfo next-free-cluster hint (persisted to card) |
| `fsi_free_count` | LONG | FSInfo free cluster count ($FFFF_FFFF = unknown) |
| `fat_sec` | LONG | First sector of FAT1 |
| `fat2_sec` | LONG | First sector of FAT2 (mirror) |
| `sec_per_fat` | LONG | Sectors per FAT |
| `sec_per_clus` | LONG | Sectors per cluster |
| `cluster_offset` | LONG | Sector offset to first cluster's data |
| `fat_sec_in_buf` | LONG | Which FAT sector is currently cached (-1 = none) |
| `dir_sec_in_buf` | LONG | Which dir sector is currently cached (-1 = none) |
| `sec_in_buf` | LONG | Which data sector is currently cached (-1 = none) |
| `entry_address` | LONG | Byte address of last found directory entry |
| `entry_buffer` | BYTE[32] | Copy of last found directory entry |
| `date_stamp` | LONG | Current packed date/time stamp |
| `test_max_clusters` | LONG | Test hook: artificial cluster limit (0 = disabled) |
| `fat_buf` | BYTE[512] | FAT sector cache buffer |
| `dir_buf` | BYTE[512] | Directory sector cache buffer |
| `buf` | BYTE[512] | Data sector cache buffer |

---

## Key Methods Referenced (must exist in target driver)

| Method | Purpose |
|--------|---------|
| `readSector(sector, buf_type)` | Read a sector into the specified cache buffer |
| `writeSector(sector, buf_type)` | Write the specified cache buffer to a sector |
| `readFat(cluster)` | Read FAT entry for a cluster, return pointer to entry in fat_buf |
| `allocateCluster(cluster)` | Allocate a free cluster, optionally linking to previous |
| `searchDirectory(name_ptr)` | Find a file in the current directory |
| `firstCluster()` | Extract first cluster from entry_buffer |
| `dirEntFileSize(p_entry)` | Extract file size from a directory entry |
| `dirEntSetAttr(p_entry, attr)` | Set attribute byte in directory entry |
| `dirEntSetStartClus(p_entry, cluster)` | Set first cluster in directory entry |
| `dirEntSetCreateStamp(p_entry, stamp)` | Set creation timestamp |
| `dirEntSetModifyStamp(p_entry, stamp)` | Set modification timestamp |
| `dirEntSetFileSize(p_entry, size)` | Set file size in directory entry |
| `clus2sec(cluster)` | Convert cluster number to first sector number |
| `byte2clus(byte_addr)` | Convert byte address to cluster number |
| `clearCluster(cluster)` | Zero all sectors in a cluster |
| `allocateHandle()` | Find and return a free handle slot |
| `freeHandle(handle)` | Release a handle back to the free pool |
| `send_command(cmd, p0, p1, p2, p3)` | Send a command to the worker cog via mailbox |
| `set_error(code)` | Store error code in per-cog error array |
