# Punch List - Pre-Release Cleanup

## Open

- [ ] **Delete `src/regression-tests/DFS_FL_RT_circular_compat_tests.spin2`** (raised 2026-07-23,
      Regression Run-Through §5). Its coverage was folded into `DFS_FL_RT_circular_tests.spin2`
      (which now produces the records it verifies, cycles the mount, and re-verifies them), and it
      has been removed from the regression run. The file is retained only for reference; deleting
      it is Stephen's call. It still compiles, so it is not a build risk either way.

Prior punch lists:
- 2026-03-01: v1.0 punch list (4 items, all complete -- see `archive/PUNCH_LIST-completed-2026-03-01.md`)
- 2026-03-03: Test weakness patterns (identified during device guard audit -- extracted to `DOCs/procedures/Test-Weakness-Patterns.md` for incorporation into a future comprehensive test suite audit)
