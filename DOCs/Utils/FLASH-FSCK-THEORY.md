# Flash FSCK - Theory of Operations

*DFS_FL_fsck.spin2*

## Overview

The Flash FSCK (Filesystem Check) utility detects and repairs corruption in the onboard Flash filesystem. Unlike the SD FSCK utility (which implements a custom four-pass repair engine), Flash FSCK leverages the **mount process itself** as the repair mechanism -- the Flash driver's mount routine already resolves duplicates, cancels orphans, and validates CRC-32 checksums.

## Design Rationale

The Flash filesystem's block-based architecture makes repair straightforward:

- **Duplicate block IDs**: Two blocks claiming the same file ID. Mount keeps the one with the newer lifecycle generation and cancels the other.
- **Orphaned blocks**: Blocks with valid lifecycle bits but not part of any file chain. Mount cancels them, returning their space to the free pool.
- **Bad CRC blocks**: Blocks where the stored CRC-32 does not match the computed CRC of the block data. Mount treats these as invalid and cancels them.

All three repair actions are performed by `fl_cancel_block()`, which programs %00011111 into the block's first byte, clearing its lifecycle bits. The block becomes effectively dead and will be erased when the filesystem needs space.

Because mount already handles repair, the FSCK utility only needs to:
1. Detect whether repair is needed (`canMount`)
2. If so, trigger repair (`mount`)

## Two-Phase Architecture

```
Phase 1: canMount() health check (read-only)
  |
  +---> PASS: Mount, report stats, done
  |
  +---> FAIL: Proceed to Phase 2
        |
        v
Phase 2: mount() for repair
     Mount triggers automatic repair, report post-repair stats
```

### Phase 1: Read-Only Health Check

Calls `dfs.canMount(DEV_FLASH)`, which runs `fl_can_mount()` internally:

1. Clears translation tables
2. **Pass 1**: Scans all 3,968 blocks -- reads lifecycle bits, validates CRC-32, detects duplicate IDs. Uses `fl_check_block_read_only()` (never calls `fl_cancel_block()`).
3. **Pass 2**: Traces file chains from head blocks, sets B_HEAD/B_BODY flags
4. **Pass 3**: Counts remaining B_TEMP blocks (orphans). Read-only -- does NOT cancel them.

Returns TRUE if zero bad blocks were found, FALSE otherwise.

**If PASS**: The filesystem is clean. FSCK mounts to collect statistics (used/free/file count), reports them, and exits with "No repairs needed."

**If FAIL**: Proceeds to Phase 2.

### Phase 2: Repair via Mount

Calls `dfs.mount(DEV_FLASH)`, which runs `do_flash_mount()`:

1. **M1 pass**: Scans all blocks, fixes duplicate IDs by cancelling the older generation (`fl_check_block_fix_dupe_id`)
2. **M2 pass**: Traces file chains from head blocks, sets B_HEAD/B_BODY flags
3. **M3 pass**: Cancels all remaining B_TEMP blocks (orphaned or corrupt). Each cancelled block is freed and its ID is released.

After mount completes, FSCK reads post-repair statistics and reports:
- Used blocks, free blocks, and file count
- Overall status: REPAIRS APPLIED or FAILED

If mount itself fails (e.g., Flash chip not responding), FSCK reports that `format()` may be needed to recover.

## Repair Actions

| Problem | Detection | Repair |
|---------|-----------|--------|
| Duplicate block ID | Two blocks with same ID in translation table | Cancel block with older lifecycle generation |
| Orphaned block | Valid lifecycle but no file chain reference | Cancel block, return to free pool |
| Bad CRC-32 | Stored CRC != computed CRC of block data | Block stays B_FREE (never promoted to B_TEMP) |
| Corrupt lifecycle | Bits [7:5] not in {%011, %101, %110} | Already treated as free -- no action needed |

## Comparison with SD FSCK

| Aspect | Flash FSCK | SD FSCK |
|--------|-----------|---------|
| Architecture | 2-phase (detect + mount-repair) | 4-pass (structural, chain, lost clusters, FAT sync) |
| Repair engine | Built into `do_flash_mount()` | Custom `isp_fsck_utility.spin2` (temp cog) |
| Time complexity | ~1 second (block scan) | ~60 seconds (FAT scan on 16 GB card) |
| Hub RAM | No extra (uses driver tables) | 256 KB bitmap for cluster tracking |
| Repairs cross-links | N/A (no FAT chain structure) | Detects but cannot untangle |
| FAT sync | N/A | Copies FAT1 -> FAT2 |

## Typical Results

**Clean filesystem**:
```
Phase 1: Health check: PASS (no issues detected)
  Used blocks: 12   Free blocks: 3956   File count: 3
FSCK COMPLETE - No repairs needed
```

**Filesystem with orphaned blocks**:
```
Phase 1: Health check: ISSUES DETECTED
Phase 2: Repairing via mount...
  Mount/repair: SUCCESS
  Post-repair statistics:
  Used blocks: 12   Free blocks: 3956   File count: 3
FSCK COMPLETE - Repairs applied
```

**Unrecoverable corruption**:
```
Phase 1: Health check: ISSUES DETECTED
Phase 2: Mount/repair FAILED
  Flash may need format() to recover.
FSCK FAILED - Manual intervention required
```
