# Changelog

All notable changes to the P2 Dual SD FAT32 + Flash Filesystem driver will be documented in this file.

Follows [Keep a Changelog](https://keepachangelog.com/) and [Semantic Versioning](https://semver.org/). See [changelog-style-guide.md](DOCs/procedures/changelog-style-guide.md) for conventions.

## [Unreleased]

### Changed
- **Regression test hardening**: consolidated two test utilities into unified `DFS_RT_utilities.spin2`, fixed test-code bugs, replaced tautological assertions, converted DAT state to locals, added Flash absolute path tests, fixed sub-test counting -- 32 standard suites now produce 1,335 tests (up from 912), all hardware-verified

## [1.0.0] - 2026-02-28

Initial release of the unified dual-FS driver.

### Added
- **Unified driver**: `dual_sd_fat32_flash_fs.spin2` — SD FAT32 and Flash filesystems in a single cog
- **SD FAT32**: 8.3 filenames, directory navigation, up to 6 simultaneous handles, 25 MHz SPI
- **Flash filesystem**: 16 MB onboard Flash with wear leveling and CRC-32 integrity
- **Cross-device copy**: `copyFile()` between SD and Flash devices
- **Multi-cog safety**: hardware lock serializes access from up to 8 cogs
- **Conditional compilation**: `SD_INCLUDE_RAW`, `SD_INCLUDE_REGISTERS`, `SD_INCLUDE_SPEED`, `SD_INCLUDE_DEBUG`
- **Status-returning API**: all PUB methods return status codes (SUCCESS=0 or negative error)
- **Feature parity**: `exists()`, `file_size()`, `serial_number()`, `stats()`, byte/word/long/string I/O, seek with whence
- **Flash CWD emulation**: `changeDirectory()` support for Flash with per-cog isolation
- **Interactive shell**: `DFS_demo_shell.spin2` — dual-device commands, device switching, audit/fsck
- **Example programs**: basic mount/read/write, cross-device copy, data logger
- **Utilities**: SD and Flash format, audit, fsck, and SD card characterize
- **Regression tests**: 32 standard suites (SD, Flash, cross-device, multi-cog) plus optional format and 8-cog stress
- **Documentation**: theory of operations, tutorial, utilities guide, memory sizing guide

[Unreleased]: https://github.com/ironsheep/P2-Dual-uSD-FAT32-n-FLASH-FS/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ironsheep/P2-Dual-uSD-FAT32-n-FLASH-FS/releases/tag/v1.0.0
