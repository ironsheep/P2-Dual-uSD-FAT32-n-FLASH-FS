# Architecture Decisions

This directory records key architectural and implementation decisions for the P2 Dual uSD FAT32 + FLASH FS driver. Each document captures the context, options considered, decision made, and supporting data.

## Decision Log

| # | Decision | Date | Status |
|---|----------|------|--------|
| 1 | [Worker Cog Stack Sizing](DECISION-001-STACK-SIZING.md) | 2026-03-03 | Implemented |
| 2 | [Debug Record Budget Management](DECISION-002-DEBUG-RECORD-BUDGET.md) | 2026-03-28 | Proposed |
| 3 | [Test-Card Validation Self-Establishes Its Fixtures](DECISION-003-TESTCARD-SELF-ESTABLISH.md) | 2026-07-23 | Implemented |

## Procedures

| Document | Description |
|----------|-------------|
| [card-presence-detection-procedure.md](card-presence-detection-procedure.md) | SD card presence detection via MISO pull-up during CMD0 probe |
| [REGRESSION-TESTING-BEST-PRACTICES.md](REGRESSION-TESTING-BEST-PRACTICES.md) | Best practices for P2 regression test development |
