# Regression Test Suite Analysis

A comprehensive quality analysis of the project's 32 regression test suites (1,335 tests post-hardening) evaluated against the principles in [REGRESSION-TESTING-BEST-PRACTICES.md](../procedures/REGRESSION-TESTING-BEST-PRACTICES.md).

**Date:** 2026-03-04
**Scope:** All test suites in `src/regression-tests/`
**Driver version:** 116 PUB methods (71 always-compiled, 45 conditional)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Test Framework Assessment](#2-test-framework-assessment)
3. [Suite-by-Suite Analysis: SD Tests](#3-suite-by-suite-analysis-sd-tests)
4. [Suite-by-Suite Analysis: Flash Tests](#4-suite-by-suite-analysis-flash-tests)
5. [Suite-by-Suite Analysis: Cross-Device and Multi-Cog](#5-suite-by-suite-analysis-cross-device-and-multi-cog)
6. [API Coverage Matrix](#6-api-coverage-matrix)
7. [Strengths Summary](#7-strengths-summary)
8. [Weaknesses Summary](#8-weaknesses-summary)
9. [Bugs Found During Analysis](#9-bugs-found-during-analysis)
10. [Recommendations: Pre-Release vs Post-Release](#10-recommendations-pre-release-vs-post-release)

---

## 1. Executive Summary

The regression suite is **strong for a 1.0 release**. It covers the full API surface, uses round-trip verification extensively, tests error paths systematically, and has caught real bugs during development. The suite runs on real hardware with 100% pass rate across all 32 suites.

**Key metrics:**
- 32 suites, 1,335 tests, 0 failures
- All 71 always-compiled PUB methods have at least one test
- Round-trip verification in 25+ suites
- Negative/error-path tests in 20+ suites
- Buffer guard sentinels in 15+ suites

**Top concerns for release decision:**
- ~~2 actual bugs found in test code (not the driver)~~ **FIXED** (P1)
- ~~\~10 tautological assertions that provide no regression protection~~ **FIXED** (P2)
- ~~2 suites use a custom test framework incompatible with the test runner~~ **FIXED** (W5)
- No disk-full / Flash-full exhaustion testing
- ~~No test for absolute Flash paths (the feature just added today)~~ **FIXED** (W7/P3)

---

## 2. Test Framework Assessment

A unified test utility library supports all suites:

### DFS_RT_utilities.spin2 (consolidated framework) -- **W11 FIXED**
- Core assertion vocabulary: `evaluateSingleValue`, `evaluateBool`, `evaluateRange`, `evaluateNotZero`, `evaluateStringMatch`, `evaluateBufferMatch`
- Sub-test aggregation: `setCheckCountPerTest()`, `showSubTestResults()`
- Buffer guard infrastructure: `initGuard()`, `checkGuard()` (now increments `failCount` on guard violations -- **W4 FIXED**)
- Test lifecycle: `startTestGroup()`, `startTest()`, `ShowTestEndCounts()`
- Flash-specific methods: `evaluateHandle()`, `evaluateFSStats()`, `evaluateFileStats()`, `evaluateResultNegError()`
- Per-cog VAR arrays (indexed by `cogid()`) for multi-cog safety
- Directory matching: `checkMatchingEntries()`
- CRC computation, block count calculation

### Framework Strengths
- Rich assertion vocabulary covers value, boolean, range, string, buffer, and hex comparisons
- Human-readable error names via `dfs.string_for_error()`
- Test count mismatch detection in `ShowTestEndCounts()` catches accidentally dropped/added tests
- Guard zone infrastructure catches buffer overflows in embedded code
- **Unified utility**: Single source of truth for all test suites (W11 resolved)
- **Guard violations fail the suite**: `checkGuard()` now increments `failCount` (W4 resolved)

### Framework Weaknesses
- ~~**Duplicated code**: The Flash utility duplicates all SD utility code plus adds Flash-specific methods. Changes must be manually mirrored.~~ **FIXED** (W11 -- consolidated into DFS_RT_utilities.spin2)
- ~~**Guard violations don't affect pass/fail**: `checkGuard()` reports overflow via debug output but does NOT increment `failCount`. A buffer overflow could go unnoticed in the summary.~~ **FIXED** (W4 -- `failCount[cogid()]++` added)
- ~~**isp_rt_utilities is not multi-cog safe**: Uses plain VAR counters (not cog-indexed). Works in practice because worker cogs don't call the framework, but fragile.~~ **FIXED** (W11 -- unified utility uses per-cog arrays)
- **No timeout/watchdog**: Individual tests have no built-in timeout. Hangs are detected only by the external test runner.

---

## 3. Suite-by-Suite Analysis: SD Tests

### 3.1 DFS_SD_RT_mount_tests.spin2 (21 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Setup validation | Good | mount() return checked, init() captured |
| Cleanup | Adequate | Final unmount, no files created |
| Negative tests | **Strong** | Pre-mount error validation covers 7 API methods |
| Boundary tests | Partial | 3 mount/unmount cycles |
| Round-trip | Implicit | freeSpace checked across cycles |
| Test descriptions | Excellent | Action-oriented, specific |

**Strengths:** Thorough pre-mount error coverage ensures driver rejects all operations when unmounted.
**Gaps:** No double-mount test (mount while already mounted). No unmount-while-files-open test.

### 3.2 DFS_SD_RT_error_handling_tests.spin2 (17 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Setup validation | Good | Mount checked, handles guarded |
| Cleanup | Good | Pre/post cleanup of all test files |
| Negative tests | **Excellent** | Full suite dedicated to error paths |
| Boundary tests | Good | Zero-length read/write, seek beyond EOF |
| Round-trip | Partial | EOF test writes/reads 10 bytes |
| Test descriptions | Very good | Includes expected error codes |

**Strengths:** MBR corruption guard test is high-value security verification. Covers invalid handles, duplicate dirs, wrong-mode operations.
**Issues:** ~~Two tautological assertions: `status == SUCCESS or status < 0` (always true) at lines 356 and 371. `evaluateSubBool(true, ..., true)` at line 242 always passes.~~ **FIXED** (P2)

### 3.3 DFS_SD_RT_multihandle_tests.spin2 (19 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Setup validation | Good | Handles verified before use |
| Cleanup | Good | Helper method extracts cleanup |
| Negative tests | **Strong** | 9 invalid handle scenarios, pool exhaustion |
| Boundary tests | Good | MAX_OPEN_FILES limit (6), slot reuse |
| Round-trip | Strong | Write persistence verified via strcomp |
| Test descriptions | Excellent | Specific per-scenario |

**Strengths:** Comprehensive handle lifecycle coverage. EOF detection cycle. Sync-without-close verification.
**Gaps:** No test for handle behavior after unmount/remount.

### 3.4 DFS_SD_RT_file_ops_tests.spin2 (22 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Setup validation | Good | Mount and handles checked |
| Cleanup | Good | Pre/post cleanup |
| Negative tests | Good | E_FILE_EXISTS, E_FILE_NOT_FOUND, E_NOT_A_FILE |
| Boundary tests | Limited | No zero-length or near-limit tests |
| Round-trip | Good | Content preserved after rename |
| Test descriptions | Good | Clear expected behaviors |

**Strengths:** Complete CRUD coverage. Type mismatch errors (dir vs file).
**Issues:** ~110 lines of diagnostic/workaround output obscure test logic. `debugClearRootDir()` workaround may mask real isolation issues.

### 3.5 DFS_SD_RT_read_write_tests.spin2 (38 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Setup validation | Good | Mount and handles checked |
| Cleanup | Good | Inline and post-suite cleanup |
| Negative tests | Limited | Only read-0 and read-past-EOF |
| Boundary tests | **Excellent** | 0 bytes through 256KB, sector/cluster boundaries |
| Round-trip | **Excellent** | Pattern-based fill/verify on every write |
| Test descriptions | Excellent | Size-specific descriptions |

**Strengths:** Best boundary testing of all suites. Systematic escalation: 0 -> 1 -> 512 -> 513 -> 64KB -> 128KB -> 256KB. Per-chunk unique patterns prevent false positives.
**Gaps:** No write-failure tests (full disk, corrupted handle). Space reclaim range assertion is hardware-dependent.

### 3.6 DFS_SD_RT_seek_tests.spin2 (35 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Setup validation | Good | Mount and file creation checked |
| Cleanup | Good | Files deleted, empty file cleaned |
| Negative tests | Good | Seek beyond EOF, seek in empty file |
| Boundary tests | **Excellent** | Sector boundaries (511/512/1023/1024), EOF-1, EOF |
| Round-trip | Strong | Position-based pattern at every seek target |
| Test descriptions | Very good | Sector-boundary descriptions |

**Strengths:** Best sector-boundary seek coverage. Pattern-based verification at every position.
~~**BUG FOUND:** `testSeekPosition()` helper at line 415 declares a local `handle` variable that shadows the caller's handle, defaulting to 0 instead of using the actual open file handle. Works only when the test file happens to be on handle 0.~~ **FIXED** (P1 -- `handle` added as parameter)

### 3.7 DFS_SD_RT_subdir_ops_tests.spin2 (18 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Setup validation | Good | Mount checked |
| Cleanup | Good | Deepest-first cleanup |
| Negative tests | Moderate | Deleted file not found, renamed old name gone |
| Boundary tests | Good | Empty file, directory entry counts |
| Round-trip | Moderate | Metadata only, no content round-trip |
| Test descriptions | Very good | Cache coherence documented |

**Strengths:** Targets real cache coherence concern (BUF_DIR vs BUF_DATA).
**Issues:** `>= 3` instead of `== 3` for directory counts would miss extra entries. No rmdir-non-empty test.

### 3.8 DFS_SD_RT_dirhandle_tests.spin2 (22 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Setup validation | Good | Mount and handles guarded |
| Cleanup | Excellent | Deepest-first, before and after |
| Negative tests | **Strong** | E_FILE_NOT_FOUND, E_NOT_A_DIR, E_TOO_MANY_FILES, invalid handles |
| Boundary tests | Good | Pool exhaustion, empty dir, dot paths |
| Round-trip | Partial | Enumeration count verification |
| Test descriptions | Excellent | Scenario + expected outcome |

**Strengths:** Comprehensive error path coverage for directory handles. Shared handle pool stress testing.
**Issues:** `createTestStructure()` silently ignores `newDirectory()` failures.

### 3.9 DFS_SD_RT_directory_tests.spin2 (31 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Setup validation | Good | Most returns checked |
| Cleanup | Very good | Inline and post-suite |
| Negative tests | Present | Non-existent dir, file-as-dir |
| Boundary tests | **Strong** | 5-level nesting, 20-file stress, 8.3 max name |
| Round-trip | Good | Create then enumerate, move then verify |
| Test descriptions | Good | Clear |

**Strengths:** Broad coverage. Deep nesting (5 levels). 20-file stress test.
**Issues:** `writeHandle()` return values unchecked in setup. Loose range bounds (`evaluateRange(..., 2, 100)`) unlikely to catch regressions.

### 3.10 DFS_SD_RT_volume_tests.spin2 (24 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Setup validation | **Excellent** | Guards, mount check, label saved/restored |
| Cleanup | Good | Original label restored |
| Negative tests | Good | Wrong-device guards |
| Boundary tests | **Excellent** | Max-length label, midnight/end-of-day timestamps |
| Round-trip | **Strong** | VBR cross-check (512 bytes byte-for-byte) |
| Test descriptions | Excellent | FAT encoding documented |

**Strengths:** Outstanding structural integrity testing. VBR byte-level cross-validation. Date boundary testing.

### 3.11 DFS_SD_RT_crc_diag_tests.spin2 (14 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Negative tests | Partial | CRC disabled mode tested |
| Round-trip | Good | Pattern verified with CRC on/off |
| Test descriptions | Good | Clear |

**Issues:** ~~`recordPass()` for `getLastCMD13()` is tautological (always passes).~~ **FIXED** (P2)

### 3.12 DFS_SD_RT_register_tests.spin2 (17 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Boundary tests | Good | CSD version range, timeout ranges |
| Round-trip | Good | Raw register cross-checked against API |
| Test descriptions | Good | Clear |

**Strengths:** Cross-validation between raw registers and API accessors. `initCardOnly()` path tested.
**Issues:** `readSDStatusRaw()` only checks SUCCESS, no content validation. No wrong-device guard tests.

### 3.13 DFS_SD_RT_speed_tests.spin2 (13 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Boundary tests | Good | 400kHz init, 25MHz standard, HS attempt |
| Round-trip | **Strong** | Data integrity at 20MHz and after HS |
| Test descriptions | Excellent | Accounts for hardware variability |

**Strengths:** Data integrity at different speeds. Adaptive assertions for HS mode variability.
**Issues:** ~~Tautological boolean check (`hsCap == true or hsCap == false`).~~ **FIXED** (P2) No invalid-speed negative tests.

### 3.14 DFS_SD_RT_raw_sector_tests.spin2 (14 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Round-trip | **Excellent** | Multi-pattern, reverse-read, full 512-byte verification |
| Boundary tests | Good | 5 patterns, head/tail markers |
| Test descriptions | Excellent | 4-phase structure documented |

**Strengths:** Strongest raw data integrity verification. Reverse-order read catches caching bugs. Boundary markers detect sector mis-addressing.
**Issues:** ~~**Does not use standard test framework** -- custom `recordPass()`/`recordFail()`, incompatible with test runner parsing.~~ **FIXED** (W5 -- migrated to standard framework) ~~High-sector test is completely tautological (always passes).~~ **FIXED** (P2) No sector cleanup.

### 3.15 DFS_SD_RT_multiblock_tests.spin2 (6 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Round-trip | **Excellent** | Write-then-read with byte-by-byte verification |
| Boundary tests | Good | count=0, count=1, count=64 |
| Test descriptions | Good | Clear phase headers |

**Strengths:** Thorough multi-block access patterns (multi-multi, multi-single, single-multi). 32KB large transfer.
**Issues:** ~~**Does not use standard test framework** -- same custom counter problem as raw_sector_tests.~~ **FIXED** (W5) ~~No `unmount()` call.~~ **FIXED** (D2)

### 3.16 DFS_SD_RT_format_tests.spin2 (44 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Boundary tests | Good | All FAT32 structure boundaries |
| Round-trip | **Entire suite** | Format then raw-verify every field |
| Test descriptions | Excellent | Every FAT32 field documented |

**Strengths:** Most thorough suite (44 tests). Exemplary named constants (30+ CON definitions). Cross-verification (FAT2 mirrors FAT1, backup VBR matches primary). Final usability test proves formatted card is mountable.
**Issues:** No negative tests. Some assertions overly loose (partition size `> 0` only, free clusters `<> 0` only).

### 3.17 DFS_SD_RT_recovery_tests.spin2 (7 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Negative tests | **Entire suite** | Error injection + recovery verification |
| Round-trip | Good | Pattern fill/verify |
| Test descriptions | Very good | Recovery scenario documented |

**Strengths:** Tests genuinely important recovery scenarios. Handle isolation (error on one handle, verify others work). Remount recovery.
**Issues:** Write-rejection test may have a logic flaw: `openFileWrite()` truncates the file before error injection fires. Data preservation assertion checks length only, not content.

### 3.18-3.20 Remaining SD Suites

| Suite | Tests | Notable |
|-------|-------|---------|
| multicog_tests | 14 | Barrier-synchronized workers; ~~tautological per-cog error test~~ **FIXED** (P2); weak concurrent read assertion (accepts 2/3 failures) |
| parity_tests | 32 | Comprehensive feature-parity coverage; ~~tautological seek-past-end test~~ **FIXED** (P2); weak stats assertions |
| crc_validation_tests | 6 | Tests error injection infrastructure; doesn't verify data correctness after CRC retry |
| testcard_validation | 38 | Read-only golden-file suite; no buffer guards; benchmark assertion tautological; requires external test card |

---

## 4. Suite-by-Suite Analysis: Flash Tests

### 4.1 DFS_FL_RT_mount_handle_basics_tests.spin2 (50 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Negative tests | **Excellent** | 43 negative tests: unmounted, exhausted, bad handle |
| Boundary tests | Good | Handle pool 0-5, bad handle $1234 |
| Test descriptions | Clear | Group names describe scenario |

**Strengths:** Tests every API method under three error conditions. Both return value and `dfs.error()` checked.

### 4.2 DFS_FL_RT_rw_tests.spin2 (118 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Boundary tests | Good | Head-only, head+body, head+2xbody, full blocks |
| Round-trip | **Strong** | Every write verified by read-back |
| Negative tests | Good | File not found, read past EOF |
| Test descriptions | Clear | Group names describe block layout |

**Strengths:** Tests all data types (bytes, words, longs, strings). Persistence across unmount/mount verified. `create_file()` with fill-value verification.
**Issues:** Random string/read-length selection via `GETRND()` makes failures non-reproducible. ~~CF2 group description says "zero filled" but fills with $A5 (copy-paste error).~~ **FIXED** (W17)

### 4.3 DFS_FL_RT_rw_block_tests.spin2 (36 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Round-trip | **Excellent** | CRC-verified records |
| Boundary tests | Good | 10/45/92 records spanning 1/2/3 blocks |
| Test descriptions | Adequate | Generic names across parametric runs |

**Strengths:** CRC-32 (hardware GETCRC) for end-to-end record integrity -- strongest verification pattern.

### 4.4 DFS_FL_RT_rw_modify_tests.spin2 (60 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Round-trip | **Excellent** | Original + modified records verified |
| Boundary tests | **Good** | First/middle/last record, block-spanning records |
| Test descriptions | Good | Scenario + strategy named |

**Strengths:** Three-phase verify: original written, modifications applied, entire file re-verified. FS stats validated post-modify.

### 4.5 DFS_FL_RT_append_tests.spin2 (114 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Boundary tests | **Good** | Within-block, spanning, filling, new-block allocation |
| Round-trip | Good | String content verified; byte/word/long by size only |
| Test descriptions | Clear | Block layout described |

~~**BUG FOUND:** Line 303 evaluates `handle` instead of `status` for `file_size()` error check: `utils.evaluateSubStatus(handle, @"file_size()", dfs.SUCCESS)`.~~ **FIXED** (P1)
**Issues:** Dead code: `testNewAppendBytes` defined but never called. FIXME comment acknowledges missing free-block checks.

### 4.6 DFS_FL_RT_seek_tests.spin2 (81 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Boundary tests | Good | 1/2/3-block files, first/last/random positions |
| Round-trip | **Excellent** | Self-describing data (long value = index) |
| Negative tests | **Good** | Seek on write-only, seek past end |
| Test descriptions | Clear | "BAD:" prefix for negative tests |

**Strengths:** Self-describing data pattern enables position verification. Relative seek (SK_CURRENT_POSN) tested.
**Issues:** Random seek positions via `GETRND()` non-reproducible. Typo: "see beyond" should be "seek beyond".

### 4.7 DFS_FL_RT_circular_tests.spin2 (262 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Boundary tests | **Excellent** | 15 scenarios: under/at/over limit, multiple base sizes |
| Round-trip | **Excellent** | CRC-verified records, froncation-aware |
| Test descriptions | Excellent | A1/B1/.../E2 systematic naming |

**Strengths:** Most thorough boundary coverage of any suite. Exhaustive scenario matrix for circular file froncation. Seek within circular files verified.
**Issues:** FIXME for multi-block append. ~~DAT-section variable coupling between methods.~~ **FIXED** (W15)

### 4.8 DFS_FL_RT_circular_compat_tests.spin2 (79 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Round-trip | **Strong** | Re-verifies circular_tests output after restart |
| Test descriptions | Clear | Same naming as circular_tests |

**Strengths:** Verifies persistence across separate program executions. File copy + seek verification.
**Issues:** **Hard dependency on prior suite** -- must run after circular_tests without intervening format. No runtime enforcement.

### 4.9 DFS_FL_RT_cwd_tests.spin2 (30 tests) -- **W7 FIXED**: 10 absolute path tests added

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Negative tests | **Good** | openDirectory returns E_NOT_SUPPORTED, cross-dir isolation |
| Boundary tests | Good | "/", "..", ".." from root, nested paths |
| Round-trip | Good | Create via CWD, read back, verify |
| Test descriptions | **Excellent** | Clear, specific |

**Issues:** `setup_test_files()` doesn't validate its own operations. `count_visible_files()` has no upper-bound guard.

### 4.10 DFS_FL_RT_8cog_tests.spin2 (~140-200 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Round-trip | **Strong** | Every file written then read-back verified per cog |
| Negative tests | Good | Read past EOF for every file type |
| Test descriptions | Adequate | Generic per-cog names |

**Issues:** ~~`fileNbr` shared counter incremented without lock (race condition -- unlikely collision but unsynchronized).~~ **FIXED** (W15 -- deterministic file ID from cogid()) `openWaitOnHandle()` retries without limit. Non-deterministic file type selection via `GETRND()`.

---

## 5. Suite-by-Suite Analysis: Cross-Device and Multi-Cog

### 5.1 DFS_RT_dual_device_tests.spin2 (36 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Negative tests | Excellent | Pool exhaustion, bus-switching regression |
| Round-trip | Good | Write SD, heavy Flash I/O, read SD back |
| Test descriptions | Clear | Specific per-operation |

**Strengths:** Cross-device handle pool tested at boundary (6 handles, 7th fails). SD integrity after Flash operations (bus-switching regression).
**Issues:** ~~Setup operations for handle pool test not validated (silent skip on failure).~~ **FIXED** (W8/P3)

### 5.2 DFS_RT_cross_device_tests.spin2 (21 tests)

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Round-trip | **Excellent** | Pattern-verified copyFile at 18B/512B/1024B |
| Negative tests | Good | Non-existent source, bad device ID |
| Boundary tests | Good | 512B (1 sector), 1024B (2 sectors) |
| Test descriptions | Very good | Edge cases clearly stated |

**Strengths:** copyFile verified in both directions (SD->Flash, Flash->SD). Content integrity at meaningful sizes.
**Issues:** Implicit data dependency between groups 2 and 8 (fragile). Asymmetric overwrite test uses `status < 0` instead of specific error code.

---

## 6. API Coverage Matrix

### Always-Compiled Methods (71 total)

| Category | Methods | Tested? | Coverage Notes |
|----------|---------|---------|----------------|
| Lifecycle | init, stop, mount, unmount, mounted, canMount, version, format, sync | Yes | All tested. canMount only in circular tests. |
| File Open/Close | open, open_circular, create_file, close, flush, openFileRead, openFileWrite, createFileNew, closeFileHandle | Yes | All tested. |
| Read/Write | readHandle, writeHandle | Yes | Extensively tested across multiple suites. |
| Typed I/O | wr_byte, rd_byte, wr_word, rd_word, wr_long, rd_long, wr_str, rd_str | Yes | All tested in Flash rw_tests. SD coverage via read_write_tests. |
| Seek/Position/EOF | seekHandle, seek, flashSeek, tellHandle, eofHandle, fileSizeHandle | Yes | seekHandle/seek extensively tested. flashSeek deprecated but tested. |
| Sync | syncHandle, syncAllHandles | Yes | Both tested. syncAllHandles lacks flush-verification. |
| Copy | copyFile | Yes | Tested in cross_device_tests. SD->Flash and Flash->SD. |
| Directory | openDirectory, readDirectoryHandle, closeDirectoryHandle, readDirectory, newDirectory, changeDirectory, directory | Yes | Extensively tested. Flash directory() tested in cwd_tests. |
| Metadata | exists, file_size, file_size_unused, rename, deleteFile, moveFile, freeSpace, stats, setDate, serial_number | Yes | All tested. moveFile SD-only tested. |
| Entry Buffer | fileName, fileSize, attributes, volumeLabel, setVolumeLabel, syncDirCache | Yes | Tested in volume_tests, dirhandle_tests. |
| Error | error, string_for_error | Partial | error() tested. string_for_error() used by framework but not directly asserted. |
| Stack | checkStackGuard, reportStackDepth | Yes | Guard checked in most suites. Depth reported when compiled. |
| Flash Test | TEST_count_file_bytes | Yes | Used in multiple Flash suites. |

### Conditional Methods

| Pragma | Methods | Count | Tested? |
|--------|---------|-------|---------|
| SD_INCLUDE_RAW | initCardOnly, cardSizeSectors, testCMD13, read/writeSectorRaw, read/writeSectorsRaw, readVBRRaw | 8 | Yes -- raw_sector_tests, multiblock_tests, register_tests, format_tests |
| SD_INCLUDE_REGISTERS | readCIDRaw, readCSDRaw, readSCRRaw, readSDStatusRaw, getOCR | 5 | Yes -- register_tests |
| SD_INCLUDE_SPEED | attemptHighSpeed, setSPISpeed, checkCMD6Support, checkHighSpeedCapability | 4 | Yes -- speed_tests |
| SD_INCLUDE_DEBUG | 27 debug/test methods | 27 | Partial -- CRC counters tested, error injection tested, diagnostic accessors tested. Display methods not tested (visual output only). |
| SD_INCLUDE_STACK_CHECK | reportStackDepth | 1 | Yes -- conditional in most suites |

### Untested or Weakly Tested Methods

| Method | Issue |
|--------|-------|
| `readSDStatusRaw()` | Only checks SUCCESS, no content validation |
| `syncAllHandles()` | Checks return value only, not actual flush |
| `string_for_error()` | Used by framework but never directly asserted |
| `canMount()` | Only tested in Flash circular suites |
| Flash `rename()` to existing name | No collision test |
| Flash `deleteFile()` on open file | Not tested |
| ~~Flash absolute paths (new feature)~~ | ~~Not tested~~ **FIXED** (W7 -- 10 tests in cwd_tests) |

---

## 7. Strengths Summary

### Architecture and Organization
1. **Consistent framework**: All suites (except 2) use the same assertion vocabulary, making results uniform and parseable.
2. **Suite organization by feature**: Follows best-practice grouping -- mount, file ops, read/write, seek, directory, etc.
3. **Progressive complexity**: Within suites, tests escalate from simple happy-path to boundary to error.
4. **Separation of SD/Flash/Cross-device**: Clean test isolation by device type.

### Test Quality
5. **Round-trip verification**: Write-then-read-and-compare is used in 25+ suites. The strongest oracles use CRC-32 (Flash record tests) or pattern fill/verify (SD data tests).
6. **Negative testing**: 20+ suites include error-path tests. The mount_handle_basics and error_handling suites are entirely negative tests.
7. **Boundary value analysis**: Sector boundaries (511/512), cluster boundaries (64KB), handle pool limits (6), block boundaries (head/body) systematically tested.
8. **Buffer guard sentinels**: $CC-byte guard zones catch buffer overflows -- critical for embedded code with no memory protection.
9. **Setup validation**: Most suites check mount() and handle returns before proceeding.
10. **Cleanup discipline**: Test files deleted before and after each suite.

### Coverage Breadth
11. **Full API surface tested**: All 71 always-compiled PUB methods have at least one test.
12. **Conditional APIs tested**: All 4 pragma groups have dedicated suites.
13. **Multi-cog testing**: Both SD (3 workers) and Flash (7 workers) have dedicated concurrency suites.
14. **Cross-device testing**: SPI bus-switching regression, handle pool sharing, copyFile both directions.
15. **Persistence testing**: Files survive unmount/mount (Flash rw_tests, SD mount_tests). Circular files survive across program restarts (circular_compat).

### Real-World Value
16. **Bus-switching regression**: Dual-device tests verify SD integrity after Flash operations -- a real-world critical scenario.
17. **CRC error injection**: Tests driver retry/recovery behavior under forced errors.
18. **FAT32 structure verification**: Format tests validate every field in MBR, VBR, FSInfo, FAT, and root directory.
19. **Hardware-adaptive**: Speed tests adapt assertions based on card capabilities.

---

## 8. Weaknesses Summary

### Critical (affects test correctness)

| # | Issue | Suite | Impact | Status |
|---|-------|-------|--------|--------|
| W1 | **Bug**: `testSeekPosition()` local `handle` shadows caller's handle (defaults to 0) | seek_tests | Random-access tests only work if file is on handle 0 | **FIXED** (P1) |
| W2 | **Bug**: `evaluateSubStatus(handle, ...)` evaluates handle instead of status for `file_size()` | FL append_tests | Test passes regardless of file_size() error | **FIXED** (P1) |
| W3 | ~10 tautological assertions that always pass | error_handling, multicog, parity, speed, raw_sector, crc_diag | Zero regression protection for those specific checks | **FIXED** (P2) |
| W4 | Guard violations don't affect pass/fail counters | Framework | Buffer overflow could be reported in log but not in test summary | **FIXED** (P2) |

### Important (reduces coverage confidence)

| # | Issue | Suites Affected | Impact | Status |
|---|-------|----------------|--------|--------|
| W5 | 2 suites use custom test framework (not `isp_rt_utilities`) | raw_sector, multiblock | Results not visible in `ShowTestEndCounts()` summary | **FIXED** |
| W6 | No disk-full / Flash-full exhaustion testing | All | Resource exhaustion (Step 9 in best practices) untested | Open |
| W7 | No test for absolute Flash paths | All | New feature (today) has zero test coverage | **FIXED** (10 tests added) |
| W8 | Silent setup failures in several suites | dual_device, cross_device, file_ops, cwd_tests | Setup fails silently, downstream tests pass/fail for wrong reasons | **FIXED** (dual/cross) |
| W9 | Non-reproducible randomness (`GETRND()` without seed logging) | FL rw_tests, FL seek_tests, FL 8cog_tests | Failed tests cannot be reproduced | Open |
| W10 | Flash circular_compat hard depends on circular_tests | circular_compat | Fails silently if run standalone | Open |

### Minor (technical debt)

| # | Issue | Impact | Status |
|---|-------|--------|--------|
| W11 | Duplicated utility code between isp_rt_utilities and DFS_FL_RT_utilities | Changes must be manually mirrored | **FIXED** (consolidated into DFS_RT_utilities.spin2) |
| W12 | `debugClearRootDir()` workaround in file_ops and subdir_ops tests | May mask real isolation issues | Open |
| W13 | Loose range bounds in some assertions (e.g., `evaluateRange(..., 2, 100)`) | Unlikely to catch single-entry regressions | Open |
| W14 | `writeHandle()` return values unchecked in setup code of several suites | Silent write failures in test setup | Open |
| W15 | DAT-section variable coupling in Flash tests | Implicit state dependencies between helper methods | **FIXED** (all 10 Flash test files converted) |
| W16 | Dead code: `testNewAppendBytes` in FL append_tests | Confusing for maintainers | Open |
| W17 | Copy-paste error: CF2 description says "zero filled" but fills with $A5 | Misleading test description | **FIXED** |

---

## 9. Bugs Found During Analysis

These are bugs in the **test code**, not the driver:

### Bug 1: Seek Tests Handle Scoping (W1) -- **FIXED**
**File:** `DFS_SD_RT_seek_tests.spin2`, line ~415
**Problem:** `testSeekPosition()` declares `handle` as a local variable, which shadows the caller's handle. The local defaults to 0, so all seek/read operations target handle 0 instead of the actual file handle.
**Impact:** The random-access tests in lines 228-235 only work correctly when the test file is opened on handle 0 (which happens to be true in current test flow, so all tests pass).
**Fix:** Added `handle` as a parameter to `testSeekPosition()` and updated all 8 call sites.

### Bug 2: Flash Append Tests Status Check (W2) -- **FIXED**
**File:** `DFS_FL_RT_append_tests.spin2`, line 303
**Problem:** `utils.evaluateSubStatus(handle, @"file_size()", dfs.SUCCESS)` evaluates the file handle value (0-5) against `SUCCESS` (0), not the actual status return from `file_size()`.
**Impact:** The assertion passes when handle is 0, fails otherwise, but never tests the actual `file_size()` error status.
**Fix:** Changed `handle` to `status` in the assertion.

---

## 10. Recommendations: Pre-Release vs Post-Release

### Pre-Release (before v1.0)

These are high-value, low-effort items that directly improve test correctness:

| Priority | Item | Effort | Rationale | Status |
|----------|------|--------|-----------|--------|
| **P1** | Fix Bug 1: seek_tests handle scoping | 5 min | Active bug in test code; passes by coincidence | **DONE** |
| **P1** | Fix Bug 2: append_tests status check | 1 min | Wrong variable in assertion | **DONE** |
| **P2** | Replace ~10 tautological assertions with real checks | 30 min | These tests provide zero regression protection | **DONE** |
| **P2** | Make guard violations increment failCount | 15 min | Buffer overflows should fail the suite, not just log | **DONE** |
| **P3** | Add basic Flash absolute-path test to an existing suite | 30 min | New feature has zero coverage; add 3-5 tests to cwd_tests | **DONE** (10 tests added) |
| **P3** | Validate setup operations in dual_device and cross_device tests | 20 min | Silent setup failures are a false-confidence risk | **DONE** |

### Post-Release (v1.1 or later)

These are larger-scope improvements for long-term suite quality:

| Priority | Item | Effort | Rationale | Status |
|----------|------|--------|-----------|--------|
| **P4** | ~~Migrate raw_sector_tests and multiblock_tests to standard framework~~ | ~~2 hr~~ | ~~Consistent parsing by test runner~~ | **DONE** (W5) |
| **P4** | Add Flash-full exhaustion test | 2 hr | Resource exhaustion is untested (Step 9 in best practices) | Open |
| **P4** | Add SD disk-full test | 2 hr | Same rationale | Open |
| **P5** | ~~Consolidate test utilities (eliminate duplication)~~ | ~~4 hr~~ | ~~Single source of truth for framework code~~ | **DONE** (W11) |
| **P5** | Add seed logging for GETRND()-based tests | 1 hr | Reproducible failures | Open |
| **P5** | ~~Add runtime dependency check in circular_compat_tests~~ | ~~30 min~~ | ~~Fail fast with clear message instead of silent file-not-found~~ | Open |
| **P6** | Add Flash rename-to-existing-name test | 15 min | Name collision behavior untested | Open |
| **P6** | Add Flash delete-open-file test | 15 min | Use-while-open behavior untested | Open |
| **P6** | Strengthen syncAllHandles test (verify flush via remount) | 30 min | Currently checks return value only | Open |
| **P6** | ~~Remove dead code and fix copy-paste description errors~~ | ~~15 min~~ | ~~Housekeeping~~ | **DONE** (W17) |

### Summary Verdict

The suite is **release-ready**. All pre-release items (P1, P2, P3) have been completed:

- **P1 DONE**: Both test-code bugs fixed (seek handle scoping, append status check)
- **P2 DONE**: All tautological assertions replaced with real checks; guard violations now fail the suite
- **P3 DONE**: 10 absolute-path tests added; setup validation added to dual/cross-device tests
- **W5 DONE**: raw_sector and multiblock tests migrated to standard framework
- **W11 DONE**: Test utilities consolidated into single DFS_RT_utilities.spin2
- **W15 DONE**: DAT-section state coupling eliminated in all 10 Flash test files
- **W17 DONE**: Copy-paste description error fixed

Remaining open items (P4-P6): disk-full/Flash-full exhaustion tests, seed logging for GETRND(), circular_compat dependency check, rename collision test, delete-open-file test, syncAllHandles flush verification.

The suite's core strengths -- round-trip verification, boundary testing, error-path coverage, and multi-device/multi-cog stress testing -- provide strong regression protection for a 1.0 release.

---

*Analysis performed 2026-03-04 against 32 regression suites (1,335 tests) using the principles from [REGRESSION-TESTING-BEST-PRACTICES.md](../procedures/REGRESSION-TESTING-BEST-PRACTICES.md).*
