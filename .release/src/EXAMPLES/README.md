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
| **DFS_example_basic.spin2** | Mount both devices, write/read files on each, show stats -- the "hello world" |
| **DFS_example_cross_copy.spin2** | Copy a file from SD to Flash and back, verify round-trip data integrity |
| **DFS_example_data_logger.spin2** | Log sensor data to Flash, then archive the log to SD |

## What Each Example Teaches

### Basic (Start Here)

Initialize the driver, mount both SD and Flash, write a text file to each device using its native API, read both files back, display filesystem stats, clean up and unmount. Demonstrates the complete dual-device lifecycle and error checking on every API call.

### Cross-Device Copy

Creates a file on SD, copies it to Flash using `copyFile()`, then copies it back to SD under a new name. Performs byte-by-byte comparison of the original and round-trip copy to verify data integrity across devices. Demonstrates the `copyFile()` API for moving data between SD and Flash.

### Data Logger

The most common real-world dual-FS pattern. Opens a log file on Flash for fast writes, records timestamped sensor readings (simulated), then archives the completed log from Flash to SD using `copyFile()`. Verifies the archive by reading it back from SD. This pattern is useful for embedded data acquisition where Flash provides fast write buffering and SD provides large removable archival storage.

## Pin Configuration

All examples default to the P2 Edge Module pin configuration (P58-P61). See the [Tutorial](../../DOCs/DUAL-DRIVER-TUTORIAL.md) for complete pin configuration details.

---

*Part of the [P2 Dual SD FAT32 + Flash Filesystem](../../README.md) package -- Iron Sheep Productions*
