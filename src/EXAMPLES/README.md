# Example Programs

Compilable, self-contained examples demonstrating common SD card driver operations. Each example can be compiled and run directly on P2 hardware.

## Building

From this `EXAMPLES/` directory:

```bash
pnut-ts -I .. SD_example_read_write.spin2
pnut-term-ts -r SD_example_read_write.bin
```

The `-I ..` flag tells the compiler to find `micro_sd_fat32_fs.spin2` in the parent directory.

Or use the test runner from the `tools/` directory:

```bash
cd ../../tools
./run_test.sh ../src/EXAMPLES/SD_example_read_write.spin2
```

## Examples

| Program | Description |
|---------|-------------|
| [SD_example_read_write.spin2](SD_example_read_write.spin2) | Basic file create, write, read-back, and delete — the "hello world" |
| [SD_example_data_logger.spin2](SD_example_data_logger.spin2) | Append-mode logging with periodic sync for power-fail safety |
| [SD_example_directory_walk.spin2](SD_example_directory_walk.spin2) | Directory listing, subdirectory creation, file delete and rename |
| [SD_example_multicog.spin2](SD_example_multicog.spin2) | Two cogs accessing different files concurrently |

## Pin Configuration

All examples default to the P2 Edge Module SD card slot (base pin 56). To use a different 8-pin header group, change `SD_BASE` in the `CON` section. See the [Driver Tutorial](../../DOCs/SD-CARD-DRIVER-TUTORIAL.md#using-a-different-8-pin-header-group) for the complete header group reference table.

## What Each Example Teaches

### Read/Write (Start Here)
Mount, create a file, write text, close, re-open for reading, read back, unmount. Demonstrates the complete file lifecycle and error checking on every API call.

### Data Logger
The most common real-world pattern. Opens an existing file for append (or creates a new one), writes CSV entries, and uses `syncHandle()` to checkpoint data periodically. If power is lost, all synced entries survive.

### Directory Walk
Shows both index-based (`readDirectory`) and handle-based (`openDirectory` / `readDirectoryHandle`) directory enumeration. Also demonstrates `deleteFile()`, `rename()`, `newDirectory()`, and `changeDirectory()`.

### Multi-Cog
The P2-specific killer feature. Starts a second cog that reads a file while the main cog writes a different file. Demonstrates the singleton driver pattern, per-cog isolation, and the hardware lock serialization that makes concurrent access safe.

---

*Part of the [P2 microSD FAT32 Filesystem](../../README.md) project — Iron Sheep Productions*
