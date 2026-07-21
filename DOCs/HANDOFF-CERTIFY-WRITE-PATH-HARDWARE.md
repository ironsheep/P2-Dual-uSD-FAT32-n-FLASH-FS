# HANDOFF — Certify the write-path corruption fixes on P2 hardware

**Created:** 2026-07-21
**For:** the native (house) agent that can download to a real P2 Edge Module and run the regression
suites against physical hardware. **This work cannot run in the container** (it downloads to the P2
over serial and requires a physical SD card + the onboard Flash chip).

**Goal:** certify the two write-path fixes committed this session so we can cut the **patch build**
(DFS 1.3.1 → 1.3.2, SD 1.5.1 → 1.5.2). This is the sprint's definition-of-done gate (Fixture-
Discipline plan §10, task **#13**).

---

## 1. What you are certifying (commits on `main`)

```
765a647  fix(sd write): follow FAT chain on cross-boundary overwrite; stop mid-sector zero-fill
a39dbde  docs: handoff to port write-path fixes to the standalone SD-only driver
```

Two write-path data-corruption bugs in `do_write_h` (`src/dual_sd_fat32_flash_fs.spin2`), root-caused
from a field report (refaQtor, 2026-07). Full analysis:
`DOCs/Feedback/2026-07-21-refaQtor-forum-thread-ANALYSIS.md`.

- **Bug A (🔴 critical):** a cluster-boundary crossing during an *in-place overwrite* called
  `allocateCluster()` unconditionally, which re-links the current cluster's FAT entry → truncates
  the chain → orphans the file's tail → user data over the FAT/VBR. **This is the most likely root
  cause of the long-standing recurring `DB(SD)=FAILED` / MBR-unreadable corruption.** Fix:
  `writeAdvanceCluster()` follows the existing link, allocates only at true EOC; plus a `root_sec`
  guard that refuses any write below the data region.
- **Bug B:** mid-sector write chose read-vs-zero-fill by file position, wiping the leading bytes of
  the sector on a mid-sector append/overwrite. Fix: decide by the sector's first byte.

New permanent regression gate: **`src/regression-tests/DFS_SD_RT_fatchain_tests.spin2`** (wired into
`tools/run_regression.sh` right after `DFS_SD_RT_read_write_tests`).

**Container status already verified:** driver + new suite compile clean; full **compile-only** sweep
is **33/33 pass, 0 fail**. What remains is *behavioral* proof on hardware.

---

## 2. Card policy — READ BEFORE PLUGGING ANYTHING IN

- **Only use an erasable / formattable scratch card.** Never run the SD regression against a card you
  are not willing to have reformatted. Confirm this before any run.
- Use **two** cards for full certification:
  1. The **16 GB card that originally drew blood** (recurring corruption) — the primary A/B target.
  2. A **second card of different size / cluster geometry** (e.g. small-cluster vs large-cluster) —
     Bug A only triggers with certain cluster sizes, so geometry variation is part of the proof.
- **Preflight per card = audit → format:**
  1. Run the SD FAT32 **audit** first (non-destructive): `src/UTILS/DFS_SD_FAT32_audit.spin2`. This
     catches a corrupt FS or recurred MBR corruption *as evidence* before you wipe it — capture that
     output if it's dirty.
  2. Then **format** to a clean FAT32 baseline: `src/UTILS/DFS_SD_format_card.spin2`.

---

## 3. The decisive A/B test (do this first, it's the whole point)

`DFS_SD_RT_fatchain_tests.spin2` is built to **fail on the old driver and pass on the fixed driver**.
Prove both halves on the **same card**:

1. **OLD (expect FAIL):** check out the pre-fix parent `git checkout 765a647~1 -- src/dual_sd_fat32_flash_fs.spin2`
   (or stash the fix), then run just this suite:
   ```
   cd tools/
   ./run_test.sh ../src/regression-tests/DFS_SD_RT_fatchain_tests.spin2 -t 120
   ```
   Expect **Group A** ("cross-boundary overwrite follows FAT chain") to FAIL — the whole-file read
   short-reads at the orphaned tail and/or the tail cluster no longer holds its original pattern —
   and **Group B** ("mid-sector append preserves leading bytes") to FAIL (leading bytes read as 0).
   *(If the old driver corrupts the card here, that is expected — re-format before the next step.)*
2. **FIXED (expect PASS):** restore the fixed driver (`git checkout main -- src/dual_sd_fat32_flash_fs.spin2`),
   re-format the card, rerun the same suite. Expect **all groups PASS**.

Record the A/B (old-FAIL → fixed-PASS) result — that is the certification evidence for Bug A + B.

> Why the test is shaped this way (don't be tempted to "simplify" it): a *full* overwrite does NOT
> expose Bug A, because the reader follows the rewritten-but-consistent chain. The test overwrites
> only the first 2 clusters of a 3-cluster file and checks the **untouched tail survives**.

---

## 4. Full regression (both cards, fixed driver)

Run the complete sequential suite and report **per file**:

```
cd tools/
./run_regression.sh                 # stop on first failure; logs to tools/logs/
# resume mid-run if needed:
./run_regression.sh --from fatchain
# stress + format variants (format ERASES the card — scratch only):
./run_regression.sh --include-8cog
./run_regression.sh --include-format
```

**Reporting rules (from CLAUDE.md — the user watches live):**
- Report **every test file on its own line** with its pass/fail counts, then grand totals.
- Do **NOT** group by suite-family (no "SD: 424 pass"). Each file on its own line.
- Do **NOT** abbreviate with "all N suites pass".

Example shape:
```
DFS_SD_RT_read_write_tests:      NN pass, 0 fail
DFS_SD_RT_fatchain_tests:        NN pass, 0 fail
...
Total: N,NNN tests, 0 failures
```

Run the full suite on **both** cards; both must be **deterministic, green, and order-independent**
(sanity-check order independence with a shuffled `--from` start).

---

## 5. Extra invariants to confirm on hardware

- **`compactFile` clean-fail invariant** (sprint §3/§6/§9): a relocation that cannot find contiguous
  space must fail cleanly — release the original chain only after the new chain is committed; no
  half-swap on `E_NO_CONTIGUOUS_SPACE`. Exercise the defrag suite
  (`DFS_SD_RT_defrag_tests.spin2`) and confirm no orphaned/duplicated clusters after a failed
  compaction. If it fails, fix the driver in-session and rerun.
- **`root_sec` guard never fires in normal operation** — it is a backstop. If you ever see
  `[do_write_h] REFUSING metadata-region write` during a passing run, that's a real defect to
  investigate, not noise.
- **Baseline-health exit check:** compile still clean, and no regressions versus the entry baseline
  (was 32/32 suites; now **33/33** with the new gate).

---

## 6. If something fails

- A **fatchain** failure on the *fixed* driver means the fix is incomplete — capture the suite output
  and the failing group, and treat it as a live driver bug (fix + rerun A/B). Do not ship.
- A **setup-not-met** (e.g. `assertFreeSpace` fails) is investigated, not ignored: either a genuine
  card capacity/geometry limit (document it) or a retrofit gap (fix it).
- Any **card corruption on the fixed driver** is a certification blocker — the whole point of these
  fixes is that it must not recur.

---

## 7. On success — cut the patch build

1. **Build-wrapup** (release notes): the fixes are behavior-changing, so this is a **patch** bump —
   **DFS 1.3.1 → 1.3.2, SD 1.5.1 → 1.5.2**. Record the two-bug fix + new gate in the release notes.
2. **Mark sprint task #13 complete** and run sprint-closeout.
3. **Unblock the standalone-driver handoff:** open
   `DOCs/HANDOFF-SD-WRITE-PATH-PORT-TO-STANDALONE.md`, re-audit the *shipped* `writeAdvanceCluster`,
   `root_sec` guard, and mid-sector predicate against what certified, update its §4 to match, then
   flip its §0 status **DRAFT → READY** (per its §7 checklist). The same two bugs exist in
   `REF-FLASH-uSD/uSD-FAT32/src/micro_sd_fat32_fs.spin2` and get ported next.

---

## 8. Pointers

- Analysis + verbatim field report: `DOCs/Feedback/2026-07-21-refaQtor-forum-thread*.md`
- Standalone-driver port handoff (gated on this cert): `DOCs/HANDOFF-SD-WRITE-PATH-PORT-TO-STANDALONE.md`
- Sprint plan (§↔task table at end): `DOCs/Plans/REGRESSION-FIXTURE-DISCIPLINE-SPRINT-PLAN.md`
- Prior MBR-corruption handoff (bus-theory + CRC fixes, earlier work): `DOCs/HANDOFF-MBR-CORRUPTION-FIX.md`
- Build/test commands and reporting rules: `CLAUDE.md`
