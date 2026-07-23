# HANDOFF — Port the write-path corruption fixes to the standalone SD-only driver

**Status: READY.** Certified on hardware; safe to hand to the standalone-driver agent. See
[§0 Release status](#0-release-status--read-this-first).
**Created:** 2026-07-21 · **Certified & finalized:** 2026-07-22
**Reference implementation (dual driver):** the **certified v1.3.2** build on `main` —
`src/dual_sd_fat32_flash_fs.spin2`. The fix itself landed in `765a647`; the test-harness
corrections found during certification landed in `462fd28`; the release was cut in `da52d94`.
**Read all three** — the harness fixes in `462fd28` are part of what you port (see §4.5 / §5).
**Target of this handoff:** the standalone SD-only FAT32 driver,
`REF-FLASH-uSD/uSD-FAT32/src/micro_sd_fat32_fs.spin2` (the read-only reference baseline in this
repo; apply to whichever shipping copy derives from it).

---

## 0. RELEASE STATUS — read this first

> ✅ **This document is now READY to hand off.** The dual-driver fix it describes was certified on
> real P2 hardware on **2026-07-22** and shipped as **DFS v1.3.2 / SD sub-driver v1.5.2** (commit
> `da52d94`).
>
> **What certified:**
> - **Two cards of different cluster geometry** — a Gigastone SD16G (8 KB clusters) and an 8 GB card
>   (4 KB clusters) — each ran the full sequential regression at **1,347 pass / 0 fail**,
>   order-independent.
> - The decisive **A/B on the same card**: `DFS_SD_RT_fatchain_tests` **FAILS on the pre-fix driver
>   and PASSES after the fix** (9/9), for both Bug A (tail survives) and Bug B (leading bytes survive).
> - The `root_sec` data-region guard **never fired** during any passing run (it is a backstop, as
>   intended).
>
> **What the hardware run changed (and why this doc is no longer a verbatim copy of `765a647`):**
> Certification did *not* force any change to the driver fix itself — `writeAdvanceCluster`, the
> `root_sec` guard, and the mid-sector predicate are byte-for-byte what was drafted. **But it
> exposed a separate class of defect in the *test harness*** (commit `462fd28`): a systemic Spin2
> expression hazard that made the Bug-A regression **silently skip** — i.e. report green while never
> actually running. That is now folded in below (§4.5) and it is **mandatory** for the port: without
> it your ported suite can pass without testing anything. This is exactly the "detect the problem
> before you fix it" concern — see §6.

---

## 1. What is being ported (two independent write-path bugs)

Both live in `do_write_h` and both cause real data loss / filesystem corruption. They were
root-caused from a field report (refaQtor, 2026-07); full analysis in
`DOCs/Feedback/2026-07-21-refaQtor-forum-thread-ANALYSIS.md`.

### Bug A — FAT-chain truncation on cross-boundary overwrite  🔴 CRITICAL
On a cluster-boundary crossing, `do_write_h` calls `allocateCluster(h_cluster[handle])`
**unconditionally**. `allocateCluster(cluster)` **re-links the passed cluster's FAT entry** to the
freshly allocated cluster. So an *in-place overwrite* of a multi-cluster file that crosses a
boundary rewrites a live FAT link → truncates the chain → orphans the file's tail → user data
lands on the FAT/VBR → whole-volume corruption (card unreadable by a PC until reformatted). The
read path already follows the chain correctly; only the write path is wrong.

### Bug B — mid-sector write zero-fills leading bytes  🟠
`do_write_h` chooses read-vs-zero-fill by **file position**: an append/overwrite that starts
mid-sector (`position == size`) zero-fills the tail sector and wipes the existing bytes *before*
the write point.

### Issue C (NOT a port item)
The `send_command`/`WAITATN` concurrency item from the same report is a dual-driver worker-cog
concern and does **not** apply to the standalone SD driver's architecture. Ignore it here.

---

## 2. Exact locations in `micro_sd_fat32_fs.spin2` (verified 2026-07-21)

| What | Line(s) | Note |
|---|---|---|
| `PRI do_write_h(...)` | **1707** | signature carries unused `fat_addr` local (drop after port) |
| Bug A — site 1 (resume-at-boundary advance) | **1752–1758** | `new_cluster := allocateCluster(h_cluster[handle])` |
| Bug A — site 2 (mid-write boundary advance) | **1812–1820** | comment even says *"allocate new cluster **or follow chain**"* — but only allocates |
| Bug B — read-vs-zerofill by position | **1772** | `if h_position[handle] < h_size[handle]` |
| `PRI allocateCluster(cluster)` (the relink) | **4505+** (relink at **4537–4539**) | confirms the unconditional forward-link rewrite that Bug A weaponizes |
| `PRI do_read_h(...)` chain-follow idiom to MIRROR | **1650–1659** and **1692–1702** | copy *this file's* idiom, see §4 |
| `root_sec` (data-region start var) | decl **352**, set **1159** | used by the Bug-A guard |
| `sec_per_clus` | **351** | `clusterBytes()` = `sec_per_clus << 9` |

**Legacy write path — assess separately (do NOT assume):** this driver still has a V2 non-handle
`PRI do_write(...)` at **2163** with its own `allocateCluster()` calls (2181, 2202, 2224, 2238) and
a boundary check near **2026/2138**. The dual driver consolidated onto `do_write_h`; the standalone
has not. **The agent must determine whether `do_write`/its callers ever perform an in-place
overwrite across a cluster boundary.** If they can, Bug A exists there too and needs the same
follow-vs-allocate correction; if that path is append/grow-only, document why it is immune. Do not
ship the port until this question is answered in writing.

---

## 3. House-style differences from the dual driver (mirror the target file, not the reference)

The standalone driver predates the dual driver's constants/logging conventions. **Match the target
file's existing idiom** — do not paste dual-driver code verbatim:

- **No named constants.** It uses literals: `511` (not `SECTOR_MASK`), `512`, `<< 9` (sector bits),
  `<< 2` (FAT entry shift). Keep using literals.
- **EOC compare is signed:** `do_read_h` uses `if next_cluster >= $0FFF_FFF8` (the dual driver uses
  the unsigned `+>=`). **Use `>=` here to match `do_read_h` in this file.**
- **Logging is bare `debug(...)`**, not `DEBUG[CH_FILE](...)`.
- **Control flow uses early `return`s** (e.g. `return 0`, `return bytes_written`), not the dual
  driver's assign-then-fall-through style.
- **Bitwise NOT is `!`** (already used in this file, e.g. `h_flags &= !HF_DIRTY`).

---

## 4. The fix, adapted to the standalone driver

### 4a. Add `PRI writeAdvanceCluster(handle)` — follow-or-allocate
Mirror **this file's** `do_read_h` boundary idiom (lines 1650–1659):

```spin2
PRI writeAdvanceCluster(handle) : ok | cluster, fat_addr, next_cluster, new_cluster
' Advance a WRITE handle across a cluster boundary CORRECTLY.  On an in-place overwrite that spans
' a boundary the current cluster ALREADY links forward -- FOLLOW that link, do NOT allocate.  The
' old code called allocateCluster() unconditionally; allocateCluster() re-links the passed cluster
' to a fresh cluster, truncating the chain and orphaning the tail -> FAT/VBR corruption.  Mirrors
' the chain-follow do_read_h already does; allocates only when the current cluster is truly EOC.
  cluster := h_cluster[handle]
  if readSector(cluster >> 7 + fat_sec, BUF_FAT) < 0
    debug("  [writeAdvanceCluster] FAT read FAILED for cluster ", udec_(cluster))
    return false
  fat_addr := @fat_buf + ((cluster << 2) & 511)
  next_cluster := long[fat_addr]
  if next_cluster >= $0FFF_FFF8                         ' current cluster is end-of-chain -> grow
    new_cluster := allocateCluster(cluster)
    if new_cluster < 0
      debug("  [writeAdvanceCluster] Failed to allocate cluster")
      return false
    h_cluster[handle] := new_cluster
    h_sector[handle]  := clus2sec(new_cluster)
  else                                                  ' already linked -> FOLLOW existing chain
    h_cluster[handle] := next_cluster
    h_sector[handle]  := clus2sec(next_cluster)
  return true
```

Then replace **both** unconditional `allocateCluster()` boundary-advance blocks:

- Site 1 (≈1752–1758) →
  ```spin2
      if ((h_sector[handle] - cluster_offset) & (sec_per_clus - 1)) == 0
        if not writeAdvanceCluster(handle)
          return 0
  ```
- Site 2 (≈1812–1820) →
  ```spin2
      if ((h_sector[handle] - cluster_offset) & (sec_per_clus - 1)) == 0
        if not writeAdvanceCluster(handle)
          return bytes_written
  ```

Remove the now-unused `new_cluster` / `fat_addr` locals from `do_write_h` if nothing else uses them
(the standalone has no DEFRAG pre-alloc branch, so `new_cluster` likely becomes unused — confirm).

### 4b. Add the `root_sec` data-region write guard (Bug A, correct-by-construction)
At the top of the `repeat while count > 0` loop (just before the buffer-load, ≈1762):

```spin2
  repeat while count > 0
    ' CORRECT BY CONSTRUCTION: file data lives only in the data region (sector >= root_sec).
    ' A write below root_sec means a corrupted cluster/seek would stomp the VBR/FAT/root -- refuse
    ' it loudly rather than destroy the filesystem.
    if h_sector[handle] < root_sec
      debug("  [do_write_h] REFUSING metadata-region write: sector ", udec_(h_sector[handle]), " < data start ", udec_(root_sec), " -- aborting to protect the FS")
      return bytes_written
```

### 4c. Bug B — decide load-vs-zerofill by the sector's first byte (line 1772)
```spin2
      ' Load the sector when ITS FIRST BYTE is within the file, so a mid-sector write (append at
      ' position==size, or an overwrite) preserves the existing leading bytes instead of zeroing them.
      if (h_position[handle] & !511) < h_size[handle]
```

### 4d. Add the `clusterBytes()` introspection helper (needed by the test)
```spin2
PUB clusterBytes() : n
'' Bytes per cluster of the mounted volume (test helper: place a write exactly on a cluster
'' boundary).  Valid only after a successful mount.
  n := sec_per_clus << 9
```
Guard with the standalone's mounted-state check if it has one (match how `freeSpace`/`stats` gate).
The shipped dual-driver version returns **0 when not mounted** (`if NOT sd_mounted: n := 0`); mirror
that so the ported test can detect an unmounted card instead of dividing by a garbage cluster size.

### 4e. Certified-vs-drafted note (nothing to change, but confirm)
The three driver edits above (`writeAdvanceCluster`, the `root_sec` guard, the mid-sector predicate)
certified **unchanged** from this draft — the hardware run forced no edit to them. Two cosmetic
points when you diff against the shipped dual driver `dual_sd_fat32_flash_fs.spin2`:

- The shipped dual driver uses **named constants** (`SECTOR_MASK`, `FAT_ENTRY_SHIFT`, `SECTOR_BITS`)
  and the **unsigned** EOC compare `+>=`. Per §3, the standalone uses **literals** (`511`, `<< 2`,
  `<< 9`) and the **signed** `>=` to match its own `do_read_h`. Keep the standalone's idiom — do not
  import the constants.
- The shipped guard sits at the top of `repeat while count > 0` and uses `quit` (its `bytes_written`
  is the running return var that falls through). The standalone is early-return style, so
  `return bytes_written` there is correct — but make sure the value you return is the count written
  **so far**, not 0, so a guard-triggered abort still reports the partial write.

---

## 4.5. Harness / language hazard found during certification — YOU MUST PORT THIS TOO  🔴

These are **not** driver bugs — they are defects in the *regression harness* that certification
uncovered (commit `462fd28`). They matter to the port because **without them your ported fatchain
suite can report PASS while never actually exercising Bug A.** A false green here is worse than a
red: it certifies a corruption fix that was never tested.

### 4.5a. Systemic Spin2 expression hazard: never chain two worker-routed driver calls
`assertFreeSpace`, `clustersForBytes`, and `assertContiguousFree` each combined **two** driver PUB
calls in a single Spin2 expression, e.g.:

```spin2
freeClusters := dfs.freeSpace(dfs.DEV_SD) / dfs.sectorsPerCluster()   ' WRONG
```

`freeSpace()` dispatches a command to the worker cog (`send_command` + `WAITATN`). Combining that
routed call with a second call in one expression yielded a **corrupted result** (`freeClusters` read
as 0 or -1). The capacity gate then reported **"SETUP NOT MET" and SKIPPED the gated tests** —
including the Bug-A cross-boundary-overwrite regression itself. The symptom was **recompile-sensitive
non-determinism** (green on one build, silent-skip on the next). Fix — compute each driver query into
its own local **first**, then combine:

```spin2
freeClusters := dfs.freeSpace(dfs.DEV_SD)     ' each routed call resolves on its own line
spc          := dfs.sectorsPerCluster()
freeClusters := freeClusters / spc            ' now safe to combine
```

**Does this apply to the standalone?** Yes — the standalone SD driver is **also worker-cog based**
(it has `send_command` / `WAITATN` / `COGATN` machinery). Any ported helper that chains two of its
routed query PUBs in one expression is exposed to the same corruption. **Port the local-first idiom
into every ported helper** (`assertFreeSpace`, `clustersForBytes`, and any contiguous-free/geometry
helper). It is the safe Spin2 idiom regardless of architecture and costs nothing. Impact in the dual
driver: ~9 SD suites use these helpers, so prior "green" runs may have hidden capacity-gated skips —
assume the same risk in the standalone suite until you re-run and see the gated tests actually
execute (see §6, step 0).

### 4.5b. Three structural fixes to the fatchain suite itself
Fold these into your ported `SD_RT_fatchain_tests`:

1. **`END_SESSION` + `stop()` at the end.** The suite was missing the `END_SESSION` marker (and
   `dfs.stop()`); without it the **sequential runner hangs** waiting for the suite to signal
   completion. Every other suite emits it — match them (use the standalone runner's equivalent
   end-of-session marker).
2. **Don't mix `evaluateSubValue` with a full `evaluateBool` under one `startTest`.** The growth-path
   group (A2) did, producing **BAD TEST COUNTS (9 ≠ 10)**. A `startTest` that uses sub-evaluations
   must roll up to **one** pass/fail result — use `evaluateSubBool` (not `evaluateBool`) for the
   final check in such a group. Verify the standalone's `isp_rt_utilities` has `evaluateSubValue`
   **and** `evaluateSubBool`; if only one exists, rewrite the group to use whichever gives a single
   rolled-up result.
3. **Capacity gate must not silently swallow the test.** The whole `if assertFreeSpace(...)` gate
   is there to skip gracefully on a too-small card — but a *broken* gate (4.5a) skips on a card that
   had plenty of room. After porting, **prove the gate lets the tests run** on your certification
   card (see §6 step 0) before you trust any PASS.

---

## 5. Regression test to port

Reference: `src/regression-tests/DFS_SD_RT_fatchain_tests.spin2` (committed in `765a647`).

Port it to the standalone suite as **`SD_RT_fatchain_tests.spin2`** and wire it into that project's
runner. Adapt to the standalone conventions:

- OBJ is the standalone driver (`micro_sd_fat32_fs`) and its test utils (**`isp_rt_utilities`**, not
  `DFS_RT_utilities`). **Verify equivalent helpers exist** in `isp_rt_utilities.spin2`:
  `startTestGroup`, `startTest`, `evaluateBool`, `evaluateSingleValue`, `evaluateSubValue`,
  **`evaluateSubBool`** (needed by Group A2 — see §4.5b), `fillBufferWithValue`, `verifyBufferValue`,
  `assertFreeSpace`, `clustersForBytes`, `ShowTestEndCounts`. If any are missing, add them or rewrite
  the assertions in terms of what exists. **When you add/copy `assertFreeSpace` /`clustersForBytes`,
  apply the local-first idiom from §4.5a** — do not paste the chained-call version.
- **Emit the end-of-session marker.** The shipped suite ends with `dfs.stop()` then a `debug(...)`
  `END_SESSION` line (§4.5b.1). Include the standalone runner's equivalent so the sequential runner
  doesn't hang.
- Use the standalone's public API names for open/write/read/seek/close (they should match:
  `createFileNew`, `openFileWrite`, `openFileRead`, `writeHandle`, `readHandle`, `seekHandle`,
  `fileSizeHandle`, `closeFileHandle`, `deleteFile`, `mount`, `clusterBytes`).

**Why the test is shaped the way it is (do not "simplify" it):** a *full* overwrite does **not**
expose Bug A — the reader follows the rewritten-but-consistent chain and reads all the new data.
The test builds a **3-cluster** file and overwrites only the **first two** clusters in place, then
proves the **untouched 3rd cluster (tail) survives**. On the buggy driver the tail is orphaned and
the readback short-reads at the premature EOC. Group B builds a 100-byte mid-sector file and appends
50 bytes, proving the leading bytes are not zero-filled. Sizes are derived from `clusterBytes()` at
run time so the test is cluster-geometry-agnostic.

---

## 6. Regression testing — detect the bug BEFORE the fix, prove the fix AFTER  🧪

This is the part the dual driver got wrong the first time and the reason §4.5 exists: a test that
*looks* green but never ran is worthless. Do these steps **in order**. The container can only
compile-check; every behavioral step below needs real P2 hardware, a **formattable scratch card**
(policy: never run against a card you're unwilling to reformat), and the audit→format preflight
(run the standalone SD FAT32 audit first to capture any pre-existing corruption *as evidence*, then
format to a clean FAT32 baseline).

### Step 0 — Prove the test actually RUNS (guard against the silent-skip trap)
Before you trust any pass/fail, confirm the capacity gate isn't skipping the body. Port
`SD_RT_fatchain_tests` **with the §4.5a local-first helpers**, build against the **current
(unfixed) standalone driver**, and run just this suite:

```
./run_test.sh SD_RT_fatchain_tests.spin2 -t 120      # (standalone runner equivalent)
```

Look at the output: you must see the Group A / Group B **tests execute**, not a
"SETUP NOT MET / skipped" line. If it skips on a card with room, your helper still has the chained-
call bug (§4.5a) — fix it before going further. **A green run that skipped the body is a false
green.**

### Step 1 — DETECT: reproduce the bug on the OLD driver (expect FAIL)
With the suite confirmed to run, point it at the **pre-fix** standalone driver (stash your changes,
or keep a pristine checkout). Run it and **expect a real FAILURE**:

- **Group A** ("cross-boundary overwrite follows FAT chain") FAILS — the whole-file readback
  short-reads at the orphaned tail, and/or the 3rd (untouched) cluster no longer holds its original
  pattern.
- **Group B** ("mid-sector append preserves leading bytes") FAILS — the leading bytes read back as 0.

Capture this output. *This failing run is your proof the test can see the bug.* (If the old driver
corrupts the card here, that's expected — reformat before Step 2. Also run the standalone SD audit
after this run to show the on-disk FAT/VBR damage as corroborating evidence for Bug A.)

> **Why the test must overwrite only *part* of the file:** a *full* overwrite does **not** expose
> Bug A — the reader follows the rewritten-but-consistent chain and sees all the new data. The
> suite builds a **3-cluster** file and overwrites only the **first two** clusters in place, then
> checks the **untouched 3rd cluster survives**. Do not "simplify" this into a full overwrite; you'd
> get a test that passes on the *buggy* driver.

### Step 2 — FIX, then CONFIRM: same card, same suite (expect PASS)
Apply the §4 driver fix (+ §4.5 harness fixes), reformat the card, and rerun the identical suite on
the **same physical card**. Expect **all groups PASS** (Group A tail survives, Group B leading bytes
survive). **Record the A/B (old-FAIL → fixed-PASS) pair** — that specific transition, on one card, is
the certification evidence for Bug A + B. A fatchain FAIL on the *fixed* driver means the fix is
incomplete: treat it as a live driver bug, fix in-session, and rerun the A/B. Do not ship on a
fixed-driver failure.

### Step 3 — Full regression, both geometries
Run the **complete sequential standalone suite**, reported **per file** (every suite on its own line
with pass/fail counts, then grand totals — never grouped, never "all N pass"). Then repeat on a
**second card of different cluster geometry** (small-cluster vs large-cluster — Bug A only triggers
at certain cluster sizes, so geometry variation is part of the proof). Both cards must be
**deterministic, green, and order-independent** (sanity-check order independence with a shuffled /
`--from` start). For reference, the dual driver certified at **1,347 pass / 0 fail on each** of an
SD16G (8 KB clusters) and an 8 GB card (4 KB clusters).

### Step 4 — Invariants to confirm
- The **`root_sec` guard never fires** in a passing run. If you ever see the
  `REFUSING metadata-region write` debug line during normal operation, that's a real defect to
  investigate — not noise.
- A **setup-not-met** is investigated, not ignored: it's either a genuine card capacity/geometry
  limit (document it) or a harness gap (fix it — very likely §4.5a again).
- **Any card corruption on the *fixed* driver is a hard blocker** — the entire point of these fixes
  is that it must not recur.

### Step 5 — Legacy path + ship
Answer the legacy `do_write` question from §2 in writing (fixed if it can overwrite across a boundary
in place; documented as immune if append/grow-only). Then ship as a **patch bump** of the standalone
driver — mirroring the dual driver's DFS 1.3.1 → 1.3.2 / SD 1.5.1 → 1.5.2.

---

## 7. Pre-handoff checklist (owner: this repo, at 1.3.2 certification) — COMPLETE ✅

- [x] Dual-driver 1.3.2 certified on hardware (sprint #13): A/B old-FAIL → fixed-PASS green on
      **both** cards (SD16G 8 KB clusters, 8 GB 4 KB clusters), 1,347/0 each. Cut as `da52d94`.
- [x] Re-audited the **shipped** `writeAdvanceCluster`, `root_sec` guard, and mid-sector predicate in
      `dual_sd_fat32_flash_fs.spin2` (2026-07-22). They certified **unchanged** from this draft; §4
      matches what shipped (see §4e for the constants/`quit`-vs-return cosmetic notes).
- [x] Confirmed `DFS_SD_RT_fatchain_tests.spin2` passed on hardware (9/9). Certification surfaced the
      harness defects in `462fd28` — **folded into §4.5 and §5** as mandatory port items.
- [x] Flipped §0 status DRAFT → READY. **This document is ready to hand to the standalone-driver
      agent.**

### What changed between the draft and this READY version (for reviewers)
1. Added **§4.5** — the systemic worker-routed-expression hazard (§4.5a) and the three fatchain-suite
   structural fixes (§4.5b) from `462fd28`. These are **mandatory** and were the difference between a
   real regression and a silent-skip false green.
2. Rewrote **§6** into an explicit, ordered detect-before-fix / confirm-after-fix procedure, leading
   with **Step 0 (prove the test actually runs)** so the port can't repeat the silent-skip trap.
3. Added **§4e** (certified-vs-drafted confirmation + constants/return-value cosmetics) and updated
   **§5** (helper list now includes `evaluateSubBool`; local-first idiom + end-of-session marker).
