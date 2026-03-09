# Release Checklist

Use this checklist before tagging each release. Every item must pass before the tag is created.

---

## 1. Code Freeze

- [ ] All feature work and bug fixes committed
- [ ] Working tree clean (`git status` shows no changes)

## 2. Full Regression Suite

Run the unified regression suite from `tools/`:

```bash
cd tools/
./run_regression.sh
```

This runs 29 standard suites in dependency order (stop on first failure):

- [ ] All 29 suites pass, 1,308+ tests, 0 failures
- [ ] Tested on at least two different SD cards (document card models in release notes)

### Optional: 8-cog stress test

```bash
./run_regression.sh --include-8cog
```

- [ ] 8-cog test passes (if included)

### Destructive tests (run separately, erases SD card)

```bash
./run_test.sh ../src/regression-tests/DFS_SD_RT_format_tests.spin2 -t 300
```

- [ ] Format test passes

## 3. Compile All Dependents

Verify everything compiles beyond just the test suites:

```bash
# Driver standalone
cd src && pnut-ts -d dual_sd_fat32_flash_fs.spin2

# Demo shell
cd src/DEMO && pnut-ts -I .. -I ../UTILS DFS_demo_shell.spin2

# Examples
cd src/EXAMPLES && for f in DFS_example_*.spin2; do pnut-ts -d -I .. "$f"; done

# Utilities
cd src/UTILS && for f in DFS_SD_*.spin2 DFS_FL_*.spin2; do pnut-ts -d -I .. "$f"; done
```

- [ ] Driver compiles clean
- [ ] Demo shell compiles clean
- [ ] All 4 examples compile clean
- [ ] All 7 utilities compile clean

## 4. Documentation Audit

### Driver docs

- [ ] [Theory of Operations](../DUAL-DRIVER-THEORY.md) -- API names, command tables, and architecture match driver source
- [ ] [Tutorial](../DUAL-DRIVER-TUTORIAL.md) -- code examples compile-correct, method signatures match
- [ ] [Utilities Guide](../DUAL-UTILITIES.md) -- utility descriptions match current source behavior
- [ ] [Flash FS Theory](../FLASH-FS-THEORY.md) -- block format, wear leveling, mount process match implementation
- [ ] [Memory Sizing Guide](../Reference/MEMORY-SIZING-GUIDE.md) -- hub RAM figures match current driver

### Regression test docs

- [ ] [Regression Testing Strategy](REGRESSION-TESTING-STRATEGY.md) -- test types, priorities, and audit patterns match current test suite practices

### Utility theory docs

- [ ] [SD FAT32 FSCK Theory](../Utils/SD-FAT32-FSCK-THEORY.md) -- matches current FSCK implementation
- [ ] [SD FAT32 Audit Theory](../Utils/SD-FAT32-AUDIT-THEORY.md) -- test counts match actual `auditRunTest()` calls
- [ ] [SD Format Utility Theory](../Utils/SD-FORMAT-UTILITY-THEORY.md) -- describes CMD25 bulk writes, async API
- [ ] [Flash Format Utility Theory](../Utils/FLASH-FORMAT-UTILITY-THEORY.md) -- matches current Flash format implementation

### Spot checks

- [ ] No removed or renamed API names referenced in docs
- [ ] No stale test counts in docs (verify against `run_regression.sh` output)
- [ ] No broken markdown links (`[text](path)` where path does not exist)

## 5. README Audit

### Repository READMEs

- [ ] Top-level `README.md` -- test counts, file tree, feature list match current state
- [ ] `src/README.md` -- file list matches disk
- [ ] `src/DEMO/README.md` -- file list matches disk
- [ ] `src/EXAMPLES/README.md` -- file list matches disk
- [ ] `src/UTILS/README.md` -- file list matches disk
- [ ] `src/regression-tests/README.md` -- suite count and test totals match
- [ ] `DOCs/README.md` -- file list matches disk
- [ ] `DOCs/Reference/README.md` -- file list matches disk
- [ ] `DOCs/Utils/README.md` -- file list matches disk
- [ ] No references to `logs/` directories in any README

### Release package READMEs (`.release/`)

These READMEs ship inside the release zip. They have different relative paths and content from the repo READMEs.

- [ ] `.release/README.md` -- package tree, quick start, and docs table match current state
- [ ] `.release/src/README.md` -- driver description, file tables, and build commands correct
- [ ] `.release/src/DEMO/README.md` -- command reference matches current shell commands
- [ ] `.release/src/EXAMPLES/README.md` -- example list and descriptions match current programs
- [ ] `.release/src/UTILS/README.md` -- utility list matches current utilities, workflows correct

## 6. Changelog

Per the [Changelog Style Guide](changelog-style-guide.md):

- [ ] `CHANGELOG.md` `[Unreleased]` section has entries for all user-facing changes
- [ ] Move `[Unreleased]` entries to new version heading with today's date
- [ ] Entries are terse (25 words max), additive framing, no implementation details
- [ ] Internal-only changes (refactors, renames, style cleanup) are excluded
- [ ] `[Unreleased]` link updated to compare new tag to HEAD
- [ ] New version link added at bottom of file

## 7. Release Workflow

The release is automated via `.github/workflows/release.yml`. The workflow copies source files from the repo and READMEs from `.release/` into the release zip.

- [ ] Workflow copies all current source files (check for new files added since last release)
- [ ] All `DFS_SD_RT_*`, `DFS_FL_RT_*`, and `DFS_RT_*` test patterns included
- [ ] Support libraries in `src/UTILS/` are included (isp_format_utility, isp_fsck_utility, etc.)
- [ ] No stale file references (files that were renamed or removed)
- [ ] `.release/` READMEs copied into the package at the correct locations

## 8. Tag and Release

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

- [ ] Tag pushed triggers GitHub Actions release workflow
- [ ] Release zip contains all expected files (spot-check against workflow)
- [ ] Release notes extracted correctly from CHANGELOG

---

*Adapted for the P2 Dual SD FAT32 + Flash Filesystem project.*
