# Flash Format Utility - Theory of Operations

*DFS_FL_format.spin2*

## Overview

The Flash format utility erases the onboard 16MB Flash filesystem, returning it to a clean empty state. Unlike the SD format utility (which builds a complex FAT32 disk layout), Flash formatting is straightforward: cancel every active block, then remount to rebuild the translation tables.

The utility uses the unified driver's `format(DEV_FLASH)` API, which routes to the internal `fl_format()` method running in the worker cog.

## Flash Filesystem Structure

The Flash filesystem occupies blocks $080 through $FFF of the W25Q128JV SPI Flash chip:

| Region | Blocks | Size | Purpose |
|--------|--------|------|---------|
| Boot image | $000-$07F | 512 KB | Reserved for P2 boot code (not touched by FS) |
| Filesystem | $080-$FFF | 15.5 MB | 3,968 blocks available for files |

Each block is 4 KB ($1000 bytes). The first byte of every block contains **lifecycle bits** that track the block's wear-leveling generation:

| Bits [7:5] | State | Meaning |
|------------|-------|---------|
| %000 | Erased | Block has been erased (all $FF) |
| %011 | Active (gen 1) | Block contains valid data |
| %101 | Active (gen 2) | Block contains valid data (next generation) |
| %110 | Active (gen 3) | Block contains valid data (next generation) |
| %001 | Cancelled | Block was cancelled (data invalid) |

The three active patterns cycle: %011 -> %101 -> %110 -> %011, providing wear-leveling without requiring a block erase. Flash bits can only be programmed from 1 to 0; the lifecycle pattern exploits this to transition between generations using single-byte writes.

## Format Sequence

The `fl_format()` method performs two steps:

### 1. Cancel All Active Blocks

```
repeat FL_BLOCKS with block_address
  fl_read_block_addr(block_address, @cycleBits, $000, $000)   ' Read first byte
  if lookdown(cycleBits.[7..5] : %011, %101, %110)            ' Active?
    fl_cancel_block(block_address)                             ' Cancel it
```

For each of the 3,968 filesystem blocks:
1. Read the first byte to check the lifecycle bits
2. If the block is active (any of the three valid lifecycle patterns), cancel it

**Cancelling a block** programs %00011111 into the first byte. This clears the upper lifecycle bits to %000xx, which is not a valid active pattern. The block is now effectively dead -- it will be ignored during the next mount.

Note: Erased blocks (%000 in bits [7:5]) and already-cancelled blocks are skipped. Only blocks with valid lifecycle patterns are touched.

### 2. Remount

After cancelling all blocks, the format clears the `flash_mounted` flag and calls `do_flash_mount()`. The mount process scans all blocks and rebuilds the translation tables. Since every block is now cancelled or erased, the mount finds no valid files and creates a clean, empty filesystem.

## Driver API

```spin2
OBJ dfs : "dual_sd_fat32_flash_fs"

' Initialize and mount
dfs.init(CS, MOSI, MISO, SCK)
status := dfs.mount(dfs.DEV_FLASH)

' Format (erases all files)
status := dfs.format(dfs.DEV_FLASH)

' Clean up
dfs.stop()
```

`format()` returns `SUCCESS` on completion. The mount attempt before format is optional -- `format()` works on both mounted and unmounted Flash.

## Comparison with SD Format

| Aspect | Flash Format | SD Format |
|--------|-------------|-----------|
| Complexity | Simple (cancel + remount) | Complex (MBR, VBR, FSInfo, FAT, root dir) |
| Time | < 1 second | Minutes (FAT table writes) |
| Mechanism | Program lifecycle bits to cancel | Write entire disk structure |
| Library needed | None (built into driver) | `isp_format_utility.spin2` (temp cog) |
| Block erase | Not required | N/A (sector writes) |

Flash formatting is fast because it only needs to program a single byte per active block. There is no need to erase the Flash chip -- cancelled blocks will be erased on demand when the filesystem needs free space for new writes.

## Recovery

If the Flash filesystem becomes corrupt and `format()` cannot recover it (e.g., the SPI bus is not functional), the Flash chip can be bulk-erased externally. After a chip erase, all blocks return to $FF (erased state), and the next `mount()` will create a clean filesystem.
