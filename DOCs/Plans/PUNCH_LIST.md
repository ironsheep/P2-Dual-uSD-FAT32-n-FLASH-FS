# Punch List — Pre-Release Cleanup

Items to resolve before release. Accumulated during Phase 3+ implementation.

---

## ~~1. Eliminate all `result` return variable names~~ (DONE 2026-03-01)

~~78 methods renamed from generic `result` to descriptive names: status codes→`status`, booleans→`ok`/`found`/`is_valid`/`is_mounted`, counts→`sector_count`/`free_sectors`, pointers→`p_entry`/`p_filename`, SPI returns→`rx_data`/`rx_byte`/`response`. Includes PASM2 register renames in 3 inline assembly methods.~~

---

## ~~2. Consistent VSCode documentation style~~ (DONE 2026-03-01)

~~All .spin2 files audited against CODE-STYLE-GUIDE.md. Driver: 205 @local tags added across 87 PRI methods, all @returns verified. Shell: 42 PRI doc lines fixed from '' to '. Examples: PUB/PRI docs added to all 3 files. Utilities: 13 files audited, all already compliant.~~

---

## ~~3. Plan for method ordering within driver source file~~ (DONE 2026-03-01)

~~312 methods reordered to canonical layout per METHOD-ORDERING-GUIDE.md. PUB sections 1-11 (Lifecycle through Debug) followed by PRI sections A-M (Worker Infrastructure through SD SPI Layer). IFDEF guards preserved correctly with ungated card-identification PRIs kept outside conditional blocks.~~

Plan: `METHOD-ORDERING-GUIDE.md`

---

## ~~4. Fix SPI-from-Caller-Cog violations~~ (DONE 2026-03-01)

~~6 PUB methods performed SPI operations from the caller cog. Fixed by adding worker commands (82-85) and rewriting PUB wrappers. Also: setSPISpeed→do_set_spi_speed PRI, debugDumpRootDir/displayFAT via CMD_READ_SECTOR_RAW, readVBRRaw moved to SD_INCLUDE_RAW, SPEED→REGISTERS auto-include guard.~~

Plan: `SPI-Caller-Cog-Fix-Plan.md` | Findings: `DOCs/Reference/REF-DRIVER-SPI-AUDIT.md`

---
