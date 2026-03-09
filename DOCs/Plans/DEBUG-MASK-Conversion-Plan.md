# Plan: DEBUG_MASK Channel Conversion for Dual FS Driver

**Date:** 2026-03-09
**Driver:** `src/dual_sd_fat32_flash_fs.spin2`
**Reference:** Sister driver `micro_sd_fat32_fs.spin2` channel scheme (v1.3.2)
**Guides:** `DOCs/procedures/DEBUG-MASK-Usage-Guide.md`, `Debug-Strategy-Guide.md`, `DEBUG-MASK-CHANNELS-GUIDE.md`

---

## Problem

The dual FS driver has **~448 debug() statements** but the P2 compiler limits debug records to **255 max**. Currently `DEBUG_DISABLE = 1` — all debug is killed. We need selective debug via `DEBUG_MASK` + `debug[N]()` channels so developers can enable 2-3 channels at a time and stay under 255 records.

## Design Goals

1. **Channel consistency with sister driver** — Users of both the standalone SD driver and the dual FS driver should recognize the same channel names and meanings
2. **Both devices share the same channel concepts** — SD mount and Flash mount both use CH_MOUNT; SD file ops and Flash file ops both use CH_FILE. This mirrors how the dual driver presents a unified API
3. **Flash-unique operations get new channels** — Block-level I/O and circular file operations have no SD equivalent
4. **Any 3 channels combined stay under 255 records**

## Current Debug Landscape

| Category | Debug Stmts | % of Total |
|----------|-------------|-----------|
| SD-specific methods | ~145 | 32% |
| Shared/dual infrastructure | ~289 | 64% |
| Flash-specific methods | ~16 | 4% |
| **Total** | **~448** | |

**Flash is lightly instrumented** — only 16 statements across 71 Flash methods (89% have zero debug). This means Flash channel counts will be small initially but will grow as instrumentation is added.

## Channel Scheme (12 channels)

Channels 0-9 mirror the sister SD driver. Channels 10-11 are Flash-unique.

```spin2
CON ' debug channel assignments for selective debug output
  ' --- Channels 0-9: Same meaning as standalone SD driver ---
  CH_INIT    = 0              ' Card/device initialization, pin setup, speed config
  CH_MOUNT   = 1              ' Mount/unmount, filesystem geometry, FSInfo
  CH_FILE    = 2              ' File handle operations: open, close, read, write, seek, sync
  CH_DIR     = 3              ' Directory operations: search, create, rename, move, CWD
  CH_SECTOR  = 4              ' Sector/block I/O, FAT chain walking, cluster allocation
  CH_STATUS  = 5              ' CMD13/CMD23 probe and runtime status checks (SD only)
  CH_IDENT   = 6              ' Card identity: CID/CSD/SCR parsing, timeouts (SD only)
  CH_HSPEED  = 7              ' High-speed mode: CMD6 query, switch, verify (SD only)
  CH_API     = 8              ' Public API entry points, worker cog dispatch, stack guard
  CH_RECOVER = 9              ' Error recovery: CMD12, bus recovery, wait timeouts

  ' --- Channels 10-11: Flash-unique operations ---
  CH_FL_BLOCK = 10            ' Flash block-level I/O: read/write/erase 4KB blocks, wear leveling
  CH_FL_CIRC  = 11            ' Flash circular files: froncate, wrap, old-format detection

  DEBUG_MASK = (1 << CH_INIT) | (1 << CH_MOUNT)  ' Default: init + mount
```

### Channel Mapping Rationale

| Channel | SD Usage | Flash Usage | Shared? |
|---------|----------|-------------|---------|
| CH_INIT (0) | initCard, initSPIPins, cmd | Flash SPI init, chip detect | Yes |
| CH_MOUNT (1) | do_mount, VBR/FSInfo | do_flash_mount, block scan, fl_can_mount | Yes |
| CH_FILE (2) | do_open_read/write, do_read_h, do_write_h, do_seek_h, do_close_h | fl_open, fl_close, fl_read, fl_write, fl_seek, fl_finish_open_read | Yes |
| CH_DIR (3) | searchDirectory, do_newdir, do_rename, do_chdir, do_open_dir | fl_prepend_cwd, Flash CWD ops, Flash dir handles | Yes |
| CH_SECTOR (4) | readSector, writeSector, readSectors, writeSectors, allocateCluster, readFat | (not used — Flash uses CH_FL_BLOCK instead) | SD only |
| CH_STATUS (5) | probeCmd13, probeCmd23, checkCardStatus, testCMD13 | (not used) | SD only |
| CH_IDENT (6) | identifyCard, readCID/CSD/SCR, parseMfrId | do_flash_serial_number | Yes (minimal Flash) |
| CH_HSPEED (7) | queryHighSpeedSupport, switchToHighSpeed, do_attempt_high_speed | (not used) | SD only |
| CH_API (8) | mount/unmount PUBs, fs_worker dispatch, send_command | Same worker cog serves both devices | Yes |
| CH_RECOVER (9) | sendStopTransmission, recoverToIdle, reinitCard, waitDataToken | SPI bus switching (switch_to_sd, switch_to_flash) | Yes |
| CH_FL_BLOCK (10) | (not used) | fl_write_block, fl_read_block, fl_program_block, fl_erase_block, fl_activate_block, fl_delete_chain | Flash only |
| CH_FL_CIRC (11) | (not used) | fl_froncate_file, circular file wrap detection, old-format compat | Flash only |

### Estimated Channel Sizes (After Full Conversion)

| Channel | Current Stmts | Est. After Instrumentation | Notes |
|---------|---------------|---------------------------|-------|
| CH_INIT (0) | ~66 | ~70 | initCard (35), initSPIPins (11), Flash SPI init |
| CH_MOUNT (1) | ~52 | ~60 | do_mount (26), do_flash_mount (6), fl_can_mount (2) |
| CH_FILE (2) | ~62 | ~80 | SD file ops + Flash file ops (currently uninstrumented) |
| CH_DIR (3) | ~35 | ~50 | SD dir ops + Flash dir ops (currently uninstrumented) |
| CH_SECTOR (4) | ~39 | ~39 | SD sector I/O only |
| CH_STATUS (5) | ~71 | ~71 | SD status probes only |
| CH_IDENT (6) | ~36 | ~38 | SD registers + Flash serial number |
| CH_HSPEED (7) | ~24 | ~24 | SD only |
| CH_API (8) | ~17 | ~25 | Worker cog dispatch, PUB wrappers |
| CH_RECOVER (9) | ~29 | ~35 | SD recovery + SPI bus switching |
| CH_FL_BLOCK (10) | ~3 | ~20 | Flash block I/O (needs instrumentation) |
| CH_FL_CIRC (11) | ~2 | ~10 | Circular file ops |

**Validation:** Largest 3 channels (CH_FILE ~80 + CH_STATUS ~71 + CH_INIT ~70) = ~221, under 255.

## Implementation Steps

### Change A: Version Directive and Channel Constants

**File:** `dual_sd_fat32_flash_fs.spin2` (top of file)

1. Change `{Spin2_v45}` to `{Spin2_v46}` (required for `debug[N]()` syntax)
2. Remove `DEBUG_DISABLE = 1`
3. Add channel CON constants and `DEBUG_MASK` default (as shown above)

### Change B: Convert SD Debug Statements (Channels 0-9)

Convert every `debug(` in SD-specific and shared methods to `debug[CH_xxx](` based on functional area. Use the same assignment rules as the sister driver:

| Method Pattern | Channel |
|---|---|
| initCard, initSPIPins, cmd, applySPISpeed | CH_INIT |
| do_mount, do_unmount, updateFSInfo | CH_MOUNT |
| do_open_read, do_open_write, do_read_h, do_write_h, do_seek_h, do_close_h, do_sync_h | CH_FILE |
| searchDirectory, do_newdir, do_rename, do_chdir, do_open_dir, do_movefile | CH_DIR |
| readSector, writeSector, readSectors, writeSectors, allocateCluster, readFat, readNextSector | CH_SECTOR |
| probeCmd13, probeCmd23, checkCardStatus, testCMD13 | CH_STATUS |
| identifyCard, readCID/CSD/SCR, parseMfrId | CH_IDENT |
| queryHighSpeedSupport, switchToHighSpeed, do_attempt_high_speed | CH_HSPEED |
| mount (PUB), unmount (PUB), fs_worker dispatch, send_command, checkStackGuard | CH_API |
| sendStopTransmission, recoverToIdle, reinitCard, waitDataToken, switch_to_sd | CH_RECOVER |

**Mixed-channel methods:** Assign by what the specific debug statement reports, not just the method name (same rule as sister driver).

### Change C: Convert Flash Debug Statements (Channels 1, 2, 3, 6, 10, 11)

Convert existing Flash debug statements:

| Method | Channel |
|---|---|
| do_flash_mount, fl_can_mount | CH_MOUNT |
| fl_finish_open_read | CH_FILE |
| do_flash_serial_number | CH_IDENT |
| fl_format | CH_MOUNT |
| fl_write_block, fl_delete_chain_from_id | CH_FL_BLOCK |
| fl_froncate_file (both stmts) | CH_FL_CIRC |

### Change D: Add Flash Instrumentation (Future — Not This PR)

Flash methods currently lacking debug (63 of 71 methods) should be instrumented in a follow-up pass. Priority areas:
- **fl_open, fl_close, fl_read, fl_write, fl_seek** → CH_FILE
- **fl_read_block_id, fl_read_block_addr, fl_program_block** → CH_FL_BLOCK
- **Flash CWD and directory handle methods** → CH_DIR
- **fl_count_file_bytes, fl_locate_file_byte** → CH_FL_BLOCK

This is deferred because adding new debug statements requires understanding the Flash code paths and choosing the right debug content. The current task is converting existing statements.

### Change E: Verification

1. **Count verification:** `grep -c 'debug(' driver.spin2` should match only string literals or comments; `grep -c 'debug\[' driver.spin2` should equal total debug statement count
2. **Compile check:** `pnut-ts -d` with `DEBUG_MASK = (1 << CH_INIT) | (1 << CH_MOUNT)` — must compile without exceeding 255 records
3. **Compile check:** Verify with 3 largest channels enabled simultaneously
4. **FlexSpin check:** `flexspin.mac -2` compile check
5. **Regression:** `run_regression.sh --compile-only` (29 suites)

### Change F: Consumer Files (Test Suites, Demo, Examples, Utilities)

Consumer files use their own `debug()` statements (separate record budget from the driver). They do NOT need `DEBUG_MASK` or channel constants — those are internal to the driver object.

**No changes needed** to consumer files for this conversion.

### Change G: Documentation

1. Update `DOCs/CONDITIONAL-COMPILATION-GUIDE.md` — add DEBUG_MASK section
2. Update `DOCs/DUAL-DRIVER-THEORY.md` — document channel scheme
3. Create `DOCs/procedures/DEBUG-MASK-CHANNELS-GUIDE-DUAL.md` — dual driver channel reference (parallel to sister driver's guide)

## Execution Order

1. Change A (version directive + constants) — 5 min
2. Change B (convert SD debug stmts) — bulk edit, ~430 conversions
3. Change C (convert Flash debug stmts) — 16 conversions
4. Change E (verification) — compile checks
5. Change G (documentation)
6. Change D (deferred — future Flash instrumentation)

## Risk Assessment

- **Low risk:** This is a compile-time-only change. No runtime behavior changes.
- **The mask is internal to the driver** — consumer code is unaffected.
- **Reversible:** Setting `DEBUG_MASK = 0` is equivalent to `DEBUG_DISABLE = 1`.
- **FlexSpin compatibility:** Both pnut-ts and FlexSpin 7.6.1 support `DEBUG_MASK` and `debug[N]()`.

---

*Plan produced 2026-03-09 -- Iron Sheep Productions*
