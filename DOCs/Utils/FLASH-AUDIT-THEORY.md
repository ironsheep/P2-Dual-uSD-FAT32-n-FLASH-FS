# Flash Audit - Theory of Operations

*DFS_FL_audit.spin2*

## Overview

The Flash audit utility performs a read-only integrity check of the onboard Flash filesystem. It verifies that the filesystem mounts cleanly, reports block allocation statistics, and confirms that file iteration produces consistent results. It does **not** modify the Flash chip.

For a utility that can also repair problems, see `DFS_FL_fsck.spin2`.

## Design Philosophy

The Flash filesystem is simpler than FAT32 -- there is no partition table, boot record, or FAT to validate. Health is determined by whether blocks are internally consistent (valid lifecycle bits, correct CRC-32, no duplicate IDs, no orphans). The driver's `canMount()` API performs this check non-destructively.

The audit adds a second layer: after confirming mount readiness, it mounts the filesystem and verifies that file statistics are self-consistent by iterating every file.

## Three-Phase Architecture

```
Phase 1: canMount() health check
  |  Non-destructive scan of all 3,968 blocks
  v
Phase 2: Mount and statistics
  |  Mount, read stats (used/free/file count), read JEDEC serial
  v
Phase 3: File iteration verification
     Iterate all files via directory(), compare count with stats
```

### Phase 1: Non-Destructive Health Check

Calls `dfs.canMount(DEV_FLASH)`, which internally runs `fl_can_mount()`:

1. Scans all 3,968 blocks (`FL_BLOCKS`)
2. For each block with valid lifecycle bits (%011, %101, %110):
   - Reads the full 4 KB block
   - Validates CRC-32 (last LONG of block must match P2 hardware GETCRC of first 4,092 bytes)
   - Checks for duplicate block IDs (two blocks claiming the same file ID)
3. Traces file chains from head blocks to verify link integrity
4. Counts orphaned blocks (valid lifecycle but not part of any file chain)

If any blocks would need repair, `canMount()` returns a failure status and the audit reports FAIL. The audit stops here if Phase 1 fails, since mounting a damaged filesystem would trigger automatic repair (which is the FSCK utility's job, not the audit's).

### Phase 2: Mount and Statistics

If Phase 1 passes, the audit mounts the filesystem and reads:

| Metric | Source | Description |
|--------|--------|-------------|
| Used blocks | `stats(DEV_FLASH)` | Blocks allocated to files |
| Free blocks | `stats(DEV_FLASH)` | Blocks available for new data |
| File count | `stats(DEV_FLASH)` | Number of files |
| Total blocks | used + free | Should equal 3,968 |
| JEDEC serial | `serial_number(DEV_FLASH)` | Flash chip serial number (64-bit) |

The JEDEC serial number identifies the specific Flash chip on the board.

### Phase 3: File Iteration Verification

Iterates all files using `directory(DEV_FLASH, @blockId, @fname, @fsize)`:

1. Starts with `blockId := 0`
2. Each call returns the next file's name and size, advancing `blockId`
3. Continues until the returned filename is empty (zero-length)
4. Counts files and accumulates total bytes

The iteration count is compared against the file count from `stats()`. A mismatch indicates an inconsistency between the filesystem's file index and its directory traversal -- a sign of corruption that requires FSCK.

Output is capped at 20 files to keep the report readable; if more exist, a truncation message is shown.

## Typical Results

**Healthy filesystem** (freshly formatted or after normal use):
```
Phase 1: canMount: PASS
Phase 2: Mount: PASS, Used: 0, Free: 3968, Files: 0
Phase 3: File count: MATCH
AUDIT PASSED
```

**Filesystem with issues** (bad CRC, duplicates, or orphans):
```
Phase 1: canMount: FAIL (status=-300)
Flash may need format().
```

## Relationship to Flash FSCK

| Feature | Audit | FSCK |
|---------|-------|------|
| Modifies Flash | No | Yes (via mount) |
| canMount check | Yes | Yes |
| Reports statistics | Yes | Yes (before/after) |
| File iteration | Yes | No |
| Repairs corruption | No | Yes (automatic via mount) |

**Recommended workflow**: Run audit first (safe, read-only). If it reports FAIL, run FSCK to repair. Run audit again to verify.
