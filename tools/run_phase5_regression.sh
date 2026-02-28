#!/bin/bash
#
# run_phase5_regression.sh - Run all Phase 5 migrated Flash regression tests
#
# Usage: ./run_phase5_regression.sh [--include-8cog] [--compile-only]
#
# Runs all DFS_FL_RT_* test suites through the unified dual_fs driver.
# The 8cog test is excluded by default (high resource usage, long runtime).
#
# IMPORTANT: circular_compat_tests depends on data written by circular_tests.
# They MUST run in order. Do NOT run circular_compat without circular first.
#
# Options:
#   --include-8cog   Include 8-cog stress test (long runtime)
#   --compile-only   Only compile all tests, do not run on hardware
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Verify we're in tools directory ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR_NAME="$(basename "$SCRIPT_DIR")"

if [[ "$TOOLS_DIR_NAME" != "tools" ]]; then
    echo -e "${RED}Error: This script must be run from the tools/ directory${NC}"
    exit 1
fi

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGTEST_DIR="$PROJECT_ROOT/src/regression-tests"

# --- Parse Arguments ---
INCLUDE_8COG=false
COMPILE_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --include-8cog)   INCLUDE_8COG=true; shift ;;
        --compile-only)   COMPILE_ONLY=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--include-8cog] [--compile-only]"
            echo ""
            echo "Options:"
            echo "  --include-8cog   Include 8-cog stress test (long runtime)"
            echo "  --compile-only   Only compile, do not run on hardware"
            exit 0
            ;;
        *) echo -e "${RED}Error: Unknown option: $1${NC}"; exit 1 ;;
    esac
done

# --- Define test suites with timeouts ---
# Format: "filename:timeout_secs"
# Order matters: circular_compat depends on circular_tests data
STANDARD_TESTS=(
    "DFS_FL_RT_rw_block_tests.spin2:90"
    "DFS_FL_RT_rw_modify_tests.spin2:90"
    "DFS_FL_RT_mount_handle_basics_tests.spin2:120"
    "DFS_FL_RT_rw_tests.spin2:120"
    "DFS_FL_RT_append_tests.spin2:120"
    "DFS_FL_RT_seek_tests.spin2:90"
    "DFS_FL_RT_circular_tests.spin2:120"
    "DFS_FL_RT_circular_compat_tests.spin2:120"
)

EIGHT_COG_TEST="DFS_FL_RT_8cog_tests.spin2:180"

# Build full test list
ALL_TESTS=("${STANDARD_TESTS[@]}")
if [[ "$INCLUDE_8COG" == true ]]; then
    ALL_TESTS+=("$EIGHT_COG_TEST")
fi

# --- Banner ---
echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  Phase 5: Flash Regression Tests via Unified Driver${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""
echo "  Test suites: ${#ALL_TESTS[@]}"
echo "  8-cog test: $([[ "$INCLUDE_8COG" == true ]] && echo "INCLUDED" || echo "excluded")"
echo "  Mode: $([[ "$COMPILE_ONLY" == true ]] && echo "COMPILE ONLY" || echo "COMPILE + RUN")"
echo ""

# --- Phase 1: Compile all tests first ---
echo -e "${CYAN}--- Phase 1: Compiling all test suites ---${NC}"
echo ""

COMPILE_PASS=0
COMPILE_FAIL=0
COMPILE_FAILED_FILES=()

cd "$REGTEST_DIR"

# Compute include paths once
_relpath() {
    python3 -c "import os; print(os.path.relpath('$1', '$2'))"
}
SRC_PATH="$(_relpath "$PROJECT_ROOT/src" "$REGTEST_DIR")"

for entry in "${ALL_TESTS[@]}"; do
    FILE="${entry%%:*}"
    if [[ ! -f "$FILE" ]]; then
        echo -e "  ${RED}MISSING${NC}: $FILE"
        COMPILE_FAIL=$((COMPILE_FAIL + 1))
        COMPILE_FAILED_FILES+=("$FILE")
        continue
    fi

    BASENAME="${FILE%.spin2}"
    if pnut-ts -d -I "$SRC_PATH" "$FILE" >/dev/null 2>&1; then
        SIZE=$(wc -c < "${BASENAME}.bin" | tr -d ' ')
        echo -e "  ${GREEN}OK${NC}: $FILE (${SIZE} bytes)"
        COMPILE_PASS=$((COMPILE_PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}: $FILE"
        pnut-ts -d -I "$SRC_PATH" "$FILE" 2>&1 | grep -i error || true
        COMPILE_FAIL=$((COMPILE_FAIL + 1))
        COMPILE_FAILED_FILES+=("$FILE")
    fi
done

cd "$SCRIPT_DIR"

echo ""
echo -e "  Compile results: ${GREEN}${COMPILE_PASS} pass${NC}, ${RED}${COMPILE_FAIL} fail${NC}"
echo ""

if [[ $COMPILE_FAIL -gt 0 ]]; then
    echo -e "${RED}Compile failures:${NC}"
    for f in "${COMPILE_FAILED_FILES[@]}"; do
        echo "  - $f"
    done
    echo ""
    echo -e "${RED}Fix compile errors before running tests.${NC}"
    exit 1
fi

if [[ "$COMPILE_ONLY" == true ]]; then
    echo -e "${GREEN}All ${COMPILE_PASS} test suites compiled successfully.${NC}"
    exit 0
fi

# --- Phase 2: Run all tests on hardware ---
echo -e "${CYAN}--- Phase 2: Running tests on hardware ---${NC}"
echo ""

RUN_PASS=0
RUN_FAIL=0
RUN_FAILED_FILES=()
TOTAL_TIME=0

for entry in "${ALL_TESTS[@]}"; do
    FILE="${entry%%:*}"
    TIMEOUT="${entry##*:}"

    echo -e "${BOLD}--- $FILE (timeout: ${TIMEOUT}s) ---${NC}"

    START_TIME=$(date +%s)
    if ./run_test.sh "../src/regression-tests/$FILE" -t "$TIMEOUT"; then
        RUN_PASS=$((RUN_PASS + 1))
    else
        RUN_FAIL=$((RUN_FAIL + 1))
        RUN_FAILED_FILES+=("$FILE")
    fi
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    TOTAL_TIME=$((TOTAL_TIME + ELAPSED))

    echo ""
done

# --- Summary ---
echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  Phase 5 Regression Results${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""
echo "  Suites run:    ${#ALL_TESTS[@]}"
echo -e "  Passed:        ${GREEN}${RUN_PASS}${NC}"
echo -e "  Failed:        ${RED}${RUN_FAIL}${NC}"
echo "  Total time:    ${TOTAL_TIME}s"
echo ""

if [[ $RUN_FAIL -gt 0 ]]; then
    echo -e "${RED}Failed suites:${NC}"
    for f in "${RUN_FAILED_FILES[@]}"; do
        echo "  - $f"
    done
    echo ""
    exit 1
fi

echo -e "${GREEN}All Phase 5 tests passed!${NC}"
exit 0
