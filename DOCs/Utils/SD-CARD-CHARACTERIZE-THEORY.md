# SD Card Characterize - Theory of Operations

*DFS_SD_card_characterize.spin2*

## Overview

The characterize utility is a comprehensive diagnostic tool that reads and decodes all accessible SD card registers plus FAT32 filesystem parameters. It produces a detailed report identifying the card's manufacturer, capacity, speed ratings, supported features, and filesystem layout. The utility is read-only and does not modify the card.

Use this tool to identify untested cards, verify capacity claims, debug compatibility issues, or build a card catalog for your lab.

## Design Philosophy

The utility uses `initCardOnly()` for raw card access without mounting the filesystem. This allows characterization of cards with any filesystem type (FAT32, exFAT, NTFS, etc.) -- the card registers are independent of the filesystem.

Filesystem parameters are read separately via raw sector access (`readSectorRaw`) to inspect the MBR and VBR directly.

The `SD_INCLUDE_ALL` pragma enables all conditional compilation features in the driver, providing access to card register APIs (`readCIDRaw`, `readCSDRaw`, `readSCRRaw`, `readSDStatusRaw`, `getOCR`).

## Card Registers

### CID - Card Identification Register (16 bytes)

Identifies the card manufacturer, product, and production batch:

| Field | Bits | Size | Description |
|-------|------|------|-------------|
| MID | [127:120] | 8 | Manufacturer ID |
| OID | [119:104] | 16 | OEM/Application ID (2 ASCII chars) |
| PNM | [103:64] | 40 | Product Name (5 ASCII chars) |
| PRV | [63:56] | 8 | Product Revision (BCD major.minor) |
| PSN | [55:24] | 32 | Product Serial Number |
| MDT | [19:8] | 12 | Manufacturing Date (year + month) |
| CRC7 | [7:1] | 7 | CRC checksum |

The utility includes a manufacturer lookup table mapping MID values to brand names (SanDisk, Samsung, Kingston, PNY, Transcend, etc.).

**Driver usage**: MID determines SPI speed limit -- PNY cards (MID $FE) are limited to 20 MHz; all others get 25 MHz.

### CSD - Card Specific Data Register (16 bytes)

Describes the card's electrical and timing characteristics:

| Field | Bits | Description | Driver Usage |
|-------|------|-------------|:------------:|
| CSD_STRUCTURE | [127:126] | CSD version (1=SDSC, 2=SDHC/SDXC) | [USED] |
| TAAC | [119:112] | Read access time-1 (time component) | [USED]* |
| NSAC | [111:104] | Read access time-2 (clock cycles) | [USED]* |
| TRAN_SPEED | [103:96] | Max data transfer rate | [USED] |
| CCC | [95:84] | Card command classes (12 bits) | [INFO] |
| READ_BL_LEN | [83:80] | Max read block length | [INFO] |
| C_SIZE | varies | Device size | [USED] |
| R2W_FACTOR | [28:26] | Write speed factor | [USED]* |

*TAAC, NSAC, and R2W_FACTOR are used only for SDSC (v1) cards to calculate timeouts.

**TRAN_SPEED decoding**: The byte encodes a time value (bits [6:3]) and unit multiplier (bits [2:0]). The utility uses lookup tables to compute the actual frequency in Hz. Most SDHC cards report 25 MHz; High Speed mode doubles this to 50 MHz.

**C_SIZE decoding**: For CSD v1 (SDSC), capacity uses C_SIZE, C_SIZE_MULT, and READ_BL_LEN fields. For CSD v2 (SDHC/SDXC), capacity is simply `(C_SIZE + 1) * 512 KB`.

### SCR - SD Configuration Register (8 bytes)

Describes SD specification compliance and supported features:

| Field | Bits | Description | Driver Usage |
|-------|------|-------------|:------------:|
| SD_SPEC | [59:56] | SD spec version | [USED] |
| SD_SECURITY | [54:52] | Security support level | [INFO] |
| SD_BUS_WIDTHS | [51:48] | Supported bus widths | [INFO] |
| SD_SPEC3 | [47] | SD spec 3.0 support | [INFO] |
| SD_SPEC4 | [42] | SD spec 4.0 support | [INFO] |
| SD_SPECX | [41:38] | Extended spec version | [INFO] |
| CMD_SUPPORT | [33:32] | Command support bits | [INFO] |

**Driver usage**: SD_SPEC determines whether CMD6 (High Speed mode) is supported. Cards reporting spec >= 1.10 can switch to 50 MHz SPI.

The utility computes a human-readable SD spec version string (e.g., "3.x", "5.x") from the combination of SD_SPEC, SD_SPEC3, SD_SPEC4, and SD_SPECX fields.

### OCR - Operating Conditions Register (4 bytes)

Reports power supply voltage ranges and card type:

| Field | Bit | Description | Driver Usage |
|-------|-----|-------------|:------------:|
| CCS | [30] | Card Capacity Status | [USED] |
| UHS-II | [29] | UHS-II support | [INFO] |
| S18A | [24] | 1.8V switching accepted | [INFO] |
| Voltage window | [23:15] | Supported voltage ranges | [INFO] |

**Driver usage**: CCS is the most critical register field in the entire card. CCS=0 means SDSC (byte addressing, sector number shifted left 9), CCS=1 means SDHC/SDXC (block addressing, sector number used directly). Using the wrong addressing mode corrupts all reads and writes.

### SD Status Register (64 bytes, via ACMD13)

Performance classification data (optional -- some cards don't support ACMD13 over SPI):

| Field | Source | Description |
|-------|--------|-------------|
| Speed Class | byte[8] | Speed class (0, 2, 4, 6, 10) |
| UHS Speed Grade | byte[14] | UHS grade (U1, U3) |
| Video Speed Class | byte[15] | Video class (V6, V10, V30, V60, V90) |
| App Performance Class | byte[21] | Application class (A1, A2) |

## Filesystem Analysis

After reading card registers, the utility reads the MBR (sector 0) to find the partition type and start sector, then reads the VBR at the partition start for FAT32 parameters:

| Parameter | VBR Offset | Description |
|-----------|------------|-------------|
| OEM Name | $03 | Formatter identification (8 bytes) |
| Bytes/Sector | $0B | Always 512 for SD |
| Sectors/Cluster | $0D | Cluster size (4 KB to 32 KB) |
| Reserved Sectors | $0E | Typically 32 |
| Number of FATs | $10 | Always 2 |
| Total Sectors | $20 | Partition size |
| Sectors/FAT | $24 | FAT table size |
| Root Cluster | $2C | Typically 2 |
| Volume Serial | $43 | Random serial assigned at format |
| Volume Label | $47 | User-visible name (11 bytes) |
| FS Type | $52 | "FAT32   " |

## Output Sections

The report includes the following sections in order:

1. **Card register read status** -- confirms each register was read successfully
2. **CID fields** -- manufacturer, product name, revision, serial, manufacturing date
3. **CSD fields** -- capacity, speed, timing, block sizes
4. **OCR fields** -- voltage support, card type
5. **SCR fields** -- SD spec version, bus widths, security
6. **Raw register hex dumps** -- for verification
7. **FAT32 filesystem parameters** -- from MBR and VBR
8. **SD Status fields** -- speed class, UHS grade, video class (if available)
9. **Unique Card ID** -- generated string from CID fields (manufacturer_product_revision_serial_date)
10. **Card Designator** -- canonical 2-line summary of all card characteristics
11. **Driver Usage Summary** -- which register fields the driver actively uses
