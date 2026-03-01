# Changelog

All notable changes to the P2 Dual SD FAT32 + Flash Filesystem driver will be documented in this file.

This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- **BREAKING API CHANGE**: 15 PUB methods now return status codes (SUCCESS=0 or negative error) instead of boolean (TRUE/FALSE):
  - File management: `deleteFile()`, `rename()`, `moveFile()`, `setVolumeLabel()`
  - Directory: `newDirectory()`, `changeDirectory()`
  - Sync: `sync()`
  - Raw access: `initCardOnly()`, `readCIDRaw()`, `readCSDRaw()`, `readSCRRaw()`, `readSDStatusRaw()`, `readVBRRaw()`, `writeSectorRaw()`, `readSectorRaw()`
  - Callers checking `if result` or `if not method()` must change to `if status == dfs.SUCCESS` / `if status <> dfs.SUCCESS`
- All test files, utilities, demo shell, and examples updated for status-returning methods
- Reorganized phase-specific regression tests by function:
  - `DFS_RT_dual_device_tests.spin2` (37 tests) — Flash mount, bus switching, SD integrity, handle pool (replaces Phase 1/2/3 verify files)
  - `DFS_RT_cross_device_tests.spin2` (21 tests) — interleaved I/O, copyFile(), edge cases (replaces Phase 6 file)
  - Removed 65 redundant tests already covered by migrated SD and Flash suites
  - Updated `run_all_regression.sh` to use new file names and fixed stale paths

### Added
- `DFS_SD_RT_parity_tests.spin2` — 32 tests for Feature Parity methods: `exists()`, `file_size()`, `file_size_unused()`, `serial_number()`, `stats()`, `seek()` with whence, `open()` modes on SD
- `DFS_FL_RT_cwd_tests.spin2` — 20 tests for Flash CWD emulation: `changeDirectory()` basics/parent/root, file isolation across directories, `openDirectory()` returns E_NOT_SUPPORTED, CWD-aware open/delete/rename/exists
- Cross-device handle pool tests (6 tests in dual_device): shared pool exhaustion, cross-device slot reclaim, interleaved open/close
- Cross-device edge cases (4 tests in cross_device): copyFile to existing file, seekHandle + write at position on SD, seekHandle + read at position on Flash
- Register coverage (8 tests in register_tests): CID/readCIDRaw, SCR/readSCRRaw, OCR/getOCR, SD Status/readSDStatusRaw
- Error path edge cases (6 tests in error_handling): deleteFile/rename on open file, mount(99) bad device, writeHandle/readHandle count=0, seekHandle past EOF
- Feature parity plan: Flash directory emulation, SD `exists()`, `file_size()`, `serial_number()`, `stats()`, byte/word/long/string I/O, seek with whence, `openFileWrite` semantic alignment
- SD and Flash utility programs: `DFS_SD_format_card`, `DFS_SD_FAT32_audit`, `DFS_SD_FAT32_fsck`, `DFS_SD_card_characterize`, `DFS_FL_format`, `DFS_FL_audit`, `DFS_FL_fsck`
- Flash audit and fsck support in the demo shell
- GitHub issue templates and release workflow
- `DOCs/Reference/MEMORY-SIZING-GUIDE.md` updated for unified driver
- README files in all `src/` and `DOCs/` subdirectories

### Changed
- Driver renamed from `dual_fs.spin2` to `dual_sd_fat32_flash_fs.spin2`
- Source tree reorganized: demo shell to `src/DEMO/`, examples to `src/EXAMPLES/`, utilities to `src/UTILS/`
- Documentation updated for dual-device scope throughout

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
- **Interactive demo shell** (`DFS_demo_shell.spin2`): dual-device shell with DOS/Unix-style commands, device switching, cross-device copy, audit/fsck
- **Example programs**: basic mount/read/write, cross-device copy, data logger
- **Regression test suite**: 1,200+ tests across 35 test files covering SD operations, Flash operations, cross-device operations, and multi-cog scenarios
- **Documentation**: driver theory of operations, tutorial, utilities guide, Flash filesystem theory, memory sizing guide

### Architecture
- Worker cog pattern: dedicated cog runs command loop, caller cogs send commands via parameter block and wait via `WAITATN()`
- SD: smart pin SPI engine (P_TRANSITION clock, P_SYNC_TX/RX data)
- Flash: GPIO bit-bang with inverted clock polarity (Mode 3)
- Handle pool shared across both devices; each handle tracks its device
- SD card re-initialization after Flash operations (P60 doubles as Flash SCK)

[Unreleased]: https://github.com/ironsheep/P2-Dual-uSD-FAT32-n-FLASH-FS/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ironsheep/P2-Dual-uSD-FAT32-n-FLASH-FS/releases/tag/v1.0.0
