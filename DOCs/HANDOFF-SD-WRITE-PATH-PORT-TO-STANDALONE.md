# HANDOFF — Port the write-path corruption fixes to the standalone SD-only driver

**Status: DRAFT / pre-certification.** See [§0 Release gating](#0-release-gating--read-this-first).
**Created:** 2026-07-21
**Reference implementation (dual driver):** commit `765a647` on `main` —
`src/dual_sd_fat32_flash_fs.spin2`.
**Target of this handoff:** the standalone SD-only FAT32 driver,
`REF-FLASH-uSD/uSD-FAT32/src/micro_sd_fat32_fs.spin2` (the read-only reference baseline in this
repo; apply to whichever shipping copy derives from it).

---

## 0. RELEASE GATING — read this first

> ⚠️ **Do not hand this document to the standalone-driver agent yet.**
>
> The dual driver here sits at a **formal release point** (v1.3.0, tagged) with these write-path
> fixes staged as the **pre-release build (patch bump DFS 1.3.1 → 1.3.2)**. That pre-release build
> is **not yet certified** — it still owes the native-hardware A/B + full regression run (sprint
> task #13) on the 16 GB card that drew blood and a second card of different cluster geometry.
>
> **When we certify the 1.3.2 release here, we will study our own source one last time and update
> this document** so the standalone agent ports *exactly* what certified — not what we drafted
> before the hardware run. If the hardware run forces any change to the dual-driver fix (e.g. an
> edge case in `writeAdvanceCluster`, the `root_sec` guard, or the mid-sector predicate), that
> change must be reflected here before handoff.
>
> Until then this is an accurate draft: the bugs, locations, and fix shape below are verified
> against current source and are safe to review, but treat the exact code as provisional.

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

---

## 5. Regression test to port

Reference: `src/regression-tests/DFS_SD_RT_fatchain_tests.spin2` (committed in `765a647`).

Port it to the standalone suite as **`SD_RT_fatchain_tests.spin2`** and wire it into that project's
runner. Adapt to the standalone conventions:

- OBJ is the standalone driver (`micro_sd_fat32_fs`) and its test utils (**`isp_rt_utilities`**, not
  `DFS_RT_utilities`). **Verify equivalent helpers exist** in `isp_rt_utilities.spin2`:
  `startTestGroup`, `startTest`, `evaluateBool`, `evaluateSingleValue`, `evaluateSubValue`,
  `fillBufferWithValue`, `verifyBufferValue`, `assertFreeSpace`, `clustersForBytes`,
  `ShowTestEndCounts`. If any are missing, add them or rewrite the assertions in terms of what
  exists.
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

## 6. Certification (definition of done for the port)

The container can only compile-check. The port is **not done** until, on real P2 hardware with a
**formattable scratch card** (policy: never run against a non-formattable card; preflight is
audit-then-format):

1. **A/B proof on the same card:** the new `SD_RT_fatchain_tests` **FAILS on the pre-fix standalone
   driver** and **PASSES after the fix** (Group A tail-survives, Group B leading-bytes-survive).
2. **Full standalone regression** passes, reported per-file (every suite its own line with
   pass/fail + totals — never grouped).
3. Run on **two cards of different cluster geometry** (small vs large clusters), order-independent.
4. The `root_sec` guard never fires in normal operation (it is a backstop, not a code path).
5. Legacy `do_write` question from §2 answered: fixed if vulnerable, or documented as immune.

Ship as a **patch bump** of the standalone driver, after regression is green — mirroring the dual
driver's DFS 1.3.1 → 1.3.2.

---

## 7. Pre-handoff checklist (owner: this repo, at 1.3.2 certification)

- [ ] Dual-driver 1.3.2 certified on hardware (sprint #13): A/B green on both cards.
- [ ] Re-audit the **shipped** `writeAdvanceCluster`, `root_sec` guard, and mid-sector predicate in
      `dual_sd_fat32_flash_fs.spin2`; update §4 here to match exactly what certified.
- [ ] Confirm the new `DFS_SD_RT_fatchain_tests.spin2` passed on hardware; fold any test refinements
      back into §5.
- [ ] Flip §0 status from DRAFT to READY and hand this document to the standalone-driver agent.
