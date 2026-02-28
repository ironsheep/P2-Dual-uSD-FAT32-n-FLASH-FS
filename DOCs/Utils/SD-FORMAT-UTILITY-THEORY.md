# Format Utility — Theory of Operations

*SD_format_card.spin2 · isp_format_utility.spin2*

## Overview

The format utility creates a complete FAT32 filesystem on an SD card from scratch. It is a library object (not a standalone program) that provides `format()` and `formatWithLabel()` public methods. The `SD_format_card.spin2` runner and regression tests use this library.

The utility writes all filesystem structures using raw sector access (`initCardOnly` + `writeSectorRaw`), creating a Microsoft-compatible FAT32 filesystem that works with Windows, macOS, and Linux.

## FAT32 Disk Layout

The format utility creates the following on-disk structure:

```
Sector 0:          MBR (Master Boot Record) with partition table
Sectors 1-8191:    Unused (gap for 4MB alignment)
Sector 8192:       VBR (Volume Boot Record / BPB)
Sector 8193:       FSInfo sector
Sectors 8194-8197: Reserved
Sector 8198:       Backup VBR (copy of sector 8192)
Sector 8199:       Backup FSInfo (copy of sector 8193)
Sectors 8200-8223: Reserved (total 32 reserved sectors)
Sector 8224:       FAT1 start
Sector 8224+S:     FAT2 start (S = sectors per FAT)
Sector 8224+2S:    Data region start (root directory cluster)
```

## Format Sequence

The `doFormat()` method executes these steps in order:

### 1. Card Initialization

Calls `sd.initCardOnly()` for raw sector access, then reads card size via `sd.cardSizeSectors()`.

### 2. Parameter Calculation (`calculateParameters`)

Computes filesystem geometry from card size:

**Partition alignment**: Always starts at sector 8192 (4MB aligned), matching modern card formatting conventions.

**Cluster size selection** (Microsoft-recommended):

| Card Size | Sectors/Cluster | Cluster Size |
|-----------|-----------------|--------------|
| <= 8 GB   | 8               | 4 KB         |
| <= 16 GB  | 16              | 8 KB         |
| <= 32 GB  | 32              | 16 KB        |
| > 32 GB   | 64              | 32 KB        |

**FAT size calculation**:
```
totalClusters = (dataSectors - 32) / sectorsPerCluster
sectorsPerFat = (totalClusters * 4 + 511) / 512
```
Each FAT entry is 4 bytes (LONG), so one FAT sector holds 128 entries.

**Derived layout**:
```
fat1Start = partitionStart + 32   (reserved sectors)
fat2Start = fat1Start + sectorsPerFat
dataStart = fat2Start + sectorsPerFat
```

FAT32 requires a minimum of 65,525 clusters. Cards too small for this are rejected.

### 3. MBR Write (`writeMBR`)

Creates sector 0 with a single partition table entry:

| Offset | Size | Value | Description |
|--------|------|-------|-------------|
| $1BE   | 1    | $00   | Not bootable |
| $1C2   | 1    | $0C   | FAT32 with LBA |
| $1C6   | 4    | 8192  | Partition start (LBA) |
| $1CA   | 4    | var   | Partition size in sectors |
| $1FE   | 2    | $AA55 | Boot signature |

CHS fields use legacy placeholder values ($FE/$FF/$FF for end).

### 4. VBR Write (`writeVBR`)

Creates the Volume Boot Record at the partition start sector with the BIOS Parameter Block (BPB):

**Jump instruction**: `$EB $58 $90` (standard FAT32 jump)

**OEM name**: `"P2FMTER "` (8 bytes, identifies our formatter)

**BPB fields**:

| Offset | Field | Value |
|--------|-------|-------|
| $0B | Bytes/sector | 512 |
| $0D | Sectors/cluster | Calculated |
| $0E | Reserved sectors | 32 |
| $10 | Number of FATs | 2 |
| $11 | Root entries (16-bit) | 0 (FAT32) |
| $13 | Total sectors (16-bit) | 0 (FAT32) |
| $15 | Media type | $F8 (fixed disk) |
| $16 | FAT size (16-bit) | 0 (FAT32) |
| $1C | Hidden sectors | partitionStart |
| $20 | Total sectors (32-bit) | totalSectors - partitionStart |
| $24 | FAT size (32-bit) | sectorsPerFat |
| $2C | Root cluster | 2 |
| $30 | FSInfo sector | 1 |
| $32 | Backup boot sector | 6 |
| $42 | Extended boot sig | $29 |
| $43 | Volume serial | getct() (random) |
| $47 | Volume label | 11-byte padded label |
| $52 | FS type string | "FAT32   " |
| $1FE | Boot signature | $AA55 |

### 5. FSInfo Write (`writeFSInfo`)

Creates the FSInfo sector at partition+1:

| Offset | Field | Value |
|--------|-------|-------|
| $000 | Lead signature | $41615252 ("RRaA") |
| $1E4 | Structure signature | $61417272 ("rrAa") |
| $1E8 | Free cluster count | totalClusters - 1 |
| $1EC | Next free cluster hint | 3 |
| $1FC | Trail signature | $AA550000 |

The free count is `totalClusters - 1` because cluster 2 (root directory) is allocated.

### 6. Backup Boot (`writeBackupBoot`)

Copies the VBR to partition sector 6 and FSInfo to partition sector 7. This provides redundancy for critical boot structures.

### 7. FAT Initialization (`initFAT`)

Called twice (once for FAT1, once for FAT2). Each FAT table requires `sectorsPerFat` sectors.

**First sector** has three special entries:

| Entry | Value | Meaning |
|-------|-------|---------|
| FAT[0] | $0FFFFFF8 | Media type descriptor |
| FAT[1] | $0FFFFFFF | End-of-chain marker |
| FAT[2] | $0FFFFFFF | Root directory (single cluster, EOC) |

**Remaining sectors** are written as all zeros (every cluster is free).

Progress is reported every 256 sectors since this is the longest step (writing thousands of sectors for each FAT copy).

### 8. Root Directory (`initRootDirectory`)

Initializes the first data cluster (cluster 2) with a volume label directory entry:

| Offset | Field | Value |
|--------|-------|-------|
| $00 | Name (11 bytes) | Volume label, space-padded |
| $0B | Attributes | $08 (volume label) |
| $10 | Creation date | $0021 (1980-01-01) |
| $18 | Modification date | $0021 (1980-01-01) |
| $1C | File size | 0 |

All remaining bytes in the root cluster are zeroed (indicating no more directory entries).

## Volume Label Handling

Labels are always:
- Converted to uppercase (FAT32 requirement)
- Padded with spaces to exactly 11 characters
- Stored in both the VBR (offset $47) and as the first root directory entry

The default label is `"P2-XFER    "`.

## Library API

```spin2
OBJ fmt : "isp_format_utility"

' Format with default label "P2-XFER"
result := fmt.format(cs, mosi, miso, sck)

' Format with custom label (max 11 chars)
result := fmt.formatWithLabel(cs, mosi, miso, sck, @"MYVOLUME")

' Release SPI pins after formatting
fmt.stop()
```

Both methods return TRUE on success, FALSE on failure. After formatting, call `stop()` to release the worker cog and SPI pins before using the card with another driver instance.

## Cross-OS Compatibility

The format follows the Microsoft FAT32 specification to ensure compatibility:
- Standard partition alignment (4MB / sector 8192)
- All required BPB fields populated
- Dual FAT tables (FAT1 and FAT2)
- FSInfo sector with proper signatures
- Backup boot structures at standard locations
- Volume label in both VBR and root directory
