# Plan: Circular Files on SD

**Status**: Deferred — to be activated independently after Feature Parity plan is complete.

## Context

Circular files are currently Flash-only (`open_circular(DEV_FLASH, ...)`). SD returns `E_NOT_SUPPORTED`. The goal is circular file support for SD cards, enabling use cases like fixed-size log files that wrap around.

## Flash Circular File Behavior (reference)

Flash circular files work via front-truncation ("froncation"):
- `open_circular(@name, FILEMODE_APPEND, max_length)`: writes append to end; on close/flush, if file exceeds max_length, head blocks are removed to trim back to max_length
- `open_circular(@name, FILEMODE_READ, max_length)`: read starts at (file_length - max_length) offset, or at beginning if file hasn't reached max_length yet
- The "circular" behavior is simulated — the file grows then gets trimmed, not a true ring buffer

## SD Architectural Options

### Option A: Front-Truncation (match Flash semantics)
- On close/flush: if file exceeds max_length, rewrite file starting from offset (file_length - max_length)
- Rewriting means: create new file, copy tail portion, delete old file
- **Pro**: Semantically identical to Flash
- **Con**: Very expensive on SD — requires full file rewrite on every close. For a 100KB circular file, every close rewrites 100KB.

### Option B: Modular Write Position (true ring buffer)
- Reserve first sector (or first N bytes) as metadata: write_position, wrap_flag, max_length
- Writes go to write_position, wrap around to data start when reaching max_length
- Reads start from write_position (oldest data) and wrap around
- **Pro**: Efficient — writes are sequential, no rewriting
- **Con**: Complex seek logic; file not readable by external tools (custom format); metadata overhead

### Option C: Rolling File Pair
- Maintain two files: `name.0` and `name.1` (or similar)
- Write to current file until it reaches max_length/2, then switch to other file and delete the previous
- Read concatenates both files logically
- **Pro**: No rewriting, always has recent max_length/2 to max_length of data
- **Con**: Complex, two files visible, not exactly max_length boundary

### Option D: Sector-Level Ring Buffer (raw sectors)
- Allocate a contiguous cluster chain of fixed size
- Write circularly within those sectors using a write pointer stored in the first sector
- **Pro**: Very efficient, true circular behavior
- **Con**: Requires pre-allocation, breaks FAT32 file size semantics, external tools see wrong file size

## Recommended Approach

**Option A** (front-truncation) is recommended despite the performance cost because:
1. Semantically identical to Flash — true API parity
2. No custom on-disk format — file is always valid FAT32
3. Simplest implementation — leverages existing file ops
4. SD cards are fast enough for embedded log sizes (4KB-64KB typical)

## Implementation Sketch (Option A)

1. Add `sd_circular_max_length` per-handle tracking (LONG array, like Flash's `hCircularLength`)
2. `open_circular(DEV_SD, @name, FILEMODE_APPEND, max_length)`:
   - Open file for append (existing `openFileWrite`)
   - Store max_length in handle state
3. On `closeFileHandle()` or `syncHandle()` for circular SD handles:
   - Check if file_size > max_length
   - If yes: create temp file, copy last max_length bytes from current file, delete original, rename temp
   - This is expensive but correct
4. `open_circular(DEV_SD, @name, FILEMODE_READ, max_length)`:
   - Open for read
   - If file_size > max_length: seek to (file_size - max_length)
   - Reads proceed from there

## Cost Analysis

For a 32KB circular log file with 512-byte writes:
- Every 64 writes, file reaches ~32KB
- Close triggers: read 32KB + write 32KB + delete + rename = ~4 operations
- At 25 MHz SPI: ~130ms for the truncation operation
- Acceptable for logging use cases (write every few seconds)

For a 256KB circular file: ~1 second truncation — may be too slow for frequent flushes.

## Earlier Cost Analysis (from Phases-4-7 Plan)

A different set of approach options was analyzed earlier:

| Option | Mechanism | Pros | Cons |
|--------|-----------|------|------|
| A. Header in file | Pre-allocate fixed-size file. First N bytes = wrap pointer + metadata. Data wraps after header. | Self-contained, one file | Header read/write on every wrap; cluster chain walk on open |
| B. Sidecar file | Data file + `.meta` companion file storing wrap pointer | Data file is plain FAT32 | Two files per circular file; sidecar can get orphaned |
| C. Pre-allocated + seek | Pre-allocate exact cluster count. Seek to wrap position. Overwrite in-place. | Simple seek-based writes | Requires in-place overwrite (SD supports this); no truncation |

Earlier estimate: ~200-300 lines driver code, ~16 bytes per-handle state, ~1-2KB binary size.

## Verification

- Test circular append on SD (write until wrap, verify oldest data removed)
- Test circular read on SD (verify read starts at correct offset)
- Cross-device: circular file on Flash, copy to SD, verify content
- Stress test: many write/flush cycles, verify max_length constraint holds
- Compare Flash and SD circular file content for identical write sequences

## Dependencies

- Requires Feature Parity plan features: seekHandle with whence (B8), file_size by name (B3)
- Should be implemented AFTER Feature Parity plan is complete

## Open Questions (to resolve when plan is activated)

- Final approach selection (Option A recommended but not decided)
- Performance testing of Option A at various file sizes
- Whether Option C or D should be prototyped as alternatives if Option A proves too slow
