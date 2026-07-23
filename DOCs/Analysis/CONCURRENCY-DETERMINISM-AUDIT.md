# Concurrency Determinism — post-mortem + driver/test-suite audit

**Created:** 2026-07-22
**Trigger:** commit `462fd28` ("repair fatchain gate + systemic assertFreeSpace expression bug") and
the observation that its symptom — a regression gate that *silently skipped* — was recompile-sensitive
and, during an earlier attempt, read as "unsolvable" because instrumentation made the cause vanish.
**Related:** `DOCs/Reference/DEBUGGING-METHODOLOGY.md` → "The Recompile-Sensitive Heisenbug".
**Root-cause task:** todo `#14`.

---

## 1. The phenomenon and why it looked unsolvable

A test-harness helper computed a capacity gate as `dfs.freeSpace(...) / dfs.sectorsPerCluster()`.
On some builds the value came back wrong (0 / -1), the gate reported "SETUP NOT MET", and the gated
regression tests — including the Bug-A cross-boundary-overwrite regression — were **silently skipped**.
A green run that tested nothing.

The behavior was **recompile-sensitive**: green on one build, skip on the next. An earlier agent
tried to instrument it, the act of instrumenting shifted layout/timing, the symptom moved, and the
agent concluded it was not observable and therefore not solvable.

**That conclusion is the trap, not a fact.** A fixed `.bin` on a P2 is fully deterministic and the SD
card is a deterministic state machine — nothing here is random. "Recompile-sensitive" means the
changed input was the *binary* (addresses, instruction counts, stack-temp placement), and
instrumentation is itself a recompile. The instrumentation didn't fail to reveal the bug; it *moved*
it.

## 2. The corrected model — timing vs. result

Deterministic inter-cog communication is not only possible, it is the norm. The distinction the
first analysis collapsed:

- **Latency** (cycles between "worker done" and "caller notices") varies across builds. It always
  will, and it never needs to be fixed.
- A **correct synchronization protocol makes the logical result independent of that latency.** That
  is what synchronization *is*.

Primitives that deliver it, all present in this driver:

| Primitive | Role | Deterministic because |
|---|---|---|
| `LOCKTRY`/`LOCKREL` (`api_lock`) | mutual exclusion on the shared mailbox | hardware-atomic |
| hub-RAM completion flag (`pb_cmd → CMD_NONE`) | the actual handoff | worker writes DATA then FLAG; reader reads FLAG then DATA |
| `COGATN` / `WAITATN` | **doorbell only** (sleep instead of busy-poll) | *not* trusted for correctness — see below |

**ATN is a doorbell, not a mailbox.** Per P2 silicon (confirmed via P2KB): `COGATN` is edge-triggered,
has **no queue** (two strobes before a check merge into one), auto-clears on `WAITATN`/`POLLATN`, and
has no delivery guarantee if the target wasn't waiting. Therefore a bare `WAITATN()` that is *trusted*
as the synchronization is a defect: a stale/coalesced ATN returns early and the caller reads the
PREVIOUS op's mailbox result. Correctness must come from the lock + polled flag. This driver already
learned this — `send_command` (line ~4208) polls `pb_cmd == CMD_NONE` and uses `WAITATN()` only to
sleep between checks.

## 3. Re-analysis of `462fd28` — the committed explanation does not hold

The commit says the bug was "chaining two routed driver calls in one expression." Reading the code:

- `freeSpace(DEV_SD)` **is** worker-routed — it calls `send_command`, which uses the *correct*
  lock + poll-flag handshake and snapshots the result into the per-cog `saved_data0[]` slot. It is
  properly synchronized.
- `sectorsPerCluster()` is a **bare hub read**: `count := sec_per_clus`. No `send_command`, no lock,
  no ATN, and the value is constant after mount.

So within a single caller cog, `freeSpace()` fully completes before the division even evaluates
`sectorsPerCluster()`, and the second operand is a stable constant. **The "second routed call
corrupted the first" narrative cannot be the literal mechanism** — the second call isn't routed, and
the first is correctly synchronized.

That leaves two live hypotheses, and they demand different fixes:

- **H1 — Spin2 expression code-gen.** How the compiler stacks a method-call *return value* inside a
  compound expression (`routedCall() / bareCall()`) is fragile; splitting each call into its own
  local genuinely sidesteps that code path. If true, the local-first fix is a **real cure** and the
  same rewrite is needed everywhere the pattern appears.
- **H2 — mailbox race hit elsewhere / mis-attributed.** The real corruption came through a different
  helper or ordering (e.g. a genuine bare-WAITATN or unlocked shared-slot read), and the
  freeSpace/sectorsPerCluster expression was a plausible-but-unproven attribution; "local-first" then
  merely masked it by changing timing.

**Either way, the local-first idiom is safe to keep** (it is the correct Spin2 idiom regardless). But
the bug is **not root-caused**, and the fix has the shape of a Heisenbug mask. See task `#14` for the
bytecode-level root cause (freeze one build → prove same-binary determinism → diff pass-build vs
skip-build listing → stack-temp placement ⇒ H1, instruction-count shift around the handshake ⇒ H2).

**Sharpening from the audit (§4.3):** the original case is not even "two routed calls" — it is *one*
routed call (`freeSpace`) combined with a *non-routed direct field read* (`sectorsPerCluster`, which
is literally `count := sec_per_clus`). So the only value that could plausibly be mishandled is the
*routed call's return value being held across the second call* — which points almost entirely at H1
(how the compiler stacks a method-call return inside a compound expression), and further undermines
any race-based story. If H1 is confirmed, the general rule to enforce is narrower than "never chain
driver calls": it is **"don't hold a worker-routed call's return value live across another call in
the same expression — sink it to a local first."**

## 4. Audit — where else could this bite us?

**Verdict: CLEAN across the board.** Three independent sweeps (driver handshake/ATN/mailbox; driver
chained-expressions; all 50 test-suite/helper files) found **no P1, no P2, and no new P3** sites. The
handshake discipline is uniformly correct and the `462fd28` fix captured every live instance of the
chained-expression shape. The only residue is one optional *stylistic* cleanup (non-routed getters in
`mount_tests` debug lines, §4.3) with zero functional risk. **Nothing further needs remediation; what
remains is proving the root cause (task `#14`), not fixing more sites.**

Because H1/H2 were unresolved going in, both failure modes were audited across the driver and the test
suite:

- **Pattern P1 — bare `WAITATN()` trusting the doorbell:** any inter-cog wait whose completion is an
  ATN edge rather than a re-verified hub flag.
- **Pattern P2 — unlocked shared-slot read:** reading a single-copy mailbox slot (`pb_data0`,
  `pb_status`, …) outside the lock instead of via the per-cog `saved_data0[]` snapshot.
- **Pattern P3 — chained side-effecting calls in one expression:** the `462fd28` shape — two+
  worker-routed / side-effecting calls (or one routed + one other) combined in a single Spin2
  expression, in the driver or the test helpers.

### 4.1 Driver handshake / ATN / mailbox audit — CLEAN ✅
Full census of `dual_sd_fat32_flash_fs.spin2`: **no P1 and no P2 findings.** Every synchronization
site derives correctness from the lock + a polled hub flag; ATN is used only to sleep/wake and to
drain stale doorbells.

- **WAITATN — 1 use, correct.** L4211, inside `repeat: if pb_cmd == CMD_NONE quit; WAITATN()`
  (`send_command`). Completion is the flag re-check at L4209, not the ATN edge → a coalesced/stale
  ATN only causes a harmless spurious wake.
- **POLLATN — 2 uses, correct.** L1540 (`getResult`) and L1555 (`cancelAsync`) — both DRAIN the
  worker's completion ATN before `LOCKREL`, so the next `send_command`'s `WAITATN()` can't consume a
  stale doorbell. Known-good drain pattern.
- **COGATN — 4 uses, correct.** L3724, L3748, L3759, L4107 — all worker-side, every one emitted
  *after* the data slots are written and *after* `pb_cmd := CMD_NONE` (data-first-then-flag).
- **Shared single-slot reads outside `send_command`:** only L1533/L1537 in `getResult()`, and those
  occur while the async `api_lock` is still held (acquired at submit, L1475/L1501) and read
  flag-first-then-data. Everything else reads the per-cog `saved_data0[]` snapshot (taken under lock
  at L4222-4224). No unprotected shared-slot read exists.
- **`pb_cmd`/mailbox writes without the lock:** none. All caller writes (L4200, L1481, L1507) are
  under `api_lock`.

Two low-severity design-assumption notes (not defects, worth a follow-up hardening pass):
1. `isComplete()`/`getResult()` (L1518/L1531) rely on the invariant that the *same* cog that
   submitted the async op is the one polling it. Safe today; a one-line `async_caller == COGID()`
   assertion would make it robust to future misuse.
2. `getResult()` returns from the shared slots directly and does **not** persist to
   `saved_data*[COGID()]` (unlike `send_command`); callers must consume its return value directly.
   An easy trap for a future call site.

**Implication for §3:** because the mailbox/ATN machinery is provably correct, **H2 (a mailbox race)
is much less likely and H1 (Spin2 expression code-gen) is the leading hypothesis** for `462fd28`.
The bytecode diff in task `#14` should confirm.

### 4.2 Driver chained-expression audit (P3) — CLEAN ✅
No P3 findings in `dual_sd_fat32_flash_fs.spin2`. The `freeSpace()/sectorsPerCluster()` shape does not
recur anywhere: every worker-routed call (all ~90 `send_command` sites across the public API) and
every shared-mailbox read sits in its own statement, result stored to a local before use. Searched:
call-result-joined-to-another-call operators, nested routed calls, two-routed-names-per-line over the
read/size/free family, and every `saved_data*` compound use. The only nested calls are pure
worker-side helpers (`clus2sec(byte2clus(...))`, `cmd_crc7`, `strsize`, …), not routed. `stats()`
(L2221) already uses the split-into-locals shape. Two borderline-but-safe lines noted (L2453
`writeHandle(h, p, strsize(p)+1)` — one routed call + a pure arg; L1574 ternary re-reading the same
`saved_data0` slot, no routed call). The driver consistently follows the "one routed call per
statement, store to local, then combine" discipline the `462fd28` fix established.

**Consequence:** if H1 (Spin2 code-gen) is confirmed, the driver body needs no further P3 edits — the
exposure is confined to the test helpers (§4.3).

### 4.3 Test-suite / helper chained-expression audit (P3) — CLEAN ✅
All 50 files swept (39 in `regression-tests/`, 11 in `UTILS/`). **No remaining true instances** — the
`462fd28` fix to the three helpers (`assertFreeSpace`, `clustersForBytes`, `assertContiguousFree`)
captured every real case. Key to the analysis: the corruption vector requires a **worker-routed**
call (one that calls `send_command` and reads back `saved_data*[COGID()]`). The agent confirmed the
routed vs non-routed split, which sharpens §3:

- **Routed (hazardous to chain):** `freeSpace`, `largestFreeExtent`, `stats`, `fileSizeHandle`,
  `mount`, `readSectorRaw`, `writeSectorRaw`, `testCMD13`, …(~60).
- **NOT routed (direct DAT field reads, immune):** `sectorsPerCluster` (`count := sec_per_clus`),
  `mounted`, `attributes`, and all CRC/CMD13 diagnostic getters.

Candidates reviewed and cleared: the `assertFreeSpace(dfs.DEV_SD, clustersForBytes(dfs.DEV_SD, X)+N)`
nests two *utility* helpers (each already computes its driver query into a local) — the safe idiom,
not two raw routed queries; `evaluateSingleValue(dfs.fileSizeHandle(h), …)` etc. are a single routed
call + constants; the `mount_tests` `debug(...)` lines pair 2–3 driver *getters* but all are
non-routed field reads (no value to corrupt). The `dfs.freeSpace()/dfs.sectorsPerCluster()` match at
`DFS_RT_utilities.spin2:912` is inside the doc comment documenting the original bug, not live code.

**One optional stylistic item (no functional risk):** the `DFS_SD_RT_mount_tests.spin2` diagnostic
`debug` lines (≈L129-131, 179-180) put 2–3 driver calls in one expression. All are non-routed getters
so there is nothing to corrupt; worth a cleanup only if we want to enforce "one driver call per
expression" *mechanically* as a lint rule rather than as a routed-only rule.

### 4.4 Standalone SD driver
The standalone SD-only driver (`REF-FLASH-uSD/uSD-FAT32/src/micro_sd_fat32_fs.spin2`) is **also
worker-cog based**, so P1–P3 apply there too. This is folded into the port handoff
(`DOCs/HANDOFF-SD-WRITE-PATH-PORT-TO-STANDALONE.md`, §4.5).

## 5. Recommendations

1. **Root-cause `462fd28` at the bytecode level** (task `#14`) before trusting the local-first fix as
   a cure. Decide H1 vs H2 from a build diff, not from "it went away."
2. **Fix every P1/P2/P3 site** the audit finds (§4), even the ones currently benign — they are
   latent recompile-sensitive faults.
3. **Adopt the doorbell-vs-mailbox rule** as a review checklist item for any new worker command or
   test helper (now in the debugging-methodology doc).
4. **Never certify green without proving the gated tests actually executed** — a broken capacity gate
   silently skips (the original sin here). The port handoff §6 Step 0 encodes this.
