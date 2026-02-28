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
