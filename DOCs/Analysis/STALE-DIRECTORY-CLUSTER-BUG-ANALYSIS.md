# Bug Analysis: Stale Directory Cluster Data in `do_newdir()`

**Date discovered:** 2026-03-30
**Severity:** Data corruption (silent)
**Affected versions:** All (reference standalone SD driver through dual-FS v1.2.0)
**Fixed in:** Working tree (post-v1.2.0)
**Root cause:** Missing `clearCluster()` call when allocating a new subdirectory's data cluster

---

## Summary

When `do_newdir()` creates a new subdirectory, it allocates a FAT cluster for the directory's data but only initializes the first sector (512 bytes) with the `.` and `..` entries. The remaining sectors in the cluster retain whatever data previously occupied that cluster. If the cluster was previously used by a file containing non-zero fill data, the stale bytes masquerade as occupied directory entries. This causes `searchDirectory()` to place new file entries outside the directory's cluster chain, silently corrupting other data on the card.

## Detailed Description

### The FAT32 directory model

In FAT32, a subdirectory is simply a file whose data clusters contain 32-byte directory entries. When a new subdirectory is created, the driver must:

1. Allocate a cluster for the directory's data
2. Zero-fill all sectors in that cluster (so every entry starts with `$00`, the "end of directory" marker)
3. Write the `.` and `..` entries into the first two 32-byte slots of the first sector

Step 2 is critical. Without it, stale data in sectors 2 through `sec_per_clus` may contain bytes that `searchDirectory()` interprets as valid (occupied) directory entries.

### The bug in `do_newdir()`

In `dual_sd_fat32_flash_fs.spin2`, `do_newdir()` performs step 1 (line 5546) but skips step 2. It proceeds directly to step 3 (lines 5569-5589), writing `.` and `..` to only the first sector:

```spin2
  temp := allocateCluster(0)              ' Step 1: allocate cluster
  ' <-- Step 2 MISSING: clearCluster(temp)
  ...
  bytefill(@dir_buf, 0, SECTOR_SIZE)     ' Step 3: zero first sector buffer
  bytemove(@dir_buf[0], string(".   ...   ' Write "." entry
  bytemove(@dir_buf[32], string("..  ...  ' Write ".." entry
  writeSector(n_sec, BUF_DIR)            ' Write FIRST SECTOR ONLY
```

The `clearCluster()` method exists in the driver (line 9363) and is even documented as "Initialize entire contents of cluster to 0 -- used for new directories." It IS correctly called for parent directory extension clusters (line 5544), but not for the new directory's own cluster.

### The trigger conditions

On the test card (`sec_per_clus = 32`, cluster size = 16 KB), a single directory cluster holds 32 sectors of 16 entries each (512 entries total). The first sector accommodates `.`, `..`, and up to 14 files. All five of the following conditions must be true simultaneously for the bug to manifest:

1. **Cluster reuse**: A cluster previously used for file data must be allocated for the new directory. This happens naturally via FAT's next-fit allocator when files are created and deleted before directory creation.

2. **Non-zero fill data**: The previously-stored data must not contain `$00` (end-of-directory marker) or `$E5` (deleted-entry marker) in the first byte of any 32-byte-aligned position. Pure fill patterns like `$AA`, `$BB`, `$CC` satisfy this.

3. **More than 14 files**: The test must create enough files to overflow the first sector (16 entries minus `.` and `..` = 14 file slots). The 15th file forces `searchDirectory()` into sector 2 where the stale data lives.

4. **No intervening format**: A format operation zeros all clusters, eliminating stale data.

5. **Test ordering**: The cluster-polluting operation must run before the directory creation within the same card session.

### Failure mechanism in detail

When all trigger conditions are met:

1. `searchDirectory("STR14.TXT")` scans the first sector (16 occupied entries), then advances to sector 2 via `readNextSector()`.

2. Sector 2 contains `$AA$AA$AA...` (stale fill data). The first byte of each 32-byte chunk is `$AA`, which is neither `$00` nor `$E5`. `searchDirectory()` treats every chunk as an occupied entry, checks for name match (no match), and advances.

3. This repeats through all remaining sectors (2-32) of the cluster. No free slot is found within the cluster.

4. At the cluster boundary, `readNextSector()` follows the FAT chain and hits end-of-chain marker `$0FFF_FFF8`+. It zeros the buffer and increments `n_sec` to point past the directory's cluster.

5. `searchDirectory()` finds `$00` in the zeroed buffer and sets `entry_address` to `(n_sec << SECTOR_BITS) | 0`. This address points to a sector **outside the directory's cluster chain**.

6. Back in `do_create()`, the directory entry for STR14.TXT is written to this wrong sector. The file's data cluster is properly allocated, but its directory entry is placed in an unrelated sector, potentially overwriting other file data or FAT structures.

7. The file appears to be created successfully (valid handle returned, `created` counter increments), but the directory entry is invisible to enumeration and the file cannot be opened by name.

### Consequences

- **Silent data loss**: Files appear to create successfully but are permanently invisible. No error code is returned.
- **Cross-file corruption**: Directory entries written to wrong sectors can overwrite other files' data or FAT metadata.
- **Intermittent manifestation**: The bug only triggers when specific cluster reuse patterns exist, making it extremely difficult to reproduce without understanding the root cause.

## Origin and Version History

### Reference standalone SD driver

The bug originates in the reference standalone SD driver (`REF-FLASH-uSD/uSD-FAT32/src/micro_sd_fat32_fs.spin2`, "Original: Chris Gadd, V3: S.M. Moraco"). The identical pattern exists at line 2324:

```spin2
  temp := allocateCluster(0)              ' Allocate new directory's cluster
  ' <-- clearCluster(temp) MISSING
  dirEntSetAttr(@entry_buffer, $10)
```

The three `clearCluster()` calls in the reference driver (lines 1526, 2291, 2322) all clear **parent directory extension** clusters, never the new directory's own cluster.

### Dual-FS driver

The code was ported character-for-character into the dual-FS driver during the Feature Parity work (commit `5544c57`, "Rename driver to dual_sd_fat32_flash_fs, reorganize src/ tree, add feature parity"). The missing `clearCluster()` was carried forward without modification.

### Affected releases

| Version | Date | Bug present? |
|---------|------|-------------|
| Reference standalone SD driver (all versions) | Pre-2026 | Yes |
| Dual-FS driver v1.0.0 | 2026-03-08 | Yes |
| Dual-FS driver v1.1.0 | 2026-03-09 | Yes |
| Dual-FS driver v1.2.0 | 2026-03-18 | Yes |
| Working tree (post-v1.2.0) | 2026-03-30 | **Fixed** |

## Why the Bug Was Not Discovered Earlier

### 1. No cluster-polluting test existed

Until the defrag test suite (`DFS_SD_RT_defrag_tests.spin2`) was added on 2026-03-28, no test wrote large files with non-zero fill patterns (`$AA`, `$BB`, `$CC`) and then deleted them. Without freed clusters containing stale non-zero data, newly allocated directory clusters came from clean regions (factory-erased or format-zeroed), and the uninitialized sectors happened to contain `$00` bytes.

### 2. Small directory sizes

Most test suites create 1-10 files per subdirectory, well within the 14-file capacity of a single sector. Only the 20-file stress test in `DFS_SD_RT_directory_tests.spin2` exceeds this threshold.

### 3. Format test masks the problem

The format test (`DFS_SD_RT_format_tests.spin2`) runs at position #34 (last in regression). It zeros all data clusters. In previous regression runs without the defrag test, no test between format and directory tests would have polluted clusters.

### 4. Standalone execution is clean

When running any single test suite standalone, the P2 reboots fresh and the card's cluster allocation starts from a clean state. The stale-cluster condition requires a specific sequence of file creation, deletion, and directory creation within the same card session.

### 5. ASCII test data contains null bytes

Normal test files contain ASCII text with null terminators. Even if their clusters were reused, the `$00` bytes in the data would be interpreted as "end of directory" markers, causing `searchDirectory()` to find free slots at the correct positions within the directory cluster.

## The Fix

### Code change

One line added to `do_newdir()` in `dual_sd_fat32_flash_fs.spin2`, immediately after `allocateCluster(0)`:

```spin2
  temp := allocateCluster(0)
  clearCluster(temp)                    ' Zero all sectors in new dir cluster
  dirEntSetAttr(@entry_buffer, $10)
```

`clearCluster()` iterates through all `sec_per_clus` sectors of the cluster, writing zeros to each. This ensures every directory entry position starts with `$00` (end-of-directory marker). The subsequent `.` and `..` write to sector 1 overwrites two of those zero entries with valid data. All other positions correctly signal "end of directory" to `searchDirectory()`.

### Cost

For `sec_per_clus = 32` (16 KB cluster), the fix adds 32 sector writes (~32 ms at 25 MHz SPI) to each `newDirectory()` call. This is a one-time cost per directory creation and is negligible compared to the time spent creating files.

### Regression test

A self-contained regression test group ("Stale Cluster Directory Test") was added to `DFS_SD_RT_directory_tests.spin2`. It deliberately pollutes clusters with `$AA` fill data, deletes the polluting file, creates a new subdirectory, and verifies that 20+ files can be created, enumerated, and opened. This test catches the bug regardless of prior card state or test ordering.

## Related

- `clearCluster()` definition: `dual_sd_fat32_flash_fs.spin2` line 9363
- `do_newdir()`: `dual_sd_fat32_flash_fs.spin2` line 5515
- `searchDirectory()`: `dual_sd_fat32_flash_fs.spin2` line 8741
- Reference driver `do_newdir()`: `REF-FLASH-uSD/uSD-FAT32/src/micro_sd_fat32_fs.spin2` line 2301
- Regression test: `DFS_SD_RT_directory_tests.spin2`, test group "Stale Cluster Directory Test"
