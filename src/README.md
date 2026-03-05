# Source Tree

Unified dual-filesystem driver and associated programs for the Parallax Propeller 2 (P2). Supports simultaneous access to an onboard 16MB Flash chip and a microSD card (FAT32) via shared SPI bus.

## Contents

| Path | Description |
|------|-------------|
| `dual_sd_fat32_flash_fs.spin2` | Unified dual-FS driver (SD FAT32 + Flash) |
| `isp_stack_check.spin2` | Stack depth measurement utility (conditional via SD_INCLUDE_STACK_CHECK) |
| [DEMO/](DEMO/) | Interactive dual-device filesystem shell |
| [EXAMPLES/](EXAMPLES/) | Compilable example programs |
| [UTILS/](UTILS/) | Standalone utilities (format, audit, fsck, characterize) |
| [regression-tests/](regression-tests/) | Regression test suites (32 standard suites, 1,300+ tests) |

## Building

All source files compile with `pnut-ts`. Files in subdirectories use `-I ..` to find the driver in this directory:

```bash
# From src/
pnut-ts -d dual_sd_fat32_flash_fs.spin2

# From a subdirectory (EXAMPLES/, regression-tests/, etc.)
pnut-ts -d -I .. <filename>.spin2
```

## Hardware

Requires a Parallax P2 Edge Module (P2-EC or P2-EC32MB) connected via USB.

---

*Part of the [P2 Dual SD FAT32 + Flash Filesystem](../README.md) project — Iron Sheep Productions*
