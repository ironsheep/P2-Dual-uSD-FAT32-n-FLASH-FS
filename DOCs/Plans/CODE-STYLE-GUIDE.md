# Spin2 Code Style Guide — pnut-ts / VS Code Documentation Conventions

**Version:** 1.0.0
**Applies to:** All `.spin2` files in P2 projects using pnut-ts compiler and VS Code with Spin2 extension
**Reference:** P2KB v3.4.0 documentation extraction standard

---

## Comment Types

Spin2 has four comment syntaxes. Two are "doc comments" that pnut-ts extracts to `.txt` interface documents and VS Code displays in IntelliSense. Two are regular comments that are never extracted.

| Syntax | Type | Extracted to .txt? | Use for |
|--------|------|:------------------:|---------|
| `''` | Doc comment (line) | **YES** | PUB method documentation ONLY |
| `'` | Non-doc comment (line) | No | PRI method docs, inline comments, CON/VAR/DAT annotations |
| `{{ }}` | Doc comment (block) | **YES** | File header block and end-of-file license block |
| `{ }` | Non-doc comment (block) | No | Internal explanations, multi-line non-public notes |

**Key rule:** `''` and `{{ }}` cause content to appear in the extracted interface document. Use them ONLY where extraction is intended — PUB methods, the file header, and the license block.

---

## File Header

Every `.spin2` file begins with a `{{ }}` doc-block containing:
- File name and purpose
- Author and copyright
- Card/hardware compatibility notes (if applicable)
- Quick-start usage examples

```spin2
{{┌──────────────────────────────────────────┐
  │ SD card driver V3 — Release v1.1.0       │
  │ Original: Chris Gadd, V3: S.M. Moraco    │
  │ Copyright (c) 2023 Chris Gadd            │
  └──────────────────────────────────────────┘

  sd.mount(CS, MOSI, MISO, SCK)              ' mount SD card
  h := sd.createFileNew(@"myfile.txt")        ' create file
  sd.writeHandle(h, @data, byteCount)         ' write data
  sd.closeFileHandle(h)                       ' close handle
}}
```

The end-of-file license block also uses `{{ }}` (extracted, but placed after all code).

---

## PUB Method Documentation (double apostrophe — extracted)

Every PUB method gets `''` doc comments immediately after the signature with no blank line between the signature and the first `''` line.

### Structure

1. **Description line** — one sentence starting with a verb phrase
2. **Blank `''` separator** — separates description from tags
3. **`@param` tags** — one per parameter, in signature order
4. **`@returns` tags** — one per return variable
5. **`@local` tags** — use `'` (single apostrophe, NOT `''`) since locals are internal

### Example

```spin2
PUB start(_cs, _mosi, _miso, _sck) : result
'' Start worker cog (singleton) - initialize SD card driver and launch dedicated worker cog.
'' This method is idempotent - calling multiple times is safe.
''
'' @param _cs - Chip select pin number
'' @param _mosi - Master Out Slave In pin number
'' @param _miso - Master In Slave Out pin number
'' @param _sck - Serial clock pin number
'' @returns result - Cog ID (0-7) on success, -1 on failure
```

### Rules

- **No `@returns` for void methods** — only document return values that exist
- **No `@local` with `''`** — local variables are internal; use `'` if documenting them
- **Match the signature exactly** — every `@param` name must match a parameter, every `@returns` name must match a return variable
- **Description reflects current behavior** — no stale references to removed APIs

---

## PRI Method Documentation (single apostrophe — NOT extracted)

PRI methods use `'` (single apostrophe) for all documentation. Same structural pattern as PUB but nothing is extracted to the interface document.

### Example

```spin2
PRI set_error(code) : code_out
' Set error code for this cog - store error code in per-cog slot and return the code.
'
' @param code - Error code to store
' @returns code_out - The same error code (for chained returns)
```

### With @local tags

```spin2
PRI fs_worker() | cur_cmd
' Worker cog main loop - runs in the dedicated worker cog.
' Owns the SPI pins and handles all filesystem operations.
'
' @local cur_cmd - Current command being processed
```

---

## Block Declaration Lines (VS Code Outline)

Comments placed on the same line as `CON`, `DAT`, `VAR`, `OBJ`, `PUB`, or `PRI` keywords appear in the VS Code Outline panel. These serve as navigation labels.

### Rules

- **Always use `'` (single apostrophe)** — never `''` on block declaration lines
- **Keep labels short and meaningful** — they are navigation aids, not documentation
- **Use dashes as section separators** when the label names a section

### Examples

```spin2
CON ' ---- Error Codes ----

CON ' driver mode (enforces valid command sequences)

DAT ' singleton control - SHARED across all object instances

VAR ' application state
```

### Section Dividers in Outline

Extra `CON` or `DAT` lines with descriptive comments can be injected purely for Outline navigation:

```spin2
CON ' ═══════════════════════════════════════════════════════════════════════════
    ' MULTI-COG LIFECYCLE METHODS
    ' ═══════════════════════════════════════════════════════════════════════════
```

The first line (`CON ' ═══...`) appears in the Outline. The indented lines below it provide context when reading the source but don't appear in the Outline.

---

## CON / VAR / DAT Declaration Comments

Individual constant, variable, and data declarations use `'` (single apostrophe) comments.

### Preceding vs. Trailing Comments

VS Code gives **higher hover priority** to a preceding comment (line above, no blank line gap) than to a trailing comment (same line). Use preceding comments for important descriptions and trailing comments for brief annotations.

```spin2
CON ' driver mode (enforces valid command sequences)
  ' Current operating mode of the driver
  MODE_NONE       = 0       ' Not initialized - only mount() or initCardOnly() allowed
  MODE_RAW        = 1       ' Raw sector access only - initCardOnly() was called
  MODE_FILESYSTEM = 2       ' Full filesystem access - mount() was called
```

### Enum Group Descriptions

Groups of related constants get a preceding group description:

```spin2
CON ' command codes for worker cog
  CMD_NONE      = 0         ' Idle / command complete
  CMD_MOUNT     = 1         ' Mount filesystem
  CMD_UNMOUNT   = 2         ' Unmount filesystem
```

### DAT Variables

```spin2
DAT ' singleton control - SHARED across all object instances
  cog_id        LONG    -1              ' Worker cog ID (-1 = not started)
  api_lock      LONG    -1              ' Hardware lock ID (-1 = not allocated)
  driver_mode   LONG    0               ' Current mode: MODE_NONE/MODE_RAW/MODE_FILESYSTEM
```

---

## Variable Naming

### No Single-Letter Names

Every variable name must describe what it holds. This applies to:
- Method parameters
- Return values
- Local variables
- DAT and VAR declarations

**Bad:**

```spin2
PRI scan(p, n) : r | i, c
```

**Good:**

```spin2
PRI scanDirectory(pEntry, maxEntries) : status | entryIdx, attrByte
```

### Exceptions

- Inline PASM register names follow hardware conventions (e.g., `pa`, `pb`, `ptra`)
- Type-prefixed short names are acceptable when context is clear (e.g., `pStr`, `pBuf`)

---

## Consistency Rule

### Same Name = Same Description

When the same parameter name appears across multiple methods, its `@param` description must be identical everywhere. This prevents confusion and enables automated consistency checking.

**Canonical examples:**

| Name | Canonical Description |
|------|----------------------|
| `handle` | File handle (0 to MAX_OPEN_FILES-1) |
| `pFilename` | Pointer to zero-terminated filename string |
| `sector` | Absolute sector number on the SD card |
| `pBuffer` | Pointer to hub RAM buffer for data transfer |
| `byteCount` | Number of bytes to read or write |
| `result` | Operation status: 0 (SUCCESS) or negative error code |

The same rule applies to `@returns` descriptions.

### Enforcement

When adding a new method, check existing methods for the same parameter names and copy their descriptions verbatim.

---

## Internal Block Comments

For multi-line internal documentation (architecture diagrams, protocol descriptions, algorithm explanations), use `{ }` non-doc blocks — NOT `{{ }}`:

```spin2
{ FAT32 Cluster Chain Layout:
  Cluster 0: Media byte + $0FFFFFFF
  Cluster 1: End-of-chain marker
  Cluster 2+: User data clusters
  Each FAT entry is 4 bytes (28 bits used, 4 reserved)
}
```

Reserve `{{ }}` exclusively for the file header and end-of-file license block.

---

## Summary Checklist

- [ ] File header uses `{{ }}`
- [ ] Every PUB method has `''` doc comments with accurate `@param`/`@returns`
- [ ] Every PRI method has `'` doc comments with accurate `@param`/`@returns`/`@local`
- [ ] CON/DAT/VAR/OBJ declaration lines use `'` (never `''`)
- [ ] No `{{ }}` blocks except file header and license
- [ ] No single-letter variable names in method signatures
- [ ] Same parameter name has identical description across all methods
- [ ] `@local` tags use `'` prefix (never `''`)
