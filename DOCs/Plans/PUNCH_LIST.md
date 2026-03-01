# Punch List — Pre-Release Cleanup

Items to resolve before release. Accumulated during Phase 3+ implementation.

---

## 1. Eliminate all `result` return variable names

Every PUB and PRI method must name its return value for what it actually is — not `result`. This applies to the entire codebase (SD-origin PUBs included), not just Phase 3 code.

**Rule**: Return names describe the content:
- Status codes → `status`
- Booleans → `found`, `deleted`, `renamed`, `is_mounted`, `ok`, `bIntact`, etc.
- Counts → `free_count`, `bytes_read`, `sector_count`
- Handles → `handle`
- Specific values → `workerCog`, `size_in_bytes`, `error_code`

**Scope**: All PUB/PRI methods in `dual_sd_fat32_flash_fs.spin2`. Phase 3 methods are mostly fixed; the pre-existing SD-origin PUBs still use `result` throughout (mount, unmount, readSectorRaw, writeSectorRaw, newFile, openFile, sync, moveFile, etc.).

---

## 2. Consistent VSCode documentation style

Audit/Repair ALL .spin2 project files to precisely follow [VSCode Style Guide](./CODE-STYLE-GUIDE.md)

---

## 3. Plan for method ordering within driver source file

Ensure the developer reading the driver source code sees a sense of order within the list of methods within the driver

Pedagogically, is there an order we should use to methods appearing in the file? Thoughts:

- public then private?
- privates after all publics that call them?
- rough call hierarchy - entry points at the top, callees lower?
- etc.

---

## ~~4. Fix SPI-from-Caller-Cog violations~~ (DONE 2026-03-01)

~~6 PUB methods performed SPI operations from the caller cog. Fixed by adding worker commands (82-85) and rewriting PUB wrappers. Also: setSPISpeed→do_set_spi_speed PRI, debugDumpRootDir/displayFAT via CMD_READ_SECTOR_RAW, readVBRRaw moved to SD_INCLUDE_RAW, SPEED→REGISTERS auto-include guard.~~

Plan: `SPI-Caller-Cog-Fix-Plan.md` | Findings: `DOCs/Reference/REF-DRIVER-SPI-AUDIT.md`

---
