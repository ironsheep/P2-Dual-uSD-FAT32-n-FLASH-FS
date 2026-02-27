# Systematic Debugging Methodology

**Purpose:** A disciplined approach to finding root causes when defects are difficult to locate.

**Core Insight:** When a problem is hard to find, it's usually because we haven't collected all the symptoms. Without the complete picture, we resort to trial-and-error guessing, which is deeply ineffective.

---

## The Process

### Phase 1: Symptom Collection (No Filtering)

**Goal:** Gather EVERY observable symptom without judgment or classification.

**Rules:**
- Do NOT classify symptoms as "primary" or "secondary"
- Do NOT dismiss anything as "probably unrelated"
- Do NOT apply your existing mental model (it's incomplete - that's why you're stuck)
- Treat every symptom as equally important initially

**Sources to examine:**
- All available log files from failing runs
- All available log files from passing runs (for comparison)
- Any error messages, return values, debug output
- Timing observations (when does it fail, how often)
- State observations (what values were present)

**Document each symptom as a simple factual statement:**
- "Test #20 failed with X instead of Y"
- "sec_in_buf showed value 63,572 when reading sector 38,688"
- "Failure occurred 1 in 6 runs"
- "Buffer position 128 contained garbage"

### Phase 2: Trace Each Symptom to Root Cause

**Goal:** For EACH symptom, follow the code path that could produce it.

**Rules:**
- No symptom gets dismissed without being traced through code
- "I don't think that's related" is NOT valid reasoning
- "I traced this through code and it's caused by X" IS valid reasoning
- Be suspicious if you conclude something is "unrelated" - prove it

**For each symptom, ask:**
1. What code path produces this output/behavior?
2. What conditions cause this code path to execute?
3. What state must exist for this to happen?
4. Trace backwards: what sets that state?

**Document your trace:**
```
Symptom: [factual statement]
Code path: [function] at line [N] -> [function] at line [M] -> ...
Conditions required: [what must be true for this path]
State dependency: [what variables/state affect this]
Conclusion: [root cause found | side effect of X | needs instrumentation]
```

### Phase 3: Identify Convergence

**Goal:** Find where multiple symptom traces point to the same code or state.

**Key principle:** A good root cause hypothesis explains MULTIPLE symptoms. If you have a hypothesis that only explains one symptom, it's probably not root cause.

**Look for:**
- Multiple symptoms that trace back to the same function
- Multiple symptoms that depend on the same state variable
- Multiple symptoms that require the same precondition

**The root cause should explain:**
- Why the failure occurs
- Why it's intermittent (if applicable)
- All or most of the observed symptoms

### Phase 4: Prove or Disprove in Code

**Goal:** Validate hypotheses through static code analysis before running tests.

**For each hypothesis, define:**
- What evidence would PROVE this hypothesis?
- What evidence would DISPROVE this hypothesis?
- What code path would need to execute?
- What conditions would need to exist?

**Search the code for:**
- Can these conditions actually occur?
- Is there a code path that creates this situation?
- What would prevent this from always happening? (explains intermittent)

**Document eliminations:**
- Track what was ruled out and WHY
- This prevents revisiting dead ends
- "Ruled out hypothesis X because [specific code evidence]"

### Phase 5: Instrumentation (Only If Needed)

**Goal:** Add targeted instrumentation only for hypotheses that cannot be proven/disproven through code analysis.

**Before adding any debug code, specify:**
- What specific question does this instrumentation answer?
- What values/state need to be captured?
- Where in the code path is the critical observation point?
- What result would prove the hypothesis?
- What result would disprove it?

**Avoid:**
- Shotgun debugging (adding prints everywhere)
- Instrumentation without a specific question
- Changing code while instrumenting (confounds results)

---

## Common Root Cause Categories

When tracing symptoms, be aware these are common bug patterns:

1. **Stale State** - Using a cached/stored value after it should have been invalidated
2. **Shared Resource Conflict** - Multiple operations using the same resource (buffer, variable) without proper coordination
3. **Ordering/Timing** - Operations happening in unexpected order
4. **Boundary Conditions** - Off-by-one, buffer limits, edge cases
5. **Missing Invalidation** - State not cleared/reset when it should be
6. **Incorrect Assumptions** - Code assumes something that isn't always true

---

## Anti-Patterns to Avoid

1. **Premature Classification** - Labeling symptoms as "primary/secondary" before investigation
2. **Assumption-Based Filtering** - Dismissing symptoms because they don't fit your mental model
3. **Trial-and-Error Fixes** - Making changes to "see if they help" without understanding root cause
4. **Single-Symptom Hypotheses** - A hypothesis that only explains one symptom is probably wrong
5. **Uninstrumented Testing** - Running tests without specific questions to answer
6. **Confirmation Bias** - Only looking for evidence that supports your theory

---

## Template: Symptom Investigation Log

```markdown
# Symptom Investigation: [Brief Description]

## Symptoms Collected
| # | Symptom | Source | Run |
|---|---------|--------|-----|
| 1 | [factual statement] | [log file] | [pass/fail] |
| 2 | ... | ... | ... |

## Symptom Traces
### Symptom 1: [statement]
- Code path: ...
- Conditions: ...
- State dependencies: ...
- Conclusion: ...

### Symptom 2: [statement]
...

## Convergence Analysis
- Symptoms [1, 3, 5] all trace to [function/state]
- This suggests root cause is related to [X]

## Hypotheses
### Hypothesis A: [description]
- Explains symptoms: [1, 3, 5]
- Would be proven by: [evidence]
- Would be disproven by: [evidence]
- Code analysis result: [proven/disproven/needs testing]

## Eliminated Hypotheses
- [Hypothesis X]: Ruled out because [specific evidence]

## Remaining Questions (Need Instrumentation)
- [Specific question requiring runtime observation]
```

---

## When to Use This Methodology

Apply this systematic approach when:
- You've spent significant time without finding root cause
- Trial-and-error changes aren't working
- The failure is intermittent
- You find yourself saying "I don't understand why this happens"

The time invested in systematic symptom collection ALWAYS pays off faster than continued guessing.
