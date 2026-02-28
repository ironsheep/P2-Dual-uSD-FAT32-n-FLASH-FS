# FAT32 Audit — Theory of Operations

*SD_FAT32_audit.spin2*

## Overview

The audit utility is a read-only filesystem validator that checks FAT32 structures without modifying any data on the card. It runs 41 individual tests across 7 categories and reports pass/fail results. Use it to verify filesystem integrity after testing, before deployment, or to diagnose mount failures.

For a utility that can also repair problems, see `SD_FAT32_fsck.spin2`.

## Design Philosophy

The audit tool is intentionally read-only. It uses `initCardOnly()` + `readSectorRaw()` for raw sector reads and `mount()` for a high-level mount test, but never calls `writeSectorRaw()`. This makes it safe to run on any card without risk of further damage.

## Test Categories

### 1. MBR Verification (5 tests)

Reads sector 0 and validates the Master Boot Record:

| Test | Expected Value |
|------|----------------|
| Boot signature | $AA55 at offset $1FE |
| Bootable flag | $00 or $80 at offset $1BE |
| Partition type | $0C (FAT32 LBA) at offset $1C2 |
| Partition start | > 0 at offset $1C6 |
| Partition size | > 0 at offset $1CA |

The partition start sector is saved for subsequent VBR reads.

### 2. VBR Verification (17 tests)

Reads the Volume Boot Record at the partition start sector and validates all BPB fields:

| Test | Expected Value |
|------|----------------|
| Jump instruction | $EB or $E9 at offset 0 |
| Boot signature | $AA55 at offset $1FE |
| OEM name | Printable ASCII at offset $03 |
| Bytes/sector | 512 |
| Sectors/cluster | Power of 2, 1-128 |
| Reserved sectors | 32 |
| Number of FATs | 2 |
| Root entry count | 0 (FAT32) |
| Total sectors 16-bit | 0 (FAT32) |
| Media type | $F8 |
| FAT size 16-bit | 0 (FAT32) |
| Hidden sectors | = partition start |
| Total sectors 32-bit | > 0 |
| Sectors/FAT | > 0 |
| Root cluster | 2 |
| FSInfo sector | 1 |
| Backup boot sector | 6 |
| Extended boot sig | $29 |
| FS type string | "FAT32" |

Key values (sectors/FAT, total sectors, partition start) are saved for use in subsequent checks.

### 3. Backup VBR Verification (1 test)

Reads partition sector 6 (backup VBR) and compares byte-by-byte with the primary VBR at partition sector 0. Reports the first mismatching offset if different.

### 4. FSInfo Verification (6 tests)

Reads partition sector 1 (FSInfo) and validates:

| Test | Expected Value |
|------|----------------|
| Lead signature | $41615252 at offset 0 |
| Structure signature | $61417272 at offset 484 |
| Trail signature | $AA550000 at offset $1FC |
| Free cluster count | Non-zero at offset 488 |
| Next free hint | $FFFFFFFF or >= 2 at offset 492 |
| Backup FSInfo match | Sector 7 matches sector 1 byte-for-byte |

### 5. FAT Table Verification (5 tests)

Reads the first sector of FAT1 and FAT2:

| Test | Expected Value |
|------|----------------|
| FAT[0] | $0FFFFFF8 (media type) |
| FAT[1] | $0FFFFFFF (EOC) |
| FAT[2] | $0FFFFFFF (root cluster EOC) |
| FAT[3] | 0 (free) |
| FAT1 == FAT2 | First sector byte-for-byte match |

Note: The audit checks the first sector only for FAT1/FAT2 comparison, while the FSCK utility compares all FAT sectors.

### 6. Root Directory Verification (3 tests)

Reads the first sector of the data region (cluster 2) and validates:

| Test | Expected Value |
|------|----------------|
| Volume label entry | Attribute byte $08 at offset $0B |
| Valid label chars | First byte is printable ASCII ($20-$7E) |
| Second entry | End marker ($00), deleted ($E5), or valid entry |

### 7. Mount Test (2 tests)

Uses the driver's high-level `mount()` API:

| Test | Expected Value |
|------|----------------|
| mount() succeeds | Returns TRUE |
| Free space > 0 | `freeSpace()` returns positive value |

This verifies the filesystem is mountable by the actual driver, not just structurally correct at the raw sector level.

## Test Framework

Each test uses the `runTest(pTestName, passed)` helper:
- Increments a global test counter
- If passed: increments `passCount`, prints `[PASS]` with test name
- If failed: increments `failCount`, prints `[FAIL]` with test name

The final summary reports total tests, passes, and failures, with an overall status of **OK** (0 failures) or **ISSUES DETECTED** (any failures).

## Typical Results

**Clean card** (freshly formatted): 41 tests, 41 pass, 0 fail

**Card after FSCK repair**: May show 2 failures in root directory verification if the volume label entry was overwritten by test data. These are cosmetic issues that don't affect filesystem operation.

## Relationship to FSCK

The audit and FSCK utilities are complementary:

| Feature | Audit | FSCK |
|---------|-------|------|
| Modifies card | No | Yes |
| Checks boot structures | Yes | Yes (+ repairs) |
| Checks FAT consistency | First sector only | All sectors |
| Walks directory tree | No | Yes |
| Detects lost clusters | No | Yes |
| Detects cross-links | No | Yes |
| Corrects free count | No | Yes |
| Mount test | Yes | No |

**Recommended workflow**: Run audit first (safe, read-only). If failures are detected, run FSCK to repair. Run audit again to verify repairs.
