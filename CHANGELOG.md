# Changelog

All notable changes to the P2 Dual SD FAT32 + Flash Filesystem driver will be documented in this file.

Follows [Keep a Changelog](https://keepachangelog.com/) and [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/ironsheep/P2-Dual-uSD-FAT32-n-FLASH-FS/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/ironsheep/P2-Dual-uSD-FAT32-n-FLASH-FS/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ironsheep/P2-Dual-uSD-FAT32-n-FLASH-FS/releases/tag/v1.0.0
