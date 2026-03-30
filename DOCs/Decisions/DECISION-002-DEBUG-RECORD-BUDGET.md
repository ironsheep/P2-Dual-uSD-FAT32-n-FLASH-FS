# Decision 002: Debug Record Budget Management

**Date:** 2026-03-28
**Status:** Proposed
**Scope:** `src/dual_sd_fat32_flash_fs.spin2`, `src/regression-tests/DFS_RT_utilities.spin2`, `src/UTILS/isp_format_utility.spin2`, all regression test files

## Context

The pnut-ts compiler imposes a hard limit of 255 debug records per compile unit. A "debug record" is a unique entry in the binary's debug metadata table -- a distinct combination of format string and argument types. The compiler **deduplicates**: multiple `debug()` calls with identical content (same format string, same argument structure) share a single record in the output. For example, `debug("   -> ", zstr_(pPassFail))` appearing in 10 different evaluate methods compiles to one record, not 10. This means raw `grep` counts of `debug()` lines significantly overstate the actual record usage.

The dual-FS driver (`dual_sd_fat32_flash_fs.spin2`) was converted to channeled debug in v1.2.0: all 455 debug statements use `debug[CH_xxx]()` with a 12-channel `DEBUG_MASK` bitmask. Disabled channels compile to zero records. This was well-designed.

However, the supporting files -- `DFS_RT_utilities.spin2` (test framework), `isp_format_utility.spin2` (SD formatter), and the regression test files themselves -- continued using plain `debug()` with no channel discipline. Every plain `debug()` unconditionally compiles into a record.

When new features were added to the driver (v1.2.0+ SD enhancements), the driver's two default-enabled channels (CH_INIT at 61 records, CH_MOUNT at 56 records) grew by ~13 statements. This pushed `DFS_SD_RT_format_tests.spin2` -- the only test that includes an extra OBJ (`isp_format_utility`) -- past the 255 limit, breaking the compile.

### Root cause

Two independent failures in budget discipline:

1. **Driver DEBUG_MASK defaulted to non-zero.** CH_INIT and CH_MOUNT were enabled by default (`DEBUG_MASK = (1 << CH_INIT) | (1 << CH_MOUNT)`), contributing ~117 records to every compile unit. These channels were useful during early driver development but serve no purpose during regression testing -- the test framework produces its own output.

2. **No channel discipline in support files.** The test framework (122 plain debug calls), format utility (43 plain debug calls), and test files (4-55 each) all use unconditional `debug()`. As the driver grew, the cumulative count approached and then exceeded the limit.

### Budget anatomy (format test, heaviest compile unit)

| Object | Plain `debug()` | Enabled channels | Disabled channels | Records |
|--------|-----------------|------------------|-------------------|---------|
| Driver (CH_INIT + CH_MOUNT on) | 0 | 117 | 338 | ~117 |
| DFS_RT_utilities | 122 | 0 | 0 | ~122 |
| isp_format_utility | 43 | 0 | 0 | ~43 |
| DFS_SD_RT_format_tests | 26 | 0 | 0 | ~26 |
| **Total** | | | | **~308** |

Note: Raw `debug()` line counts overstate actual records due to deduplication (see Context). The format test's raw total (~308 lines) compiles to fewer unique records, but still exceeds 255. Other suites without the format utility stay under -- for example, `DFS_SD_RT_file_ops_tests` has ~294 raw lines but compiles successfully because many debug calls in DFS_RT_utilities share identical format strings (e.g., `debug("   -> ", zstr_(pPassFail))` used across all evaluate methods counts as one record).

## Decision

### 1. Driver DEBUG_MASK: zero for committed code

**Set `DEBUG_MASK = 0` in the committed driver source.**

The driver's channeled debug infrastructure remains intact -- all 455 `debug[CH_xxx]()` statements stay in the source. A developer enables specific channels temporarily by editing `DEBUG_MASK` when debugging a subsystem, then resets to 0 before committing. This follows the existing comment: "Set DEBUG_MASK = 0 for production builds (zero debug overhead)."

**Rationale:** Regression tests do not consume driver debug output. The test framework has its own output (group headers, test names, pass/fail counts). Leaving channels enabled wastes ~117 records of budget for output nobody reads during regression.

### 2. Test infrastructure channel taxonomy

Add channeled debug to `DFS_RT_utilities.spin2` and `isp_format_utility.spin2` following a **purpose-based naming convention**. Unlike the driver (which names channels by subsystem: CH_INIT, CH_FILE, CH_SECTOR), the test infrastructure names channels by **what visibility you're restoring** when investigating a problem.

#### DFS_RT_utilities channels

| Channel | Name | Records | Purpose | When to enable |
|---------|------|---------|---------|----------------|
| 0 | CH_EVAL | ~44 | Assertion details: expected vs. actual values in `evaluateBool()`, `evaluateSingleValue()`, `evaluateHandle()`, `evaluateBufferMatch()`, `evaluateSubValue()`, `evaluateSubBool()`, `evaluateStringMatch()`, `evaluateResultNegError()`, and related methods | **Test repair.** A previously-passing test fails. Enable CH_EVAL first to see what the assertions are receiving vs. what they expected. This is the most common diagnostic need. |
| 1 | CH_STATE | ~14 | Filesystem state inspection: `showFiles()`, `showFileDetails()`, `evaluateFSStats()`, `evaluateFileStats()`, `evaluateFileStatsRange()`, `ShowStats()`, `showChipAndDriverVersion()`, `showError()`, `showErrorCode()`, `checkMatchingEntries()` | **Test development or repair.** Understanding the filesystem context around a failure -- what files exist, how many blocks are used, what the directory looks like. |
| 2 | CH_DUMP | ~12 | Raw memory and buffer inspection: `dbgMemDump()`, `dbgMemDumpAbs()`, `dbgMemDumpRow()`, `verifyBufferPattern()`, `verifyBufferValue()`, `checkGuard()` | **Deep debugging.** Byte-level investigation when assertion details aren't sufficient. Guard violation detection. Rarely needed. |

**Essential output (~23 calls) remains plain `debug()`:** group headers (`startTestGroup()`), test names (`startTest()`), sub-test result summaries (`showSubTestResults()`), final pass/fail counts (`ShowTestEndCounts()`, `ShowMultiCogTestEndCounts()`), pass/fail indicators (`recordPass()`, `recordFail()`), and directory validation results (`ensureEmptyDirectory()`). These produce the structured output that the test runner parses and the developer watches live.

Default: `DEBUG_MASK = 0` (all diagnostic channels off).

#### isp_format_utility channels

| Channel | Name | Records | Purpose | When to enable |
|---------|------|---------|---------|----------------|
| 0 | CH_VERIFY | ~19 | Write-readback verification: MBR/VBR hex dumps, buffer addresses, write diagnostic codes, FAT progress counters | **Format utility development or repair.** Verifying that written data matches expected structure on readback. |

**Essential output (~24 calls) remains plain `debug()`:** format operation headers/footers, step progress ("Writing MBR...", "Writing VBR..."), error messages ("ERROR: Failed to write MBR!"), format result summary (volume label, size, clusters), and critical verification failures ("MBR READBACK MISMATCH!").

Default: `DEBUG_MASK = 0` (verification channel off).

#### Regression test files

Test files should use plain `debug()` sparingly for supplementary test output that contextualizes pass/fail results (card size, filesystem parameters, session markers). If a test file needs diagnostic dumps during development, use `CH_EVAL` or `CH_STATE` from the utilities rather than adding more plain `debug()` calls.

### 3. Channel naming principle

**Driver channels name subsystems** (CH_INIT, CH_FILE, CH_SECTOR, CH_DIR) because the driver is large and you debug one subsystem at a time. The developer thinks: "I need to see what the mount sequence is doing."

**Test infrastructure channels name visibility** (CH_EVAL, CH_STATE, CH_DUMP, CH_VERIFY) because when a test breaks, you think: "Show me what the assertions are seeing" or "Show me the filesystem state" -- not "show me the file operations subsystem."

This distinction keeps channel names intuitive for their context. A developer working on a test failure enables `CH_EVAL` in the utilities to see assertion details. A developer working on a driver bug enables `CH_MOUNT` in the driver to see filesystem geometry. Different mental models, different naming conventions.

### 4. Budget accounting and headroom

**The 255 limit counts unique debug records after deduplication, not raw source lines.** Because the compiler merges identical debug calls into a single record, the actual budget usage is lower than a `grep -c 'debug('` count suggests. However, we cannot easily predict the exact record count from source inspection alone -- deduplication depends on format string and argument type identity, which is an internal compiler detail.

**Current constraint:** pnut-ts v1.53.2 does not report the debug record count during compilation. The only signal today is a hard failure at 255. A future pnut-ts version will report statistics (statements compiled, unique records generated, max 255) during compilation, which will make budget tracking precise. Until that feature is available, we manage the budget conservatively by minimizing the number of unconditional debug records.

**Conservative policy:** Keep `DEBUG_MASK = 0` in all committed code. This eliminates the driver's contribution entirely and ensures only essential test output plus test-file-specific debug consume the budget. Under this policy, the budget is dominated by:

| Component | Raw debug() lines | Unique records (estimated) |
|-----------|-------------------|---------------------------|
| Driver (DEBUG_MASK = 0) | 0 | 0 |
| DFS_RT_utilities (essential only) | ~23 | lower (deduplication) |
| Test file (typical) | ~15-55 | lower (deduplication) |
| Extra OBJ if any (e.g., format util essential) | ~24 | lower (deduplication) |

The exact record counts are unknowable today, but channeling the diagnostics removes the largest sources of unique records (each evaluate method's value-printing debug has distinct format strings that do NOT deduplicate). The essential-only output has high deduplication potential (repeated patterns like pass/fail indicators, separators).

**Verification:** The format test must compile successfully. That is the budget gate.

### 5. Verification gate

The format test (`DFS_SD_RT_format_tests.spin2`) is the heaviest compile unit because it includes `isp_format_utility` as an extra OBJ. It serves as the canary for budget overflow.

**Rule:** The format test must always be included in the compile phase of `run_regression.sh`, even when `--include-format` is not specified. The `--include-format` flag controls whether it *runs on hardware* (destructive), not whether it *compiles*. This ensures every regression run validates the debug record budget.

### 6. Development workflow

| Phase | Driver DEBUG_MASK | RT Utilities DEBUG_MASK | Action |
|-------|-------------------|-------------------------|--------|
| **Normal regression** | 0 | 0 | All diagnostic channels off. Only essential test output. |
| **Debugging a driver bug** | Enable 1-2 channels | 0 | Temporarily set driver mask (e.g., `(1 << CH_FILE)` to trace file ops). Reset to 0 before commit. |
| **Developing a new test** | 0 | Enable CH_EVAL, maybe CH_STATE | See assertion details while building test logic. Disable before committing the test. |
| **Repairing a broken test** | 0 (or 1 channel if driver-side) | Enable CH_EVAL | See what assertions are receiving. If deeper inspection needed, add CH_STATE or CH_DUMP. |
| **Debugging format utility** | 0 | 0 (format util: CH_VERIFY on) | See write-readback details during format development. |

**Critical rule:** Never commit code with non-zero DEBUG_MASK in any file. Enabled channels are developer-local, temporary, and must be reset before committing.

## Alternatives Considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **Comment out diagnostic debug** | Simple, no infrastructure | Rots over time, goes stale, not updated with code changes | Rejected |
| **`#ifdef` conditional compilation** | Familiar pattern | Clutters source, separate mechanism from existing DEBUG_MASK | Rejected |
| **Channeled debug (chosen)** | Proven pattern in driver, one-line enable, stays in sync with code | Requires defining channels and converting calls | **Chosen** |
| **Remove diagnostic debug entirely** | Maximum headroom | Loses diagnostic capability for test repair | Rejected |

## Implementation Plan

1. Set `DEBUG_MASK = 0` in `dual_sd_fat32_flash_fs.spin2` (immediate fix)
2. Add `DEBUG_MASK` + channel CONs to `DFS_RT_utilities.spin2` (CH_EVAL, CH_STATE, CH_DUMP)
3. Convert ~70 diagnostic `debug()` calls to `debug[CH_xxx]()` in DFS_RT_utilities
4. Add `DEBUG_MASK` + CH_VERIFY to `isp_format_utility.spin2`
5. Convert ~19 diagnostic `debug()` calls to `debug[CH_VERIFY]()` in isp_format_utility
6. Update `CLAUDE.md` with budget rules and verification gate
7. Modify `run_regression.sh` to always compile the format test
8. Verify all 33 suites compile (including format test)
9. Run full regression on hardware

## Files to Modify

| File | Change |
|------|--------|
| `src/dual_sd_fat32_flash_fs.spin2` | `DEBUG_MASK` changed from `(1 << CH_INIT) \| (1 << CH_MOUNT)` to `0` |
| `src/regression-tests/DFS_RT_utilities.spin2` | Add DEBUG_MASK, CH_EVAL/CH_STATE/CH_DUMP channels; convert ~70 diagnostic debug calls |
| `src/UTILS/isp_format_utility.spin2` | Add DEBUG_MASK, CH_VERIFY channel; convert ~19 diagnostic debug calls |
| `tools/run_regression.sh` | Always compile format test in Phase 1 |
| `CLAUDE.md` | Add debug record budget rules |

## Future: Compiler-Reported Debug Statistics

A planned pnut-ts enhancement will report debug record statistics during compilation:

```
DEBUG: 187 statements compiled, 241 unique records (of 255 max)
```

This will provide:
- **The actual budget number** (unique records vs. 255) -- no estimation needed
- **The deduplication ratio** (statements vs. records) -- shows how much reuse the compiler achieves
- **Early warning** -- developers see the margin and can act before the next feature addition breaks the compile

Until this feature ships, the policy in this document relies on conservative practices (DEBUG_MASK = 0 for committed code, channel all diagnostics) and the format test compile gate as the only budget check.

When the compiler feature is available, it becomes the authoritative budget check. The conservative channeling policy remains good practice regardless -- it keeps diagnostics available without consuming budget.

## References

- `DOCs/Plans/DEBUG-MASK-Conversion-Plan.md` -- Original driver channel conversion
- pnut-ts compiler limit: 255 unique debug records per compile unit (after deduplication)
- `DFS_SD_RT_format_tests.spin2` -- Budget canary (heaviest compile unit, includes extra OBJ)
