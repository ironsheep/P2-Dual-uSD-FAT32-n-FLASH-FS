# Regression Run-Through — Sprint Plan

**Status:** planned (research complete, all scope questions resolved with Stephen 2026-07-23)
**Plan authored:** 2026-07-23
**Origin:** the `462fd28` silent-skip finding + the format-in-the-middle diagnosis
(`DOCs/Analysis/CONCURRENCY-DETERMINISM-AUDIT.md`; this session's audit)
**Predecessor:** `DOCs/Plans/REGRESSION-FIXTURE-DISCIPLINE-SPRINT-PLAN.md` (established per-suite
setup/teardown/precondition-assert helpers; this sprint closes the hole that work left open)

---

## Purpose

The fixture-discipline sprint made each suite *audit* its preconditions — but chose to **skip** a
suite's body when a precondition is unmet, reporting "setup-not-met" instead of a failure, so a
full/fragmented card could not masquerade as a driver bug. That skip has **no floor and no
visibility to the runner**, and it opened a hole:

- A skipped test reports **neither pass nor fail**. `run_regression.sh` parses only `Pass:` / `Fail:`
  (lines 397-398), so a skip silently shrinks the pass count and the suite stays **green**.
- The existing `BAD TEST COUNTS` guard (`DFS_RT_utilities.spin2:154`) can't see it: the capacity
  gate wraps the `startTest` calls too, so a skipped test never increments `numberTests` either —
  `numberTests == pass+fail`, no discrepancy raised.
- `462fd28` weaponized exactly this: a *broken* gate reported setup-not-met on a card with plenty of
  room and silently deleted the Bug-A corruption regression from the run. A green run that tested
  nothing.

Compounding it, the suite has **no enforced baseline** and a **cross-suite state dependency**: the
SD card is formatted mid-run only as a side effect of the defrag suite (`fmt.format()` at
`DFS_SD_RT_defrag_tests.spin2:149`, Layer 5 in the runner), while Flash suites each self-format their
device. So SD-card cleanliness depends on run order and history — run a suite standalone, resume with
`--from` past defrag, or run weeks apart, and capacity gates fire differently and results aren't
reproducible. (This is the "format in the middle it doesn't remember weeks apart" symptom.)

This sprint makes the regression **run straight through on a known baseline with zero silent skips**:
skips become loud and fail the run (except explicitly-annotated hardware limits), the runner
establishes an identical baseline every run, and SD suites stop depending on defrag's mid-run format.

## Scope (confirmed with Stephen, 2026-07-23)

- **Skip policy — hard fail.** On a properly-baselined card, an unmet capacity/contiguity
  precondition is a *real* defect (a setup bug or a driver leak like Bug A orphaning clusters), not a
  tolerable skip. Only **documented hardware limits** (e.g. the FSCK RAM ceiling on a 64GB card) stay
  skippable, and those are explicitly annotated as a distinct category. **Audit invariant: zero
  `SETUP NOT MET` skips on a baselined run.**
- **Baseline — runner-enforced suite #0.** `run_regression.sh` runs audit → format as an enforced
  first step, behind an explicit scratch-card confirmation flag so it can never wipe a non-scratch
  card. Every run starts from an identical, known FAT32 baseline.
- **Coverage floor — skip-message audit, not declared counts.** No up-front per-suite count. Any skip
  emits a loud message; the audit is that a baselined run emits **no** `SETUP NOT MET` messages. The
  existing `BAD TEST COUNTS` guard + `END_SESSION`/timeout cover non-skip forms of missing coverage.
- **Dual driver only.** This sprint fixes the dual driver's suite and runner. The standalone SD-only
  driver inherits the same pattern via its handoff (`DOCs/HANDOFF-SD-WRITE-PATH-PORT-TO-STANDALONE.md`);
  a pointer is added there (§6), but no standalone code is changed here.

## Hardware split (execution division of labor)

The devcontainer **cannot drive the P2 over serial** — same division as the predecessor sprint:

- **In the container (development):** write all runner/helper/suite/doc changes and **compile-check**
  (`pnut-ts -d …` plus a `flexspin.mac -2 -q …` cross-check on touched suites, and a full
  `./run_regression.sh --compile-only` sweep). Note: the runner-shell changes (§3, §4) are testable
  in-container with a **mock** `run_test.sh` / canned log fixtures — see those sections.
- **Native session (P2 Edge + formattable scratch card):** the end-to-end determinism certification
  (§7) is the definition-of-done gate and runs natively.

## Regression-run precondition (policy — unchanged, still in force)

The formattable-card policy and audit→format preflight from the predecessor sprint remain the
standing policy (`REGRESSION-FIXTURE-DISCIPLINE-SPRINT-PLAN.md` "Regression-run precondition"; memory
`feedback_regression_formattable_card`). **This sprint promotes that preflight from a manual step into
a runner-enforced suite #0** (§3) — it does not change the policy, only where it is enforced.

## Definition of done

**The governing invariant: a test fails *if and only if* the driver is genuinely wrong.** No failure
is ever caused by card state, free space, missing fixtures, cwd, capacity, or execution order — those
are engineered out (§5) so a single straight-through pass is trustworthy.

1. On a freshly-baselined scratch card, a full `./run_regression.sh` runs **every** suite's body —
   **zero `SETUP NOT MET` skips**, deterministic pass counts, exit 0.
2. **Order- and state-independence proven:** bit-identical per-suite pass counts across built order,
   shuffled order, standalone, and dirty/hostile-start runs (§7 adversarial matrix).
3. A deliberately-induced skip (e.g. an impossible free-space assertion) **fails the run** with a
   clear runner message — proving the silent-skip hole is closed.
4. Both cluster geometries (small vs large) green and order/state-independent.
5. Compile-clean throughout; no regression vs the predecessor sprint's 33/33 baseline.

## Open Questions

None. All four scope decisions resolved with Stephen 2026-07-23 (skip=hard-fail; baseline=runner
suite #0; coverage=skip-message audit; scope=dual driver only).

## Sprint-start record (2026-07-23)

- **Outgoing build number:** provisional target **DFS 1.3.3 / SD 1.5.3 (patch)**, finalized at
  build-wrapup — bump only if driver behavior actually changed; if the sprint ships pure
  test/runner/doc changes the driver stays at 1.3.2 (mirrors the fixture-discipline "no bump at
  entry; patch at wrap-up iff behavior changed").
- **Working-tree audit:** clean for the sprint blast radius (`tools/`, `src/regression-tests/`,
  `src/UTILS/` — no uncommitted or untracked files). Session doc/plan work committed
  (`e0c9163`, `746688a`, `c6856d2`); skill onboarding done (`.claude/` is gitignored — conventions +
  overlays are local-only). Only untracked item is the intentional `DOCs/CARDs-NO-COMMIT/`.
- **Tracking-readiness (entry):** READY. Archived 11 completed fixture-discipline tasks; context
  (1 key) and memory (~13 lines) well under thresholds.
- **Baseline-health (entry):** in-container compile sweep **33 pass / 0 fail** (matches the
  predecessor 33/33). Per the baseline-health overlay, the hardware pass/fail baseline is host-native
  and is established/re-checked in the native session (§7); a container run cannot assert it.
- **Leftover-task decisions:** `#13` (Fixture-Discipline §10 native-HW cert) **folded into §7** —
  the run-through §7 cert is a strict superset and becomes the single native pass that closes both
  sprints. `#14` (root-cause 462fd28 Heisenbug) **kept separate and deferred** — it does not affect
  this plan's implementation (the zero-skip gate + local-first idiom stand on their own); revisit
  after, likely as a container-side bytecode diff.

---

## §1 — Skip-signal contract: make skips loud and two-category

**Why.** The audit invariant ("zero skips") and the runner enforcement (§4) both depend on a skip
being an unambiguous, machine-greppable, *categorized* signal. Today there is one undifferentiated
"setup-not-met" outcome, and a legitimate hardware-limit skip is indistinguishable from a defect
skip.

**Current code.** `DFS_RT_utilities.spin2`:
- `assertPrecondition(bHeld, pMessage)` (line 839) emits `# SETUP NOT MET: <msg> (skipped; NOT a
  driver failure)` (line 849), bumps `setupNotMetCount[]` (line 72), returns FALSE.
- `ShowTestEndCounts()` (line 144) prints `Setup-not-met (skipped, NOT failures): N` (line 153) and
  the `BAD TEST COUNTS` line (line 154-156). `ShowMultiCogTestEndCounts()` (line 159) mirrors it.
- Callers: `assertFreeSpace` (~908), `assertContiguousFree` (~927), `ensureCleanBaseline` (~880).

**Target behavior.**
- Split the outcome into **two categories** with distinct, greppable markers:
  - `# SETUP NOT MET:` — a precondition that a baselined card must satisfy. Must be zero on a
    baselined run. Counted in `setupNotMetCount[]` (unchanged name).
  - `# HARDWARE LIMIT:` — a precondition representing a documented device limit; allowed. Counted in
    a new `hwLimitSkipCount[]`, reported on its own summary line, never failed.
- Add `assertHardwareLimit(bHeld, pMessage)` alongside `assertPrecondition`, emitting the
  `HARDWARE LIMIT` marker. `assertPrecondition` keeps the `SETUP NOT MET` marker.
- `ShowTestEndCounts()` / `ShowMultiCogTestEndCounts()` print both counts on separate, distinctly
  labeled lines so §4's runner parse is unambiguous.
- Every emitted skip line already includes the precondition message; keep that (it is the operator's
  breadcrumb to *which* gate skipped).

**Integration points.** All existing `assertPrecondition` call sites keep working unchanged (they
remain `SETUP NOT MET`). §2 decides which few migrate to `assertHardwareLimit`.

**Verification.**
- *Normal:* a suite with all preconditions met emits neither marker; both counts zero.
- *Edge:* a suite that hits a `HARDWARE LIMIT` gate prints the HW-limit line, `SETUP NOT MET` stays
  zero, suite still green.
- *Error:* an unmet `assertPrecondition` prints exactly one `# SETUP NOT MET:` line with its message
  and increments `setupNotMetCount[]`. Compile-check both new/changed helpers.

## §2 — Reclassify every precondition: baseline-guaranteed (hard-fail) vs hardware-limit (skippable)

**Why.** The hard-fail policy is only correct if each precondition is classified. A free-space or
contiguity gate on a baselined card must be a failure; a genuine device-capacity ceiling must remain
a tolerated skip. Misclassify the first as skippable and the `462fd28` hole reopens; misclassify the
second as hard-fail and a large card throws false failures.

**Current code.** Producer/consumer inventory of the assert helpers (the "data model" this section
rewires):
- `assertFreeSpace` (~908) and `assertContiguousFree` (~927) — called by ~9 SD suites (per `462fd28`
  commit note). Today all route to `assertPrecondition` → `SETUP NOT MET`.
- `ensureCleanBaseline` (~880) — a teardown/cleanliness assert.
- Walk **every** call site of these three helpers plus direct `assertPrecondition` calls across
  `src/regression-tests/*.spin2`, and record for each: what precondition, and is it satisfiable on a
  freshly-baselined scratch card of the smallest supported geometry?

**Target behavior.**
- **Baseline-guaranteed** (free space for a bounded fixture, contiguity after a fresh format, clean
  baseline) → stay `assertPrecondition` (`SETUP NOT MET`) so §4 **fails** the run if they ever fire.
  On a baselined card they must never fire; if one does, that is the defect the sprint exists to
  surface (setup bug or driver leak).
- **Documented hardware limit** (e.g. FSCK cluster-chain validation ceiling ~64GB per CLAUDE.md "Key
  Limitations"; any test whose fixture genuinely cannot fit a small card) → migrate to
  `assertHardwareLimit` (`HARDWARE LIMIT`) with a one-line rationale comment citing the limit.
- Produce a short **classification table** (in the §6 contract doc) listing every gate and its
  category — the authoritative record of what may skip.

**Integration points.** Depends on §1's two-category helpers. Feeds §4 (runner fails on the
`SETUP NOT MET` category only) and §6 (the classification table is contract content).

**Verification.**
- *Normal:* on the standard scratch card every baseline-guaranteed gate passes; no `SETUP NOT MET`.
- *Edge:* a suite carrying a real hardware-limit gate emits `HARDWARE LIMIT` and stays green.
- *Error:* deliberately shrink a fixture's assertion to be impossible → it emits `SETUP NOT MET` and
  (via §4) fails the run — confirming baseline-guaranteed gates are wired to fail, not skip.

## §3 — Runner-enforced baseline (audit → format as suite #0)

**Why.** Removes cross-run state carryover. Today the runner assumes the card is already good; the
audit→format is a manual preflight (cert handoff only), and the only in-run SD format is defrag's
side effect (§5). An enforced baseline makes every run start identically.

**Current code.** `tools/run_regression.sh`:
- No baseline step; first suite is `DFS_SD_RT_mount_tests` (line 90).
- `--include-format` appends the destructive format suite at the **end** (lines 161-163).
- Suite list + `--from` resume (line 170); per-suite run via `./run_test.sh` (line 371).
- `DFS_SD_FAT32_audit` (`src/UTILS/`) and `DFS_SD_format_card` (`src/UTILS/`) are the existing
  audit/format utilities the preflight already uses.

**Target behavior.**
- New **`--card-is-scratch`** flag (explicit; required to enable the destructive baseline). Without
  it, the runner **refuses to run on hardware** and prints how to confirm the card is scratch
  (mirrors the formattable-card policy; makes the standing "confirm scratch card" gate mechanical).
- With it, **suite #0** runs before all others: (1) `DFS_SD_FAT32_audit` (non-destructive) — capture
  its output to the log as pre-wipe evidence; if it reports corruption, surface it prominently but
  continue to format (the whole point is to reset). (2) `DFS_SD_format_card` — establish the clean
  FAT32 baseline. A failure of either aborts the run with a clear message.
- `--from` skips suite #0 by default (resuming assumes an already-baselined card) — but prints a
  visible reminder that resume relies on prior baseline; `--compile-only` never touches the card.
- Report suite #0 on its own line like any other suite.

**Integration points.** Purely runner-side + the two existing utilities. §5's decoupling assumes this
baseline exists (suites can rely on a clean card at run start).

**Verification** (container-testable with a mock `run_test.sh` + canned audit/format logs):
- *Normal:* `--card-is-scratch` → suite #0 audits then formats, then suites run.
- *Edge:* `--from <suite>` → suite #0 skipped, reminder printed; `--compile-only` → card untouched.
- *Error:* no `--card-is-scratch` on a hardware run → refuse with guidance; audit-or-format failure →
  abort with the failing utility's output.

## §4 — Runner skip-visibility + fail-on-skip

**Why.** Even the signals that exist today (`Setup-not-met`, `BAD TEST COUNTS`) are dropped because
the runner reads only `Pass:`/`Fail:`. This is the section that actually closes the hole.

**Current code.** `tools/run_regression.sh`:
- Parses `Pass:`/`Fail:` from the summary line (lines 391-399); marks a suite failed only on
  `RUN_EXIT != 0` or `SUITE_FAIL > 0` (lines 403-408).
- Per-suite log already contains the `Setup-not-met (skipped…)` and `BAD TEST COUNTS` lines from §1.

**Target behavior.**
- After parsing pass/fail, also grep the cleaned log for the §1 markers:
  - any `# SETUP NOT MET:` line **or** a nonzero `Setup-not-met (skipped…)` summary → mark the suite
    **failed** (this is the policy from decision #1); include the skipped precondition message(s) in
    the runner's failure output.
  - any `BAD TEST COUNTS` line → mark failed (missing/extra coverage).
  - `# HARDWARE LIMIT:` / the HW-limit summary line → surface as an informational note (count shown),
    **not** a failure.
- Extend the summary table with a **Skipped** column (SETUP-NOT-MET count) so a run's coverage is
  visible at a glance; a nonzero value is rendered in the failure color.
- Keep the existing stop-on-first-failure behavior; a skip-induced failure stops the run like any
  other.

**Integration points.** Consumes §1's markers; enforces §2's classification (fails only the
`SETUP NOT MET` category). No driver changes.

**Verification** (container-testable with canned logs):
- *Normal:* a log with zero skips and matched counts → suite green.
- *Edge:* a log with a `HARDWARE LIMIT` line only → green, note shown, Skipped column zero.
- *Error:* a log with a `SETUP NOT MET` line, or a nonzero setup-not-met summary, or `BAD TEST
  COUNTS` → suite failed, run stopped, message names the gate.

## §5 — Per-test starting-condition discipline: decouple everything, enforce single-pass integrity

**Principle (the whole point of this section).** On a baselined scratch card the **driver is the only
variable**. A test must fail **if and only if** the driver is genuinely wrong. Every non-driver input
— card state, free space, fixture existence, cwd, execution order — is either *established by the test
itself* or *asserted* as a hard, categorized precondition that can only be unmet on a real defect (or
a whitelisted hardware limit). Decouple everything that can be decoupled; a suite must run correctly
in **built order, shuffled order, or standalone**, every time, in a single pass.

**Why.** A full-suite fixture-discipline audit (this session, `DOCs/Analysis/` + the four sub-audits)
found ~19 CLEAN / ~16 MINOR / 3 VIOLATION across the ~38 suites. The predecessor sprint built the
helpers and retrofitted some suites; the rest still carry ambient assumptions and intra-suite
coupling that would false-fail a shuffled/standalone/dirty run.

**Current code — the worklist.**

*Three VIOLATIONs (fix first):*
- `DFS_SD_RT_file_ops_tests.spin2:146` and `DFS_SD_RT_subdir_ops_tests.spin2:106` — call
  `dfs.debugClearRootDir()` unconditionally at start, wiping the **entire** card root (not their owned
  names) and **masking** a dirty/corrupt baseline instead of asserting it. Anti-pattern; contradicts
  the scoped `ensureCleanBaseline` contract every disciplined suite uses.
- `DFS_SD_RT_testcard_validation.spin2` — establishes and asserts **nothing**; all ~13 fixtures are
  externally prepped and each test only checks `handle >= 0`, so a missing fixture scores as a
  *driver* failure. Also fundamentally incompatible with §3's auto-format baseline (suite #0 would
  wipe its prepped fixtures). **Design sub-decision** (recommendation): convert it to
  *self-establish* — it knows the expected content/checksums (e.g. `130560`), so it can author its own
  fixture tree in setup, making it baseline-compatible. Any fixture that genuinely cannot be
  self-authored moves to an explicitly-excluded, opt-in "prepared-card" suite outside the default run.
- `DFS_FL_RT_circular_compat_tests.spin2` → `DFS_FL_RT_circular_tests.spin2` — the one genuine
  *cross-suite* dependency: `circular_compat` comments out its own `format` (L86-88) and reads files
  `circular` deliberately leaves behind (no teardown, L248-250). Fix: `circular_compat` self-produces
  its own records (uncomment format + add the produce step), **or** fold the compat verification into
  `circular` as one self-contained suite. Either removes the dependency.

*Five systemic MINOR patterns (retrofit across the affected suites):*
- **A — capacity gate that doesn't gate / is absent.** `speed:111` and `read_write:171` call
  `assertFreeSpace(...)` and **ignore the return**; most file-writing suites have no gate at all. Make
  every file-writing group gate with `if assertFreeSpace(...)`; per §2 an unmet gate on a baselined
  card is a hard failure (a real leak — the Bug-A signature), not a skip.
- **B — `cwd == root` silently assumed** by nearly every suite after mount. Assert it at entry (or set
  it); any group that changes cwd restores it.
- **C — intra-suite producer/consumer coupling.** Later groups read fixtures built by earlier groups
  (`parity` Grp2→Grp3, `directory` path-nav/listing, `volume`, `async`, `seek`, `read_write`,
  `crc_diag`, `multihandle`). Retrofit **per-group self-establishment**: each group delete-then-creates
  the fixtures it reads, so one real failure is isolated, never cascaded.
- **D — scoped+audited `ensureCleanBaseline` used by a minority.** Most blind-`deleteFile` with no
  post-delete audit → a stuck leftover false-fails as a driver error. Use `ensureCleanBaseline(@owned)`
  at **start and end** of every file-writing suite.
- **E — silent create-failure.** `createTestFiles()` failures only `debug(...)`. Route through the §1
  precondition path so a fixture that won't build fails loud (and, on a baselined card, means a real
  defect).

*Exemplars to copy (already correct):* `dirhandle` (dedicated `createTestStructure()` + exact
self-built count asserts), `defrag` (format baseline + `assertContiguousFree` gating + fixture
audits), `volume` (saves/restores the ambient volume label), `mbr_sentinel` (captures baseline from
live state + asserts health), `recovery` (explicit setup block + `ensureCleanBaseline` both ends).
*Note:* `defrag` is **CLEAN** — its `fmt.format()` is scoped to its own contiguity need and **no other
suite relies on it** (the earlier "decouple SD from defrag" concern was disproven by the audit).

**Target behavior.** Every suite conforms to the standard, at **test-group granularity**:
1. Establish its own world from the §3 baseline — create every fixture it reads (delete-then-create,
   scoped to owned names), set/assert its own cwd, per-cog/per-device where applicable.
2. No `debugClearRootDir`; no reliance on a sibling suite or an earlier group's leftovers.
3. Assert every precondition it needs but cannot create (capacity, contiguity, health) via §1's
   markers — hard-fail category, so wrong state fails loud, never silently.
4. `ensureCleanBaseline(@owned)` at start and end.

**Integration points.** Depends on §1 (skip markers), §2 (hard-fail classification), §3 (baseline).
Uses the predecessor sprint's setup/teardown helpers (`DFS_RT_utilities.spin2` ~L831); extend them
only for a genuinely-shared need (plan shared up front, never "refactor to shared later"). The
testcard_validation sub-decision is resolved in writing before that suite is touched.

**Enforcement (§5c — how the property is *assured*, not just hoped).**
- **Runtime gate, every run:** zero `SETUP NOT MET`, zero fixture-establishment errors, matched counts
  (delivered by §1/§4). A discipline regression that produces any skip/setup-error fails the run
  immediately.
- **Adversarial proof, at certification + as a retained periodic gate (§7):** the suites run in
  **built order**, **shuffled**, **each standalone**, and **from a deliberately dirty/hostile card**
  (seeded with colliding leftover files, a non-root cwd, a fragmented free list, abandoned handles) —
  and must produce **bit-identical** results. A self-establishing suite is invariant to all of these;
  any divergence is a coupling bug to fix. This is the mechanical proof that decoupling holds.

**Verification.**
- *Normal:* full run green, pass counts unchanged, zero skips.
- *Edge:* every suite run **standalone** and in a **shuffled** order on a baselined card yields
  bit-identical pass counts; the **dirty-card** seed before each suite changes nothing.
- *Error:* a suite pointed at a deliberately-hostile card that its setup should neutralize must still
  pass (proving self-establishment); a suite whose real fixture can't be built (induced) fails loud as
  a categorized precondition — never a silent skip, never a masked driver failure.

## §6 — Documentation: contract, reporting rules, cross-references

**Why.** Documentation currency is a plan deliverable. This sprint changes the fixture contract (skip
semantics, baseline ownership, precondition classification) and the runner's reporting, and both are
documented surfaces.

**Current code / docs.**
- The Fixture-Discipline Contract lives in `REGRESSION-FIXTURE-DISCIPLINE-SPRINT-PLAN.md` "The
  Fixture-Discipline Contract" (line 148+). Decide whether to amend in place or extract to a standalone
  contract doc under `DOCs/` and reference it — recommend **extract to `DOCs/REGRESSION-CONTRACT.md`**
  now that two sprints share it, and leave a pointer in both plans.
- `CLAUDE.md` "Output Rules — Regression Test Reporting" governs how runs are reported.
- `DOCs/Analysis/CONCURRENCY-DETERMINISM-AUDIT.md` §4/§5 and `DOCs/Reference/DEBUGGING-METHODOLOGY.md`
  reference the silent-skip hole.

**Target behavior.**
- Contract doc gains: the **governing invariant** (a test fails iff the driver is wrong), the
  **zero-skip audit invariant**, the two skip categories (§1), the precondition classification table
  (§2), runner-owned baseline (§3), the self-establishment-at-group-granularity rule (§5), and the
  **retained periodic adversarial gate** (shuffled + standalone + dirty-start, §7).
- Record the resolved `testcard_validation` sub-decision (§5) — self-establish vs opt-in prepared-card
  suite — so its status is unambiguous.
- `CLAUDE.md` reporting rules updated to require the **Skipped** column and to state that a nonzero
  `SETUP NOT MET` is a run failure (not a footnote).
- Add the pointer in `DOCs/HANDOFF-SD-WRITE-PATH-PORT-TO-STANDALONE.md` (§4.5 area) telling the
  standalone agent to apply this sprint's fixture/runner pattern to its suite.
- Close the loop in `CONCURRENCY-DETERMINISM-AUDIT.md` §5 (recommendation #4 "never certify green
  without proving gated tests executed" is now enforced by §4).

**Integration points.** References the shipped names from §1–§5 (author after they exist —
standards-after-implementation, matching the predecessor sprint's ordering note).

**Verification.** Docs review: every new rule traces to a shipped mechanism; no dangling references;
`CLAUDE.md` example output shows the Skipped column.

## §7 — End-to-end determinism certification (native hardware, definition-of-done gate)

**Why.** The whole point: prove the regression runs straight through, deterministically, order-
independently, with zero silent skips — on real hardware, both geometries.

**Current code.** `tools/run_regression.sh` (with §3/§4 changes), the retrofitted suites (§5), and the
two existing cards from the predecessor cert (SD16G 8KB, 8GB 4KB).

**Target behavior / procedure** (native session, formattable scratch card, `--card-is-scratch`). The
adversarial matrix below is the mechanical proof of §5's decoupling — a self-establishing suite is
invariant to order and starting state:
1. **Built order:** full `./run_regression.sh --card-is-scratch` → all suites green, **Skipped column
   all zero**, deterministic pass counts, exit 0. Report per-file (every suite its own line).
2. **Shuffled order:** run the suites in a randomized order → **bit-identical** per-suite pass counts.
3. **Standalone:** each suite run on its own (freshly baselined) → its full pass count, zero skips.
4. **Dirty/hostile start:** before each suite, seed the card with colliding leftover files, a non-root
   cwd, a fragmented free list, and abandoned handles → results **unchanged** (proves self-
   establishment). Any divergence in (2)–(4) is a coupling bug — fix in-session and rerun.
5. **Negative control (the hole is closed):** temporarily make one baseline-guaranteed assertion
   impossible → the run **fails** with a clear `SETUP NOT MET` message and stops. Revert.
6. Repeat (1)–(4) on the **second geometry** card.
7. Baseline-health exit check: compile-clean, no regression vs the 33/33 predecessor baseline; suite #0
   accounted for.

**Retained as a periodic gate.** Steps (2)–(4) become a recurring check (documented in §6), not a
one-time cert — that is what keeps decoupling from regressing.

**Integration points.** Consumes §1–§6. This is the DoD gate; executed natively (see Hardware split).

**Verification.** The procedure *is* the verification. Any `SETUP NOT MET` on a baselined run, any
order-dependence, or a negative control that doesn't fail = the sprint is not done; fix in-session and
rerun.

---

## Cross-cutting notes

- **Compile gate (container):** after each section, `pnut-ts -d` the touched files and a
  `flexspin.mac -2 -q …` cross-check; full `./run_regression.sh --compile-only` sweep before hand-off.
  Runner-shell sections (§3, §4) are unit-tested in-container with a mock `run_test.sh` and canned
  logs — no hardware needed for their logic.
- **No guessing on Spin2/PASM2** — consult P2KB before any language/compiler assumption
  ([[feedback-no-guessing-p2]]).
- **Any bug found mid-sprint is fixed in-session**, not deferred.
- **Runner artifacts** (`performance.log`, `pnut-term-settings.json`, `tests/`) are pnut-term output —
  do not commit.
- **Determinism lens** — this whole sprint is about removing hidden inputs (ambient card state,
  execution order) from the *result*; see [[feedback-recompile-sensitive-heisenbug]] and
  `DOCs/Analysis/CONCURRENCY-DETERMINISM-AUDIT.md`.

---

## Section ↔ Task cross-reference (todo-mcp, sprint tag `regression-runthrough`)

_Tasks generated by `plan-to-tasks` at sprint-start; IDs filled in then._

| Plan § | Deliverable | Task | seq |
| ------ | ----------- | ---- | --- |
| §1 | Skip-signal contract: loud, two-category skip markers + helpers | TBD | 1 |
| §2 | Reclassify preconditions (baseline-guaranteed vs hardware-limit) | TBD | 2 |
| §3 | Runner-enforced baseline (audit→format suite #0, scratch-gated) | TBD | 3 |
| §4 | Runner skip-visibility + fail-on-skip + Skipped column | TBD | 4 |
| §5 | Per-test starting-condition discipline (3 violations + 5 systemic retrofits + adversarial enforcement) | TBD | 5 |
| §6 | Docs: contract extract, CLAUDE.md reporting, cross-refs, handoff pointer | TBD | 6 |
| §7 | End-to-end determinism certification (native hardware) | TBD | 7 |

Ordering: primitives first (§1 skip signal), then policy (§2 classification), then runner baseline
(§3) and enforcement (§4), then suite decoupling (§5), then docs (§6, authored after names exist),
then native certification (§7, the DoD gate).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
