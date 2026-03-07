# Plans

Implementation plans and design documents for the dual-FS project.

Style guides and procedures are in [`DOCs/procedures/`](../procedures/) (gitignored, local-only).

## Active

| Document | Description |
|----------|-------------|
| [PUNCH_LIST.md](PUNCH_LIST.md) | Pre-release cleanup tasks (nothing outstanding) |
| [SPI-BACKEND-CONSOLIDATION-GUIDE.md](SPI-BACKEND-CONSOLIDATION-GUIDE.md) | SPI backend refactoring: 3 shared methods, ~286 lines saved (pending) |

## Deferred

| Document | Description |
|----------|-------------|
| [Circular-Files-on-SD-Plan.md](Circular-Files-on-SD-Plan.md) | Circular file support for SD (post-1.0) |

## Completed (archived)

Completed plans are in `archive/` (gitignored, local-only). Kept for reference but not tracked in version control.

| Document | Description |
|----------|-------------|
| R1-Bit7-Fix-Plan.md | R1 response bit-7 fix (SD spec 7.3.2.1), 9 loops in 7 methods |
| SD-Driver-v1.3.0-Upgrade-Plan.md | SD driver v1.3.0 upgrade (CMD13/CMD23 probes, CMD12 tolerance) |
| Driver-Path-Resolution-Plan.md | Driver-internal path resolution for SD and Flash |
| Flash-Directory-Support-Plan.md | Flash openDirectory/readDirectoryHandle + demo shell support |
| PUNCH_LIST-completed-2026-03-01.md | v1.0 punch list (all 4 items complete) |
| SPI-Caller-Cog-Fix-Plan.md | Fix 6 SPI-from-caller-cog violations |
| Phases-4-7-Implementation-Plan.md | Phases 4-7: test migration, cross-device ops, shell, examples |
| Phase3-Flash-File-Operations-Plan.md | Phase 3: Flash file operations integration |
| Phase-5b-Post-v1.0.0-SD-Updates-Plan.md | Phase 5b: post-v1.0.0 SD driver updates |
| Feature-Parity-Plan.md | Feature parity: SD/Flash API alignment, utilities, docs |
| Regression-Test-Coverage-Gaps.md | Regression test coverage expansion (32 suites, 1,335 tests) |
| Decouple-Flash-Block-Buffers.md | Flash buffer pool decoupling (~12 KB savings) |
| PENDING-api-tutorial-mount-patterns.md | Multi-cog mount/unmount best practices |

---

*Part of the [P2 Dual SD FAT32 + Flash Filesystem](../../README.md) project — Iron Sheep Productions*
