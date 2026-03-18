# Changelog

All notable changes to the P2 Dual SD FAT32 + Flash Filesystem driver will be documented in this file.

Follows [Keep a Changelog](https://keepachangelog.com/) and [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.2.0] - 2026-03-18

Update SD sub-driver to v1.4.0 feature set: live clock, auto-flush, non-blocking I/O, and modification timestamps.

### Added
- **Live clock**: `setDate()` now validates parameters and activates a 2-second FIELD-based clock that ticks inside the worker loop. New `getDate()` reads the live clock from any cog.
- **Auto-flush**: After 200 ms of idle time the worker cog automatically flushes all dirty file handles and FSInfo -- protects against data loss on card removal without `closeFileHandle()` or `unmount()`
- **Non-blocking I/O** (`SD_INCLUDE_ASYNC`): `startReadHandle()`, `startWriteHandle()`, `isComplete()`, `getResult()`, `cancelAsync()` -- caller cog runs at full 350 MHz while the SD I/O completes
- **Modification timestamps**: `do_close_h()` and `do_sync_h()` now write `date_stamp` to the directory entry's WrtTime/WrtDate fields on every flush
- **Directory entry accessors**: `wrtDate()` and `wrtTime()` PUB methods for reading modification timestamps from the current entry
- **Demo shell**: `date` command (set/display), `dir` now shows date/time columns for SD listings
- **New test suites**: `DFS_SD_RT_timestamp_tests` (9 tests), `DFS_SD_RT_async_tests` (12 tests), 3 auto-flush tests added to `DFS_SD_RT_volume_tests`
- **Error codes**: `E_INVALID_PARAM` (-94), `E_ASYNC_BUSY` (-95), `E_NO_ASYNC_OP` (-96)
- **Constants**: `IDLE_FLUSH_MS` (200), `PENDING` (1)

### Changed
- Worker loop restructured from tight blocking poll to multi-concern architecture (clock tick, command dispatch, auto-flush)
- `setDate()` now returns `: status` (SUCCESS or E_INVALID_PARAM) -- previously void
- SD sub-driver version bumped to v1.4.0
- Regression runner updated: 31 standard suites, 1,332 tests

### Hardware Verified
- Full regression: 31 suites, 1,332 tests, 0 failures
- Both pnut-ts and FlexSpin compile clean

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
