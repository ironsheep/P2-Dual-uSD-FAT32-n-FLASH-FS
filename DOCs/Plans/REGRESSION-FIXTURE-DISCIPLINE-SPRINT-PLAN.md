# Regression Fixture-Discipline — Sprint Plan

**Status:** planned (research complete, all scope questions resolved)
**Plan authored:** 2026-07-05
**Origin:** `DOCs/HANDOFF-REGRESSION-FIXTURE-DISCIPLINE.md`

---

## Purpose

Regression suites depend on **ambient microSD card state** instead of each
establishing and **auditing** its own preconditions. A "green" run today can mean
"the card happened to be in a favorable state," not "the driver is correct." The
fragility is latent in any suite that assumes free-space layout, allocation
contiguity, or directory entry counts — it drew blood in the defrag suite first
(fails 7/12 on a fragmented card, passes 12/12 on a freshly-formatted card, and
misreports a *setup* deficiency as a *driver* failure).

This sprint makes every standard suite establish **and audit** its own
preconditions, adds the one driver capability required to audit a space
precondition, hardens the one driver behavior that must fail cleanly, and
certifies the whole regression as deterministic regardless of card size or suite
order.

## Scope (confirmed with Stephen, 2026-07-05)

- **All 32 standard suites retrofitted in this one sprint.** No split. (One heavy
  suite + ~5 medium + a mechanical audited-baseline conversion for the rest, all
  riding on shared helpers built once — a split would only add a seam.)
- **`compactFile()` clean-fail is an in-scope driver invariant**, not assert-only.
- **`largestFreeExtent` / defrag / contiguity are SD-only.** Flash does not do
  defrag; its 4 KB-block / circular allocation model does not share the
  free-space-contiguity concept.

## Hardware split (execution division of labor)

The devcontainer **cannot drive the P2 over serial.** Therefore:

- **In the container (this sprint's development):** write all code — driver query,
  driver robustness fix, framework helpers, suite retrofits, doc updates — and
  **compile-check** everything. Compilation (`pnut-ts -d …` plus a
  `flexspin.mac -2 -q …` cross-check on touched files) is the container's
  proof-of-correctness gate. Section 10's certification is *specified* here but
  *executed* natively.
- **Native session (P2 Edge attached):** run all hardware testing and the final
  certification pass. That run is the definition-of-done gate.

"Can't run on hardware" is not a blocker — it is the expected division of labor.
Leave the tree compiling-clean and fully staged for a native certification pass.

## Regression-run precondition (policy, confirmed with Stephen 2026-07-05)

**The regression suite is run only against a card designated formattable — a
dedicated scratch/test card. Claude will not run the regression against a
non-formattable card.**

**Pre-run gate (every hardware regression run).** Before running any regression on
hardware, confirm: *"has an erasable/formattable scratch card been provided?"* If
not confirmed, do not run. (Stephen's standing policy is to always provide a
formattable card, so in practice this is a one-line confirmation, not a
negotiation.)

**Preflight sequence — audit, then format.** Once the card is confirmed formattable:
1. **Audit (non-destructive health check):** run `DFS_SD_FAT32_audit` against the
   card *first*, to detect a **corrupt filesystem** before it is wiped. Given the
   project's active shared-bus MBR-corruption history, a pre-run audit captures "did
   corruption recur?" — evidence a blind format would destroy. A failed audit is
   surfaced (and investigated), not silently formatted over.
2. **Format (deterministic baseline):** format the card to a clean FAT32 baseline so
   entry state is identical across cards and reruns.

This audit-then-format order preserves diagnostic signal *and* guarantees a clean
start.

Rationale, and why it matters to the design:

- **Safety gate.** The suite contains destructive tests (`DFS_SD_RT_format_tests`
  reformats; `raw_sector`/`multiblock` write absolute sectors that clobber existing
  data). Restricting the runner to a scratch card protects any card the user
  values.
- **It supersedes the "can't format the SD card" hedge for regression.** Because the
  regression card is always formattable, suites **may normalize to a known baseline
  by formatting** — strictly more powerful than working blind to ambient files. This
  is what lets contiguity-dependent suites *guarantee* their preconditions rather
  than skip when the card is fragmented (see Section 6).
- **It does not weaken the retrofit's motivation.** Card-size independence still
  matters (differing cluster sizes across card sizes even when freshly formatted);
  inter-suite isolation still matters (a sequential run churns the card between
  suites even from a clean entry state). The "assert only against self-created
  state, never the ambient root" discipline remains in force as defense-in-depth for
  every suite that does not itself format.

## Definition of done

- Every standard suite establishes **and audits** its own preconditions; no suite
  depends on ambient card state.
- Full **sequential** `tools/run_regression.sh` passes deterministically
  **regardless of card size or suite order**, on hardware, reported per-file.
- The `compactFile`-on-insufficient-contiguous-space invariant is proven on
  hardware (clean `E_NO_CONTIGUOUS_SPACE`, file intact + readable, filesystem
  consistent + usable) — or the driver bug it exposes is fixed in-session.
- Contract documented; framework helpers in place; defrag-guide API updated.

## Sprint-start record (2026-07-05)

Sprint started via the `sprint-start` skill. Decisions and entry checks:

- **Build number:** no bump at start (predominantly test augmentation). Revisit at
  `build-wrapup` — patch `DFS_VERSION` 1.3.1 → 1.3.2 / `SD_VERSION` 1.5.1 → 1.5.2
  **iff** `compactFile` behavior changed at certification or the new API ships to the
  field. See Section 9.
- **Branch:** none — single-developer model, commit directly to `main` (overrides the
  repo's default "branch first"). Confirmed by Stephen.
- **Working-tree audit:** clean of mid-edits; no tracked file in the blast radius was
  modified. Plan doc committed as the sprint foundation. Runner artifacts
  (`performance.log`, `pnut-term-settings.json`, `tests/`) left untracked
  (pnut-term output).
- **Tracking-readiness (entry):** READY. 0 context keys; board clean. Leftover task
  `#1` (MBR investigation, overtaken by v1.3.1) closed out and archived
  (`tasks/archives/archive_20260705_190232.md`) — no pending tasks.
- **Baseline-health (entry) — build:** CLEAN. `run_regression.sh --compile-only` →
  **32/32 suites compile, 0 warnings, 0 failures.** This is the entry build baseline
  the closeout exit baseline is compared against.
- **Baseline-health (entry) — tests:** not measurable in-container (hardware-gated);
  the runtime test baseline is established at native certification (Section 10).
- **Process note:** no `.claude/skill-conventions.md` exists; build/test commands were
  taken from `CLAUDE.md` (authoritative), not guessed. Consider running
  `bootstrap-conventions` to formalize the slots (non-blocking).

## Open Questions

**None.** All scope and code-mechanics questions raised during planning are
resolved:

- Sprint size, `compactFile` scope, and SD-only device scope — resolved by Stephen
  (see Scope above).
- New-query gating — resolved from code: `largestFreeExtent` builds on
  `findContiguousRun`, `test_max_clusters`, and `E_NO_CONTIGUOUS_SPACE`, all
  already under `#ifdef SD_INCLUDE_DEFRAG`; the query lives under the same pragma.
- Device-parameterizing the Flash-only framework helpers — resolved from P2KB:
  Spin2 has **no default parameters**, so the sanctioned method-overloading pattern
  is used (existing Flash-signature helpers become thin `DEV_FLASH`-defaulting
  wrappers delegating to new parameterized cores; the 11 Flash suites are
  untouched).

---

## The Fixture-Discipline Contract (the standard every section enforces)

Every retrofitted suite follows this lifecycle, and **may not assert a driver
result until it has proven its precondition held**:

1. **Setup** — establish *and audit* preconditions. Every setup call
   (mount/format/create/delete) is checked. Space/contiguity/entry-count
   preconditions are *measured*, not assumed.
2. **Build + audit fixture** — construct the exact state the test needs, and verify
   it was constructed.
3. **Act** — the single operation under test.
4. **Verify postconditions** — including that untouched state stayed untouched and
   data is intact.
5. **Teardown** — restore a clean working area (delete owned files; note that
   deleting files does **not** defragment free space).

**Hard rule:** an unmet precondition reports as *"setup not met"* (a distinct,
non-driver outcome), **never** as a driver failure. This is the core sin the sprint
eliminates.

---

# Section 1 — Codify the Fixture-Discipline Contract (documentation)

**Why.** The principle already half-exists but is documented-as-advice and not
enforced, and it names the wrong precondition class. `REGRESSION-TESTING-BEST-
PRACTICES.md` §4 (four-phase anatomy) and §11 (Setup Validation) cover
mount/open/create failures but say nothing about **free-space amount, contiguity,
or directory entry counts** — exactly the ambient dependencies that bit us.

**Current code / doc starting point.**
- `DOCs/Decisions/REGRESSION-TESTING-BEST-PRACTICES.md` §4 (line 118), §11 (line
  400) — principle stated as advice.
- `DOCs/procedures/REGRESSION-TESTING-STRATEGY.md` §5 "Setup Validation" (line 79) —
  the actionable checklist twin.
- `DOCs/procedures/Test-Weakness-Patterns.md` — home for the anti-pattern catalog.

**Target.**
- Promote §11 into a **mandatory contract** (the five-phase lifecycle above),
  adding an explicit **space/contiguity/entry-count precondition class** and the
  **"unmet precondition = setup-not-met, never driver-fail"** rule.
- Document the two levers this sprint provides for SD determinism:
  `largestFreeExtent(dev)` (audit a contiguity precondition) and
  `setTestMaxClusters()` (force the `E_NO_CONTIGUOUS_SPACE` negative case).
- Add the four ambient-state anti-patterns to `Test-Weakness-Patterns.md`:
  (a) no precondition audit; (b) ambient-count assertions
  (`evaluateRange(fileCount, 2, 100)`, `foundDirs > 0` on the ambient root);
  (c) teardown that deletes files but does not restore free-space layout;
  (d) geometry hard-coding (absolute sector addresses).
- Align `REGRESSION-TESTING-STRATEGY.md` §5 to reference the contract and helpers.

**Integration points.** Named references to the Section 5 helpers so suite authors
have a single home for "reset working area" / "assert ≥ N contiguous free clusters."

**Verification.** Documentation deliverable — verified by review against the
Section 5 helper surface and the Section 6 template (the contract must exactly
describe what the defrag template does). No runtime case.

---

# Section 2 — Driver capability: `largestFreeExtent(dev)` query

**Why.** You cannot audit a space precondition you cannot measure. Suites with a
contiguity requirement need to ask the driver "what is the longest run of
consecutive free clusters right now?" so they can report *setup-not-met* instead of
asserting into a driver failure.

**Current code starting point** (`src/dual_sd_fat32_flash_fs.spin2`), from the
worker-dispatch research:
- Command constants CON block: lines 131–234 (defrag group
  `CMD_CREATE_CONTIGUOUS=87`, `CMD_COMPACT_FILE=88`, `CMD_FILE_FRAGMENTS=89`).
- Mode-gating guard: line 3710 (`SD_INCLUDE_DEFRAG` branch; currently
  `cur_cmd <= CMD_FILE_FRAGMENTS`).
- Dispatch case group: lines 3958–3969 (inside `#ifdef SD_INCLUDE_DEFRAG`).
- Template worker scan: `findContiguousRun` at lines 9079–9111 (FAT walk from
  cluster 2, `test_max_clusters` guard at 9098, free test
  `(fatEntry & FAT_EOC_MASK) == 0` at 9101, cache invalidate `fat_sec_in_buf := -1`
  at 9111).
- Template wrapper (count-returning, error-propagating): `fileFragments` at lines
  2556–2568, dispatch at 3959–3961.
- FAT/geometry: `readFat` (8880–8892), `readSector` cache (10119; `fat_sec_in_buf`
  short-circuit 10157–10160), `sec_per_fat`, `fat_sec`, constants `FAT_EOC_MASK`
  (358), `FAT_ENTRY_SHIFT` (339), `SECTOR_MASK` (333), `ROOT_CLUSTER` (357).
- Error constant `E_NO_CONTIGUOUS_SPACE = -131` (298, under `SD_INCLUDE_DEFRAG`).

**Target.** Add SD-only `largestFreeExtent(dev) : count` returning the longest run
of consecutive free clusters (in clusters), gated `#ifdef SD_INCLUDE_DEFRAG`. Five
touch sites (implementation recipe):
1. **Constant** — add `CMD_LARGEST_FREE_EXTENT = 90` in the CON block.
2. **Mode gate** — widen line 3710 upper bound from `CMD_FILE_FRAGMENTS` to
   `CMD_LARGEST_FREE_EXTENT` so it is gated as a `MODE_FILESYSTEM` op.
3. **Dispatch case** — `CMD_LARGEST_FREE_EXTENT: pb_data0 :=
   do_largest_free_extent(); pb_status := pb_data0 < 0 ? pb_data0 : SUCCESS`.
4. **Worker method** — `PRI do_largest_free_extent() : max_run` near
   `findContiguousRun`: copy its FAT-scan structure but track
   `max_run := runLen > max_run ? runLen : max_run` on every free entry, scan to end
   (or `test_max_clusters`), honor the 9098 cap guard, return `E_IO_ERROR` on read
   failure, invalidate `fat_sec_in_buf := -1` on exit, guard on `F_MOUNTED`.
5. **PUB wrapper** — `PUB largestFreeExtent(dev) : count` modeled on
   `fileFragments`: `if dev <> DEV_SD : count := set_error(E_NOT_SUPPORTED)` else
   `send_command(CMD_LARGEST_FREE_EXTENT,0,0,0,0)` then
   `count := LONG[@saved_data0][COGID()]`.

No changes to `send_command`, the parameter block, `readFat`, or `readSector`.

**Integration points.** Consumed by the Section 5 helper `assertContiguousFree`;
must respect `test_max_clusters` so a suite can cap clusters, verify
`largestFreeExtent < needed`, and expect `createFileContiguous` →
`E_NO_CONTIGUOUS_SPACE` (Section 6, Test 11).

**Verification (cases the work must prove).**
- **Normal:** on a freshly-formatted card, `largestFreeExtent(DEV_SD)` ≈ total free
  clusters (one big run); unit-assert it equals `freeSpace`-derived free-cluster
  count when the card is known-empty.
- **Edge:** with `setTestMaxClusters(N)` active, the result is `≤ N-2` and honors
  the cap identically to the allocator; after a `spacer` fragmentation fixture, the
  result is strictly less than total free clusters.
- **Error:** `largestFreeExtent(DEV_FLASH)` → `E_NOT_SUPPORTED`; called unmounted →
  `E_NOT_MOUNTED`/0 per `do_freespace` convention; a FAT read failure surfaces
  `E_IO_ERROR`.

---

# Section 3 — Driver robustness: `compactFile()` clean-fail invariant

**Why.** The defrag `-40` symptom suggests `compactFile()` may not fail cleanly when
there is no contiguous home to relocate into — it could lose or corrupt the file.
Stephen's requirement: **it has to fail *successfully*.** `E_NO_CONTIGUOUS_SPACE` is
a legitimate failure, but the target file and the filesystem must remain intact and
usable afterward.

**Current code starting point.**
- `compactFile` PUB wrapper near the defrag PUBs (2586–2617 region) and its worker
  `do_compact_file` (defrag `#ifdef` region near `findContiguousRun`,
  `allocateContiguousChain` 9113–9150).
- `E_NO_CONTIGUOUS_SPACE = -131` (298), `E_VERIFY_FAILED = -133` (300).

**Target — the invariant that must hold** (and that Section 6 asserts):

> `compactFile(DEV_SD, file)` on insufficient contiguous space returns
> `E_NO_CONTIGUOUS_SPACE`, **and** afterward: (a) the target file still exists, (b)
> its byte-for-byte contents are unchanged and fully readable, (c) its cluster
> chain is still valid (`fileFragments`/`isFileContiguous` return sane values), and
> (d) the filesystem free-cluster accounting is consistent (no leaked/half-relocated
> clusters).

Because this cannot be observed in-container, the deliverable here is:
- **In-container:** review `do_compact_file` for the relocation-failure path — if it
  mutates the directory entry or FAT chain *before* confirming a contiguous
  destination is secured, that is the suspected bug; restructure so the original
  chain is only released *after* the new chain is fully committed
  (allocate-verify-then-swap), and never left half-swapped on the `E_NO_CONTIGUOUS_
  SPACE` path. Compile-check.
- **At certification:** the Section 6 assertion proves the invariant on hardware. If
  it fails, the exact fix is finalized in-session against the observed behavior
  (per the working agreement — no deferral).

**Integration points.** Section 6 Test set exercises this directly; the
`largestFreeExtent` query (Section 2) + `setTestMaxClusters` (existing) create the
insufficient-space condition deterministically.

**Verification (cases the work must prove).**
- **Normal:** compact a fragmented file with ample contiguous space → `SUCCESS`,
  file contiguous, data intact (already covered by defrag Tests 4/5).
- **Error (the new invariant):** with `setTestMaxClusters` forcing no contiguous
  home, `compactFile` → `E_NO_CONTIGUOUS_SPACE`; then re-open and read the file
  fully and compare against a pre-compact CRC/pattern (intact); then
  create/read/delete an unrelated file (filesystem still usable); then confirm free
  accounting unchanged from pre-attempt.
- **Edge:** compact on empty file and already-contiguous file remain `SUCCESS`
  no-ops (defrag Tests 6/9) and are unaffected by the hardening.

---

# Section 4 — Framework: device-parameterize the Flash-only helpers

**Why.** Every shared audit/fixture helper in `DFS_RT_utilities.spin2` is hardcoded
to `dfs.DEV_FLASH`. That is *why* the Flash suites are the gold standard
(format → audit-empty → build → assert-deltas) and the SD suites structurally
cannot follow suit. SD suites can only adopt the audited-baseline pattern once these
helpers accept a device.

**Current code starting point** (`src/regression-tests/DFS_RT_utilities.spin2`):
- `evaluateFSStats` (436), `ShowStats` (546), `showFiles` (569),
  `ensureEmptyDirectory` (584), `checkMatchingEntries` (671), `ReadFile` (755) — all
  call `dfs.…(dfs.DEV_FLASH)` directly.
- Consumers: 11 `DFS_FL_RT_*` suites (must stay untouched — they are the reference).

**Target.** Apply the **method-overloading pattern** (P2KB: Spin2 has no default
parameters):
- Introduce device-parameterized cores, e.g. `ensureEmptyDirectoryDev(dev)`,
  `evaluateFSStatsDev(dev, pMessage, expectedFileCount, expectedBlocksUsed)`,
  `checkMatchingEntriesDev(dev, pDirEntries)`, `showFilesDev(dev)`,
  `ShowStatsDev(dev)`, `ReadFileDev(dev, …)`.
- Rewrite the existing Flash-signature methods as **thin wrappers** that call the
  core with `dfs.DEV_FLASH`. The 11 Flash suites compile and behave identically —
  zero blast radius.
- Note the FAT32/SD reality inside the cores: `evaluateFSStats` on SD reports via
  `dfs.stats(DEV_SD)` / `freeSpace(DEV_SD)`; directory enumeration uses the SD
  directory walk. Where a Flash-specific concept (blocks-used deltas) has no SD
  analog, the SD path asserts the SD-meaningful equivalent (file-count delta +
  free-space delta), not a forced blocks metric.

**Integration points.** Section 5 builds the SD setup helpers on these cores;
Sections 6–8 consume them.

**Verification.**
- **Normal:** each Flash wrapper produces byte-identical output to today (diff a
  Flash suite's log before/after — must be unchanged).
- **Edge:** the `dev` core called with `DEV_SD` enumerates the SD root correctly.
- **Error:** core called with an invalid `dev` degrades to a visible setup failure,
  not a silent pass.
- Compile-check every touched Flash suite (`--compile-only` sweep) — the wrappers
  must not change any call site.

---

# Section 5 — Framework: SD setup / teardown / precondition-assert helpers

**Why.** There is **no** SD-capable shared setup helper today; each SD suite
hand-rolls a local `cleanup()` that only deletes named files. Compliance with the
contract must be cheap and identical across suites — a single home for
"reset working area," "assert ≥ N contiguous free clusters," "assert ≥ N free
clusters," and "audit a clean baseline."

**Current code starting point.**
- Local per-suite `cleanup()` patterns (e.g. defrag 334–345) — delete-only.
- Good idempotency exemplars to generalize: `multihandle` (cleanup at start+end),
  `volume`, `timestamp`.
- Section 2 `largestFreeExtent(dev)` and existing `freeSpace(dev)` (2167),
  `sectorsPerCluster()` (2765), `setTestMaxClusters()` (3625) are the primitives.

**Target.** Add to `DFS_RT_utilities.spin2` (built on the Section 4 cores):
- `ensureCleanBaseline(dev, pOwnedNames)` — delete this suite's owned files (start
  *and* end idempotency), then audit the working area is clean *for the entries this
  suite owns* (never assert the ambient root is globally empty on SD).
- `assertPrecondition(bHeld, pMessage)` — the *setup-not-met* reporter: emits a
  distinct "setup not met" line and short-circuits the test as skipped-precondition,
  **not** a driver failure (satisfies the contract's hard rule). Distinct from
  `recordFail()`.
- `assertContiguousFree(dev, minClusters, pMessage)` — SD-only (under
  `SD_INCLUDE_DEFRAG`): `largestFreeExtent(dev) >= minClusters`, else *setup-not-
  met*.
- `assertFreeSpace(dev, minClusters, pMessage)` — ungated: `freeSpace`-derived free
  clusters ≥ min, else *setup-not-met*. (Ungated so every suite doing large writes
  can audit capacity without enabling defrag.)
- `clustersForBytes(dev, sizeBytes)` — helper mirroring defrag Test 11's dynamic
  sizing (`sectorsPerCluster()`), so suites size fixtures independent of card
  cluster size.

**Design note (shared-first).** These are planned shared from the start (multiple
suites need them); no suite gets a private copy to "promote later." Gating:
contiguity helpers under `SD_INCLUDE_DEFRAG`; clean-baseline/free-space/setup-not-
met helpers ungated.

**Integration points.** Section 6 is the first consumer (template); Sections 7–8
adopt uniformly.

**Verification.**
- **Normal:** `assertContiguousFree` passes on a fresh card; `ensureCleanBaseline`
  leaves exactly the ambient non-owned entries.
- **Edge:** with `setTestMaxClusters(N)`, `assertContiguousFree(dev, N)` reports
  setup-not-met deterministically.
- **Error:** `assertPrecondition(false, …)` increments neither pass nor fail driver
  counters — it registers as skipped-precondition and the suite proceeds/aborts
  without polluting driver pass/fail totals.

---

# Section 6 — Retrofit the defrag suite as the template

**Why.** The only true HIGH-risk suite and the archetype the contract is written
against. Getting this exactly right defines the pattern every other retrofit copies.

**Current code starting point** (`DFS_SD_RT_defrag_tests.spin2`, 344 lines):
- Fixture-building is partly good: Test 3 (145–167) forces fragmentation with a
  spacer. Test 11 (261–273) already models `setTestMaxClusters` + dynamic
  `allocSize`.
- Gaps: `cleanup()` (334–345) deletes but never restores free-space contiguity;
  Group 3/4 (247–315) assume a contiguous free region ≥ 64 KB with **no audit**;
  Test 10 misreports `E_NO_CONTIGUOUS_SPACE` as a driver failure on a fragmented
  card.

**Target — full contract compliance:**
- **Setup (normalize, then verify — enabled by the formattable-card policy):**
  format-normalize the SD card to a known-clean, fully-contiguous FAT32 baseline at
  the suite's own setup (mirroring the Flash suites' `format(DEV_FLASH)` pattern),
  then `assertContiguousFree(DEV_SD, clustersForBytes(DEV_SD, FRAG_FILE_SIZE))` as
  **verification that normalization succeeded** — not as a skip gate. On a normalized
  card the audit passes and every contiguity test runs with full coverage; a
  *post-format* audit failure now signals a real defect (format or allocator bug),
  not an expected fragmented-card skip, and is treated as such (fix in-session).
  The SD format entry point is the one exercised by `DFS_SD_RT_format_tests`.
- **Build + audit fixture:** build both a fragmented file (spacer technique) **and**
  a contiguous file, and audit each (`fileFragments > 1` / `== 1`) before acting.
- **Act / Verify:** compact → assert target contiguous, **others untouched**, data
  intact (byte compare); keep next-fit Group 4.
- **New invariant assertion (ties to Section 3):** with `setTestMaxClusters` forcing
  no contiguous home, assert `compactFile` → `E_NO_CONTIGUOUS_SPACE` **and** the file
  is intact + readable **and** the filesystem is still usable (create/read/delete an
  unrelated file) **and** free accounting is unchanged.
- **Add** a unit assertion of `largestFreeExtent` against a known constrained window.
- **Teardown:** `ensureCleanBaseline` at end.

**Integration points.** First consumer of Sections 2, 3, 4, 5.

**Verification (cases).**
- **Normal:** on a fresh/contiguous card, all positive tests pass 12/12.
- **Edge:** on a deliberately fragmented card, contiguity-dependent tests report
  *setup-not-met* (not fail); the constrained-window negative test still asserts
  `E_NO_CONTIGUOUS_SPACE` deterministically.
- **Error:** the Section 3 invariant assertion (intact-after-clean-fail) is the
  headline error case.

---

# Section 7 — Retrofit the MEDIUM-risk cluster

**Why.** Five suites carry concrete, identifiable ambient assumptions beyond defrag.

**Current code starting points & targets.**
- `DFS_SD_RT_directory_tests` — `evaluateRange(fileCount, @"directory entries
  found", 2, 100)` (~line 237). **Target:** assert only on **self-created** entry
  counts (count what this suite made), or audit the ambient baseline first and
  assert deltas; drop the magic `100` upper bound.
- `DFS_SD_RT_dirhandle_tests` (SD) — asserts ambient root `foundFiles > 0 and
  foundDirs > 0` and `>= 4 entries` (~242–243). **Target:** build a known subdir
  fixture (already partially does with `DHTDIR1`) and assert against it, not the
  ambient root.
- `DFS_SD_RT_raw_sector_tests` — absolute `TEST_SECTOR_BASE = 100_000`,
  `HIGH_SECTOR_NUM = 1_000_000` (49–65), destructive with no capacity check.
  **Target:** audit card geometry first (register/CSD capacity) and report
  *setup-not-met* if the card is too small; keep raw writes confined to an audited
  safe region.
- `DFS_SD_RT_multiblock_tests` — same absolute-sector geometry assumption.
  **Target:** same geometry audit.
- `DFS_FL_RT_dirhandle_tests` (the one Flash exception that does **not** format) —
  **Target:** format + build fixture like its 10 Flash siblings
  (`ensureEmptyDirectoryDev(DEV_FLASH)` after format), removing the ambient-Flash-
  directory dependence.

**Integration points.** Uses Section 4 cores + Section 5 helpers + Section 2 query
(where contiguity is implicated).

**Verification (cases, per suite).**
- **Normal:** each suite passes against its self-built fixture regardless of ambient
  card contents.
- **Edge:** a card with many pre-existing root entries no longer breaks
  `directory`/`dirhandle` (no absolute-count assertion left); an undersized card
  makes `raw_sector`/`multiblock` report *setup-not-met*.
- **Error:** destructive raw writes never touch outside the audited region.

---

# Section 8 — Retrofit the LOW/NONE sweep (remaining suites)

**Why.** The rest are mostly self-provisioning, but the contract requires each to
*audit* its preconditions (several have latent gaps) and be re-run-idempotent.

**Current code starting points & targets.**
- **Latent no-audit large-writers:** `DFS_SD_RT_read_write_tests`,
  `DFS_SD_RT_speed_tests` — add `assertFreeSpace(DEV_SD, clustersForBytes(...))`
  before large writes so a full/fragmented card reports *setup-not-met*, not a
  driver write failure.
- **Missing start-of-run cleanup** (re-run collision risk): `recovery`,
  `read_write`, `error_handling`, `subdir_ops`, `crc_diag`, `crc_validation` — adopt
  `ensureCleanBaseline` at **start and end** (as `multihandle`/`volume`/`timestamp`
  already do).
- **Already clean (audit + confirm only):** `mount`, `parity`, `file_ops`, `seek`,
  `async`, `multicog`, `multihandle`, `volume`, `timestamp`, `register` (NONE),
  `subdir_ops`, cross/dual (`cross_device`, `dual_device`, `mbr_sentinel_stress`),
  and the 10 already-formatting Flash suites — verify contract compliance, add a
  precondition audit only where an assertion depends on state, otherwise leave as-is
  (do not churn NONE-risk suites needlessly).

**Integration points.** Section 5 helpers, uniformly.

**Verification (cases).**
- **Normal:** every suite passes on a clean card.
- **Edge:** re-running a suite twice in a row (no reformat) passes both times
  (idempotency) — the concrete test for start-of-run cleanup.
- **Error:** on a near-full card, the large-writer suites report *setup-not-met*
  rather than a spurious driver failure.

---

# Section 9 — Documentation finalization

**Why.** New driver API and changed test discipline are project deliverables; the
docs must land with the code, not after.

**Targets.**
- `DOCs/Plans/DEFRAG-ALLOCATION-GUIDE.md` — document `largestFreeExtent(dev)`
  alongside `createFileContiguous`/`compactFile`/`fileFragments`, including the
  clean-fail invariant for `compactFile` (Section 3) as a documented contract.
- `DOCs/DUAL-DRIVER-THEORY.md` — add `largestFreeExtent` to the SD API surface list
  where the other defrag methods appear.
- Section 1's contract/anti-pattern doc updates (best-practices, strategy,
  Test-Weakness-Patterns) are authored there but cross-checked here for consistency
  with the shipped helper names.
- **Version — UPDATED 2026-07-05 (during §2 execution): patch bump now CONFIRMED.**
  Task «#2» uncovered and fixed a real latent driver bug (`findContiguousRun` missing
  the FAT-sector-0 pre-load; affects `createFileContiguous`/`compactFile`). Driver
  *behavior* has therefore changed, and Stephen confirmed we ship a driver fix patch
  after the regression work. So at `build-wrapup` bump the **patch**: `DFS_VERSION`
  1.3.1 → 1.3.2 / `SD_VERSION` 1.5.1 → 1.5.2 (`dual_sd_fat32_flash_fs.spin2:89-90`).
  Original conditional entry decision retained below for provenance.

- **Version (original entry decision, 2026-07-05): no bump planned — revisit at closeout.**
  This sprint is predominantly regression-test augmentation. Two items touch the
  driver source: the additive, `SD_INCLUDE_DEFRAG`-gated public `largestFreeExtent()`
  method (backward-compatible), and the `compactFile` clean-fail fix *only if*
  certification shows the invariant is currently violated. Decision: **do not bump at
  start.** At `build-wrapup`, bump a **patch** (`DFS_VERSION` 1.3.1 → 1.3.2 /
  `SD_VERSION` 1.5.1 → 1.5.2, `dual_sd_fat32_flash_fs.spin2:89-90`) **iff** the driver
  behavior actually changed (compactFile fix landed) or the new API is being released
  to the field — otherwise ship no version change. Rationale for not going minor:
  build-marker versioning + additive/gated API; rationale for a patch-if-changed:
  v1.3.1 is currently in field testing and a changed-behavior binary must not reuse
  that label.

**Verification.** Doc review against the final shipped API signatures and helper
names; the defrag guide's `largestFreeExtent` description matches the compiled
wrapper.

---

# Section 10 — Certification (native, hardware)

**Why.** The definition-of-done gate. Specified here; executed natively.

**Target.** Full **sequential** `tools/run_regression.sh` passes deterministically
**regardless of card size or suite order**, reported **per-file** (every suite on
its own line with pass/fail counts + totals — never grouped or abbreviated).

**Procedure (native session).**
- **Card gate:** confirm an erasable/formattable scratch card has been provided
  before any run (per the run-policy above). Never run against a non-formattable
  card.
- `--compile-only` sweep must already be clean from the container.
- **Preflight (audit → format):** run `DFS_SD_FAT32_audit` against the card first
  (non-destructive; catches a corrupt FS / recurred MBR corruption as evidence),
  surface any audit failure, then format the scratch card to a clean FAT32 baseline
  before each sequential run so entry state is deterministic across cards and reruns.
- Run the full sequential regression on the 16 GB scratch card (the card that
  originally drew blood), then on a second card of a different size/cluster-geometry.
- Both runs deterministic and green; the defrag/`compactFile` invariant proven.
- Any suite that reports *setup-not-met* is investigated: either the card genuinely
  cannot host the fixture (acceptable, documented) or a retrofit gap (fixed
  in-session).

**Verification (cases).**
- **Normal:** two different-size cards → identical per-file green.
- **Edge:** running the suite order shuffled (or resuming mid-sequence via
  `--from`) yields the same result — order independence.
- **Error:** the `compactFile` clean-fail invariant holds on hardware; if not, the
  driver bug is fixed in-session and the run repeated.

---

## Cross-cutting notes

- **Compile gate (container):** after each section, `pnut-ts -d` the touched files
  (`cd src && pnut-ts -d dual_sd_fat32_flash_fs.spin2`;
  `cd src/regression-tests && pnut-ts -d -I .. <suite>.spin2`) plus a
  `flexspin.mac -2 -q -I . -I UTILS <file>` cross-check; and a full
  `cd tools && ./run_regression.sh --compile-only` sweep before hand-off.
- **No guessing on Spin2/PASM2** — consult P2KB before any language/compiler
  assumption (already applied: default-parameter finding drove Section 4's design).
- **Any bug found mid-sprint is fixed in-session**, not deferred.
- **Runner artifacts** (`src/regression-tests/performance.log`,
  `pnut-term-settings.json`, `tests/`) are pnut-term output — do not commit.

---

## Section ↔ Task cross-reference (todo-mcp, sprint tag `fixture-discipline`)

| Plan § | Deliverable | Task | seq |
| ------ | ----------- | ---- | --- |
| §2 | `largestFreeExtent` SD driver query | «#2» | 1 |
| §3 | `compactFile` clean-fail invariant | «#3» | 2 |
| §4 | Device-parameterize Flash-only helpers | «#4» | 3 |
| §5 | SD setup / precondition helpers | «#5» | 4 |
| §1 | Fixture-discipline contract (docs) | «#6» | 5 |
| §6 | Defrag retrofit (template) | «#7» | 6 |
| §7 | MEDIUM retrofit — directory-fixture (directory, dirhandle-SD) | «#8» | 7 |
| §7 | MEDIUM retrofit — geometry (raw_sector, multiblock) | «#9» | 8 |
| §8 | LOW retrofit — needs-changes (large-writers, idempotency, FL_dirhandle) | «#10» | 9 |
| §8 | LOW — compliance verification sweep | «#11» | 10 |
| §9 | Documentation finalization | «#12» | 11 |
| §10 | Native hardware certification | «#13» | 12 |

Ordering note: §1 (contract) is authored at seq 5 — after the §4/§5 helpers exist so it
references their shipped names, and before the retrofits (§6–8) that apply it
(standards-before-application).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
