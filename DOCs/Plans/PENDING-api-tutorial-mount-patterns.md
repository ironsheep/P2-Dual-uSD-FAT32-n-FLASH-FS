# PENDING: API Tutorial Addition — Multi-Cog Mount/Unmount Best Practices

**Status:** Waiting for original API tutorial document to merge into.

## Section: Multi-Cog Filesystem Coordination

### Startup Pattern

The main cog owns the driver lifecycle. It initializes the worker cog and mounts the devices that the application needs, **before** spawning any worker cogs:

```spin2
PUB go() | workerCog
    workerCog := dfs.init(SD_CS, SD_MOSI, SD_MISO, SD_SCK)

    dfs.mount(dfs.DEV_BOTH)       ' or DEV_SD / DEV_FLASH if only one is needed

    cogspin(NEWCOG, dataLogger(), @loggerStack)
    cogspin(NEWCOG, archiveTask(), @archiveStack)
```

Worker cogs arrive in a world where the filesystem is ready. They do **not** need to call `init()` — the worker cog is already running and the API lock handles multi-cog serialization automatically.

### Checking Mount Status: `mounted()`

`mounted()` is a zero-cost check — it reads a shared DAT flag with no SPI bus activity and no command sent to the worker cog. Use it for:

**Gating a code path based on device availability:**

```spin2
pri archiveTask()
    ' Only archive if SD was mounted at startup
    if dfs.mounted(dfs.DEV_SD)
        copyLogsToSD()
    else
        debug("SD not available, skipping archive")
```

**Verifying a prerequisite at worker startup:**

```spin2
pri sensorLogger()
    if not dfs.mounted(dfs.DEV_FLASH)
        debug("FATAL: Flash not mounted")
        return
    ' proceed with logging...
```

### Late-Discovered Need: Just Call `mount()`

`mount()` is idempotent — if the device is already mounted, it returns SUCCESS immediately with negligible cost. A worker cog that discovers it needs a device the main cog didn't mount can mount it directly:

```spin2
pri handleAlarm()
    ' Alarm triggered — need to write report to SD
    ' Main cog only mounted Flash at startup
    if dfs.mount(dfs.DEV_SD) <> dfs.SUCCESS
        debug("SD unavailable, can't write alarm report")
        return
    ' SD is now mounted, write the report...
```

This is safe because:
- `mount()` is idempotent (no harm if already mounted)
- The hardware lock serializes the mount with any concurrent filesystem operations
- In an embedded system, the SD card and Flash chip are physically present and don't change

### Shutdown Pattern

`unmount()` is exclusively a main-cog operation. The main cog must coordinate worker shutdown **before** unmounting:

```spin2
PUB shutdown()
    ' Signal workers to stop (application-specific mechanism)
    shutdownFlag := TRUE
    waitms(1000)                   ' allow workers to close files and exit

    dfs.unmount(dfs.DEV_BOTH)
    dfs.stop()
```

A worker cog should **never** call `unmount()`. If it did, other cogs with open file handles would encounter errors.

### Summary of Multi-Cog Rules

| Operation | Who calls it | When |
|-----------|-------------|------|
| `init()` | Main cog only | Once, at application start |
| `mount()` | Main cog at startup; any cog if late need arises | Before first filesystem use |
| `mounted()` | Any cog | To check availability (zero-cost) |
| `unmount()` | Main cog only | After all workers have stopped |
| `stop()` | Main cog only | Final cleanup, stops worker cog |

### Key Points for Developers

- **`mount()` is cheap when already mounted.** Don't fear calling it as a precaution.
- **`mounted()` is zero-cost.** It reads a shared variable — no SPI traffic, no worker command.
- **The hardware lock handles everything.** Multiple cogs can call `open()`, `read()`, `write()`, etc. concurrently. The API lock serializes access to the worker cog automatically.
- **File handles are a shared pool.** The default is 6 handles across all cogs and both devices. Plan handle usage accordingly — close files promptly.
