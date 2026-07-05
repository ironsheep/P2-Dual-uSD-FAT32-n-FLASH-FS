# KICKOFF / HANDOFF -- Regression Fixture-Discipline Systemic Fix

**Purpose of this doc:** everything a fresh session (running **inside the devcontainer**) needs to
develop the full plan and execute it, with zero dependence on the authoring session's context.

**Date:** 2026-07-05
**Author context:** native session with a P2 Edge + 16 GB scratch microSD attached.
**Execution context:** devcontainer (full edit/commit freedom, **no serial/hardware access**).

---

## 0. READ FIRST -- working agreement (persisted in memory too)

- **Fix systemically, not narrowly.** When a root problem is found, fix the whole class in place
  and let regression *certify* it. Do not ship a narrow patch and defer the broad fix. (memory:
  `feedback-fix-systemically`) This whole effort exists because of that principle.
- **Full freedom in the container.** Make edits and commits without asking permission. The user
  moved this work into the container specifically so you don't have to.
- **Never use the AskUserQuestion tool.** Ask in plain text if you must. (memory:
  `feedback_no_ask_ui`)
- **No guessing on Spin2/PASM2.** Consult P2KB (`mcp__p2kb-mcp__p2kb_find` / `_get`) before
  assuming any language/compiler/hardware behavior. (CLAUDE.md)
- **Any bug found during the work must be fixed in-session**, not deferred. (CLAUDE.md)
- **Regression reporting rule:** report EVERY test file on its own line with pass/fail counts +
  totals. Never group by family or abbreviate. (CLAUDE.md)

## 0a. Hardware split (IMPORTANT)

The container **cannot drive the P2 over serial.** So the workflow is:
- **In the container:** develop the plan, write all code (driver query, framework helpers, suite
  retrofits, doc updates), and **compile-check** everything (`pnut-ts -d ...` and
  `flexspin.mac -2 -q ...`). Compilation is the container's proof-of-correctness gate.
- **Back out in a native session (P2 Edge attached):** run **all hardware testing** and the final
  certification run. The user will drive this: *"After all the change is in place, we'll come back
  out of the container and do all the actual testing against hardware."*

So: leave the tree compiling-clean and fully staged for a native certification pass. Do not treat
"can't run on hardware" as a blocker -- it's the expected division of labor.

---

## 1. The systemic problem

Regression suites depend on **ambient microSD card state** instead of each establishing and
**auditing** its own preconditions. A "green" run today can mean "the card happened to be in a
favorable state," not "the driver is correct." The fragility is latent in any suite that assumes
free-space layout, allocation contiguity, or directory entry counts -- it just drew blood in the
defrag suite first (see section 4 for the full evidence trail).

**Definition of the fix being complete (certification):** a full **sequential**
`tools/run_regression.sh` passes **deterministically regardless of card size or suite order**, on
hardware, reported per-file. After that we're back to hunting new issues on solid ground.

---

## 2. The agreed plan (develop the detail in-container, then execute)

Author a proper sprint plan first (use the `sprint-plan` skill; put it at
`DOCs/Plans/REGRESSION-FIXTURE-DISCIPLINE-SPRINT-PLAN.md`), then execute. The shape is fixed; fill
in the detail:

1. **Fixture-discipline contract.** Codify the standard every suite follows:
   **Setup** (establish *and audit* preconditions) -> **Build + audit fixture** -> **Act** ->
   **Verify postconditions** -> **Teardown**. Hard rule: a suite may not assert a driver result
   until it has proven its precondition held; an unmet precondition reports as *"setup not met,"*
   never as a driver failure. Document it in the regression best-practices doc (see section 5).

2. **Enabling driver capability.** Add a **largest-contiguous-free-extent** query to the driver
   (you cannot audit a space precondition you cannot measure). Put it near the existing space/geom
   APIs. Include a unit assertion of known values where possible.

3. **Shared framework helpers.** Add uniform setup/teardown/precondition-assert helpers to
   `src/regression-tests/DFS_RT_utilities.spin2` so compliance is cheap and identical across
   suites (single home for "reset working area", "assert >= N contiguous free clusters", etc.).

4. **Retrofit all standard suites.** Audit each for ambient-state dependence and make it
   self-sufficient. Do **defrag first as the template**, then the rest. This is also where the
   open robustness question becomes an explicit assertion (see section 4, "open question").

5. **Certify (native, hardware).** Full sequential `run_regression.sh` passes deterministically on
   any card size / order. That run is the certification.

---

## 3. Concrete starting points (files + anchors)

- **Driver:** `src/dual_sd_fat32_flash_fs.spin2` (~11.5k lines). Add the contiguous-extent query
  near existing space/geometry APIs:
  - `PUB freeSpace(dev)` @ line ~2167
  - `PUB sectorsPerCluster()` @ line ~2765
  - `PUB setTestMaxClusters(limit)` @ line ~3625  (test hook that caps the allocatable range --
    used by defrag test #11 to force `E_NO_CONTIGUOUS_SPACE`)
  - Worker-cog architecture: PUB methods are caller-cog wrappers; the real work runs in PRI
    `do_*()` methods in the worker cog via `send_command()`. A new query that touches the FAT must
    route through the worker (see MEMORY.md "SPI Worker-Cog Architecture").
- **Test framework:** `src/regression-tests/DFS_RT_utilities.spin2`. Existing surface includes
  `startTestGroup`, `startTest`, `evaluateBool/SingleValue/Range/...`, `ensureEmptyDirectory()`
  (line ~580, a setup-ish helper to build on), `ShowTestEndCounts()`.
- **Suites (37 `DFS_*_tests.spin2`, 32 standard):** `src/regression-tests/`. Template first:
  **`DFS_SD_RT_defrag_tests.spin2`** (see section 4 for its exact gaps).
- **Runners:** `tools/run_regression.sh` (sequential, stop-on-first-fail, `--from <substr>`,
  `--compile-only`, `--include-format`), `tools/run_test.sh <path> -t <sec>` (single suite; sets
  all `-I` include paths incl. UTILS/REF -- needed for the format suite). Logs -> `tools/logs/`.
  These are **native-only** (hardware). In-container use `--compile-only` or direct `pnut-ts -d`.
- **Format utility (for setup normalization):** `DFS_SD_RT_format_tests.spin2` reformats + verifies
  clean FAT32 (46 tests). The format helper it uses is the model for a "normalize free space"
  setup primitive.
- **Best-practices docs to update:** `DOCs/Decisions/REGRESSION-TESTING-BEST-PRACTICES.md` and/or
  `DOCs/procedures/REGRESSION-TESTING-STRATEGY.md` (there is no live `BEST-PRACTICES-GUIDE.md`; the
  old one is archived under `DOCs/procedures/archive/`).

### Build / compile-check commands (container-safe)
```
# Driver standalone
cd src && pnut-ts -d dual_sd_fat32_flash_fs.spin2
# A suite (from regression-tests/)
cd src/regression-tests && pnut-ts -d -I .. <suite>.spin2
# FlexSpin cross-check (macOS binary name is flexspin.mac)
flexspin.mac -2 -q -I . -I UTILS <file>.spin2
# Compile-only regression sweep (no hardware)
cd tools && ./run_regression.sh --compile-only
```

---

## 4. Why we're doing this -- evidence trail (defrag investigation)

Symptom: full sequential regression stopped at `DFS_SD_RT_defrag_tests` (suite 21). Diagnosis:

- Defrag failed **7/12** in the sequential run, but **passes 12/12 on a freshly-formatted card**
  and fails **4/12 on the unmodified pre-fix driver** -- so it is **card-state dependent, not a
  code regression** and unrelated to the (separate, now-shipped) MBR fix.
- The failure signature was `compactFile()` -> file comes back `-40` (not found); this cascaded
  into later directory-walking suites (`DFS_SD_RT_directory_tests` hung, `DFS_SD_RT_dirhandle_tests`
  4/13). **All of them pass 100% on a clean card.** (memory: `defrag-suite-needs-clean-card`)
- Likely amplifier: the scratch card is **16 GB** vs the historical **64 GB** baseline. FAT32
  cluster size scales with volume size (16 GB ~ smaller clusters), so the same churn fragments the
  free space finer and leaves no long contiguous run. The card had ~16 GB *free* when it failed --
  so it is **contiguity, not capacity**.

### The exact gaps in `DFS_SD_RT_defrag_tests.spin2`
- It **does** build a fragmented file itself (test #3: create fragFileA, create a spacer, append
  to fragFileA so its clusters straddle the spacer -> >1 fragment). Good.
- It calls `cleanup()` at the **start** (deletes its own named files) -- but **deleting files
  cannot defragment free space.** Freed clusters stay scattered, so the *free-space contiguity*
  the tests actually need is still whatever prior suites left.
- Consequently `compactFile()` (needs a contiguous home to relocate into) and
  `createFileContiguous()` / next-fit (need a contiguous free region) fail on a fragmented card,
  and `fragFileA` is left broken/absent -> the `-40`.
- **Worst part:** the suite does **not audit the precondition**, so a *setup* deficiency (no
  contiguous space) is reported as a *driver* failure. That is the core sin this whole effort fixes.

### Open question to resolve via the retrofit (do NOT leave unproven)
Does a `compactFile()` that hits insufficient contiguous space **fail cleanly**, or does it
**corrupt/lose the file**? The `-40` suggests it may not fail cleanly. Turn this into an explicit
assertion: *"compactFile with insufficient contiguous space returns `E_NO_CONTIGUOUS_SPACE` and
leaves the file intact and readable."* If that assertion fails on hardware, it's a real driver
robustness bug -> fix it in-session (per the working agreement).

---

## 5. Suggested execution order (in container)

1. Author the sprint plan (`sprint-plan` skill) at
   `DOCs/Plans/REGRESSION-FIXTURE-DISCIPLINE-SPRINT-PLAN.md`; create tracking tasks (todo-mcp).
2. Codify the fixture-discipline contract in the regression best-practices doc.
3. Add the driver **largest-contiguous-free-extent** query (worker-cog routed); compile-check;
   add a unit assertion.
4. Add framework helpers to `DFS_RT_utilities.spin2` (normalize-working-area, assert-preconditions,
   teardown); compile-check.
5. Retrofit **defrag** as the template (setup normalizes free space + audits it; build both a
   fragmented AND a contiguous file and audit each; act; verify target-contiguous +
   others-untouched + data-intact; add the `E_NO_CONTIGUOUS_SPACE`-and-intact assertion; teardown).
   Compile-check.
6. Retrofit the remaining 31 standard suites, auditing each for ambient-state dependence.
7. Full `--compile-only` sweep clean (pnut-ts) + FlexSpin cross-check on touched files.
8. **Hand back to native** for the hardware certification run.

## 6. Definition of done
- Every standard suite establishes **and audits** its own preconditions; no suite depends on
  ambient card state.
- Full **sequential** `run_regression.sh` passes deterministically **regardless of card size or
  order** (hardware, reported per-file).
- The `compactFile`-on-failure robustness question is resolved (asserted clean, or bug fixed).
- Contract documented; framework helpers in place; sprint plan + tasks tracked and closed.

---

## 7. State at hand-off (already done this session)
- **MBR-corruption fix shipped as v1.3.1** (commit `5d90d73` version bump, `ea93f0d` fix), tagged
  `v1.3.1`, pushed; release workflow ran; the reporting user was sent the build to field-test.
  (memory: `mbr-corruption-fix-verified`) Not part of this effort -- context only.
- **Standalone-driver CRC port hand-off** written: `DOCs/HANDOFF-SD-CRC-PORT-TO-STANDALONE.md`
  (for the separate SD-only driver's agent). Open follow-up noted there: whether to add a CMD59
  graceful-fallback to the dual driver too (a v1.3.2 candidate) -- **not** part of this effort.
- Runner artifacts left untracked in `src/regression-tests/` (`performance.log`,
  `pnut-term-settings.json`, `tests/`) -- pnut-term output, do not commit.

```
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```
