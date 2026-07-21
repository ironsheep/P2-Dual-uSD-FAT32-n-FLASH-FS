# Forum Thread — refaQtor field feedback on dual driver

**Captured:** 2026-07-21
**Source:** Parallax forums thread (mixed text + images; text captured verbatim below, images pending)
**Poster:** refaQtor (Posts: 224)
**Relevant to:** `src/dual_sd_fat32_flash_fs.spin2` — and per poster, probably the SD-only filesystem driver too.

> Verbatim capture. Do not edit the quoted content; analysis lives in a separate document.

---

## Post #24 — refaQtor — 2026-07-12 19:43 (edited 19:45)

this open file in append mode bit surprised me a bit

*(image)*

but this mod in the driver makes it work for me now.

*(image)*

@"Stephen Moraco" maybe this works as designed

dual_sd_fat32_flash_fs do_write_h chose read-vs-zero-fill by FILE POSITION, so an append starting mid-sector (position == size) ZERO-FILLED the tail sector and wiped the bytes before it. test_earl_fsonly's append check asserted only the size, which is how it survived. Fixed: load the sector when ITS FIRST BYTE is inside the file ((position & !SECTOR_MASK) < size); aligned writes and the block store hot path are untouched.

---

## Post #25 — refaQtor — 2026-07-12 19:53

another tweak I have in place in the dual driver to accommodate my multicog/multitask scenario:

"dual_sd_fat32_flash_fs send_command waited on a bare WAITATN() for its worker cog. But Earl's message fabric wakes a service cog with cogatn, and the datastore consumes its message by polling -- leaving a stale ATN that made WAITATN return early, so every FS call read the PREVIOUS op's result (spurious E_INVALID_HANDLE -91 on writes). Replaced the bare WAITATN with a poll loop on the worker's done-flag (repeat: if pb_cmd==CMD_NONE quit; WAITATN), mirroring the driver's own async getResult path -- immune to spurious/concurrent ATN."

the driver may be performing entirely as expected in this scenario. though worked around it this way.

*(image)*

---

## Post #26 — refaQtor — 2026-07-21 07:20 (edited 07:21)

Me again... this might be the root of the intermittent buggering of my sdcard to the point of needing manual recovery before recognition by plain old computers. It hasn't been an intermittent amount of time since fix was applied, but this reasoning sounded sensible. And I'll be running with this modified driver code. will keep you posted.

  Root cause — do_write_h in dual_sd_fat32_flash_fs.spin2: on a cluster-boundary crossing it called
  allocateCluster() unconditionally, even for an in-place overwrite spanning a boundary. That rewrote the cluster's
  FAT link → truncated the chain → orphaned the file's tail → cascading corruption onto the FAT/VBR. do_read_h
  already followed the chain correctly; the write path's own comment even said "allocate new cluster OR follow
  chain" — but only allocated.

  The fix:
  - writeAdvanceCluster() — follow the existing FAT link on an in-place overwrite; allocate only at true EOC
  (growth). Mirrors do_read_h.
  - A correct-by-construction guard — do_write_h now refuses any write below the data region (root_sec), so a
  corrupted cluster can never again stomp the VBR/FAT; it fails loudly instead.

  Proven on hardware (definitive A/B, same card & test):

  ┌─────────────┬─────────────────────────────────────────────────────────────────────────────────┐
  │   Driver    │                               test_earl_fatchain                                │
  ├─────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ Old (buggy) │ FAIL — MISMATCH in [33280,98304): 64773 bytes → FAT chain broken, tail orphaned │
  ├─────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ Fixed       │ 6/6 PASS                                                                        │
  └─────────────┴─────────────────────────────────────────────────────────────────────────────────┘

  New permanent regression gate test_earl_fatchain.spin2 (wired into build.sh + suite.sh) forces the exact trigger
  — a multi-cluster file overwritten across a boundary — and checks the tail survives. Post-fix: DB(SD)=OK (was
  FAILED), canon 4/4, backup 12/12, coldboot 4/4; the guard never fires in normal operation.

  Why it looked intermittent: it only triggers when a file spans multiple clusters and is overwritten across a
  boundary. With big 32 KB clusters + small store files it can't trigger — the original card likely had smaller
  clusters or grew larger files. The card was recovered via sd_rescue's DO_FORMAT (which also gained a read-only
  FAT32 forensic dump).

these bits added and changed in my used dual driver. this applies probably ALSO to the sdcard only filesystem driver.

```spin2
PUB clusterBytes() : n
'' Bytes per cluster of the mounted SD volume (test / introspection helper -- lets a test
'' place a write exactly across a cluster boundary to exercise the FAT-chain path).
  n := sec_per_clus << SECTOR_BITS

'''

PRI writeAdvanceCluster(handle) : ok | cluster, fat_addr, next_cluster, new_cluster
' Advance a write handle across a cluster boundary CORRECTLY.
' The file's data lives in a FAT chain.  If the current cluster already links to a next
' cluster (an in-place OVERWRITE that spans a boundary), we MUST follow that link -- NOT
' allocate a new cluster.  The old code called allocateCluster() unconditionally here, which
' rewrote the current cluster's FAT entry to a fresh cluster, TRUNCATING the chain and
' orphaning the file's tail -> whole-FAT/VBR corruption (file data written over the FAT and
' volume boot record; the recurring DB(SD)=FAILED, root-caused 2026-07-21).  Mirrors the
' chain-follow do_read_h already does; only allocates when the current cluster is truly EOC.
  cluster := h_cluster[handle]
  if readSector(cluster >> 7 + fat_sec, BUF_FAT) < 0
    DEBUG[CH_FILE]("  [writeAdvanceCluster] FAT read FAILED for cluster ", udec_(cluster))
    return false
  fat_addr := @fat_buf + ((cluster << FAT_ENTRY_SHIFT) & SECTOR_MASK)
  next_cluster := LONG[fat_addr] & $0FFF_FFFF
  if next_cluster >= 2 AND next_cluster < $0FFF_FFF8         ' already linked -> FOLLOW existing chain
    h_cluster[handle] := next_cluster
    h_sector[handle]  := clus2sec(next_cluster)
    return true
  ' current cluster is end-of-chain -> genuine file growth: allocate + link a new cluster
  new_cluster := allocateCluster(cluster)
  if new_cluster < 0
    DEBUG[CH_FILE]("  [writeAdvanceCluster] Failed to allocate cluster")
    return false
  h_cluster[handle] := new_cluster
  h_sector[handle]  := clus2sec(new_cluster)
  return true
```

and diff to see the usage of these fixes in the code

```spin2
          if NOT writeAdvanceCluster(handle)
            bytes_written := 0

    bytes_written := 0
    repeat while count > 0
      ' CORRECT BY CONSTRUCTION: file data lives only in the data region (cluster >= 2 ->
      ' sector >= root_sec).  A write target below root_sec means a corrupted cluster/seek
      ' would put user data onto the VBR/FAT/root -- the exact whole-volume corruption we
      ' root-caused (2026-07-21).  Refuse it loudly rather than destroy the filesystem.
      if h_sector[handle] < root_sec
        DEBUG[CH_FILE]("  [do_write_h] REFUSING metadata-region write: sector ", udec_(h_sector[handle]), " < data start ", udec_(root_sec), " (cluster ", udec_(h_cluster[handle]), ") -- aborting to protect the FS")
        quit
      ' Ensure current sector is in handle's buffer
      if h_buf_sector[handle] <> h_sector[handle]
        ' Flush dirty buffer first if needed
        if h_flags[handle] & HF_DIRTY
          DEBUG[CH_FILE]("  [do_write_h] Flushing dirty sector ", udec_(h_buf_sector[handle]))
          bytemove(@buf, p_hbuf, SECTOR_SIZE)
          writeSector(h_buf_sector[handle], BUF_DATA)
          h_flags[handle] &= !HF_DIRTY

...
```

hope that helps some.
