# Measuring Program Memory Consumption with pnut-ts

A practical guide to determining how much hub RAM your Spin2 program and its component objects consume -- code space, data space, variable space, and total runtime footprint -- using the pnut-ts compiler's `-m` (map) and `-l` (listing) output files.

This document also serves as the **current shipping memory footprint reference** for the P2-uSD-FAT32-FS driver. All example numbers reflect the driver as of v1.3.0 (DFS), SD sub-driver v1.5.0 (2026-04-02).

- **Compiler**: pnut-ts v1.53.2+
- **Author**: Stephen M. Moraco, Iron Sheep Productions, LLC

---

## Table of Contents

1. [Background: P2 Hub RAM and Spin2 Object Layout](#1-background-p2-hub-ram-and-spin2-object-layout)
2. [Generating Map and Listing Files](#2-generating-map-and-listing-files)
3. [Reading the Map File](#3-reading-the-map-file)
4. [Reading the Listing File](#4-reading-the-listing-file)
5. [Calculating Total Runtime Hub RAM](#5-calculating-total-runtime-hub-ram)
6. [Comparing Build Configurations](#6-comparing-build-configurations)
7. [Analyzing a Multi-Object Program](#7-analyzing-a-multi-object-program)
8. [Sizing Audit Methodology](#8-sizing-audit-methodology)
9. [SD vs Flash Size Breakdown](#9-sd-vs-flash-size-breakdown)
10. [Quick Reference](#10-quick-reference)

---

## 1. Background: P2 Hub RAM and Spin2 Object Layout

The Propeller 2 has **512 KB of hub RAM**. Every Spin2 program must fit within this space along with its runtime data. Understanding what consumes that space is critical for larger projects.

A compiled Spin2 program consists of three memory regions loaded into hub RAM:

| Region | Contents | When Allocated |
|---|---|---|
| **Code/Data** | Method table + DAT sections + Spin2 bytecodes, for all objects | At load time (fixed) |
| **VAR** | Instance variables declared in `VAR` blocks, for all object instances | At load time (fixed) |
| **Stack** | Call stack for each running COG (not in the binary) | At runtime |

The **binary file** (.bin) includes the code/data region plus a ~6 KB P2 loader stub. The VAR region is not stored in the binary -- it is allocated in hub RAM at load time immediately following code/data.

### Object Structure Within Code/Data

Each Spin2 object occupies a contiguous block within the code/data region:

```
+-------------------+
| Method Table      |  N entries x 4 bytes (method count + 1 for header)
+-------------------+
| DAT Section       |  Static data: buffers, constants, PASM, state variables
+-------------------+
| Bytecodes         |  Compiled Spin2 method bodies
+-------------------+
```

Objects are concatenated in the binary in the order the compiler encounters them during OBJ resolution. The top-level object comes first, followed by its children recursively.

---

## 2. Generating Map and Listing Files

The pnut-ts compiler has two diagnostic output flags:

| Flag | Output File | Purpose |
|---|---|---|
| `-m` | `.map` | Memory map: object hierarchy, memory layout, per-object details (methods, DAT variables, VAR variables, sizes) |
| `-l` | `.lst` | Listing: symbol table (constants, method names, struct definitions with values) |

### Basic Usage

```bash
# Generate map file alongside the binary
pnut-ts -m my_program.spin2

# Generate both map and listing
pnut-ts -l -m my_program.spin2

# With include paths and preprocessor defines
pnut-ts -m -I .. -I ../UTILS -D SD_INCLUDE_ALL my_program.spin2

# With debug enabled (adds debug records -- larger binary)
pnut-ts -m -d my_program.spin2
```

The output files are written next to the source file:
- `my_program.map`
- `my_program.lst`
- `my_program.bin`

### Analyzing a Driver or Library Object in Isolation

To measure a library object's footprint without any consumer program, compile it as top-level. Most library objects have a `PUB null()` placeholder method as entry point 0, which allows standalone compilation:

```bash
# Driver alone -- minimal build (no optional features)
pnut-ts -m dual_sd_fat32_flash_fs.spin2

# Driver alone -- full build (all optional features)
pnut-ts -m -D SD_INCLUDE_ALL dual_sd_fat32_flash_fs.spin2
```

This tells you the object's intrinsic size before any consumer adds its own code.

---

## 3. Reading the Map File

The map file (`.map`) is the primary tool for memory analysis. It has five sections.

### 3.1 Program Summary

```
=== PROGRAM SUMMARY ===

  Total Size:    70072 bytes (69696 code/data + 376 var bytes)
  Objects:       4
  Methods:       401
```

This is your top-level answer: **total hub RAM consumed** = code/data + VAR. The binary file will be larger than the code/data value because it includes the P2 loader stub (~6 KB).

### 3.2 Object Hierarchy

```
=== OBJECT HIERARCHY ===

  DFS_SD_RT_mount_tests  (1 methods)
      \-- UTILS : isp_stack_check  (332 methods)
          \-- child_0 : object_5
```

This shows the tree of objects, their instance names, and how many methods each contributes. Use this to understand which objects are included and their nesting.

### 3.3 Memory Layout

```
=== MEMORY LAYOUT ===

  Start   End      Size  Object           Instance         Overrides
  ------  ------  -----  ---------------  ---------------  ---------
  $00000  $0096E   2415  DFS_SD_RT_mount_tests  (entry)
  $00970  $0137D   2574  dual_sd_fat32_flash_fs  (entry)
  $01380  $10EBD  64318  isp_stack_check  UTILS
  $10EC0  $1103C    381  DFS_RT_utilities  (entry)

    CODE/DATA TOTAL:   69696 bytes

  $11040  $111B7    376  VAR SPACE        (runtime)

    PROGRAM TOTAL:     70072 bytes
```

This is the key table. It shows:
- **Address range** (`Start` to `End`) of each object within hub RAM
- **Size** of each object in bytes (code + DAT combined)
- The **VAR SPACE** line shows total runtime variable allocation across all objects

From this table you can immediately answer: "How much space does object X add to my program?" In this example, `isp_stack_check` embeds the dual-FS driver and the test utilities as child objects, so its 64,318 bytes includes the driver's full footprint.

### 3.4 Object Details

Each object gets a detailed breakdown:

#### Methods Section

```
--- DFS : dual_sd_fat32_flash_fs ---
    Location: $00970-$0F128 (61737 bytes)
    VAR Base: $11040
    Source:   dual_sd_fat32_flash_fs.spin2

    Methods:
      NULL                  Entry $00000  ($008CC)
      INIT                  Entry $00001  ($008CD)
      STOP                  Entry $00002  ($008CE)
      MOUNT                 Entry $00003  ($008CF)
      CANMOUNT              Entry $00006  ($008D2)
      ...
```

- **Location**: absolute address range and total size (code + DAT)
- **VAR Base**: where this object's VAR variables start in hub RAM
- **Entry numbers**: each method's index in the method table
- **Absolute addresses** (in parentheses): hub address of each method's entry in the table

#### DAT Section

```
    DAT:
      LONG      COG_ID                +$0055C  ($0055C)
      LONG      API_LOCK              +$00560  ($00560)
      LONG      SD_MOUNTED            +$00568  ($00568)
      LONG      FLASH_MOUNTED         +$0056C  ($0056C)
      LONG      COG_STACK             +$00635  ($00635)
      LONG      COG_STACK_GUARD       +$008B5  ($008B5)
      BYTE      DIR_BUF               +$00A06  ($00A06)
      BYTE      FAT_BUF               +$00C06  ($00C06)
      BYTE      BUF                   +$00E06  ($00E06)
      BYTE      H_BUF                 +$012E0  ($012E0)
      LONG      H_BUF_SECTOR          +$01EE0  ($01EE0)
      WORD      FL_IDTOBLOCKS         +$01EFC  ($01EFC)
      BYTE      FL_HBLOCKBUFF         +$03FAB  ($03FAB)
      BYTE      FL_TMPBLOCKBUFF       +$06FAB  ($06FAB)
```

Each DAT variable shows:
- **Type** (`LONG`, `WORD`, `BYTE`)
- **Name** (the label from your source code)
- **Relative offset** (`+$xxxx`) within the object
- **Absolute address** (`($xxxx)`) in hub RAM

To calculate the size of a DAT variable, subtract its offset from the next variable's offset. For arrays and buffers, this reveals their actual footprint:

```
H_BUF    at +$012E0
H_BUF_SECTOR at +$01EE0
  => H_BUF size = $01EE0 - $012E0 = $0C00 = 3,072 bytes (6 handles x 512 bytes)
```

#### VAR Section

```
--- UTILS : isp_rt_utilities ---
    VAR:
      LONG      NUMBERTESTS           +$0004  ($0FBC0)
      LONG      SUBTESTPER            +$0008  ($0FBC4)
      LONG      PASSCOUNT             +$000C  ($0FBC8)
      LONG      FAILCOUNT             +$0010  ($0FBCC)
      BYTE      FILENAME              +$0020  ($0FBDC)
```

VAR variables use the same format as DAT. These consume runtime hub RAM but are NOT stored in the binary file.

#### Inline PASM Labels

```
    PASM Labels:
      ENTRY_BUFFER          COG $003  HUB $00988

    Inline PASM:
      WAITRX'0176           +$00A  ($00028)
```

If your object contains inline PASM (`org / end`), the map shows COG-space labels and inline PASM block locations. These don't add extra hub RAM -- the PASM is part of the bytecode/DAT already accounted for.

### 3.5 Address Index

```
=== ADDRESS INDEX ===

  Address  Type      Object                  Name
  -------  --------  ----------------------  ---------------
   $00000  CODE      DFS_SD_RT_mount_tests   (entry)
   $00980  CODE      dual_sd_fat32_flash_fs  DFS
   $00980  METHOD    dual_sd_fat32_flash_fs  NULL
   $00981  METHOD    dual_sd_fat32_flash_fs  INIT
   ...
```

A cross-reference of every symbol by address. Useful for locating a specific symbol when you know its address from a crash dump or debug output, but not essential for sizing analysis.

---

## 4. Reading the Listing File

The listing file (`.lst`) contains the symbol table -- every named constant, method, structure, and object reference with its resolved value.

```
TYPE: CON_INT           VALUE: 14DC9380          NAME: _CLKFREQ
TYPE: CON_INT           VALUE: 00000038          NAME: BASE_PIN
TYPE: OBJ               VALUE: 00000000          NAME: DFS
TYPE: OBJ               VALUE: 01000001          NAME: UTILS
TYPE: OBJ_CON_INT       VALUE: 00000006          NAME: MAX_OPEN_FILES,01
TYPE: OBJ_CON_INT       VALUE: FFFFFFEC          NAME: E_NOT_MOUNTED,01
TYPE: OBJ_CON_STRUCT    VALUE: 00000003          NAME: DIR_ENTRY_T,01
TYPE: OBJ_PUB           VALUE: 00000013          NAME: MOUNT,01
TYPE: OBJ_PRI           VALUE: 0006F000          NAME: DO_MOUNT,01
```

### Symbol Types

| Type | Meaning |
|---|---|
| `CON_INT` | Integer constant defined in this object's CON block |
| `OBJ` | Child object reference (value encodes instance index) |
| `OBJ_CON_INT` | Constant exported from a child object (suffix `,01` = first child object) |
| `OBJ_CON_STRUCT` | Structure type defined in a child object |
| `OBJ_PUB` | Public method in a child object (value encodes method index + parameter info) |
| `OBJ_PRI` | Private method in a child object |

### When to Use the Listing File

The listing file is less useful for sizing analysis than the map file. Its primary uses are:

- **Verifying constant values**: confirming that preprocessor defines resolved correctly
- **Checking conditional compilation**: if `SD_INCLUDE_RAW` is not in the listing, those methods were excluded
- **Method index lookup**: confirming which method index corresponds to which name (useful when debugging method dispatch)

For memory sizing, the **map file is the primary tool**.

---

## 5. Calculating Total Runtime Hub RAM

The binary file size is NOT your runtime memory footprint. Runtime hub RAM usage is:

```
Runtime Hub RAM = Code/Data + VAR + Stacks
```

The map file gives you the first two directly from the PROGRAM SUMMARY line. Stacks must be accounted for separately.

### Stack Estimation

Every COG running Spin2 code needs a stack. The top-level COG uses the remainder of hub RAM above the program as its stack. Additional COGs launched with `cogspin()` use explicitly allocated stack buffers (typically declared in DAT or VAR).

Look for stack allocations in the map's DAT section:

```
LONG      COG_STACK             +$00635  ($00635)
LONG      COG_STACK_GUARD       +$008B5  ($008B5)
  => Stack size = $008B5 - $00635 = $0280 = 640 bytes (160 LONGs)
```

The dual-FS driver allocates a 640-byte stack for its worker COG. The `COG_STACK_GUARD` variable at the end allows runtime detection of stack overflow. The stack was sized via a full audit across all 32 standard test suites (peak measured: 127 LONGs).

### Complete Accounting Example

For a test program like `DFS_SD_RT_mount_tests`:

```
Code/Data:           69,696 bytes   (from map: CODE/DATA TOTAL)
VAR:                    376 bytes   (from map: VAR SPACE size)
                    ---------
Program Total:       70,072 bytes

P2 Hub RAM:         524,288 bytes   (512 KB)
Available:          454,216 bytes   (for main COG stack + other uses)
```

The driver's DAT section contains most of the static data -- SD sector buffers, Flash translation tables, and handle buffers -- so VAR is minimal in typical programs.

---

## 6. Comparing Build Configurations

The dual-FS driver supports conditional compilation via preprocessor defines. To measure the cost of optional features, generate map files for each configuration and compare:

```bash
# Minimal build (no optional SD features)
pnut-ts -m dual_sd_fat32_flash_fs.spin2
# => Total Size: 61,744 bytes (61,740 code/data + 4 var bytes), 278 methods

# Full build (all optional SD features)
pnut-ts -m -D SD_INCLUDE_ALL dual_sd_fat32_flash_fs.spin2
# => Total Size: 67,401 bytes (67,397 code/data + 4 var bytes), 368 methods
```

Comparison:

| | Minimal | Full | Delta |
|---|---|---|---|
| Methods | 278 | 368 | +90 |
| Code/Data | 61,740 B | 67,397 B | +5,657 B |
| VAR | 4 B | 4 B | +0 B |

The DAT section is identical in both builds (data doesn't change). Only method table entries and bytecodes are added by optional features. This tells you the conditional compilation gates affect only code, not static data.

The optional feature groups are:

| Define | What It Adds |
|---|---|
| `SD_INCLUDE_RAW` | Raw sector read/write, VBR read |
| `SD_INCLUDE_REGISTERS` | Card register access (CID, CSD, SCR, SD Status, OCR) |
| `SD_INCLUDE_SPEED` | High-speed mode switching (CMD6) |
| `SD_INCLUDE_DEBUG` | Debug/diagnostic methods, CRC getters |
| `SD_INCLUDE_ASYNC` | Non-blocking I/O (startReadHandle, startWriteHandle, isComplete, getResult) |
| `SD_INCLUDE_DEFRAG` | Defragmentation (fileFragments, compactFile, createFileContiguous) |
| `SD_INCLUDE_ALL` | All of the above |

---

## 7. Analyzing a Multi-Object Program

Real programs include multiple objects. The map file shows each object's contribution:

```
=== MEMORY LAYOUT ===

  Start   End      Size  Object           Instance
  ------  ------  -----  ---------------  ---------
  $00000  $0096E   2415  DFS_SD_RT_mount_tests  (entry)
  $00970  $0137D   2574  dual_sd_fat32_flash_fs  (entry)
  $01380  $10EBD  64318  isp_stack_check  UTILS
  $10EC0  $1103C    381  DFS_RT_utilities  (entry)

    CODE/DATA TOTAL:   69696 bytes

  $11040  $111B7    376  VAR SPACE        (runtime)

    PROGRAM TOTAL:     70072 bytes
```

### Per-Object Breakdown

To understand where your memory is going, extract each object's contribution:

| Object | Code/Data | % of Total |
|---|---|---|
| DFS_SD_RT_mount_tests (top-level) | 2,415 B | 3.5% |
| dual_sd_fat32_flash_fs (driver stub) | 2,574 B | 3.7% |
| isp_stack_check (driver + test utils) | 64,318 B | 92.3% |
| DFS_RT_utilities (test framework) | 381 B | 0.5% |
| **Total** | **69,696 B** | **100%** |

Note: `isp_stack_check` wraps the dual-FS driver and test utilities as child objects, so its 64,318 bytes includes the driver's full footprint. The driver itself is ~66 KB standalone (with all optional features). To measure the driver in isolation, compile it as top-level (see Section 6).

### VAR Contributions

The Object Details section shows each object's VAR variables. The VAR SPACE line in the memory layout shows total VAR across all objects (376 bytes in this example).

The driver's minimal VAR (4 bytes) is by design -- nearly all state lives in DAT so the worker COG can access it directly. The test framework and stack check wrapper hold runtime counters and string buffers in VAR.

---

## 8. Sizing Audit Methodology

This section describes a repeatable process for auditing the memory footprint of any Spin2 project.

### Step 1: Isolate the Object Under Study

Compile the object standalone (as top-level) to measure its intrinsic footprint without consumer overhead:

```bash
# Minimal configuration
pnut-ts -m my_driver.spin2

# Full configuration (all optional features)
pnut-ts -m -D MY_INCLUDE_ALL my_driver.spin2
```

Record from the PROGRAM SUMMARY:
- Total code/data size
- Method count
- VAR size

### Step 2: Extract Region Sizes from the Map

Open the map file and calculate each region's size from the Object Details section. For a single-object build, the regions within the object are:

- **Method table**: from `$00000` to the first DAT variable's offset. Size = first DAT offset.
- **DAT section**: from first DAT variable to start of bytecodes. Calculate by subtracting first DAT offset from the bytecode start (which is method table size + DAT size up to the object's Location end minus bytecodes).
- **Bytecodes**: the remainder of the object after method table + DAT.

For a more direct approach: since the map shows every DAT variable with its offset, the DAT section spans from the first DAT variable's offset to the last DAT variable's offset plus that variable's size. Method table size = first DAT offset. Bytecodes = object total - method table - DAT.

### Step 3: Itemize the DAT Section

Walk the DAT variables in the map file. For each variable, compute its size by subtracting its offset from the next variable's offset:

```
COG_STACK        +$00635
COG_STACK_GUARD  +$008B5
  => COG_STACK is $0280 = 640 bytes (160 LONGs)
```

Group variables into logical categories (buffers, state, pin config, etc.) and total each category. This reveals which categories dominate. For example, in the dual-FS driver:

| Category | Key Variables | Approx. Size |
|---|---|---|
| Worker COG stack | COG_STACK | 640 B |
| SD sector buffers | DIR_BUF, FAT_BUF, BUF | 3 x 512 = 1,536 B |
| SD handle buffers | H_BUF (6 handles x 512 B) | 3,072 B |
| SD copy buffer | COPY_BUF | 512 B |
| Flash translation tables | FL_IDTOBLOCKS, FL_IDVALIDS, FL_BLOCKSTATES | ~8,200 B |
| Flash buffer pool | FL_HBLOCKBUFF (`MAX_FLASH_BUFFERS` x 4 KB, default 3) | 12,288 B |
| Flash buffer pool tracking | FL_BUF_OWNER + FL_HBUFINDEX | 9 B |
| Flash temp buffer | FL_TMPBLOCKBUFF | 4,096 B |
| Flash CWD per cog | FL_COG_CWD (8 x 128 B) | 1,024 B |

The Flash buffer pool and translation tables dominate. With `MAX_FLASH_BUFFERS` decoupled from `MAX_OPEN_FILES` (default 3 vs 6), the buffer pool is now 12,288 B instead of 24,576 B, saving ~12 KB.

### Step 4: Measure Real-World Programs

Compile several representative consumer programs that include the object and record their map summaries. This shows the object's impact in context:

```bash
pnut-ts -m -I .. my_app.spin2
```

For each program, record:
- Total binary size (.bin file)
- Code/Data total (from map)
- VAR total (from map)
- Runtime hub RAM = Code/Data + VAR

### Step 5: Compare Configurations

If the object supports conditional compilation, compile each configuration and tabulate the differences. This answers: "What does enabling feature X cost?"

### Step 6: Automate for Repeatability

For projects with many programs, create a benchmark script that compiles all top-level files and records size, checksum, and compile time:

```bash
# For each source file:
pnut-ts [flags] "$filename"
size=$(wc -c < "$binfile")
md5=$(md5 -q "$binfile")    # or md5sum on Linux
```

This produces a repeatable baseline. When you upgrade the compiler or refactor code, re-run the benchmark and diff against the previous run to detect size changes or binary drift.

---

## 9. SD vs Flash Size Breakdown

The unified driver combines two independent filesystems. This section quantifies each subsystem's contribution.

### Reference Driver Baselines

Compiling the original standalone drivers establishes a baseline for what each filesystem costs in isolation:

| Driver | Code/Data | Methods | DAT | Bytecodes |
|---|---|---|---|---|
| Ref SD (`micro_sd_fat32_fs`, full) | 23,024 B | 206 | 5,727 B | 16,469 B |
| Ref Flash (`flash_fs`) | 28,744 B | 85 | 20,122 B | 8,278 B |
| Sum of both | 51,768 B | 291 | 25,849 B | 24,747 B |
| **Unified driver** (full, default) | **67,397 B** | **368** | **~33,200 B** | **~32,800 B** |
| **Merging overhead** | **+15,629 B** | +77 | +7,351 B | +8,053 B |

The unified driver is 30% larger than the sum of the two reference drivers. Most of the remaining overhead is in DAT (static data) and additional methods for the unified API dispatch layer, diagnostic getters, and SPI bus switching.

### DAT Breakdown by Subsystem

The DAT section dominates the driver at ~33,200 bytes (49% of total code/data). Here is every significant allocation grouped by subsystem:

| Subsystem | DAT Item | Size |
|---|---|---|
| **Flash buffer pool** | `FL_HBLOCKBUFF` (`MAX_FLASH_BUFFERS` x 4,096 B, default 3) | 12,288 B |
| **Flash buffer tracking** | `FL_BUF_OWNER[3]` + `FL_HBUFINDEX[6]` | 9 B |
| **Flash translation tables** | `FL_IDTOBLOCKS` (file-to-block mapping) | 5,952 B |
| | `FL_BLOCKSTATES` (per-block state) | 992 B |
| | `FL_IDVALIDS` (per-file-ID valid flags) | 496 B |
| | Scratch LONGs (`FL_IDTOBLOCK`, etc.) | 12 B |
| **Flash temp buffer** | `FL_TMPBLOCKBUFF` (4,096 B block) | 4,096 B |
| **Flash handle state** | `FL_HSTATUS` through `FL_HFILENAME` (6 handles) | 906 B |
| **Flash misc** | `FL_COG_CWD` (8 cogs x 128 B) | 1,024 B |
| | `FL_DIR_ENTRY_NAME`, `FL_ERRORCODE`, etc. | 144 B |
| *Flash subtotal* | | *25,919 B (77%)* |
| **SD sector buffers** | `DIR_BUF`, `FAT_BUF`, `BUF` (3 x 512 B + pad) | 1,568 B |
| **SD handle buffers** | `H_BUF` (6 handles x 512 B) + `H_BUF_SECTOR` | 3,096 B |
| **SD handle state** | `H_DEVICE` through `H_CLUSTER` (6 handles) | 174 B |
| **SD metadata** | FAT pointers, cluster info, card state, diagnostics | 269 B |
| **SD copy buffer** | `COPY_BUF` (512 B for copyFile) | 512 B |
| *SD subtotal* | | *5,619 B (17%)* |
| **Shared** | Worker COG stack (160 LONGs) | 640 B |
| | State vars + IPC parameter block | 229 B |
| | Error message strings | ~696 B |
| *Shared subtotal* | | *~1,565 B (5%)* |
| **Total DAT** | | **~33,200 B** |

### Full Driver by Subsystem

Combining DAT with estimated bytecodes (proportioned from reference driver ratios):

| | SD | Flash | Shared | Total |
|---|---|---|---|---|
| DAT (buffers + state) | 5,619 B | 25,919 B | 1,645 B | 33,183 B |
| Bytecodes (est.) | ~22,300 B | ~8,700 B | ~1,740 B | ~32,740 B |
| Method table | -- | -- | 1,474 B | 1,474 B |
| **Total** | **~27,900 B (41%)** | **~34,600 B (51%)** | **~4,900 B (7%)** | **~67,400 B** |

Flash accounts for 51% of the driver. Flash bytecodes are smaller than SD bytecodes (8.7 KB vs 22.3 KB) because the Flash filesystem is structurally simpler. SD bytecodes grew with v1.2.0-v1.3.0 features (live clock, auto-flush, async I/O, defragmentation, CMD13/CMD23 probing, diagnostic getters).

> **Note**: These figures reflect default `MAX_FLASH_BUFFERS = 3`. Previous releases allocated one 4 KB buffer per handle (6 x 4,096 = 24,576 B). The buffer pool saves 12,288 bytes with identical functionality for typical applications.

### Sources of Merging Overhead

The 15,629-byte overhead from combining the two drivers into one:

| Source | Bytes | Notes |
|---|---|---|
| Flash buffer pool: 2 -> 3 slots | +4,096 B | 1 extra buffer x 4,096 B (pool decoupled from handles) |
| `FL_COG_CWD` (CWD emulation) | +1,024 B | 8 cogs x 128 B; not in ref Flash |
| `COPY_BUF` (cross-device copy) | +512 B | New for copyFile() |
| `FL_DIR_ENTRY_NAME` | +128 B | CWD directory enumeration buffer |
| `SAVED_DATA` arrays | +96 B | 3 x 8 LONGs for multi-cog IPC |
| Error message strings (Flash) | ~696 B | `string_for_error()` lookup table |
| Bus switching + dispatch bytecodes | ~5,200 B | Device routing, SPI mode switching, diagnostics |
| Async/defrag/timestamp bytecodes | ~2,700 B | v1.2.0-v1.3.0 features |
| Misc (pin vars, device tracking, pad) | ~1,167 B | |
| Flash buffer pool tracking | +9 B | `fl_buf_owner[3]` + `fl_hBufIndex[6]` |
| **Total** | **+15,629 B** | |

The reference Flash driver defaults to 2 open files (8 KB of buffers); the unified driver's pool of 3 buffers (12 KB) adds only 4 KB. The bus switching and dispatch overhead grew with v1.2.0-v1.3.0 features (live clock, auto-flush, async I/O, defragmentation, CMD13/CMD23 probing, diagnostic getters, card presence detection).

### Handle and Buffer Cost per Slot

Handles and Flash buffers are now independently sized:

| Resource | Per-Unit Cost | What It Controls |
|---|---|---|
| Handle (`MAX_OPEN_FILES`) | ~688 B | 28 B SD state + 512 B SD buffer + 148 B Flash state |
| Flash buffer (`MAX_FLASH_BUFFERS`) | 4,097 B | 4,096 B block buffer + 1 B owner tracking |

With the default configuration (6 handles, 3 buffers): 6 x 688 + 3 x 4,097 = 4,128 + 12,291 = 16,419 B for handle/buffer storage. Override in OBJ:

```spin2
OBJ
  fs : "dual_sd_fat32_flash_fs" | MAX_OPEN_FILES = 4, MAX_FLASH_BUFFERS = 2
```

| Use Case | MAX_OPEN_FILES | MAX_FLASH_BUFFERS | Total Handle+Buffer |
|---|---|---|---|
| SD-only system | 4 | 0 | 2,752 B |
| Typical dual-FS | 6 | 3 | 16,419 B |
| Flash-heavy | 6 | 5 | 24,613 B |
| Minimal embedded | 3 | 2 | 10,258 B |

---

## 10. Quick Reference

### Generate Files

```bash
pnut-ts -m program.spin2           # Map file only
pnut-ts -l -m program.spin2        # Map + listing
pnut-ts -m -D FLAG program.spin2   # Map with preprocessor define
pnut-ts -m -d program.spin2        # Map with debug enabled
```

### Key Map File Sections

| Section | What It Tells You |
|---|---|
| PROGRAM SUMMARY | Total size = code/data + VAR |
| OBJECT HIERARCHY | Which objects are included and their nesting |
| MEMORY LAYOUT | Per-object code/data size and address ranges |
| Object Details: Methods | Every method name and entry index |
| Object Details: DAT | Every DAT variable with offset and absolute address |
| Object Details: VAR | Every VAR variable with offset and absolute address |

### Size Formulas

```
Binary File Size    = Code/Data + P2 Loader Stub (~6 KB)
Runtime Hub RAM     = Code/Data + VAR + Stack allocations
Object Code/Data    = Method Table + DAT Section + Bytecodes
DAT Variable Size   = (next variable offset) - (this variable offset)
Available RAM       = 524,288 - Runtime Hub RAM
```

### What Lives Where

| Spin2 Block | Goes Into | In Binary? | In Map Section |
|---|---|---|---|
| `CON` | Resolved at compile time | No (inlined) | Listing file only |
| `OBJ` | Embedded as child objects | Yes | MEMORY LAYOUT + OBJECT HIERARCHY |
| `PUB` / `PRI` | Method table + bytecodes | Yes | Object Details: Methods |
| `DAT` | Static data in code/data region | Yes | Object Details: DAT |
| `VAR` | Allocated after code/data at load time | No | Object Details: VAR |

### Dual-FS Driver Quick Reference

| Build | Code/Data | Methods | Binary |
|---|---|---|---|
| Minimal (no defines) | 61,740 B | 278 | 70,886 B |
| Full (`SD_INCLUDE_ALL`) | 67,397 B | 368 | 76,543 B |
| Delta | +5,657 B | +90 | +5,657 B |

> Default `MAX_FLASH_BUFFERS = 3` (decoupled from `MAX_OPEN_FILES = 6`). Worker COG stack sized at 160 LONGs (640 bytes) based on measured peak of 127 LONGs.
