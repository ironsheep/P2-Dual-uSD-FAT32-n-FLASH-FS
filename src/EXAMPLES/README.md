# Example Programs

Compilable, self-contained examples demonstrating dual filesystem (SD + Flash) operations. Each example can be compiled and run directly on P2 hardware.

## Building

From this `EXAMPLES/` directory:

```bash
pnut-ts -d -I .. DFS_example_basic.spin2
pnut-term-ts -r DFS_example_basic.bin
```

The `-I ..` flag tells the compiler to find `dual_sd_fat32_flash_fs.spin2` in the parent directory. The `-d` flag enables debug output.

## Examples

| Program | Description |
|---------|-------------|
| [DFS_example_basic.spin2](DFS_example_basic.spin2) | Mount both devices, write/read files on each, show stats — the "hello world" |
| [DFS_example_cross_copy.spin2](DFS_example_cross_copy.spin2) | Copy a file from SD to Flash and back, verify round-trip data integrity |
| [DFS_example_data_logger.spin2](DFS_example_data_logger.spin2) | Log sensor data to Flash, then archive (copy) the log to SD |
| [DFS_example_sd_manifest.spin2](DFS_example_sd_manifest.spin2) | Read a manifest file from SD and copy listed files/folders to Flash |

## What Each Example Teaches

### Basic (Start Here)

Initialize the driver, mount both SD and Flash, write a text file to each device using its native API (SD uses `createFileNew`/`writeHandle`, Flash uses `open`/`wr_str`), read both files back, display filesystem stats, clean up and unmount. Demonstrates the complete dual-device lifecycle and error checking on every API call.

### Cross-Device Copy

Creates a file on SD, copies it to Flash using `copyFile()`, then copies it back to SD under a new name. Performs byte-by-byte comparison of the original and round-trip copy to verify data integrity across devices. Demonstrates the `copyFile()` API for moving data between SD and Flash.

### Data Logger

The most common real-world dual-FS pattern. Opens a log file on Flash for fast writes, records timestamped sensor readings (simulated), then archives the completed log from Flash to SD using `copyFile()`. Verifies the archive by reading it back from SD. This pattern is useful for embedded data acquisition where Flash provides fast write buffering and SD provides large removable archival storage.

### SD Manifest Copy (Deployment Pattern)

Reads a text manifest file (MANIFEST.TXT) from the SD card containing one entry per line, then copies each listed file or folder from SD to Flash. Lines ending with `/` are folders -- all files in that SD directory are copied. Demonstrates: byte-level line parsing with `rd_byte()`, folder enumeration via `openDirectory()`/`readDirectoryHandle()`, duplicate detection, `exists()` pre-checks, `copyFile()` for SD-to-Flash transfer, absolute Flash paths (e.g., `"/ASSETS/PARAMS.TXT"`) to bypass CWD, and post-copy size verification. SD directories become path-prefixed filenames on Flash -- the directory trees look the same on both devices. This pattern is useful for embedded deployment where configuration and data files are prepared on a PC, placed on SD, and the firmware copies them to onboard Flash on first boot.

---

*Part of the [P2 Dual SD FAT32 + Flash Filesystem](../../README.md) project — Iron Sheep Productions*
