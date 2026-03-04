# Punch List - Pre-Release Cleanup

Items to resolve before release. Prior punch list completed 2026-03-01 (see archive).

---

## Test Weakness Patterns (Classified)

These anti-patterns were identified during the device guard audit (2026-03-03). Each pattern
is a reusable testing technique - apply when writing or reviewing regression tests for any
driver project.

### Pattern A: Always-True Assertions

**What it is:** An assertion that structurally cannot fail, regardless of the value under test.
Typically `evaluateBool(x == true or x == false, ...)` or `evaluateBool(x >= 0 or x < 0, ...)`.

**Why it's dangerous:** Gives false confidence. The test "passes" even when the code is broken.

**How to fix:** Replace with a specific expected value or a meaningful range. If the correct
answer depends on hardware, use `evaluateRange()` with the tightest bounds possible.

**Instances found:**
- [x] `DFS_SD_RT_speed_tests.spin2` - `checkCMD6Support()` always-true *(fixed in this audit)*
- [ ] `DFS_SD_RT_speed_tests.spin2` - `checkHighSpeedCapability()` always-true (line 177)
- [ ] `DFS_SD_RT_format_tests.spin2` - 3 instances of `or` always-true assertions
- [ ] `DFS_RT_dual_device_tests.spin2` - 1 instance of `or` always-true assertion
- [ ] `DFS_SD_RT_error_handling_tests.spin2` - 1 instance of `or` always-true assertion

### Pattern B: Hardcoded Pass/Fail

**What it is:** An assertion where the tested value is a literal (`true` or `false`) rather
than a variable holding the actual result. Example: `evaluateBool(true, @"op worked", true)`.

**Why it's dangerous:** The assertion never tests anything - it always passes (or always fails).
Often used as a "did not crash" placeholder that should be replaced with a return-value check.

**How to fix:** Capture the return value from the operation and assert on it. If the operation
has no return value, consider whether the test is actually verifying anything useful.

**Instances found:**
- [x] `DFS_SD_RT_mount_tests.spin2` line 88 - hardcoded true for closeFileHandle *(fixed in this audit)*
- [x] `DFS_SD_RT_speed_tests.spin2` line 209 - hardcoded true on failure path *(fixed in this audit)*
- [ ] `DFS_SD_RT_mount_tests.spin2` - 2 additional hardcoded-true assertions
- [ ] `DFS_SD_RT_parity_tests.spin2` - 2 hardcoded-true assertions
- [ ] `DFS_SD_RT_multiblock_tests.spin2` - 1 hardcoded-true assertion
- [ ] `DFS_SD_RT_seek_tests.spin2` - 1 hardcoded-true assertion

### Pattern C: Unchecked Setup/Teardown Returns

**What it is:** Calling mount(), createFile(), deleteFile(), etc. in test setup/teardown
without checking the return value. If setup silently fails, subsequent test assertions
may pass or fail for the wrong reasons.

**Why it's dangerous:** A failing setup can cascade false passes or obscure the real
failure. Example: if `mount()` fails silently, every subsequent test may return
E_NOT_MOUNTED and get compared against a completely different expected value.

**How to fix:** Add `evaluateSubValue(status, @"setup: mount", dfs.SUCCESS)` after
every setup call, or use a helper that aborts the test group on setup failure.

**Instances found:**
- [ ] 50+ unchecked return values across all 35 test suites (setup mount, create, delete, close calls)
- [ ] Priority targets: mount_tests, multihandle_tests, seek_tests, rw_tests (highest setup complexity)

### Pattern D: Missing Negative/Wrong-Device Tests

**What it is:** Only testing the "happy path" for device-parameterized methods. Never
calling `method(DEV_FLASH)` when the method only supports SD, or `method(99)` for
an invalid device ID.

**Why it's dangerous:** Device guard bugs (like the `setVolumeLabel(dev)` bug) are
completely invisible. The method silently does the wrong thing on the wrong device.

**How to fix:** For every `PUB method(dev, ...)`, add tests with:
1. The wrong valid device (DEV_FLASH when method is SD-only, or vice versa)
2. An invalid device ID (99, -1)
Both should return the appropriate error code (E_NOT_SUPPORTED or E_BAD_DEVICE).

**Instances found:**
- [x] `setVolumeLabel(DEV_FLASH)` - never tested *(fixed in this audit)*
- [ ] `mount(DEV_FLASH)` with no Flash pins configured - no negative test
- [ ] `freeSpace(DEV_FLASH)`, `volumeLabel(DEV_FLASH)` - no wrong-device test
- [ ] `openFileRead/Write/Append(DEV_FLASH, ...)` - no wrong-device test (6+ methods)
- [ ] Create a dedicated `DFS_RT_device_guard_tests.spin2` suite testing ALL 12+ `(dev)` methods

### Pattern E: Overly Wide Range Assertions

**What it is:** Using `evaluateRange(value, ..., 1, $7FFF_FFFF)` or similar ranges so
wide they accept virtually any non-zero value. The assertion technically tests something,
but the pass criteria is too loose to catch real bugs.

**Why it's dangerous:** A method returning garbage (e.g., uninitialized memory) can still
fall within the range and pass.

**How to fix:** Narrow the range based on known hardware constraints. For `freeSpace()`,
use the card's actual sector count as an upper bound. For timeouts, use datasheet limits.

**Instances found:**
- [ ] `DFS_SD_RT_volume_tests.spin2` - `freeSpace` range `(1, $7FFF_FFFF)` (3 instances)
- [ ] `DFS_SD_RT_multiblock_tests.spin2` - similar wide range on sector count

### Pattern F: Missing Error Code Coverage

**What it is:** Error codes defined in the driver that are never explicitly asserted in
any test. The error path exists in the code but has zero test coverage.

**Why it's dangerous:** Error handling code can be broken (wrong error code, missing
set_error() call) and no test will ever catch it.

**How to fix:** For each error code in the driver's CON block, ensure at least one test
deliberately triggers that error and asserts the specific code.

**Instances found:**
- [ ] `E_FLASH_BAD_HANDLE` - never asserted in any test
- [ ] `E_DEVICE_NOT_MOUNTED` - used in code but never explicitly asserted
- [ ] Create error code coverage matrix: list all E_* codes vs. test files that assert them

### Pattern G: Missing Post-Unmount Error Tests

**What it is:** No test verifies that file operations return proper errors after a device
is unmounted. The unmount-then-re-use path is untested.

**Why it's dangerous:** Use-after-unmount bugs can corrupt data or crash. If unmount
doesn't properly invalidate handles, subsequent calls may operate on stale state.

**How to fix:** Add a test group that unmounts, then calls every file operation and
verifies E_NOT_MOUNTED (or appropriate error) is returned.

**Instances found:**
- [ ] No SD post-unmount error suite exists
- [ ] No Flash post-unmount error suite exists
- [ ] Create `DFS_SD_RT_post_unmount_tests.spin2` and `DFS_FL_RT_post_unmount_tests.spin2`

### Pattern H: Missing Resource Exhaustion Tests

**What it is:** No test opens all available handles (MAX_OPEN_FILES) and then tries to
open one more. No test fills the directory to capacity. Resource limits are untested.

**Why it's dangerous:** Off-by-one errors in handle allocation, or missing limit checks,
are invisible without exhaustion testing.

**How to fix:** Open MAX_OPEN_FILES handles, verify the next open returns E_NO_HANDLE.
Then close one and verify a new open succeeds.

**Instances found:**
- [ ] Handle pool exhaustion - partially tested in multihandle_tests but not to the limit
- [ ] Flash block buffer exhaustion - MAX_FLASH_BUFFERS limit untested
