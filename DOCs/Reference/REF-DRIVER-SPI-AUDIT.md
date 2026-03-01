# Reference Driver SPI Audit: micro_sd_fat32_fs.spin2

**Date**: 2026-03-01
**File**: `REF-FLASH-uSD/uSD-FAT32/src/micro_sd_fat32_fs.spin2`
**Severity**: All methods listed below perform SPI operations from the caller's cog, but the SPI pins are owned exclusively by the worker cog.

## Background

The SD driver uses a **dedicated worker cog** that owns the SPI smart pins (CS, MOSI, MISO, SCK). All SPI operations must be routed through the worker cog via the parameter block (`pb_cmd`, `pb_param0-3`). The caller cog sends a command and blocks on `WAITATN()` until the worker completes.

Methods that call SPI functions (`sp_transfer_8()`, `pinl(cs)`, `pinh(cs)`, `readSector()`, `writeSector()`, `wxpin(sck,...)`, etc.) directly from a PUB method execute in the **caller's cog context**, not the worker cog. Since the caller's cog doesn't own the SPI pins, these operations have undefined behavior — they may silently fail, corrupt data, or interfere with concurrent worker operations.

## SPI-from-Caller-Cog Violations

### 1. `testCMD13()` — Line 2747, `SD_INCLUDE_RAW`

**Call chain**: Direct `sp_transfer_8()`, `pinl(cs)`, `pinh(cs)`, `waitR1Response()`

**Issue**: Sends CMD13 command bytes and reads R2 response directly via SPI from caller cog.

**Fix**: Add a worker command (e.g., `CMD_TEST_CMD13`). Move the SPI sequence into a `do_test_cmd13()` PRI method. PUB becomes a `send_command()` wrapper. Debug decoding (which only reads the returned value) stays in the PUB.

---

### 2. `readVBRRaw()` — Line 2982, `SD_INCLUDE_REGISTERS`

**Call chain**: `readVBRRaw()` → `readSector()` → streamer SPI

**Issue**: Calls `readSector()` directly, which performs a streamer-based SPI sector read from caller cog.

**Additional issue**: This method is misplaced — it reads a raw sector (the VBR), not a card register. It belongs under `SD_INCLUDE_RAW`, not `SD_INCLUDE_REGISTERS`.

**Fix**: Route through a worker command (`CMD_READ_SECTOR_RAW`). Move to `SD_INCLUDE_RAW` guard.

---

### 3. `attemptHighSpeed()` — Line 3404, `SD_INCLUDE_SPEED`

**Call chain**: `attemptHighSpeed()` → `queryHighSpeedSupport()` → `readSCR()` + `sendCMD6()` → SPI; then `switchToHighSpeed()` → `sendCMD6()` → SPI; then `setSPISpeed()` → `wxpin(sck)`, `pinl(sck)`; then `readSector()` + `writeSector()` → streamer SPI

**Issue**: The entire multi-step sequence (query → switch → speed change → verify read/write) runs from the caller cog. Multiple SPI functions are called.

**Fix**: Add a worker command (e.g., `CMD_ATTEMPT_HIGH_SPEED`). Move the entire sequence into a `do_attempt_high_speed()` PRI method. **Stack safety note**: The current implementation uses 1024 bytes of stack locals (`test_buf[128]` + `verify_buf[128]`). If the worker stack is 1024 bytes total, use existing DAT buffers (`@buf` + `@dir_buf`) instead of stack locals.

---

### 4. `checkHighSpeedCapability()` — Line 3528, `SD_INCLUDE_SPEED`

**Call chain**: `checkHighSpeedCapability()` → `sendCMD6()` → `sp_transfer_8()`, `pinl(cs)`, `pinh(cs)`, `sp_transfer()`

**Issue**: Calls `sendCMD6()` which performs SPI operations from caller cog.

**Fix**: Add a worker command (e.g., `CMD_CHECK_HS_CAPABILITY`). Move into a `do_check_hs_capability()` PRI method.

---

### 5. `setSPISpeed()` — Line 4738, ungated (always compiled)

**Call chain**: Direct `wxpin(sck, half_period)`, `pinl(sck)`

**Issue**: Directly reconfigures the SPI clock smart pin from the caller cog.

**Internal callers** (worker-cog context, safe): `initCard()`, `setOptimalSpeed()`, `reinitCard()`

**External callers** (caller cog, broken): `attemptHighSpeed()` (if not fixed)

**Fix**: Make PRI (rename to `do_set_spi_speed()`). All current internal callers run in the worker cog. If external speed control is needed, add a `CMD_SET_SPI_SPEED` worker command with a PUB `setSPISpeed()` wrapper.

---

### 6. `debugDumpRootDir()` — Line 4338, `SD_INCLUDE_DEBUG`

**Call chain**: `debugDumpRootDir()` → `readSector(root_sec, BUF_DIR)` → streamer SPI

**Issue**: Calls `readSector()` directly from caller cog.

**Fix**: Use an existing worker command (`CMD_READ_SECTOR_RAW`) to read into a local buffer, then parse entries from the local buffer instead of `@dir_buf`.

---

### 7. `displayFAT()` — Line 6014, `SD_INCLUDE_DEBUG`

**Call chain**: `displayFAT()` → `readSector(n_sec, BUF_DATA)` → streamer SPI

**Issue**: Calls `readSector()` directly from caller cog.

**Fix**: Use `CMD_READ_SECTOR_RAW` to read into a local buffer, then `bytemove()` to `@buf` before calling `displaySector()` (which reads from `@buf`).

---

## Cross-Flag Compilation Dependencies

### `checkCMD6Support()` — Line 3513, `SD_INCLUDE_SPEED`

**Calls**: `readSCRRaw()` which is under `SD_INCLUDE_REGISTERS`

**Issue**: Enabling `SD_INCLUDE_SPEED` without `SD_INCLUDE_REGISTERS` causes an undefined-method compile error.

**Fix**: Either auto-define `SD_INCLUDE_REGISTERS` when `SD_INCLUDE_SPEED` is defined, or document the dependency clearly. A compile-time guard is recommended:
```spin2
#IFDEF SD_INCLUDE_SPEED
#IFNDEF SD_INCLUDE_REGISTERS
#DEFINE SD_INCLUDE_REGISTERS
#ENDIF
#ENDIF
```

---

## Misplaced Method

### `readVBRRaw()` — Line 2982

**Current guard**: `SD_INCLUDE_REGISTERS`
**Should be**: `SD_INCLUDE_RAW`

**Rationale**: This method reads a raw sector (the Volume Boot Record), not a card register. It uses `readSector()` internally, which is the same infrastructure as `readSectorRaw()`. Placing it under `SD_INCLUDE_RAW` is semantically correct and eliminates the need for `CMD_READ_SECTOR_RAW` to be always-compiled just for this one register-flagged method.

---

## Summary

| # | Method | Line | Guard | Issue Type |
|---|--------|------|-------|------------|
| 1 | `testCMD13()` | 2747 | `SD_INCLUDE_RAW` | Direct SPI from caller cog |
| 2 | `readVBRRaw()` | 2982 | `SD_INCLUDE_REGISTERS` | SPI via readSector + wrong guard |
| 3 | `attemptHighSpeed()` | 3404 | `SD_INCLUDE_SPEED` | Multi-step SPI from caller cog |
| 4 | `checkHighSpeedCapability()` | 3528 | `SD_INCLUDE_SPEED` | SPI via sendCMD6 from caller cog |
| 5 | `setSPISpeed()` | 4738 | (none) | Direct pin config from caller cog |
| 6 | `debugDumpRootDir()` | 4338 | `SD_INCLUDE_DEBUG` | SPI via readSector from caller cog |
| 7 | `displayFAT()` | 6014 | `SD_INCLUDE_DEBUG` | SPI via readSector from caller cog |

**Cross-flag**: `checkCMD6Support()` (SPEED) → `readSCRRaw()` (REGISTERS)
**Misplaced**: `readVBRRaw()` belongs in `SD_INCLUDE_RAW`, not `SD_INCLUDE_REGISTERS`

All issues have been fixed in the unified driver (`dual_sd_fat32_flash_fs.spin2`).
