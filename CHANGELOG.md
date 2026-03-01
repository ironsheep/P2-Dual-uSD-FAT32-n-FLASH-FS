# Changelog

All notable changes to the P2 Dual SD FAT32 + Flash Filesystem driver will be documented in this file.

This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-02-28

Initial release of the unified dual-FS driver.

### Added
- **Unified driver** (`dual_sd_fat32_flash_fs.spin2`) combining SD FAT32 and Flash filesystems in a single cog
- **SD FAT32 support**: full FAT32 filesystem with 8.3 filenames, directory navigation, up to 6 simultaneous file/directory handles, SPI mode at 25 MHz
- **Flash support**: block-based filesystem on onboard 16 MB Flash chip with wear leveling, CRC-32 integrity, up to 6 simultaneous file handles
- **Cross-device operations**: `copyFile()` between SD and Flash devices
- **Shared SPI bus management**: automatic bus switching between SD (Mode 0) and Flash (Mode 3) with proper smart pin reconfiguration
- **Multi-cog safety**: hardware lock serializes access from up to 8 cogs
- **Conditional compilation**: `SD_INCLUDE_RAW`, `SD_INCLUDE_REGISTERS`, `SD_INCLUDE_SPEED`, `SD_INCLUDE_DEBUG` for minimal builds
- **Status-returning API**: all methods return status codes (SUCCESS=0 or negative error) rather than boolean
- **Feature parity**: Flash directory emulation, SD `exists()`, `file_size()`, `serial_number()`, `stats()`, byte/word/long/string I/O, seek with whence
- **Interactive demo shell** (`DFS_demo_shell.spin2`): dual-device shell with DOS/Unix-style commands, device switching, cross-device copy, audit/fsck
- **Example programs**: basic mount/read/write, cross-device copy, data logger
- **Utility programs**: `DFS_SD_format_card`, `DFS_SD_FAT32_audit`, `DFS_SD_FAT32_fsck`, `DFS_SD_card_characterize`, `DFS_FL_format`, `DFS_FL_audit`, `DFS_FL_fsck`
- **Regression test suite**: 912+ tests across 35 test files covering SD operations, Flash operations, cross-device operations, and multi-cog scenarios
- **Documentation**: driver theory of operations, tutorial, utilities guide, Flash filesystem theory, memory sizing guide
- README files in all `src/` and `DOCs/` subdirectories

### Architecture
- Worker cog pattern: dedicated cog runs command loop, caller cogs send commands via parameter block and wait via `WAITATN()`
- SD: smart pin SPI engine (P_TRANSITION clock, P_SYNC_TX/RX data)
- Flash: GPIO bit-bang with inverted clock polarity (Mode 3)
- Handle pool shared across both devices; each handle tracks its device
- SD card re-initialization after Flash operations (P60 doubles as Flash SCK)
- Source tree: driver in `src/`, demo in `src/DEMO/`, examples in `src/EXAMPLES/`, utilities in `src/UTILS/`, tests in `src/regression-tests/`

[Unreleased]: https://github.com/ironsheep/P2-Dual-uSD-FAT32-n-FLASH-FS/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ironsheep/P2-Dual-uSD-FAT32-n-FLASH-FS/releases/tag/v1.0.0
