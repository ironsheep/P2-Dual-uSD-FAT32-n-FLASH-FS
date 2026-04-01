# Changelog

All notable changes to the P2 Dual SD FAT32 + Flash Filesystem driver will be documented in this file.

Follows [Keep a Changelog](https://keepachangelog.com/) and [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.3.0] - 2026-03-29

SD sub-driver upgraded to v1.4.3: next-fit allocator, defragmentation API, contiguous file creation.

### Added
- **Next-fit allocator** (unconditional): `allocateCluster()` now scans from previous allocation point instead of always starting at cluster 2, reducing fragmentation and improving sequential write contiguity
- **Defragmentation API** (`SD_INCLUDE_DEFRAG`):
  - `fileFragments()`: Count non-contiguous fragments in a file's cluster chain
  - `isFileContiguous()`: Check if a file's clusters are stored contiguously
  - `createFileContiguous()`: Create a file with pre-allocated contiguous cluster chain for guaranteed zero-fragmentation writes
  - `compactFile()`: Relocate a fragmented file's clusters into a contiguous chain with copy-then-free and mandatory read-back verification
- **FSCK fragmentation reporting**: Audit and FSCK summaries now report fragmented file count and total fragments
- **Test hook**: `setTestMaxClusters()` for testing allocation wrap-around with artificially constrained FAT
- Named FAT32 constants: `ROOT_CLUSTER`, `FAT_EOC_MIN`, `FAT_BAD` (replace inline magic numbers)
- New error codes: `E_NO_CONTIGUOUS_SPACE`, `E_FILE_OPEN_FOR_COMPACT`, `E_VERIFY_FAILED`
- `DFS_SD_RT_defrag_tests` -- 12 tests for defrag API, contiguous creation, and next-fit allocation

### Changed
- `do_delete()` refactored: cluster-freeing loop extracted into reusable `freeClusterChain()`
- `auditRootDir()` improved: scans all entries in first root directory sector for volume label (not just offset 0)
- Regression suite expanded to 32 standard suites, 1,344 tests

## [1.2.0] - 2026-03-18

SD sub-driver upgraded to v1.4.0: live clock, auto-flush, non-blocking I/O, modification timestamps.

### Added
- **Internal date/time**: `setDate()` validates parameters and activates a 2-second clock; `getDate()` reads the Internal date/time
- **Auto-flush**: Dirty file handles and FSInfo flushed automatically after 200 ms idle
- **Non-blocking I/O** (`SD_INCLUDE_ASYNC`): `startReadHandle()`, `startWriteHandle()`, `isComplete()`, `getResult()`, `cancelAsync()`
- **Modification timestamps**: Files receive correct write timestamps on close and sync
- `wrtDate()`, `wrtTime()`: Read modification timestamps from directory entries
- **Demo shell**: `date` command (set/display), `dir` now shows date/time columns
- `DFS_SD_RT_timestamp_tests` -- 9 tests for live clock and date validation
- `DFS_SD_RT_async_tests` -- 12 tests for non-blocking I/O
- 3 auto-flush tests added to `DFS_SD_RT_volume_tests`

### Changed
- `setDate()`: Now validates parameters and returns status code (SUCCESS or E_INVALID_PARAM)
- Regression suite expanded to 31 standard suites, 1,332 tests

## [1.1.0] - 2026-03-09

### Fixed
- **BUGFIX**: SPI write data integrity at power-of-2 half-period clock speeds (`writeSector()` and `writeSectors()`)

### Added
- **Selective debug**: 12-channel `DEBUG_MASK` system for `debug[CH_xxx]()` output -- developers enable 2-3 channels at a time to stay under the P2 255-record limit
- **FlexSpin compatibility**: All 43 compilable files build with both pnut-ts and FlexSpin 7.6.1

### Changed
- Version directive upgraded from `{Spin2_v45}` to `{Spin2_v46}` (required for `debug[N]()` syntax)
- `DEBUG_DISABLE = 1` replaced by `DEBUG_MASK = 0` for production builds (finer control, same zero overhead)
- Unused variables removed across all 43 compiled files 
- Converted to lowercase preprocessor directives (`#ifdef`, `#pragma exportdef`) 

### Removed
- Manufacturer-specific SPI speed limiting -- all cards now use full reported speed

## [1.0.0] - 2026-03-07

Initial release of the unified dual-FS driver for the Parallax Propeller 2.

### Features
- **Unified driver**: `dual_sd_fat32_flash_fs.spin2` -- SD FAT32 and Flash filesystems managed by a single worker cog
- **SD FAT32**: 8.3 filenames, directory navigation, up to 6 simultaneous file handles, 25 MHz SPI
- **Flash filesystem**: 16 MB onboard Flash with wear leveling, CRC-32 integrity, and circular file support
- **Cross-device operations**: `copyFile()` and `moveFile()` between SD and Flash devices
- **Multi-cog safety**: hardware lock serializes access from up to 8 cogs via `WAITATN()`/`COGATN()` signaling
- **Status-returning API**: all PUB methods return status codes (SUCCESS=0 or negative error constant)
- **Flash directory emulation** — per-cog current working directory on the flat Flash filesystem using slash-delimited filename convention
- **Card presence detection**: `E_NO_CARD` (-8) via MISO pull-up probe during CMD0
- **Interactive shell**: `DFS_demo_shell.spin2` -- dual-device commands with `sd`/`fl` device switching, inline audit/fsck
- **Example programs**: basic mount/read/write, cross-device copy, data logger, SD manifest reader (4 programs)
- **Utilities**: SD format, SD audit, SD FSCK, SD card characterize, Flash format, Flash audit, Flash FSCK (7 utilities)
- **Regression tests**: 29 standard suites, 1,308 tests (SD, Flash, cross-device, dual-device, multi-cog) plus optional format and 8-cog stress tests
- **Documentation**: theory of operations, tutorial, utilities guide, memory sizing guide, Flash FS theory, utility theory docs
- **Conditional compilation**: `SD_INCLUDE_RAW`, `SD_INCLUDE_REGISTERS`, `SD_INCLUDE_SPEED`, `SD_INCLUDE_DEBUG` (and `SD_INCLUDE_ALL`)
- **Configurable resources**: `MAX_OPEN_FILES` and `MAX_FLASH_BUFFERS` independently tunable via OBJ overrides

### Hardware Verified
- Tested on P2 Edge Module with 32 GB GigaStone and Elite SD cards -- 29 suites, 1,308 tests, 0 failures on both

[Unreleased]: https://github.com/ironsheep/P2-Dual-uSD-FAT32-n-FLASH-FS/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/ironsheep/P2-Dual-uSD-FAT32-n-FLASH-FS/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/ironsheep/P2-Dual-uSD-FAT32-n-FLASH-FS/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ironsheep/P2-Dual-uSD-FAT32-n-FLASH-FS/releases/tag/v1.0.0
