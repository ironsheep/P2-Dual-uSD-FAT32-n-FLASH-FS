# Regression Testing: Best Practices and Principles

A comprehensive guide to designing, organizing, and maintaining regression test suites for software libraries, drivers, and APIs. This document covers the theory and methodology; for project-specific coding conventions, see the companion REGRESSION-TEST-STYLE-GUIDE.md.

---

## Table of Contents

1. [What Regression Testing Is (and Is Not)](#1-what-regression-testing-is-and-is-not)
2. [The Testing Pyramid](#2-the-testing-pyramid)
3. [Foundational Principles](#3-foundational-principles)
4. [Test Anatomy: The Four Phases](#4-test-anatomy-the-four-phases)
5. [What to Test: Coverage Strategies](#5-what-to-test-coverage-strategies)
6. [Negative Testing and Error Path Coverage](#6-negative-testing-and-error-path-coverage)
7. [API Boundary Testing: Design by Contract](#7-api-boundary-testing-design-by-contract)
8. [The Test Oracle Problem](#8-the-test-oracle-problem)
9. [Test Organization and Naming](#9-test-organization-and-naming)
10. [Test Independence and Isolation](#10-test-independence-and-isolation)
11. [Setup Validation: Trusting Your Test Preconditions](#11-setup-validation-trusting-your-test-preconditions)
12. [Test Suite Prioritization and Selection](#12-test-suite-prioritization-and-selection)
13. [Evaluating Test Suite Quality](#13-evaluating-test-suite-quality)
14. [Test Maintenance and Avoiding Test Rot](#14-test-maintenance-and-avoiding-test-rot)
15. [Property-Based Testing](#15-property-based-testing)
16. [Applying These Principles to a Driver or Library](#16-applying-these-principles-to-a-driver-or-library)
17. [Bibliography](#17-bibliography)

---

## 1. What Regression Testing Is (and Is Not)

**Regression testing** is the practice of re-running existing tests after every code change to verify that previously working behavior still works. The word "regression" means "going backward" -- a regression bug is one where something that used to work now doesn't.

Michael Feathers defines legacy code as "code without tests" (*Working Effectively with Legacy Code*, 2004). The corollary: a codebase with a comprehensive regression suite is *not* legacy code, because every change can be verified against known-good behavior.

Regression testing is **not**:

- **Exploratory testing.** Regression tests are automated and repeatable. Exploratory testing is manual, creative, and one-time.
- **Performance testing.** Regression tests verify correctness, not speed. (Though a regression suite *can* include performance benchmarks.)
- **A substitute for design.** Tests verify behavior; they don't create it. A perfectly passing suite doesn't prove the design is right -- only that the implementation matches its tests.

The goal is simple: **catch unintended side effects of change.** Every time you modify code, the regression suite tells you whether you broke something.

---

## 2. The Testing Pyramid

Mike Cohn introduced the **Test Automation Pyramid** at a Scrum gathering in 2004 and published it in *Succeeding with Agile* (Addison-Wesley, 2009). Martin Fowler popularized it in his influential "TestPyramid" article (martinfowler.com, 2012).

```
        /  E2E  \          Few: slow, brittle, expensive
       /----------\
      / Integration \       Some: test component interactions
     /----------------\
    /    Unit Tests     \   Many: fast, isolated, cheap
   /____________________\
```

**The principle:** Write many small, fast unit tests at the base. Write fewer integration tests in the middle. Write very few end-to-end tests at the top.

Fowler (2012): "You should have many more low-level unit tests than high-level broad-stack tests running through a GUI."

**Why this shape matters:**

| Layer | Speed | Stability | Diagnostic Value | Cost to Write |
|-------|-------|-----------|------------------|---------------|
| Unit | Milliseconds | Very stable | Points to exact defect | Low |
| Integration | Seconds | Stable | Points to interaction | Medium |
| E2E | Seconds-minutes | Brittle | "Something is broken" | High |

When a unit test fails, you know exactly which function broke and why. When an E2E test fails, you know *something* is wrong but must investigate to find where.

**The Ice Cream Cone anti-pattern** is the inverted pyramid -- mostly E2E tests, few unit tests. Cohn called the integration layer "the forgotten layer of test automation." The anti-pattern produces suites that are slow, brittle, and expensive to maintain.

### Alternative Models

- **Testing Diamond** (~2015): Wider in the middle (integration), narrower at top and bottom. Appropriate when component interactions are the primary defect source.
- **Testing Trophy** (Kent C. Dodds, 2018, building on Guillermo Rauch's "Write tests. Not too many. Mostly integration."): Emphasizes integration tests with static analysis as a foundation layer.

The exact proportions depend on your system. The shared principle across all models: **push each test down to the lowest level where it can still catch the defect it targets.**

---

## 3. Foundational Principles

### 3.1 The FIRST Properties

Robert C. Martin defined these in *Clean Code* (Prentice Hall, 2008, Chapter 9):

- **Fast.** Tests must run in milliseconds. A slow suite stops being run. Feathers (*Working Effectively with Legacy Code*): "A test that takes 1/10 of a second is too slow."
- **Independent.** No test depends on another test's outcome or execution order. Any test should be runnable in isolation, in any order.
- **Repeatable.** Same result every time, in every environment. No dependence on clocks, networks, random seeds (unless explicitly seeded), or external services.
- **Self-Validating.** Reports pass or fail automatically. No human inspection of output required.
- **Timely.** Written at the right time -- ideally before or alongside the production code, not months later.

### 3.2 Tests Are Documentation

Roy Osherove (*The Art of Unit Testing*, Manning, 2009): Tests serve as living, executable documentation of how the system behaves. A well-named test tells a reader: *what* is being tested, under *what conditions*, and *what the expected outcome* is.

### 3.3 One Logical Concept per Test

Osherove: "Test one logical concept per test." When a test with multiple unrelated assertions fails, the diagnosis is ambiguous. Meszaros calls this the **Eager Test** smell (*xUnit Test Patterns*, 2007).

This does not mean one assertion per test. A single logical concept may require several assertions to verify. But all assertions in a test should relate to the same behavior.

### 3.4 Test Behavior, Not Implementation

Vladimir Khorikov (*Unit Testing: Principles, Practices, and Patterns*, Manning, 2020) distinguishes two schools:

- **London school:** Isolate the unit from all collaborators using mocks. Tests are tightly coupled to implementation structure.
- **Classical (Detroit) school:** Isolate *tests* from each other (not units from collaborators). Tests are coupled to observable behavior.

The classical school produces more resilient tests. When you refactor internals without changing behavior, classical tests continue to pass. London-school tests break because the mock expectations no longer match the new internal structure.

**Principle:** Test the public interface. Assert on observable outcomes (return values, state changes, output), not on internal method calls or private state.

---

## 4. Test Anatomy: The Four Phases

Meszaros (*xUnit Test Patterns*, 2007) defines every test as having four phases:

1. **Setup (Arrange).** Establish preconditions. Create objects, initialize state, prepare test data.
2. **Exercise (Act).** Execute the operation under test. This is typically a single function call.
3. **Verify (Assert).** Check that the outcome matches expectations.
4. **Teardown (Cleanup).** Restore the system to its pre-test state.

Bill Wake (2001) introduced the shorthand **Arrange-Act-Assert (AAA)**, popularized by Osherove. The teardown phase is implicit (handled by the test framework or by test isolation).

**Key discipline:** Keep the Exercise phase to a single operation. If you're calling multiple functions, you're testing an interaction scenario, not a unit -- which is fine, but be explicit about it.

---

## 5. What to Test: Coverage Strategies

### 5.1 Equivalence Partitioning

Formalized by Glenford J. Myers (*The Art of Software Testing*, 1979).

Partition the input domain into **equivalence classes** -- groups of inputs that should all produce the same category of behavior. Write at least one test per class.

Example for a function `setSpeed(hz)` that accepts 100,000 to 50,000,000 Hz:

| Class | Representative Value | Expected Behavior |
|-------|---------------------|-------------------|
| Below minimum | 50,000 | Error: E_INVALID_SPEED |
| Valid low end | 100,000 | Accepts, sets speed |
| Valid middle | 25,000,000 | Accepts, sets speed |
| Valid high end | 50,000,000 | Accepts, sets speed |
| Above maximum | 60,000,000 | Error: E_INVALID_SPEED |

### 5.2 Boundary Value Analysis (BVA)

Also from Myers (1979). Bugs cluster at boundaries, not in the middle of equivalence classes. For each boundary, test:

- The last valid value (just inside)
- The first invalid value (just outside)

For the speed example: test 99,999 (invalid), 100,000 (valid), 50,000,000 (valid), 50,000,001 (invalid).

**The "bracketing" pattern:** For any limit in your API, write two tests that straddle it -- one on each side. This proves the boundary is exactly where the documentation says it is.

### 5.3 Decision Table Testing

For operations with multiple conditions that interact, build a decision table. Each column is a combination of conditions; each row is a condition or an expected action.

Example: `openFile(name, mode)` behavior matrix:

| File exists? | Mode = READ | Mode = WRITE | Mode = APPEND |
|-------------|-------------|--------------|---------------|
| Yes | Open, return handle | Truncate, return handle | Open at end, return handle |
| No | E_FILE_NOT_FOUND | Create new, return handle | Create new, return handle |

Write one test for each cell. This ensures every combination is covered.

### 5.4 State Transition Testing

For stateful APIs (like a filesystem driver), model the system as a state machine:

```
UNMOUNTED --mount()--> MOUNTED --openFile()--> FILE_OPEN --close()--> MOUNTED --unmount()--> UNMOUNTED
```

Test every valid transition. Then test every *invalid* transition (e.g., `openFile()` from UNMOUNTED state) and verify the correct error.

---

## 6. Negative Testing and Error Path Coverage

Myers (*The Art of Software Testing*, 1979): Every invalid equivalence class must be covered with at least one test case, just as every valid class must be. Negative testing is not optional -- it is half of the testing obligation.

### 6.1 Categories of Negative Tests

1. **Invalid input values.** Pass arguments outside valid ranges, null/zero pointers, empty strings, overlength strings, negative values where positive expected.

2. **Wrong sequence / state.** Call operations out of order: read before open, write to a read-only handle, unmount while files are open.

3. **Resource exhaustion.** Open more handles than the pool allows. Fill the disk. Exhaust memory.

4. **Concurrent misuse.** Two cogs writing to the same file. Two cogs mounting simultaneously.

5. **Corruption and hardware failure.** Bad CRC on a sector read. Timeout on card response. Unexpected card removal.

### 6.2 What to Assert in Negative Tests

For each negative test, verify three things:

1. **Correct error code.** The function returns the specific documented error, not a generic failure or (worse) success.
2. **No state corruption.** The system remains in a consistent, usable state after the error. Other operations still work.
3. **No resource leaks.** Failed operations don't consume handles, memory, or locks that are never released.

### 6.3 Commenting Negative Tests

When a test deliberately provokes an error, explain *why* this is the expected behavior. Without the comment, a future reader may think the error is a bug in the test.

```
' Opening a 7th file when MAX_OPEN_FILES=6 should fail
' because the handle pool is exhausted
handle := sd.openFileRead(@"EXTRA.TXT")
utils.evaluateSingleValue(handle, @"7th open exceeds pool", sd.E_TOO_MANY_FILES)
```

### 6.4 Post-Teardown Testing (Use After Invalidation)

A particularly important category of negative test verifies that operations fail correctly **after a resource has been invalidated** -- after a device is unmounted, a handle is closed, or a subsystem is shut down.

**Why this deserves its own category:** Use-after-invalidation bugs are among the most dangerous in stateful systems. If an unmount does not properly invalidate handles, subsequent calls may operate on stale cached state, corrupt data on the storage medium, or crash. These bugs only surface in long-running applications where mount/unmount cycles or open/close cycles occur over time -- exactly the scenarios that simple happy-path tests never exercise.

**Scenarios to test for any stateful API:**

1. **Use after close.** Close a handle, then call every operation that takes a handle (read, write, seek, close again). Each must return the documented error (e.g., `E_BAD_HANDLE`), not crash or silently succeed.

2. **Use after unmount.** Unmount a device or subsystem, then call every operation that requires it to be mounted. Each must return `E_NOT_MOUNTED` or equivalent.

3. **Use after shutdown.** Stop the entire driver or service, then call any method. Verify graceful failure -- no crash, no hang, no undefined behavior.

4. **Re-open after close.** Close a handle, then open a new one. The system must correctly recycle the handle slot. The new handle must not inherit stale state from the old one.

**What to assert:** The same three things as any negative test (Section 6.2): correct error code, no state corruption, no resource leaks. Additionally, verify that the system can **recover** -- after the error, a fresh mount/open/init should succeed normally.

---

## 7. API Boundary Testing: Design by Contract

Bertrand Meyer coined **Design by Contract** in 1986 (*Object-Oriented Software Construction*, Prentice Hall, 1988). The concept provides a rigorous framework for API testing.

### 7.1 The Three Contract Elements

Every public API method has an implicit or explicit contract:

- **Preconditions:** What must be true before calling. The *caller's* obligation. Example: "The filesystem must be mounted before calling openFile()."
- **Postconditions:** What the method guarantees after returning. The *implementation's* obligation. Example: "After a successful write(), the file size has increased by the number of bytes written."
- **Invariants:** Properties that are always true between operations. Example: "The number of open handles is always between 0 and MAX_OPEN_FILES."

### 7.2 Testing the Contract

For each API method, write tests in three categories:

**A. Precondition enforcement tests:** Call the method with each precondition violated, one at a time. Verify the API rejects the call with a clear, specific error code. The system must not crash, corrupt state, or return misleading success.

```
' PRECONDITION: filesystem must be mounted
' Violate: call openFileRead() before mount()
handle := sd.openFileRead(@"TEST.TXT")
assert(handle == E_NOT_MOUNTED)
```

**B. Postcondition verification tests:** After each successful call, verify every guarantee. If `write()` promises to advance the file position, check the position. If `createFile()` promises the file exists afterward, verify with `openFileRead()`.

```
' POSTCONDITION: after write(100 bytes), position advances by 100
sd.writeHandle(handle, @data, 100)
pos := sd.positionHandle(handle)
assert(pos == previous_pos + 100)
```

**C. Invariant tests:** Check system invariants before and after each operation. These are especially valuable as assertions embedded in the test framework itself.

```
' INVARIANT: open handle count is within bounds
count := sd.openHandleCount()
assert(count >= 0 AND count <= sd.MAX_OPEN_FILES)
```

### 7.3 Bracketing Behavior

"Bracketing" means testing both sides of every boundary to prove the boundary is in exactly the right place:

- Max filename length: test at max (passes), test at max+1 (fails with E_NAME_TOO_LONG)
- Max file size: test writing up to the limit (passes), test writing one byte past (fails with E_DISK_FULL)
- Handle pool: open MAX_OPEN_FILES handles (passes), open one more (fails with E_TOO_MANY_FILES)

The pair of tests together *prove* the boundary. A single test on one side only proves half the story.

---

## 8. The Test Oracle Problem

A **test oracle** is the mechanism that determines whether a test outcome is correct (IEEE ISTQB Glossary). "An oracle is a predicate that determines whether a given sequence of stimuli and observations is acceptable or not."

### 8.1 Types of Oracles

| Oracle Type | Description | Example |
|-------------|-------------|---------|
| **Specified** | Expected results from specifications | "mount() returns SUCCESS per API docs" |
| **Pseudo-oracle** | Independent alternative implementation | Compare your FAT32 parser against a known-good one |
| **Partial** | Verify only some properties of the output | "The returned buffer is non-null and 512 bytes long" |
| **Implicit** | General correctness: no crash, no corruption | "No assertion fires, no watchdog timeout" |
| **Round-trip** | Encode then decode returns the original | "Write file, read it back, compare byte-for-byte" |
| **Model-based** | Compare against a simpler reference model | Compare directory listing against a known file list |

### 8.2 Choosing the Right Oracle

For driver/library testing, the most powerful oracles are:

1. **Round-trip verification.** Write data, read it back, compare. This catches corruption at every layer -- encoding, transmission, storage, retrieval, decoding.

2. **Contract-based oracles.** Postconditions and invariants from Design by Contract (Section 7) serve directly as oracles without needing a separate expected-value table.

3. **Known-answer tests.** For operations with deterministic outputs (CRC calculation, date parsing, path normalization), hard-code the known correct answer.

4. **Cross-reference oracles.** Compare your implementation's output against a reference tool. For a FAT32 driver, compare directory listings against what a PC sees on the same card.

---

## 9. Test Organization and Naming

### 9.1 Naming Convention

Osherove (*The Art of Unit Testing*) established the widely-adopted pattern:

```
MethodUnderTest_StateUnderTest_ExpectedBehavior
```

Examples:
- `readHandle_pastEndOfFile_returnsEOF`
- `mount_whenAlreadyMounted_returnsE_ALREADY_MOUNTED`
- `openFileWrite_whenDiskFull_returnsE_DISK_FULL`

Robert C. Martin (*Clean Code*, 2008): "With code, we do more reading than writing, by a huge factor." Test names are documentation. A reader should understand the test's purpose from its name alone, without reading the body.

### 9.2 Suite Organization

Group tests by the unit or feature under test, not by fixture or test technique:

```
SD_RT_mount_tests.spin2          ' Tests for mount/unmount lifecycle
SD_RT_read_write_tests.spin2     ' Tests for read and write operations
SD_RT_seek_tests.spin2           ' Tests for seek/position operations
SD_RT_directory_tests.spin2      ' Tests for directory operations
SD_RT_error_handling_tests.spin2 ' Tests for error paths and misuse
```

Within each suite, order tests from simplest to most complex:

1. **Nominal / happy path** -- the simplest correct usage
2. **Variations** -- different valid inputs, modes, configurations
3. **Boundary cases** -- minimum, maximum, edge values
4. **Error paths** -- invalid inputs, wrong state, resource exhaustion
5. **Stress / volume** -- many iterations, large data, concurrent access

### 9.3 Test Group Labels

Within a suite, use descriptive group labels that explain *what aspect* is being tested:

```
utils.startTestGroup(@"Mount Lifecycle")
utils.startTestGroup(@"Mount Error Handling")
utils.startTestGroup(@"Mount with Invalid Pins")
```

---

## 10. Test Independence and Isolation

Meszaros (*xUnit Test Patterns*, 2007): Each test should use a **Fresh Fixture** -- start from a known, clean state. Shared mutable state between tests is the root cause of:

- **Order-dependent failures.** Test B passes when run after Test A but fails when run alone.
- **Cascading failures.** Test A corrupts state; Tests B, C, D all fail even though their code is correct.
- **Non-deterministic failures.** Tests pass or fail depending on timing, memory layout, or execution order.

### 10.1 Strategies for Isolation

**For stateful systems** (like a filesystem driver where you can't easily reset hardware):

1. **Known starting state.** Begin each suite by mounting a freshly formatted or known-state card. Document what files/directories should exist.

2. **Create-test-cleanup pattern.** Each test creates what it needs, tests it, and removes it. The next test doesn't inherit leftover files.

3. **Unique filenames per test.** Avoid reusing the same filename across tests. If test A creates "TEST.TXT" and test B also uses "TEST.TXT", they are coupled.

4. **Guard zones.** Use sentinel patterns around buffers to detect overflows that could corrupt adjacent test state. (See also: Section 15.)

### 10.2 What "Independent" Does Not Mean

Independence does not mean every test must stand alone with zero shared setup. It's fine to have a shared `mount()` at suite start and `unmount()` at suite end. The requirement is that no test's *outcome* depends on what another test did.

---

## 11. Setup Validation: Trusting Your Test Preconditions

A test is only as trustworthy as its setup. If the setup silently fails, every subsequent assertion may pass or fail for the wrong reason -- and you will never know.

### 11.1 The Problem

Consider a test that mounts a filesystem, creates a file, writes data, reads it back, and compares. If `mount()` silently fails (returns an error that nobody checks), then `createFile()` returns `E_NOT_MOUNTED`, `write()` returns `E_NOT_MOUNTED`, `read()` returns `E_NOT_MOUNTED` -- and if the test happens to expect error codes for some other reason, it reports green while testing nothing.

This is not hypothetical. It is one of the most common sources of **false confidence** in test suites: tests that pass not because the code works, but because the setup failed and the downstream assertions accidentally match the resulting error state.

### 11.2 The Principle

**Assert every setup operation.** Every call in the test's setup phase (mount, open, create, delete, format) must have its return value checked. If setup fails, the test must visibly fail *at the setup step*, not silently proceed.

### 11.3 Implementation Approaches

**Approach 1: Fail-fast with early return.** Check each setup call and abort the test group if it fails:

```
status := mount()
if status <> SUCCESS
    reportSetupFailure("mount", status)
    return    ' Skip all tests in this group
```

**Approach 2: Sub-assertions in setup.** Use a non-counting assertion (one that doesn't inflate the test count) to verify setup steps, so that a setup failure is visible in the output but doesn't skew pass/fail statistics:

```
status := mount()
utils.evaluateSubValue(status, @"setup: mount", SUCCESS)
```

**Approach 3: Precondition assertions.** Before the Exercise phase of each test, assert that the preconditions actually hold:

```
' Verify file exists before testing read operations on it
utils.evaluateBool(fileExists(@"DATA.TXT"), @"precondition: file exists", true)
```

### 11.4 When Setup Validation Matters Most

- **Hardware-dependent systems.** A mount or init can fail for reasons unrelated to the code: card not inserted, serial cable loose, hardware misconfigured.
- **Tests that run in sequence.** If an earlier test's cleanup was incomplete, the next test's setup may fail because leftover state interferes.
- **Resource-limited environments.** If handles or memory are exhausted from a prior test's leak, setup calls in subsequent tests will fail.

**Rule of thumb:** If a setup call *can* fail, it *will* fail eventually. Checking it costs one line; not checking it can cost hours of debugging phantom test failures.

---

## 12. Test Suite Prioritization and Selection

When the full regression suite takes too long to run after every change, you need a strategy for choosing *which* tests to run.

### 12.1 Prioritization Strategies

Rothermel and Harrold ("A Safe, Efficient Regression Test Selection Technique," ACM TOSEM, 1997) and the comprehensive survey by Yoo and Harman (*Regression Testing Minimisation, Selection and Prioritisation*, Software Testing Verification and Reliability, 2012) define three approaches:

**Risk-based prioritization.** Run tests for the highest-risk areas first:
- Components that changed in this edit
- Components with high complexity or historical defect density
- Safety-critical paths (data integrity, resource management)

**Dependency-based prioritization.** Run tests for components with the most dependents first. A defect in a low-level utility function affects every caller.

**History-based prioritization.** Run tests that have historically caught defects first. Track which tests find bugs; they're more valuable.

### 12.2 The APFD Metric

**Average Percentage of Faults Detected (APFD)** measures how quickly a prioritized suite detects faults as a function of progress through the suite. Higher APFD means faults are caught earlier. Adaptive prioritization has achieved 86.9% APFD versus 51.5% for random ordering (Yoo and Harman, 2012).

### 12.3 Practical Strategy: Tiered Execution

| Tier | When to Run | What to Include |
|------|-------------|-----------------|
| **Smoke** | Every edit/compile | Mount, basic read, basic write -- 30 seconds |
| **Feature** | After completing a feature change | All suites touching the changed feature -- 2-5 minutes |
| **Full regression** | Before commit/release | All suites -- 10-30 minutes |
| **Extended** | Before major release | Full regression + stress + multicog + edge cases -- 1+ hour |

### 12.4 The Regression Baseline Workflow

Knowing *which* tests to run is only half the problem. You also need a repeatable process for *comparing* results before and after a change. This is the **regression baseline workflow:**

1. **Establish baseline.** Run the full regression suite on the unchanged code. Record the total test count, pass count, and fail count. Save the output log.

2. **Make the code change.** Edit the production code (the driver, library, or application).

3. **Clean build artifacts.** Delete compiled object files so the build picks up all changes. Stale cached objects are a common source of phantom passes (the old code runs instead of the new code).

4. **Run the full regression suite again.** Use the same test runner, same timeout values, same hardware configuration.

5. **Compare.** The results must satisfy:
   - Same total test count (no tests accidentally dropped)
   - Same or higher pass count
   - Zero new failures

6. **Investigate any difference.** If the test count changed, a test was added or removed -- intentional? If a new failure appeared, it is a regression introduced by the change. If a previously failing test now passes, verify this is expected (not a coincidence from a changed error path).

**When test expectations intentionally change:** If a refactoring changes return values, error codes, or API behavior, update the affected test assertions *first*, then run the suite. Document *why* expectations changed -- a comment in the test and a note in the commit message. This prevents future developers from seeing the changed assertion and wondering whether it was a mistake.

**The regression baseline is evidence.** It answers the question: "Did this change break anything?" Without it, you are relying on hope.

---

## 13. Evaluating Test Suite Quality

How do you know if your test suite is *good enough*?

### 13.1 Code Coverage

Beizer (*Software Testing Techniques*, 1990) defines a hierarchy:

| Level | Definition | Strength |
|-------|-----------|----------|
| Statement coverage | Every line executed at least once | Minimum bar |
| Branch coverage | Every `if`/`else` taken both ways | Good |
| Condition coverage | Every sub-expression in a condition evaluated both ways | Better |
| MC/DC | Each condition independently affects the decision outcome | Gold standard (required by DO-178C for safety-critical avionics) |

**Coverage is necessary but not sufficient.** 100% line coverage does not mean 100% behavior coverage. A line can be executed without its edge cases being tested.

IEEE 1008-1987 (*IEEE Standard for Software Unit Testing*): "Test the interface, not the implementation -- test only the behavioral aspects presented via the interface of the unit under test."

### 13.2 Mutation Testing

Proposed by Richard Lipton (1971), formalized by DeMillo, Lipton, and Sayward ("Hints on Test Data Selection," IEEE Computer, 1978).

**How it works:**

1. Make a small syntactic change to the production code (a **mutant**). Examples: change `>` to `>=`, change `+` to `-`, change `true` to `false`, remove a statement.
2. Run the entire test suite against the mutant.
3. If any test fails, the mutant is **killed** -- the suite detected the change. Good.
4. If all tests pass, the mutant **survived** -- the suite has a blind spot. Bad.

**Mutation score** = killed mutants / total non-equivalent mutants.

The **Competent Programmer Hypothesis** (DeMillo et al., 1978): Programmers generally write code that is "close to correct." Real bugs are small deviations from correct code -- exactly what mutations model. The **Coupling Effect**: test data that catches simple mutations also catches complex ones.

Google published "State of Mutation Testing at Google" (ICSE SEIP, 2018), demonstrating that mutation testing is practical at scale.

**For embedded/hardware projects** where automated mutation frameworks aren't available, you can apply the principle manually: temporarily introduce a deliberate bug (off-by-one, wrong error code, reversed condition) and verify that a test catches it. If no test catches it, you have a coverage gap.

### 13.3 Fault Injection

For drivers and hardware-interfacing code, inject faults at the hardware boundary:

- Corrupt a CRC in a read response
- Simulate a timeout
- Return an unexpected status byte

Verify that the driver detects the fault, reports the correct error, and does not corrupt its internal state.

### 13.4 Assertion Quality Audit

Code coverage and mutation testing evaluate whether the *code under test* is exercised. But there is a subtler problem: **tests whose assertions can never fail.** A test that always passes regardless of what the code does provides zero value -- it is worse than no test because it creates false confidence.

This problem is common enough to deserve its own audit process.

**Anti-patterns to detect:**

| Anti-pattern | Example | Why It's Broken |
|---|---|---|
| **Tautology** | `assert(x == true OR x == false)` | True for every possible value of x |
| **Hardcoded pass** | `assert(true == true)` | Literal true always equals true; the code under test is not involved |
| **Overly wide range** | `assertRange(val, 0, MAX_INT)` | Accepts garbage, uninitialized memory, any non-negative value |
| **Wrong assertion type** | `assertBool(statusCode, true)` | Status code 0 (SUCCESS) is not boolean true; this may pass or fail depending on language truthiness rules, but it never tests what it claims to test |
| **Ignored return value** | `doOperation()` with no assertion | The test exercises the code but never checks the result |

**How to audit:**

1. Search for hardcoded literal values in assertion calls (`assert(true, ...)`, `assert(0, ...)`).
2. Search for logical OR inside assertions -- potential tautologies.
3. Search for extremely wide ranges in range assertions.
4. For every assertion call, verify that its first argument (the actual value) comes from the code under test, not from a literal or a setup variable.
5. For every call to the code under test, verify that its return value is captured and asserted.

**The litmus test:** For each assertion, ask: "If the code under test were replaced with `return 0` (or `return -1`, or `return garbage`), would this assertion catch it?" If the answer is no, the assertion needs to be rewritten.

---

## 14. Test Maintenance and Avoiding Test Rot

**Test rot** is the gradual degradation of a test suite's quality and trustworthiness. Symptoms: increasing flakiness, growing maintenance burden, tests that are disabled "temporarily," team members who ignore test failures.

### 14.1 Test Smells

Meszaros (*xUnit Test Patterns*, 2007) catalogs 18 test smells. The most common:

| Smell | Symptom | Fix |
|-------|---------|-----|
| **Fragile Test** | Breaks when unrelated code changes | Test behavior, not implementation |
| **Eager Test** | Tests too much in one test | Split into focused tests |
| **Mystery Guest** | Uses external resources not visible in test | Make dependencies explicit |
| **Assertion Roulette** | Multiple assertions without messages | Label every assertion |
| **Magic Number** | Literal values without explanation | Use named constants with comments |

### 14.2 Flickering Tests

Freeman and Pryce (*Growing Object-Oriented Software, Guided by Tests*, 2009): "Once teams see these failures as false positives, they distrust their build results."

A flickering (flaky) test is **worse than no test** because it erodes trust in the entire suite. Treat flaky tests as first-class defects. Either fix the non-determinism or delete the test.

Common causes of flakiness:
- Timing dependencies (using wall-clock time)
- Uncontrolled concurrency
- Shared mutable state between tests
- Dependence on external resources (network, specific file contents)

### 14.3 Maintenance Discipline

Ham Vocke ("The Practical Test Pyramid," martinfowler.com, 2018): "Test code is as important as production code. Give it the same level of care and attention."

1. **Refactor tests** with the same discipline as production code.
2. **Delete tests that no longer provide value** rather than disabling them. A disabled test is dead code.
3. **When a test becomes brittle**, examine whether it's testing implementation details. Push coverage down to a more stable level.
4. **When a high-level test finds a bug**, add a lower-level test that catches the same defect. The lower-level test is faster, more stable, and more diagnostic.
5. **Review test code in code reviews** with the same rigor as production code.

---

## 15. Property-Based Testing

Koen Claessen and John Hughes invented QuickCheck and published "QuickCheck: A Lightweight Tool for Random Testing of Haskell Programs" (ACM ICFP, 2000). The approach has since been ported to 35+ languages.

### 15.1 The Core Idea

Instead of writing tests with specific inputs and specific expected outputs, write **properties** -- invariants that must hold for *all* valid inputs:

| Property Type | Example |
|--------------|---------|
| **Round-trip** | `read(write(data)) == data` |
| **Idempotence** | `format(format(card)) == format(card)` |
| **Monotonicity** | `fileSize after write >= fileSize before write` |
| **No-crash** | `f(anyValidInput)` never panics or corrupts state |
| **Preservation** | `unmount(mount(card))` leaves card in original state |

The framework generates hundreds or thousands of random inputs and checks the property against each one. When a violation is found, it **shrinks** the failing input to the minimal reproducing case.

### 15.2 When Property-Based Testing Shines

- **Data encoding/decoding.** Round-trip properties catch corruption that specific examples miss.
- **Stateful APIs.** Generate random sequences of API calls and verify invariants hold after each step.
- **Edge case discovery.** The generator explores input combinations a human wouldn't think of.

### 15.3 Relationship to Example-Based Tests

Property-based testing *complements* example-based testing; it does not replace it. Example tests document specific, known, important cases. Property tests explore the vast space of cases you didn't think of.

---

## 16. Applying These Principles to a Driver or Library

Here is a systematic method for building a regression suite for a software library, driver, or API. This synthesizes the principles above into a concrete process.

### Step 1: Catalog the API Surface

List every public method. For each method, document:
- Parameters and their valid ranges
- Return values (success and all error codes)
- Preconditions (what must be true before calling)
- Postconditions (what is guaranteed after calling)
- Side effects (state changes, resource allocation)

This catalog IS your test plan. Each entry generates tests.

### Step 2: Write Happy-Path Tests First

For each API method, write a test that calls it correctly and verifies the documented return value and postconditions. These are the **nominal path** tests. They form the baseline: if these fail, nothing else matters.

### Step 3: Apply Equivalence Partitioning and BVA

For each parameter, identify equivalence classes and boundary values. Write one test per class and two tests per boundary (one on each side -- the "bracket").

### Step 4: Write State Transition Tests

Model the system's states and transitions. Write a test for each valid transition. Then write a test for each *invalid* transition (wrong-state error).

### Step 5: Write Negative and Misuse Tests

For each precondition, write a test that violates it. For each error code in the API, write a test that triggers it. Verify:
- The correct error code is returned
- The system remains in a consistent state
- No resources are leaked

### Step 6: Write Data Integrity Tests

For any operation that stores and retrieves data:
- Write known data, read it back, compare byte-for-byte (round-trip oracle)
- Test at sector boundaries, cluster boundaries, and file size limits
- Test with various data patterns: all zeros, all ones, incrementing, random

### Step 7: Write Concurrency Tests (if applicable)

If the API supports concurrent access:
- Multiple readers simultaneously
- Reader and writer simultaneously
- Multiple callers from different execution contexts
- Race conditions at resource boundaries

### Step 8: Write Cross-Subsystem Isolation Tests

When a system contains multiple subsystems that share resources (a communication bus, a handle pool, a memory allocator, a lock), test that they do not contaminate each other:

- **Simultaneous use.** Operate both subsystems concurrently. Read/write through subsystem A while reading/writing through subsystem B. Verify data integrity on both sides.
- **Lifecycle independence.** Initialize A and B. Shut down A. Verify B still works correctly. Then restart A. Verify both work.
- **Resource pool sharing.** If both subsystems draw from a shared pool (handles, buffers), fill the pool from one side, free a slot, and allocate from the other side. Verify the freed slot is correctly recycled with no stale state from the previous owner.
- **Bus or channel arbitration.** If subsystems share a communication channel, verify that interleaved operations (A talks, then B talks, then A talks) produce correct results on both sides with no cross-talk or garbled data.

**Why this matters:** Resource-sharing bugs are invisible when subsystems are tested in isolation. A handle pool that works perfectly for one subsystem may corrupt state when a second subsystem recycles handles into the same pool. A shared bus may work for either subsystem alone but garble data when both are active.

### Step 9: Write Resource Exhaustion Tests

- Open maximum handles, verify the next open fails correctly
- Fill the storage medium, verify writes fail correctly
- Verify that after closing handles or freeing space, operations succeed again

### Step 10: Write Fault Injection Tests

If the system interfaces with hardware or external systems:
- Inject communication errors (bad CRC, timeout, garbled response)
- Verify detection, correct error reporting, and graceful recovery
- Verify no state corruption from the fault

### Step 11: Guard Zones and Overflow Detection

For embedded systems with manual memory management:
- Place sentinel patterns ($CC bytes) around every buffer
- After each test, verify sentinels are intact
- This catches buffer overflows that might silently corrupt adjacent data

### Step 12: Review Against Coverage Metrics

After writing the suite:
- Check code coverage: which lines/branches are untested?
- Apply manual mutation testing: introduce a deliberate bug, verify a test catches it
- If a mutation survives, add the missing test

---

## 17. Bibliography

The following works are cited in this document and recommended for further study, ordered by publication date.

1. **Myers, Glenford J.** *The Art of Software Testing.* Wiley, 1979. (3rd ed. revised by Sandler, Badgett, Thomas, 2011.)
   Foundational text defining equivalence partitioning, boundary value analysis, and error guessing.

2. **DeMillo, Richard A.; Lipton, Richard J.; Sayward, Frederick G.** "Hints on Test Data Selection: Help for the Practicing Programmer." *IEEE Computer*, 1978.
   Introduced mutation testing, the Competent Programmer Hypothesis, and the Coupling Effect.

3. **Meyer, Bertrand.** *Object-Oriented Software Construction.* Prentice Hall, 1988 (2nd ed. 1997).
   Defined Design by Contract: preconditions, postconditions, and invariants as the basis for API specification and testing.

4. **Beizer, Boris.** *Software Testing Techniques.* 2nd ed. Van Nostrand Reinhold, 1990.
   Comprehensive taxonomy of structural and functional testing techniques.

5. **Rothermel, Gregg; Harrold, Mary Jean.** "A Safe, Efficient Regression Test Selection Technique." *ACM Transactions on Software Engineering and Methodology*, 1997.
   Foundational framework for regression test selection and the inclusiveness metric.

6. **Claessen, Koen; Hughes, John.** "QuickCheck: A Lightweight Tool for Random Testing of Haskell Programs." *ACM ICFP*, 2000.
   Introduced property-based testing and automatic shrinking of counterexamples.

7. **Beck, Kent.** *Test-Driven Development: By Example.* Addison-Wesley, 2002.
   Established the TDD methodology: red-green-refactor.

8. **Feathers, Michael.** *Working Effectively with Legacy Code.* Prentice Hall, 2004.
   Defines legacy code as "code without tests." Introduces seams, sensing, separation, and pinch points for testability.

9. **Meszaros, Gerard.** *xUnit Test Patterns: Refactoring Test Code.* Addison-Wesley, 2007.
   The canonical reference for test automation patterns. Catalogs 68 patterns and 18 test smells.

10. **Martin, Robert C.** *Clean Code: A Handbook of Agile Software Craftsmanship.* Prentice Hall, 2008.
    Chapter 9 defines the FIRST properties of unit tests (Fast, Independent, Repeatable, Self-Validating, Timely).

11. **Osherove, Roy.** *The Art of Unit Testing.* Manning, 2009 (3rd ed. with Vladimir Khorikov, 2021).
    Established the standard naming convention and the Arrange-Act-Assert pattern.

12. **Cohn, Mike.** *Succeeding with Agile: Software Development Using Scrum.* Addison-Wesley, 2009.
    Introduced the Test Automation Pyramid.

13. **Crispin, Lisa; Gregory, Janet.** *Agile Testing: A Practical Guide for Testers and Agile Teams.* Addison-Wesley, 2009.
    Extended Brian Marick's test matrix into the Agile Testing Quadrants framework.

14. **Freeman, Steve; Pryce, Nat.** *Growing Object-Oriented Software, Guided by Tests.* Addison-Wesley, 2009.
    Definitive treatment of outside-in TDD, flickering tests, and the dangers of over-specification.

15. **Humble, Jez; Farley, David.** *Continuous Delivery.* Addison-Wesley, 2010.
    Introduced the deployment pipeline and how to embed testing at each stage.

16. **Yoo, Shin; Harman, Mark.** "Regression Testing Minimisation, Selection and Prioritisation: A Survey." *Software Testing, Verification and Reliability*, 2012.
    Definitive survey of regression test selection and prioritization techniques, including APFD.

17. **Fowler, Martin.** "TestPyramid." martinfowler.com, 2012.
    The most-cited explanation of the test automation pyramid.

18. **Vocke, Ham.** "The Practical Test Pyramid." martinfowler.com, 2018.
    Practical implementation guidance for the pyramid, with the principle: "Test code is as important as production code."

19. **Dodds, Kent C.** "The Testing Trophy and Testing Classifications." kentcdodds.com, 2018.
    Proposed the Testing Trophy model emphasizing integration tests and static analysis.

20. **Khorikov, Vladimir.** *Unit Testing: Principles, Practices, and Patterns.* Manning, 2020.
    Distinguishes London vs. Classical schools. Rigorous treatment of which tests provide value.

21. **Farley, David.** *Modern Software Engineering.* Addison-Wesley, 2022.
    Argues TDD is "a method of working that produces a pressure to write code that is more testable, and testable code has the same attributes as code that is easy to maintain."

---

*Document created 2026-03-04. Companion to REGRESSION-TEST-STYLE-GUIDE.md (project-specific coding conventions for test files).*
