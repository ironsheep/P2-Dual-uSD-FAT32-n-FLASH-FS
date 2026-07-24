# Decision 003: Test-Card Validation Suite Self-Establishes Its Fixtures

**Date:** 2026-07-23
**Status:** Implemented
**Scope:** `src/regression-tests/DFS_SD_RT_testcard_validation.spin2`, `src/regression-tests/TestCard/`
**Sprint:** Regression Run-Through, plan §5 (sub-decision required in writing before the suite is touched)

## Context

`DFS_SD_RT_testcard_validation.spin2` is the one regression suite that establishes and
asserts **nothing**. All ~14 fixtures are prepared outside the test run -- the developer
copies `src/regression-tests/TestCard/TESTROOT/*` onto the card by hand, per
`TEST-CARD-SPECIFICATION.md` -- and every test then only checks `handle >= 0` plus a size
or content value. Two consequences:

1. **A missing fixture scores as a driver failure.** If `TINY.TXT` was never copied,
   `openFileRead()` returns a negative handle and the suite reports a driver defect. The
   card preparation, not the driver, is what failed. This is precisely the false-failure
   class this sprint exists to eliminate.
2. **It is incompatible with the §3 enforced baseline.** Suite #0 now formats the card at
   the start of every run. Any externally-prepped fixture is erased before suite 1 runs, so
   in the default regression this suite could only ever fail.

The plan (§5) recommends converting it to self-establish, with any fixture that genuinely
cannot be self-authored moving to an explicitly-excluded, opt-in "prepared-card" suite
outside the default run. That fallback needs resolving one way or the other before the
suite is edited -- hence this document.

## Fixture audit — can each one be authored by the suite itself?

Every fixture in `TEST-CARD-SPECIFICATION.md` is defined by an algorithm or a literal
string, not by opaque captured data:

| Fixture | Size | Definition | Self-authorable |
|---|---|---|---|
| `TINY.TXT` | 29 | Literal `TINY TEST FILE - 32 BYTES OK!` | Yes |
| `EXACT512.BIN` | 512 | 512 × `0x58` | Yes |
| `TWOSEC.TXT` | 2,550 | 50 lines of `LINE####--` × 5 | Yes |
| `FOUR_K.BIN` | 4,096 | `byte[i] = i & 0xFF` | Yes |
| `SIXTYFK.BIN` | 65,536 | `byte[i] = ((i / 512) << 1) ^ (i & 0xFF)` | Yes |
| `SEEKTEST.BIN` | 2,016 | 32 blocks × (`BLK##---` + 55 × `0x55`) | Yes |
| `CHECKSUM.BIN` | 1,024 | bytes 0-255 repeated 4× (sum 130,560) | Yes |
| `LEVEL1/INLEVEL1.TXT` | 54 | Literal sentence | Yes |
| `LEVEL1/LEVEL2/DEEP.TXT` | 71 | Literal sentence | Yes |
| `MULTI/FILE1-5.TXT` | 18 each | Literal `Multi-file test N` | Yes |

No fixture depends on anything the driver cannot produce: no specific fragmentation
layout, no deliberately corrupted structure, no foreign-formatter artifact. The total
written is ~76 KB, trivial on any supported card.

## Decision

1. **The suite self-establishes all 14 fixtures.** Setup creates the full tree
   (`newDirectory` / `changeDirectory` / `createFileNew`, matching the idiom
   `DFS_SD_RT_subdir_ops_tests` already uses) with byte content generated from the same
   formulas the tests verify.
2. **No prepared-card suite is created.** The escape hatch the plan sanctioned is not
   needed, because the audit above found nothing that requires external preparation.
   Adding an opt-in suite outside the default run would carve out exactly the kind of
   unexercised corner this sprint is closing.
3. **`TestCard/TESTROOT/` and `TEST-CARD-SPECIFICATION.md` stay in the repo** as the
   byte-exact reference definition of the fixture contract (they carry the MD5s). They are
   no longer a prerequisite for running the suite. The spec is updated to say so.
4. **Fixture establishment failures use the §1 precondition path**, so a fixture that will
   not build reports `# SETUP NOT MET:` -- which, on a card the runner just baselined, the
   §4 runner treats as a hard failure. A fixture that cannot be created *is* a real defect
   under those conditions; it is never a silent skip and never a masked driver failure.
5. **The suite gates on capacity** (`assertFreeSpace`) before writing, per §5 pattern A.
6. **Root enumeration asserts owned entries, not a global count.** The old test asserted
   the root held 7-50 entries, which couples the result to whatever every *other* suite
   left behind. It now asserts that each of the 9 entries this suite created is present in
   the enumeration. `MULTI` keeps its exact count of 5 -- that directory is wholly owned by
   this suite, so an exact count is legitimate there.
7. **Teardown removes the tree** (`ensureCleanBaseline` semantics: delete, then audit that
   nothing owned remains), so the suite leaves the card as it found it.

## Consequences

- The suite changes character from **read-only** to **read-write**. Its header comment and
  the specification document are updated; the "does NOT write to the card" claim is
  retired.
- It becomes runnable on any freshly-baselined scratch card with no manual preparation,
  which is what makes it compatible with the §3 baseline and eligible for the §7
  shuffled / standalone / dirty-card determinism certification.
- Coverage is unchanged in kind: the same sizes, patterns, checksum, path resolutions, and
  enumeration behaviors are still verified. What changes is that the suite now proves the
  driver can *write* those fixtures as well as read them -- strictly more driver exercise
  than before.
- The 255-record debug budget (see [Decision 002](DECISION-002-DEBUG-RECORD-BUDGET.md))
  applies to the added setup code; the suite is compile-checked as part of the sweep.
