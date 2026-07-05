# HANDOFF — microSD MBR-Corruption Fix (shared SD/Flash bus)

**Status:** Fix implemented and compiles clean. **Hardware verification is the remaining
step and is why this is being handed off** — the authoring environment is a container that
cannot drive the physical P2 over serial. The receiving agent runs natively with the P2
Edge board attached and must run the tests on real hardware.

**Date handed off:** 2026-07-04
**Branch:** `main`
**Driver under test:** `src/dual_sd_fat32_flash_fs.spin2` (modified, **uncommitted** — see Git State)

---

## 1. The problem we're solving

Field reports: activity against the dual filesystem driver is **damaging the microSD card's
filesystem**. Two failure signatures have been described / captured:

1. **Wiped MBR** — sector 0 (the partition table) is overwritten with zeros. The card is
   electrically healthy but a desktop/OS refuses it because it has no partition table.
   This is the signature captured in `REF-NO-COMMIT/sd_rescue.log` (a healthy ~8 GB SDHC
   card whose sector 0 read back all-zero, `55AA` signature missing, card **not** locked,
   **not** write-protected).
2. **Password-locked card** — `CMD13` R2 bit0 set; the OS refuses the card as locked.

### Root-cause mechanism (confirmed from the driver's own code)

On the P2 Edge module the microSD card and the onboard boot-Flash **share four SPI pins with
their roles swapped**:

| Pin | SD role | Flash role |
|-----|---------|------------|
| P60 | **CS**  | **SCK**    |
| P61 | **SCK** | **CS**     |
| P59 | MOSI    | MOSI (shared) |
| P58 | MISO    | MISO (shared) |

So **every Flash access physically drives the SD card's chip-select, clock and data lines.**
The driver already documents this in `switch_to_sd()`:
> *"P60 (SD CS) is reused as Flash SCK, so during Flash operations the SD card sees its CS
> rapidly toggling, which corrupts the card's SPI state machine. A full re-initialization
> is required to recover."*

The **theory under test**: occasionally that stray bus traffic is latched by the SD card as a
*destructive* command — a write to LBA 0, an erase, or a `CMD42` LOCK — which a re-init cannot
undo. The existing "re-init after Flash" only recovers a confused state machine; it cannot
reverse a command the card has already executed.

Three evidence files live in `REF-NO-COMMIT/` (reference only, not committed):
- `sd_rescue.log` — capture proving the wiped-MBR signature on a healthy card.
- `sd_rescue.spin2` — a standalone, dependency-free diagnostic/recovery tool.
- `dual_sd_fat32_flash_fs.spin2` — the user's hand-modified driver containing the proposed fix
  (now folded into `src/`, see §3).

---

## 2. What we're trying to do (the goal of this hand-off)

We have **implemented the fix** and proven it **compiles**. We need the native agent to
**prove on real hardware that the fix does not break anything**, then **exercise it against
the corruption scenario**. Concretely, two runs:

1. **Full regression suite** against the fixed driver → prove no regression.
2. **The new MBR-sentinel stress harness** against the fixed driver → the hardening
   confirmation ("ARM 3").

The corruption itself is probabilistic and did **not** reproduce in the authoring run (see
§5), so the harness is primarily a *regression gate and a survivability check*, not yet a
guaranteed reproducer. Read §5 before drawing conclusions from a clean harness run.

---

## 3. What changed in the driver (the fix)

All edits are in `src/dual_sd_fat32_flash_fs.spin2` (`git diff` = 64 insertions, 8 deletions).
Five changes came from the user's `REF-NO-COMMIT` driver; **one additional change** was found
and added during a command-send audit (item 6 — the REF version missed it):

1. **`CMD59` CRC-ON at `initCard` Step 5.5** — turns on SD CRC checking for the whole SPI
   session. This is the anti-brick core: with checking on, the card **rejects** any command
   frame whose CRC-7 doesn't match, so stray Flash traffic that happens to decode as `CMD42`
   / an erase / a write is thrown out instead of executed. Persists across a P2 reset (the
   card keeps power) until the next full init.
2. **`cmd_crc7(op, parm)`** — new helper that computes the real CRC-7 of a command frame.
   Required because once checking is on, *every legitimate* command must carry a valid CRC.
3. **`CMD59` re-armed in `reinitCard`** — `CMD0` resets CRC checking to off, so it is
   re-enabled after every re-init.
4. **Park idle shared lines high** — `pinh(P60/P61/MOSI)` instead of leaving them floating
   during bus switching; floating lines let noise clock garbage bits into the card.
5. **`WAITATN()` → poll `pb_cmd == CMD_NONE` loop** — unrelated robustness fix: a bare
   `WAITATN()` can wake early on a spurious/concurrent ATN, making a caller read the previous
   op's result. Re-checking the worker's done-flag makes spurious wakes harmless.
6. **`sendCmd13Transaction()` CRC fix (ADDED here — the REF version missed it).** This path
   sent `CMD13` with a dummy `$FF` CRC and is reached from `checkCardStatus()` on **every
   read/write** and from `probeCmd13()` **during init**. Under CRC-ON those `CMD13`s would be
   rejected (COM_CRC_ERROR) and break reads/writes/init. Changed to `cmd_crc7(CMD13, 0)`.

### Command-send audit (why we believe the fix is complete)
Every place that transmits an SD command frame was checked to ensure it now sends a valid CRC:
- `cmd(op, parm)` — uses `cmd_crc7()` ✓
- `sendCommand(...)` — uses `cmd_crc7()` ✓
- `do_test_cmd13()` — uses `cmd_crc7(CMD13, 0)` ✓
- `sendCmd13Transaction()` — **fixed** to `cmd_crc7(CMD13, 0)` ✓
- `sendStopTransmission()` (`CMD12`) — already sends the correct static `CRC_CMD12 = $61` ✓

**Note on data CRC:** write data blocks already compute a real CRC-16 (`calcDataCRC`), so
they are unaffected. If any *read* path shows new CRC errors on hardware, that's the first
place to look, but the audit expects it to be clean.

---

## 4. What to run, how, and what "pass" looks like

Native agent, board attached, a **microSD card inserted**. Working dir for runners is `tools/`.

### Run 4a — Full regression suite (no-regression proof) — REQUIRED FIRST
```bash
cd tools/
./run_regression.sh
```
- Runs all standard suites on real hardware (downloads each `.bin` via `pnut-term-ts`).
- Logs land in `tools/logs/<suite>_<timestamp>.log`.
- Options: `--from <substr>` resume, `--compile-only`, `--include-8cog`, `--include-format`
  (**`--include-format` ERASES the SD card**).

**What we're looking for:**
- **Every suite passes** exactly as it did before the fix. The fix enables `CMD59` CRC
  checking across the whole session, so this run is the real test that *all* command paths
  send correct CRCs. If the audit missed a path, you'll see mount/read/write/init failures
  and/or `R1` responses with **bit3 (COM_CRC_ERROR, `$08`)** set in the logs.
- **Zero new COM_CRC_ERROR noise** in any log.

**Reporting (project rule — follow it):** report **every test file on its own line** with
pass/fail counts, then totals. Do **not** group by suite family or abbreviate with
"all N passed". Example:
```
DFS_SD_RT_mount_tests:           21 pass, 0 fail
DFS_RT_dual_device_tests:        37 pass, 0 fail
...
Total: <N> tests, 0 failures
```

If anything fails: capture the failing suite's log, note whether R1 shows COM_CRC_ERROR
($08) — that points straight at a command path still sending a bad CRC — and report before
proceeding.

### Run 4b — MBR-sentinel stress harness (hardening confirmation = "ARM 3")
```bash
cd tools/
./run_test.sh ../src/regression-tests/DFS_RT_mbr_sentinel_stress_tests.spin2 -t 300
```
**⚠ DESTRUCTIVE — use a SCRATCH microSD card.** If the bug fires, the card's partition table
is destroyed (recover with `REF-NO-COMMIT/sd_rescue.spin2` or a desktop reformat).

**What the harness does** (full rationale in the file's header comment):
- Baselines the CRC of sentinel sectors **LBA 0 (MBR), 1, 2** — sectors the filesystem must
  never write during file I/O — and snapshots `CMD13` R2 lock/WP bits.
- **ARM 1 — SD-only:** 300 iterations of SD file churn, no Flash ops (no bus switching).
  A control: corruption here would mean a pure driver wrong-LBA bug, *not* the bus.
- **ARM 2 — SD+Flash interleave:** 300 iterations alternating a Flash file round-trip and an
  SD file round-trip, forcing a bus switch each iteration. Re-checks sentinels + `CMD13`
  every 10 iterations.
- On any change it dumps the offending sector + `CMD13` R2 (same fingerprint `sd_rescue`
  produces).

**What we're looking for now that the fix is in:**
- **All arms clean, 7/7 tests pass** → the fixed driver survives interleaved dual-device load
  with no MBR/reserved-sector corruption and no lock. This is the "ARM 3" confirmation.
- Tunable in the file's `CON` block: `ARM1_ITERS`, `ARM2_ITERS`, `CHECK_EVERY`. For a
  stronger survivability soak, raise `ARM2_ITERS` (e.g. 3000 ≈ ~12 min, 10000 ≈ ~40 min) and
  bump `-t`.

**Interpreting results (IMPORTANT):**
- A **clean** harness run is *necessary but not sufficient* proof — the corruption is
  probabilistic and did not reproduce even on the *unfixed* driver in the authoring run (§5).
  Do not read "ARM 2 clean" as "bug fixed"; read it as "no regression + survived this load."
- If **ARM 2 ever corrupts a sentinel while ARM 1 stays clean**, that is a live reproduction
  of the shared-bus mechanism — capture the full log, note LBA and `CMD13` R2, and report. If
  it happens on the *fixed* driver, the fix is insufficient and needs escalation.

---

## 5. Prior run result (context for interpreting new runs)

The harness was run once in the authoring environment **against the pre-fix driver**:
- ARM 1 (SD-only) **clean**, ARM 2 (interleave) **clean** — 7/7 pass, no corruption.
- i.e. **the bug did not reproduce** in 300+300 cycles.

Mechanistic reasoning for why routine interleave is a *weak* trigger: during a Flash data
transfer, SD-SCK (P61) is held static (it's Flash CS, asserted) while SD-CS (P60) toggles as
the Flash clock — so the card only receives stray SD-SCK edges at Flash select/deselect
boundaries, a couple per command, while its CS thrashes and constantly resets its command
receiver. Assembling a coherent 48-bit destructive frame that way is rare. The **likely real
triggers are elsewhere** and are harder/impossible for this harness to hit:
- **Reset / power-up** — the P2 boot ROM reads Flash *before the driver runs*; `CMD59`-at-mount
  cannot protect that window at all.
- **Float-glitch windows** during bus switching (addressed by fix #4, line parking).
- **Multi-cog collisions** — an SD op in flight when another cog starts a Flash op.

**Implication for the native agent:** the strongest available proof is Run 4a passing (fix
doesn't break normal operation) plus Run 4b surviving a long soak. A definitive repro may only
come from the field, or from a future harness variant targeting reset/boot-ROM and multi-cog
collisions (see §7).

---

## 6. Compile status (already verified in-container)
- Driver compiles standalone: `cd src && pnut-ts -d dual_sd_fat32_flash_fs.spin2` ✓
- **All 37 regression suites compile clean** against the fixed driver ✓
  (the format suite needs its extra include: `-I .. -I ../UTILS`).
- Harness compiles: `cd src/regression-tests && pnut-ts -d -I .. DFS_RT_mbr_sentinel_stress_tests.spin2` ✓

So any hardware failure is a *runtime* issue, not a build issue.

---

## 7. Open items / possible follow-ups
- **Field questions still outstanding** (asked of the reporting user, plain-language): when
  failures happen (near Flash use / reset vs pure SD), which signature (wiped-MBR vs locked),
  whether reformattable, and whether clustered at power-on. Their answers determine whether the
  real trigger is the boot-ROM path (which needs mitigation beyond `CMD59`-at-mount).
- **Harness enhancements** if a repro is wanted: a multi-cog collision arm, and/or a mode that
  emits Flash byte patterns more likely to decode as SD command tokens.
- The boot-ROM/reset window is **not** covered by `CMD59`-at-mount; if field data points there,
  a different mitigation is required and should be designed separately.

---

## 8. Git state at hand-off
```
 M .gitignore                                             (pre-existing, unrelated)
 M src/dual_sd_fat32_flash_fs.spin2                       (THE FIX — uncommitted)
?? src/regression-tests/DFS_RT_mbr_sentinel_stress_tests.spin2   (new harness — untracked)
?? DOCs/HANDOFF-MBR-CORRUPTION-FIX.md                     (this document)
```
The fix and harness are **uncommitted** deliberately — the intent was to let the native agent
run hardware verification against this working tree first. Suggested sequence:
1. Run 4a (full regression) → confirm no regression.
2. Run 4b (sentinel harness) → confirm survival.
3. If both good, **commit** the driver fix + harness + this doc together.

### Commit gating (READ BEFORE COMMITTING)
- **Run 4a green is the gate.** Commit only after the full regression passes with **zero new
  COM_CRC_ERROR (`R1` bit3 = `$08`) noise** in the logs — that is the real proof the
  `CMD59` CRC-ON change is safe. Bundle the driver fix + harness + this doc as **one commit**.
- **Run 4b does not gate the commit.** The sentinel harness is a destructive survival check,
  not a pass/fail regression. If 4a is green, a clean *or* inconclusive 4b is fine — just
  record its outcome (arms run, iteration counts, any sentinel/`CMD13` changes) in the commit
  body. Only a 4b result showing corruption **on the fixed driver** should block the commit
  and be escalated (see below).
- **If Run 4a FAILS: do NOT commit, and do NOT fix in-flight — stop and report back.** A
  regression here most likely means a command-send path is still transmitting a bad CRC now
  that checking is on. Capture the failing suite's log, note whether `R1` shows COM_CRC_ERROR
  (`$08`), and surface it — that log *is* the diagnosis and should be reviewed, not patched
  blind. (The §3 audit lists every known command-send site; a failure points at one not on
  that list or one still using a static/dummy CRC.)

`.bin` build artifacts in `src/regression-tests/` are regenerated by the runners and can be
ignored.
```
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```
(Use the above trailer on the eventual commit, per repo convention.)
```
