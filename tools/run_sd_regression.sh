#!/bin/bash
#
# run_sd_regression.sh - Run all SD regression tests
#
# Usage: ./run_sd_regression.sh [--include-format] [--include-testcard] [--compile-only]
#
# Runs all DFS_SD_RT_* test suites through the unified driver.
# Format tests and testcard validation are excluded by default (destructive/special card).
#
# Options:
#   --include-format    Include format tests (WARNING: erases SD card!)
#   --include-testcard  Include testcard validation (requires pre-formatted test card)
#   --compile-only      Only compile all tests, do not run on hardware
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
INCLUDE_FORMAT=false
INCLUDE_TESTCARD=false
COMPILE_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --include-format)    INCLUDE_FORMAT=true; shift ;;
        --include-testcard)  INCLUDE_TESTCARD=true; shift ;;
        --compile-only)      COMPILE_ONLY=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--include-format] [--include-testcard] [--compile-only]"
            echo ""
            echo "Options:"
            echo "  --include-format    Include format tests (WARNING: erases SD card!)"
            echo "  --include-testcard  Include testcard validation (needs test card)"
            echo "  --compile-only      Only compile, do not run on hardware"
            exit 0
            ;;
        *) echo -e "${RED}Error: Unknown option: $1${NC}"; exit 1 ;;
    esac
done

# --- Define test suites with timeouts ---
# Format: "filename:timeout_secs"
STANDARD_TESTS=(
    "DFS_SD_RT_mount_tests.spin2:60"
    "DFS_SD_RT_error_handling_tests.spin2:60"
    "DFS_SD_RT_multihandle_tests.spin2:60"
    "DFS_SD_RT_file_ops_tests.spin2:60"
    "DFS_SD_RT_read_write_tests.spin2:90"
    "DFS_SD_RT_subdir_ops_tests.spin2:60"
    "DFS_SD_RT_dirhandle_tests.spin2:60"
    "DFS_SD_RT_directory_tests.spin2:60"
    "DFS_SD_RT_volume_tests.spin2:60"
    "DFS_SD_RT_seek_tests.spin2:60"
    "DFS_SD_RT_crc_diag_tests.spin2:60"
    "DFS_SD_RT_register_tests.spin2:60"
    "DFS_SD_RT_speed_tests.spin2:60"
    "DFS_SD_RT_raw_sector_tests.spin2:60"
    "DFS_SD_RT_multiblock_tests.spin2:90"
    "DFS_SD_RT_multicog_tests.spin2:120"
    "DFS_SD_RT_parity_tests.spin2:90"
)

FORMAT_TEST="DFS_SD_RT_format_tests.spin2:300"
TESTCARD_TEST="DFS_SD_RT_testcard_validation.spin2:120"

# Build full test list
ALL_TESTS=("${STANDARD_TESTS[@]}")
if [[ "$INCLUDE_FORMAT" == true ]]; then
    ALL_TESTS+=("$FORMAT_TEST")
fi
if [[ "$INCLUDE_TESTCARD" == true ]]; then
    ALL_TESTS+=("$TESTCARD_TEST")
fi

# --- Banner ---
echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  SD Regression Tests via Unified Driver${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""
echo "  Test suites: ${#ALL_TESTS[@]}"
echo "  Format tests: $([[ "$INCLUDE_FORMAT" == true ]] && echo "INCLUDED (destructive!)" || echo "excluded")"
echo "  Testcard tests: $([[ "$INCLUDE_TESTCARD" == true ]] && echo "INCLUDED" || echo "excluded")"
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
UTILS_PATH="$(_relpath "$PROJECT_ROOT/src/UTILS" "$REGTEST_DIR")"
DEMO_PATH="$(_relpath "$PROJECT_ROOT/src/DEMO" "$REGTEST_DIR")"
REF_SD_SRC="$(_relpath "$PROJECT_ROOT/REF-FLASH-uSD/uSD-FAT32/src" "$REGTEST_DIR")"
REF_SD_UTILS="$(_relpath "$PROJECT_ROOT/REF-FLASH-uSD/uSD-FAT32/src/UTILS" "$REGTEST_DIR")"
REF_SD_DEMO="$(_relpath "$PROJECT_ROOT/REF-FLASH-uSD/uSD-FAT32/src/DEMO" "$REGTEST_DIR")"

for entry in "${ALL_TESTS[@]}"; do
    FILE="${entry%%:*}"
    if [[ ! -f "$FILE" ]]; then
        echo -e "  ${RED}MISSING${NC}: $FILE"
        COMPILE_FAIL=$((COMPILE_FAIL + 1))
        COMPILE_FAILED_FILES+=("$FILE")
        continue
    fi

    BASENAME="${FILE%.spin2}"
    if pnut-ts -d -I "$SRC_PATH" -I "$UTILS_PATH" -I "$DEMO_PATH" -I "$REF_SD_SRC" -I "$REF_SD_UTILS" -I "$REF_SD_DEMO" "$FILE" >/dev/null 2>&1; then
        SIZE=$(wc -c < "${BASENAME}.bin" | tr -d ' ')
        echo -e "  ${GREEN}OK${NC}: $FILE (${SIZE} bytes)"
        COMPILE_PASS=$((COMPILE_PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}: $FILE"
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
echo -e "${BOLD}  SD Regression Results${NC}"
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

echo -e "${GREEN}All SD regression tests passed!${NC}"
exit 0
