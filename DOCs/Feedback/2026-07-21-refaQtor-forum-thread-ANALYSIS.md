# Analysis & Handling — refaQtor forum feedback (2026-07-21)

Companion to the verbatim capture: [`2026-07-21-refaQtor-forum-thread.md`](2026-07-21-refaQtor-forum-thread.md).

refaQtor (a field user running the dual driver under a multicog "Earl" message-fabric / datastore
workload) reported three distinct issues, each verified here against `src/dual_sd_fat32_flash_fs.spin2`.

## Do the images matter?

**No.** The three post images are screenshots of the symptom / of the same diffs already quoted in
full in the text, all of which were confirmed directly in our source. Nothing in this analysis
depends on them. They can be archived for completeness later without affecting any decision.

---

## Issue A — FAT-chain truncation on cross-boundary overwrite  🔴 CRITICAL

**Status when reported:** present and unfixed in our tree. **Now: FIXED.**

### What was found
`do_write_h`, on crossing a cluster boundary, called `allocateCluster(h_cluster[handle])`
**unconditionally** — at *both* boundary-advance sites. `allocateCluster(cluster)` **re-links the
passed cluster's FAT entry** to the freshly allocated cluster. So an *in-place overwrite* of an
existing multi-cluster file that crosses a boundary rewrote a live FAT link → truncated the chain
→ orphaned the file's tail → user data landed on the FAT/VBR → whole-volume corruption
(`DB(SD)=FAILED`, card unreadable by a PC until reformatted).

The read path (`do_read_h`) already **followed** the chain correctly at boundaries — the write path
was the sole offender. The dead comment on the buggy line even read *"allocate new cluster **or
follow chain**"* — but it only ever allocated.

**This is almost certainly the true root cause of the long-standing recurring SD/MBR corruption**
that the project's "3-arm MBR reproducer" was chasing. The corruption is a filesystem-logic defect
in the write path, not (or not only) a shared SD/Flash bus artifact.

### Why it looked intermittent
It triggers only when a file spans multiple clusters **and** is overwritten across a boundary. With
large clusters (e.g. 32 KB) + small files it can't fire. It surfaces with smaller clusters and/or
larger files — exactly the geometry variation the fixture-discipline sprint's second card is meant
to cover.

### How refaQtor addressed it
- New `writeAdvanceCluster()` — follow the existing FAT link on overwrite; allocate only at true EOC.
- A correct-by-construction guard: refuse any write below the data region (`root_sec`).
- `clusterBytes()` helper + a permanent regression `test_earl_fatchain` forcing the exact trigger.
- Recovered his card with `sd_rescue` `DO_FORMAT`.

### How we handled it (this session)
Adopted the fix, mirroring **our own** `do_read_h` chain-follow idiom (not his verbatim), so the
FAT-cell read, mask-free EOC compare (`+>= $0FFF_FFF8`), and `readSector(cluster >> 7 + fat_sec …)`
expression are identical to the validated read path — eliminating any Spin2 operator-precedence
risk (precedence re-verified via P2KB: `>>`=3 binds before `+`=8; `!` unary=2 before `&`=4 before
`<`=11).

- Added `PRI writeAdvanceCluster(handle)` (follow-or-allocate).
- Replaced **both** unconditional `allocateCluster()` boundary-advance calls with it.
- Added the `root_sec` data-region write guard inside the `do_write_h` write loop.
- Added `PUB clusterBytes()` introspection helper.
- Removed the now-unused `fat_addr` local from `do_write_h`.

---

## Issue B — mid-sector write zero-fills leading bytes  🟠 (real data loss)

**Status when reported:** present and unfixed. **Now: FIXED.**

### What was found
`do_write_h` chose read-vs-zero-fill by **file position**:
`if h_position[handle] < h_size[handle]`. An append opens at `position == size`; if that is
mid-sector, the condition is false → the tail sector is **zero-filled**, wiping the existing bytes
*before* the append point. The old append test survived because it asserted only the file **size**,
never the leading content.

### How we handled it
Changed the decision to key off the **sector's first byte**, not the write position:
`if (h_position[handle] & !SECTOR_MASK) < h_size[handle]` → loads the sector whenever it still holds
real file bytes, so a mid-sector append or overwrite preserves them. Aligned writes and the
block-store hot path are untouched.

---

## Issue C — `send_command` bare `WAITATN`  🟢 ALREADY FIXED HERE

**Status: no action needed.** Our `send_command` already polls `pb_cmd == CMD_NONE` with `WAITATN()`
inside the loop (the concurrent-ATN-immune pattern refaQtor describes). His was a workaround against
an older copy; our tree already carries the equivalent. Confirmed his concern is covered.

---

## New regression gate

`src/regression-tests/DFS_SD_RT_fatchain_tests.spin2` — geometry-agnostic (sizes writes via
`clusterBytes()` at run time), wired into `tools/run_regression.sh` after `read_write_tests`.

- **Group A (Bug A):** builds a 3-cluster file, overwrites the first **two** clusters in place, then
  proves the whole file is still readable and the **untouched 3rd cluster (tail) survives**. A full
  overwrite would *not* expose the bug (the reader follows the rewritten-but-consistent chain), so
  the test deliberately leaves an untouched tail — on the buggy driver the tail is orphaned and the
  readback short-reads at the premature EOC.
- **Group A2:** fresh multi-cluster write proves the growth/allocate branch still works.
- **Group B (Bug B):** 100-byte mid-sector file + 50-byte append proves the leading `'A'` bytes
  survive (buggy driver zero-fills them); plus an interior mid-sector overwrite check.

The definitive A/B (old FAIL → fixed PASS) is proven on hardware; in-container we only compile-check.

## Verification status
- `dual_sd_fat32_flash_fs.spin2` compiles clean (DEBUG build).
- `DFS_SD_RT_fatchain_tests.spin2` compiles clean.
- Full hardware A/B + regression deferred to the sprint's native-hardware certification gate (task
  #13), on the 16 GB card that originally drew blood **and** a second card of different cluster
  geometry.

## Release
Behavior-changing driver fix → the already-planned **PATCH** bump at build-wrapup
(DFS 1.3.1 → 1.3.2, SD 1.5.1 → 1.5.2), shipped **after** regression passes on hardware.

## Note for the SD-only standalone driver
refaQtor notes (and it is true) that Bugs A and B apply to the **SD-only filesystem driver** as
well. The reference SD driver lives under `REF-FLASH-uSD/uSD-FAT32/` (read-only baseline). The same
two fixes should be ported to whichever shipping SD-only driver derives from it — tracked as a
follow-up, not done in this session.
