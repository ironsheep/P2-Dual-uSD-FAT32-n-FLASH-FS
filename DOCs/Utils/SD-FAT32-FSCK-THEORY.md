# FAT32 Fsck — Theory of Operations

*SD_FAT32_fsck.spin2 · isp_fsck_utility.spin2*

## Overview

The FSCK (Filesystem Check) utility detects and repairs FAT32 filesystem corruption on SD cards. It operates in auto-repair mode using raw sector access (`initCardOnly` + `readSectorRaw` / `writeSectorRaw`), bypassing the filesystem driver entirely. This ensures it can repair corruption that would prevent normal mounting.

## Architecture: Four-Pass Design

The utility follows a strict four-pass architecture where each pass builds on the results of previous passes.

```
Pass 1: Structural Integrity
  |  Repairs boot sectors, FSInfo, FAT signatures
  v
Pass 2: Directory & Chain Validation
  |  Walks directory tree, validates chains, builds bitmap
  v
Pass 3: Lost Cluster Recovery
  |  Frees allocated clusters not found in bitmap
  v
Pass 4: FAT Sync & Free Count
     Synchronizes FAT1->FAT2, corrects FSInfo
```

### Pass 1: Structural Integrity

Checks and repairs the foundational filesystem structures that must be correct before deeper analysis.

**Checks performed:**
- **Backup VBR**: Sector 6 of partition must match sector 0 (primary VBR). If mismatched, primary is copied to backup.
- **FSInfo signatures**: Three signatures must be correct:
  - Lead signature at offset 0: `$41615252` ("RRaA")
  - Structure signature at offset 484: `$61417272` ("rrAa")
  - Trail signature at offset $1FC: `$AA550000`
- **Backup FSInfo**: Sector 7 must match sector 1 (primary FSInfo).
- **FAT[0]**: Must contain media type `$0FFFFFF8` (lower 28 bits). Upper 4 bits are preserved.
- **FAT[1]**: Must contain end-of-chain marker `$0FFFFFFF` (lower 28 bits).
- **FAT[2]**: Must not be free (`$00000000`). This is the root directory cluster. If free, it is set to EOC. This check was added after discovering a critical bug where pass 3 could free the root cluster.

### Pass 2: Directory & Chain Validation

Walks the entire directory tree starting from the root cluster, validating every cluster chain and building a bitmap of referenced clusters.

**Process:**
1. Clear the cluster bitmap (256KB of LONGs zeroed)
2. Mark clusters 0 and 1 as used (they don't exist as data clusters)
3. Validate and mark the root directory's own cluster chain
4. Recursively scan the root directory

**For each directory entry found:**
- Skip deleted entries (`$E5`), long filename entries (attr `$0F`), volume labels (attr `$08`), and `.`/`..` entries
- For subdirectories: validate their cluster chain, then recurse into them
- For files: validate their cluster chain, checking length against file size

**Chain validation** (`validateChain`):
- Follows the chain from start cluster, reading FAT entries
- Marks each cluster in the bitmap via `setBit()`
- Detects cross-links (cluster already in bitmap from another chain)
- Detects bad references (cluster number out of range)
- Truncates chains at bad references by writing EOC
- Safety limit of 2,000,000 clusters to detect infinite loops
- For files, warns if chain length doesn't match expected cluster count from file size

**Directory scanning** (`scanDirectory`):
- Follows the directory's cluster chain to read entry sectors
- Processes 16 entries per sector (32 bytes each)
- Maximum recursion depth of 16 to prevent stack overflow
- After returning from subdirectory recursion, re-reads the parent sector (since the buffer was overwritten)

### Pass 3: Lost Cluster Recovery

Identifies "lost" clusters -- those marked as allocated in the FAT but not referenced by any file or directory in the bitmap.

**Process:**
- Iterates through all clusters (2 to totalClusters+1)
- For each cluster NOT in the bitmap, reads its FAT entry
- If the FAT entry is not free (`$00000000`) and not bad (`$0FFFFFF7`), the cluster is unreferenced
- Frees unreferenced clusters by writing `$00000000` to their FAT entry
- Flushes the FAT cache after processing all clusters

### Pass 4: FAT Sync & Free Count

Ensures FAT1 and FAT2 are identical and the FSInfo free cluster count is accurate.

**FAT synchronization:**
- Reads each FAT1 sector, then reads the corresponding FAT2 sector
- Compares byte-by-byte; if any difference, copies FAT1 sector to FAT2
- This is always FAT1 -> FAT2 (FAT1 is authoritative after passes 1-3)

**Free count:**
- While scanning FAT1 sectors, counts entries where lower 28 bits are `$00000000`
- After scanning all sectors, reads FSInfo and compares stored free count with calculated count
- Updates FSInfo (and backup at sector 7) if counts differ

## Key Data Structures

### Cluster Bitmap

```
LONG bitmapData[65536]    ' 256KB = 65536 LONGs
```

Each bit represents one cluster. A set bit means the cluster is referenced by a file or directory found during pass 2.

- **Capacity**: 65536 * 32 = 2,097,152 clusters
- **Coverage**: Cards up to approximately 64GB (depending on cluster size)
- **Cards exceeding capacity**: Receive structural checks only (passes 1 and 4)

Bit operations:
- `setBit(cluster)`: `bitmapData[cluster >> 5] |= (1 << (cluster & $1F))`
- `testBit(cluster)`: `(bitmapData[cluster >> 5] >> (cluster & $1F)) & 1`

### FAT Entry Cache

```
BYTE fatBuf[512]          ' One FAT sector (128 entries)
LONG fatBufSector         ' Which FAT1 sector is cached (-1 = none)
LONG fatBufDirty          ' TRUE if cache needs writing
```

The FAT cache holds one sector at a time. When a different sector is needed, the current one is flushed if dirty.

**Reading**: `readFAT(cluster)` computes `sector = fat1Start + (cluster >> 7)` and `offset = (cluster & $7F) * 4`. If the required sector is already cached, returns immediately.

**Writing**: `writeFAT(cluster, value)` loads the sector if needed, then modifies the entry. The upper 4 reserved bits of existing FAT entries are always preserved: `(value & $0FFFFFFF) | (existing & $F0000000)`.

**Flushing**: `flushFAT()` writes the dirty sector to both FAT1 and FAT2 using the offset: `fat2sector = fatBufSector - fat1Start + fat2Start`.

## Geometry Extraction

The utility reads filesystem geometry from MBR and VBR:

```
MBR (sector 0):
  partitionStart = LONG[$1C6]

VBR (sector partitionStart):
  sectorsPerCluster = BYTE[$0D]
  reservedSectors   = WORD[$0E]
  numFats           = BYTE[$10]
  sectorsPerFat     = LONG[$24]
  totalSectors      = LONG[$20]
  rootCluster       = LONG[$2C]

Derived:
  fat1Start    = partitionStart + reservedSectors
  fat2Start    = fat1Start + sectorsPerFat
  dataStart    = fat1Start + (numFats * sectorsPerFat)
  totalClusters = (totalSectors - reservedSectors - numFats*sectorsPerFat) / sectorsPerCluster
```

The `clus2sec(cluster)` conversion: `dataStart + ((cluster - 2) * sectorsPerCluster)`

## Performance Characteristics

Tested on PNY 16GB card (1,948,045 clusters, 16 sectors/cluster, 15,234 sectors/FAT):

| Pass | Duration | Notes |
|------|----------|-------|
| Pass 1 | < 1 second | Reads/writes a few sectors |
| Pass 2 | < 1 second | Empty card with 1 directory |
| Pass 3 | ~26 seconds | Scans all 1.9M cluster FAT entries |
| Pass 4 | ~37 seconds | Reads all 15,234 FAT sectors twice (FAT1 + FAT2) |
| **Total** | **~63 seconds** | Dominated by FAT sector I/O |

Pass 3 and 4 timing scales linearly with the number of FAT sectors (i.e., card capacity).

## Status Reporting

The utility reports one of three final statuses:
- **CLEAN**: No errors found, no repairs made
- **REPAIRED**: Errors found and successfully corrected
- **ERRORS REMAIN**: Some errors could not be automatically fixed (e.g., cross-linked clusters are reported but not untangled)

## Critical Design Lesson

The root directory cluster chain MUST be added to the bitmap BEFORE scanning directory entries. Without this, pass 3 will identify the root directory cluster(s) as "unreferenced" and free them, corrupting the filesystem. This was discovered during initial hardware testing and fixed by adding `validateChain(rootCluster, 0, true)` before `scanDirectory(rootCluster)` in pass 2.
