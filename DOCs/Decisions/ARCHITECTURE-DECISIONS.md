# Dual-FS Driver Architecture Decisions

This document captures the architectural decisions made when merging the standalone SD FAT32 driver and standalone Flash filesystem driver into a single unified dual-device driver (`dual_sd_fat32_flash_fs.spin2`). Each decision addresses a problem unique to operating two filesystems with different storage models, SPI modes, and pin assignments through one worker cog on one SPI bus.

For decisions inherited from the standalone SD driver (worker cog pattern, Spin2 worker via COGSPIN, DAT singleton, COGATN signaling, smart pin SPI, streamer DMA, error codes, timeout policy, multi-block ops, three sector buffers, CRC-16 validation), see the sister project's architecture document. Those decisions carried forward unchanged into the dual driver.

---

## Decision 1: Flash File and Folder Emulation

### The Problem

The Flash filesystem (`flash_fs.spin2` by Chip Gracey) stores files in a flat namespace -- every file is identified by a string ID with no directory hierarchy. The SD FAT32 driver provides real directories with `mkdir()`, `chdir()`, `openDirectory()`, and path-based file access. If the dual driver exposes two incompatible file models, callers must write device-specific code for every operation.

### The Solution: Slash-Delimited Name Convention

The Flash side emulates directories by encoding path structure into the flat filename string. A file logically located at `logs/sensor1.dat` is stored in Flash with the literal filename `"logs/sensor1.dat"`. The Flash filesystem treats the entire string (including slashes) as an opaque ID. The driver interprets the slash-delimited segments as a directory hierarchy.

This emulation supports:

| Operation | How It Works on Flash |
|---|---|
| `chdir(DEV_FLASH, "logs")` | Sets per-cog CWD prefix to `"logs"` |
| `exists(DEV_FLASH, "sensor1.dat")` | Prepends CWD: checks if `"logs/sensor1.dat"` exists |
| `openDirectory(DEV_FLASH, "/")` | Enumerates all files, strips CWD prefix, deduplicates directory names |
| `openDirectory(DEV_FLASH, "logs")` | Enumerates files starting with `"logs/"`, returns bare filenames |
| `mkdir(DEV_FLASH, "logs")` | No-op success -- directories are implicit in filenames |

### Key Implementation Details

- **`fl_prepend_cwd(p_dest, p_name)`** (line ~6563): Builds the full Flash path by concatenating the caller's CWD prefix with the filename. If CWD is `"logs"` and filename is `"data.txt"`, result is `"logs/data.txt"`. If filename starts with `"/"`, CWD is skipped (absolute path).

- **`fl_cwd_matches(p_stored_name, p_bare_name)`** (line ~6641): During directory enumeration, checks whether a stored Flash filename belongs to the current CWD context and strips the prefix to return the bare name to the caller.

- **Directory listing deduplication**: When listing `"/"`, a file named `"logs/sensor1.dat"` produces a directory entry `"logs"` (the first path segment). Multiple files under `"logs/"` produce only one `"logs"` directory entry.

### Why Not Real Directories in Flash?

The Flash filesystem uses a log-structured block chain with 4KB blocks. Adding real directory metadata would require:
- A directory block format (the reference driver has none)
- Directory-to-file linking (the reference driver uses flat ID lookup)
- Garbage collection awareness of directory blocks

The slash convention achieves API parity with zero changes to the underlying Flash block engine. The 128-byte filename limit (`FL_FILENAME_SIZE`) accommodates paths up to 3-4 levels deep, which matches the practical depth for embedded data logging.

### Decision

**Emulate Flash directories via slash-delimited filename convention.** The `fl_prepend_cwd()` and `fl_cwd_matches()` helpers make this transparent to callers. The same `chdir()`, `openDirectory()`, `exists()`, and file I/O calls work identically on both devices.

---

## Decision 2: SPI Bus Switching Between SD and Flash

### The Problem

The SD card and Flash chip share a 4-pin SPI bus on the P2 Edge Module, but with a critical cross-wiring: SD CS (P60) is Flash SCK (P60), and SD SCK (P61) is Flash CS (P61). The two devices also use different SPI modes (SD = Mode 0 with smart pins, Flash = Mode 3 with GPIO bit-bang). When Flash operations toggle P60 as SCK, the SD card sees its CS line toggling rapidly, corrupting its internal SPI state machine.

### The Solution: Lazy Switching with Full SD Recovery

The worker cog tracks which device currently owns the bus via `current_spi_device` (DAT LONG, values -1/0/1). Before dispatching each command, the worker checks the command code range:

```
SD commands:    codes 1-46   -> switch_to_sd()
Flash commands: codes 50-81  -> switch_to_flash()
```

Both switch functions contain early-exit guards -- if the bus is already configured for the target device, they return immediately. This means consecutive operations on the same device incur zero switching overhead.

### switch_to_flash(): PINCLEAR Teardown

When switching from SD to Flash, all four SPI pins must be fully cleared with `PINCLEAR()` to remove smart pin mode registers. Using `PINFLOAT()` instead would leave residual `P_SYNC_TX`/`P_SYNC_RX` configurations in the WRPIN registers, which intercept GPIO operations (`drvc`/`testp`) used by the Flash bit-bang engine.

This was discovered empirically during Phase 2 development: Flash reads returned corrupt data until `PINFLOAT` was replaced with `PINCLEAR`.

### switch_to_sd(): 7-Step reinitCard() Recovery

Switching from Flash back to SD requires a complete card re-initialization because Flash operations (toggling P60 as SCK) have driven the SD card's CS line through unpredictable states. The `reinitCard()` sequence:

1. **PINCLEAR all 4 pins** -- remove any residual smart pin or Flash GPIO state
2. **GPIO recovery flush** -- 4096 manual clock pulses at ~50 kHz to flush any partial transfer the SD card was stuck in
3. **Smart pin re-init at 400 kHz** -- reconfigure `P_TRANSITION`, `P_SYNC_TX`, `P_SYNC_RX`
4. **CMD0** -- reset card to idle (up to 5 retries)
5. **CMD8** -- restore SDHC/SDXC voltage acceptance
6. **ACMD41** -- re-initialize card (2-second timeout)
7. **CMD58 + speed restore** -- restore HCS addressing mode and operational SPI clock speed

Values cached from the initial `mount()` (`saved_acmd41_arg`, saved SPI speed) skip redundant discovery steps. All three sector caches (data, directory, FAT) are invalidated at the top of `reinitCard()`.

### Performance Impact

The expensive path (Flash-to-SD switch with full reinitCard) takes approximately 50-100ms depending on the card. The lazy switching design ensures this cost is paid only on actual device transitions, not on every command. Applications that batch Flash operations followed by SD operations pay the switching cost once per batch.

### Decision

**Use lazy SPI bus switching with PINCLEAR teardown and 7-step SD recovery.** Worker cog exclusivity (only one cog touches SPI pins) eliminates bus contention. The cross-wired pin arrangement is an inherent hardware constraint of the P2 Edge Module; the driver handles it transparently.

Full analysis: `DOCs/Analysis/SPI-BUS-STATE-ANALYSIS.md`

---

## Decision 3: Unified API with Device Parameter

### The Problem

The standalone SD driver and standalone Flash driver have different APIs. The SD driver uses FAT32 conventions (`openFileRead`, `openFileWrite`, `readString`), while the Flash driver uses C-style conventions (`open` with mode parameter, `rd_byte`, `wr_byte`). Callers working with both devices would need to learn two APIs and write device-specific code paths.

### The Solution: Single API with DEV Parameter

Every file operation in the dual driver takes a `dev` parameter as its first argument:

```spin2
CON
  DEV_SD    = 0       ' microSD card (FAT32)
  DEV_FLASH = 1       ' Onboard 16MB Flash chip
  DEV_BOTH  = 2       ' Both devices (for mount/unmount)
```

The PUB method routes internally via `case dev`:

```spin2
PUB exists(dev, p_filename) : found
  case dev
    DEV_SD:
      ' ... SD implementation via send_command(CMD_SD_EXISTS, ...)
    DEV_FLASH:
      ' ... Flash implementation via send_command(CMD_FLASH_EXISTS, ...)
    other:
      found := false
```

### API Harmonization Decisions

Where the two drivers had different conventions, the dual driver chose one:

| Aspect | SD Original | Flash Original | Dual Driver Choice |
|---|---|---|---|
| Open file | `openFileRead()`, `openFileWrite()` | `open(mode)` | Both: `open(dev, name, mode)` for Flash-style; `openFileRead(dev, name)` / `openFileWrite(dev, name)` preserved for SD convenience |
| Close file | `closeFile(handle)` | `close(handle)` | `close(handle)` -- handle carries device info |
| Delete file | `deleteFile(name)` | `delete(name)` | `deleteFile(dev, name)` |
| File existence | `fileExists(name)` | `exists(name)` | `exists(dev, name)` |
| Mount | `mount(cs, mosi, miso, sck)` | `mount()` | `mount(dev, cs, mosi, miso, sck)` |

### Handle-Based Operations Need No Device Parameter

Once a file is opened, the handle carries its device identity in `h_device[handle]`. Operations like `read()`, `write()`, `close()`, and `seek()` take only the handle -- the driver routes internally based on the stored device.

### Flash-Only Operations

Some operations exist only on Flash (circular files, `create_file` pre-allocation). These accept `dev` but return `E_NOT_SUPPORTED` if called with `DEV_SD`. This keeps the API uniform while being explicit about device capabilities.

### Decision

**Use a unified API with `dev` parameter for all device-level operations.** Handle-based operations route automatically via `h_device[]`. This lets callers write device-agnostic code (e.g., copy a file from SD to Flash using the same read/write calls with different handles).

---

## Decision 4: Shared Handle Pool with Device Tracking

### The Problem

The standalone drivers each managed their own handles independently. Merging them raises the question: should the dual driver maintain separate handle pools (N handles for SD, M handles for Flash) or a single shared pool?

### The Solution: Single Pool, Device-Tagged

The dual driver uses one pool of `MAX_OPEN_FILES` handles (default 6, user-overridable). Each handle slot has an `h_device[]` entry recording whether it belongs to DEV_SD or DEV_FLASH:

```spin2
DAT
  h_device      BYTE    0[MAX_OPEN_FILES]     ' DEV_SD or DEV_FLASH
  h_flags       BYTE    0[MAX_OPEN_FILES]     ' HF_FREE, HF_READ, HF_WRITE, HF_DIR
  h_position    LONG    0[MAX_OPEN_FILES]     ' Current byte position
  ' ... other per-handle state
```

When a file is opened, the driver finds the first `HF_FREE` slot regardless of device. When a handle operation arrives (read, write, seek, close), the driver checks `h_device[handle]` to route to the correct implementation.

### Why Shared, Not Separate

| Factor | Separate Pools | Shared Pool |
|---|---|---|
| Flexibility | Fixed split (e.g., 3 SD + 3 Flash) | Dynamic allocation based on actual use |
| Memory | Same total | Same total |
| Configuration | Two parameters to tune | One parameter (`MAX_OPEN_FILES`) |
| Typical use case | Often unbalanced (4 SD files, 1 Flash) | Adapts automatically |

Embedded applications typically have asymmetric access patterns -- heavy SD file I/O with occasional Flash config reads, or vice versa. A shared pool lets all 6 handles go to whichever device needs them.

### SD vs Flash Handle State

SD handles use FAT32 state (cluster chain, directory sector, per-handle 512-byte sector buffer). Flash handles use block chain state (head block ID, chain block, lifecycle, seek pointer). Both state sets are indexed by the same handle number, with parallel arrays:

- SD state: `h_sector[]`, `h_cluster[]`, `h_start_clus[]`, `h_buf[]` (512B each)
- Flash state: `fl_hHeadBlockID[]`, `fl_hChainBlockID[]`, `fl_hSeekPtr[]`, `fl_hFilename[]`

This means each handle slot carries both SD and Flash state arrays, but only one set is active at a time (determined by `h_device[]`). The memory overhead of unused parallel arrays is small (~180 bytes per handle for the inactive device's state).

### Decision

**Use a single shared handle pool with `h_device[]` device tracking.** One `MAX_OPEN_FILES` parameter controls total capacity. Handle-based operations route via `h_device[handle]` to the correct SD or Flash implementation.

---

## Decision 5: Decoupled Flash Buffer Pool

### The Problem

Flash files require 4KB block buffers for read/write operations (the Flash chip's erase unit is 4KB). Initially, the driver allocated one 4KB buffer per handle (`MAX_OPEN_FILES` x 4096 bytes). With 6 handles, this consumed 24KB of hub RAM just for Flash buffers -- even though most handles are typically used for SD files (which have their own 512-byte buffers).

### The Solution: Separate Buffer Pool

The `MAX_FLASH_BUFFERS` parameter (default 3, user-overridable) controls Flash buffer allocation independently of handle count:

```spin2
CON
  MAX_OPEN_FILES = 6          ' Total handles (SD + Flash)
  MAX_FLASH_BUFFERS = 3       ' Flash block buffers (independent)

DAT
  fl_buf_owner     BYTE    $FF[MAX_FLASH_BUFFERS]    ' Handle owning each buffer ($FF = free)
  fl_hBufIndex     BYTE    $FF[MAX_OPEN_FILES]       ' Buffer index per handle ($FF = none)
  fl_hBlockBuff    BYTE    0[MAX_FLASH_BUFFERS * BLOCK_SIZE]  ' 3 x 4096 = 12KB
```

When a Flash file is opened, it acquires a buffer from the pool (`fl_buf_owner[]`). When closed, the buffer returns to the pool. Flash operations that don't need buffers (exists, delete, rename, stats, directory listing) work with zero buffers allocated.

### Memory Savings

| Configuration | Old (Coupled) | New (Decoupled) |
|---|---|---|
| 6 handles, 3 Flash buffers | 6 x 4096 = 24,576 bytes | 3 x 4096 = 12,288 bytes |
| 6 handles, 0 Flash buffers (SD-only build) | 24,576 bytes | 0 bytes |

The decoupling saved 12KB in the default configuration and enables SD-only builds with `MAX_FLASH_BUFFERS = 0` (Flash mount still works for metadata, but `open()` fails).

### Decision

**Decouple Flash buffer pool from handle count.** `MAX_FLASH_BUFFERS` defaults to 3 (read + write + spare for Flash-to-Flash copy). Binary size dropped from 80,058 to 67,974 bytes (-12KB).

---

## Decision 6: Per-Cog Current Working Directory for Both Devices

### The Problem

The P2 supports up to 8 cogs running concurrently. Multiple cogs may access the filesystem simultaneously, each working in different directories. A single global CWD would create conflicts -- Cog 0 doing `chdir("logs")` would affect Cog 1's file operations.

### The Solution: Per-Cog CWD on Both Devices

**SD**: The FAT32 implementation tracks per-cog CWD natively via `root_dir_sector[8]` and `current_dir_start_cluster[8]` -- one slot per possible cog, indexed by `COGID()`. The SD `chdir()` updates only the calling cog's slot. Path resolution uses the calling cog's directory context.

**Flash**: Since Flash has no real directories (Decision 1), per-cog CWD is emulated via a string prefix table:

```spin2
DAT
  fl_cog_cwd    BYTE    0[8 * FL_FILENAME_SIZE]   ' 128 bytes per cog, 8 cogs = 1KB
```

Each cog's CWD is a string like `"logs"` or `"data/2026"`. The `fl_prepend_cwd()` helper reads the calling cog's slot (`COGID() << FL_FILENAME_SIZE_EXP`) and prepends it to filenames before sending commands to the worker cog.

### Thread Safety

The per-cog CWD arrays live in DAT (shared memory), but each cog only reads/writes its own slot (indexed by `COGID()`). No locking is needed for CWD access -- the hardware lock (`api_lock`) only serializes the command parameter block, not CWD state.

The CWD prepending happens in the PUB method (caller cog context) before `send_command()`, so the worker cog receives fully-qualified paths. This is important because `COGID()` in the worker cog returns the worker's cog ID, not the caller's.

### Decision

**Maintain per-cog CWD for both devices.** SD uses native FAT32 directory tracking arrays. Flash uses `fl_cog_cwd[]` string prefix table with `fl_prepend_cwd()` path construction. Both are indexed by `COGID()` for zero-contention concurrent access.

---

## Decision 7: Driver-Internal Path Resolution

### The Problem

Early versions of the driver required the caller (e.g., the demo shell) to manually navigate to a file's parent directory before performing file operations. For a path like `/logs/data.txt`, the shell had to `chdir("/logs")`, perform the operation, then `chdir` back. This pushed path-handling complexity into every caller application.

### The Solution: Resolve Paths Inside the Driver

**SD**: The `sd_resolve_path()` / `sd_restore_path()` helper pair handles full paths within the worker cog's `do_*()` methods. `sd_resolve_path()` navigates to the target directory (saving the current directory sector), extracts the leaf filename, and returns a pointer to it. After the operation completes, `sd_restore_path()` restores the original directory context. Nine SD `do_*()` methods use this pattern:

```
do_open_read(), do_open_write(), do_create_new(), do_delete(), do_rename(),
do_exists(), do_file_size(), do_open_dir(), do_mkdir()
```

**Flash**: Path resolution was already handled by `fl_prepend_cwd()` in the PUB methods (caller cog context). Flash paths are simple string concatenation -- no directory traversal needed because the Flash filesystem is flat (Decision 1).

### Why Worker-Cog Resolution for SD

SD path resolution requires reading directory sectors (FAT32 directory traversal), which involves SPI transfers. SPI transfers must run in the worker cog (the architectural constraint from the standalone driver). Therefore, SD path resolution must happen inside the `do_*()` PRI methods that run in the worker cog, not in the PUB methods that run in the caller cog.

Flash path resolution is pure string manipulation (no SPI), so it can safely run in the caller cog via `fl_prepend_cwd()`.

### Decision

**Resolve paths internally in the driver.** SD uses `sd_resolve_path()`/`sd_restore_path()` in worker-cog `do_*()` methods. Flash uses `fl_prepend_cwd()` in caller-cog PUB methods. Callers pass full paths (e.g., `"/logs/data.txt"`) and the driver handles navigation transparently.

Plan: `DOCs/Plans/Driver-Path-Resolution-Plan.md`

---

## Decision 8: Circular Files -- Flash Only, SD Deferred

### The Problem

The reference Flash filesystem (`flash_fs.spin2`) natively supports circular files -- files that automatically discard their oldest blocks when they exceed a maximum size, creating a rolling data log. This is valuable for embedded data logging (sensor data, event logs) where storage is limited and old data should be automatically aged out.

The SD FAT32 filesystem has no native circular file concept. Implementing it would require:
- Tracking the circular length and head position in FAT32 metadata (no standard location)
- Modifying the cluster chain to wrap around or truncate from the head
- Handling the FAT table updates for head-block removal during writes
- Ensuring the directory entry's file size reflects the circular window, not total bytes written

### The Decision: Implement on Flash, Defer for SD

The dual driver exposes `open_circular(dev, p_filename, mode, max_file_length)` but restricts it to `DEV_FLASH`:

```spin2
PUB open_circular(dev, p_filename, mode, max_file_length) : handle
  if dev <> DEV_FLASH
    handle := E_NOT_SUPPORTED
```

The Flash implementation (`fl_open_circular()`, line ~7943) is a direct port of the reference driver's circular file support, which uses the block chain's lifecycle counter and head-block trimming to maintain the size limit.

### Why Defer SD Circular Files

1. **No standard mechanism**: FAT32 has no metadata field for circular length or head position. Any implementation would be non-standard and invisible to other systems reading the card.
2. **Complexity vs. value**: The primary use case (data logging) is well-served by Flash circular files. SD cards are typically used for larger, non-circular files (configuration, firmware images, exported data).
3. **Risk**: Modifying FAT32 cluster chains for circular behavior risks filesystem corruption if the implementation has edge cases. The FAT32 driver is battle-tested for standard operations.

### Future Path

If SD circular files become needed, the recommended approach is:
- Application-level circular management (caller tracks head position, truncates old data)
- Or a custom file header within the file data (first sector stores circular metadata)

Neither approach requires driver changes.

### Decision

**Support circular files on Flash only. Return `E_NOT_SUPPORTED` for SD.** The Flash block chain architecture naturally supports head-block trimming. SD FAT32 circular files are deferred indefinitely as the use case is well-served by Flash.

---

## Decision 9: Card Presence Detection via P2 Internal Pull-Up

### The Problem

The P2 Edge Module's microSD socket has no card-detect pin. The SD specification (Section 6.2) defines card detection via a mechanical switch, but this hardware is not available. The SD spec defines no software-only detection method for SPI mode. Without detection, a missing card causes the driver to hang or return a generic timeout error.

### The Electrical Insight

The key distinction is on the MISO line:

| Scenario | MISO Behavior |
|---|---|
| Card present, CS asserted | Card actively drives MISO (responds within 0-8 bytes) |
| No card, with pull-up | MISO reads steady $FF (no driver on the line) |
| No card, floating | MISO reads electrical noise (unreliable) |

A pull-up resistor on MISO converts the "no card" case from unpredictable noise to a reliable, definitive $FF.

### The P2 Advantage: Built-In Pull Resistors

Every P2 I/O pin has configurable internal pull resistors. The driver enables `P_HIGH_15K` (15K ohm) on MISO before the CMD0 probe:

- **15K is ideal**: Strong enough for reliable $FF reads with no card, weak enough that a card's ~100 ohm output impedance easily overpowers it during normal operation.
- **Self-contained**: No external resistors needed on any P2 board design.
- **Auto-cleared**: The pull-up is removed when `initSPIPins()` reconfigures MISO as a smart pin for SPI operation.

### The Detection Sequence

During `initCard()`, before the standard CMD0 initialization:

1. Enable `P_HIGH_15K` pull-up on MISO, float pin as input
2. Wait 10us for pull-up to settle
3. Send 74+ clock pulses (standard power-on sequence)
4. Send CMD0 up to 5 times, tracking `got_response` flag
5. If all CMD0 attempts return $FF (timeout) -- `got_response` stays false -- return `E_NO_CARD`
6. If any non-$FF response received but not $01 -- card present but not initializing -- return `E_BAD_RESPONSE`
7. If $01 received -- card present and idle, continue normal initialization

### Error Code

```spin2
CON
  E_NO_CARD = -8    ' No card detected in slot (MISO idle during CMD0 probe)
```

This sits in the card-level error range, providing callers a specific, actionable error distinct from generic timeouts or mount failures.

### Decision

**Detect card presence using P2 internal 15K pull-up on MISO combined with CMD0 timeout analysis.** This is self-contained (no external hardware), electrically definitive ($FF from pull-up vs. card-driven response), and SD-spec-compliant (behavioral detection is the only available SPI-mode approach).

Procedure: `DOCs/procedures/card-presence-detection-procedure.md`

---

## Summary: Dual-Driver Architecture Decisions

| # | Decision | Why (Dual-Driver Specific) |
|---|---|---|
| 1 | Flash directory emulation via slash convention | API parity without changing Flash block engine |
| 2 | Lazy SPI bus switching with PINCLEAR + reinitCard | P60/P61 cross-wiring corrupts SD state during Flash ops |
| 3 | Unified API with DEV parameter | One API for both devices; callers write device-agnostic code |
| 4 | Shared handle pool with device tracking | Dynamic allocation adapts to asymmetric access patterns |
| 5 | Decoupled Flash buffer pool | Saved 12KB; enables SD-only builds with zero Flash buffers |
| 6 | Per-cog CWD for both devices | Multi-cog concurrent access without CWD conflicts |
| 7 | Driver-internal path resolution | Callers pass full paths; driver handles navigation |
| 8 | Circular files Flash-only, SD deferred | Flash block chain supports it natively; FAT32 has no standard mechanism |
| 9 | Card presence detection via P2 pull-up | No card-detect pin; P2 internal pull-up makes MISO behavior definitive |

These decisions work together to create a dual-device driver where:
- **Callers see one API** -- the `dev` parameter is the only difference between SD and Flash operations
- **Flash behaves like SD** -- directory emulation and CWD support make both devices feel identical
- **Bus sharing is transparent** -- lazy switching and reinitCard hide the hardware complexity
- **Resources are efficient** -- shared handles and decoupled buffers minimize hub RAM usage

---

*Document created: 2026-03-07*
*Scope: Decisions specific to the dual-driver merge (SD + Flash into one driver)*
*For standalone SD driver decisions (worker cog, smart pins, streamer, etc.), see the sister project*
