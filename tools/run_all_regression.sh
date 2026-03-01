#!/bin/bash
#
# run_all_regression.sh - Run full regression suite: dual-device + SD + Flash + cross-device
#
# Usage: ./run_all_regression.sh [--include-format] [--include-testcard] [--include-8cog] [--compile-only]
#
# Runs in order:
#   1. Dual-device verification (37 tests)
#   2. SD regression suites (424+ tests)
#   3. Flash regression suites (430+ tests)
#   4. Cross-device tests (21 tests)
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

# Parse arguments and build per-phase arg lists
COMPILE_ONLY=false
SD_ARGS=()
FLASH_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --compile-only)
            COMPILE_ONLY=true
            SD_ARGS+=("$arg")
            FLASH_ARGS+=("$arg")
            ;;
        --include-format|--include-testcard)
            SD_ARGS+=("$arg")
            ;;
        --include-8cog)
            FLASH_ARGS+=("$arg")
            ;;
    esac
done

echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  Full Regression Suite${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""

PHASE_PASS=0
PHASE_FAIL=0
PHASE_FAILED=()

# Compute include paths once (same as run_sd_regression.sh)
_relpath() {
    python3 -c "import os; print(os.path.relpath('$1', '$2'))"
}
SRC_PATH="$(_relpath "$PROJECT_ROOT/src" "$REGTEST_DIR")"
UTILS_PATH="$(_relpath "$PROJECT_ROOT/src/UTILS" "$REGTEST_DIR")"
DEMO_PATH="$(_relpath "$PROJECT_ROOT/src/DEMO" "$REGTEST_DIR")"
REF_SD_SRC="$(_relpath "$PROJECT_ROOT/REF-FLASH-uSD/uSD-FAT32/src" "$REGTEST_DIR")"
REF_SD_UTILS="$(_relpath "$PROJECT_ROOT/REF-FLASH-uSD/uSD-FAT32/src/UTILS" "$REGTEST_DIR")"
REF_SD_DEMO="$(_relpath "$PROJECT_ROOT/REF-FLASH-uSD/uSD-FAT32/src/DEMO" "$REGTEST_DIR")"

# --- Helper: compile and optionally run a single test file ---
run_single_test() {
    local FILE="$1"
    local TIMEOUT="$2"
    local LABEL="$3"

    if [[ "$COMPILE_ONLY" == true ]]; then
        cd "$REGTEST_DIR"
        if pnut-ts -d -I "$SRC_PATH" -I "$UTILS_PATH" -I "$DEMO_PATH" -I "$REF_SD_SRC" -I "$REF_SD_UTILS" -I "$REF_SD_DEMO" "$FILE" >/dev/null 2>&1; then
            echo -e "  ${GREEN}OK${NC}: $FILE"
            cd "$SCRIPT_DIR"
            return 0
        else
            echo -e "  ${RED}FAIL${NC}: $FILE"
            cd "$SCRIPT_DIR"
            return 1
        fi
    else
        if ./run_test.sh "../src/regression-tests/$FILE" -t "$TIMEOUT"; then
            return 0
        else
            return 1
        fi
    fi
}

# --- Dual-Device Verification ---
echo -e "${CYAN}=== Dual-Device Verification (37 tests) ===${NC}"
if run_single_test "DFS_RT_dual_device_tests.spin2" 120 "Dual-Device"; then
    PHASE_PASS=$((PHASE_PASS + 1))
else
    PHASE_FAIL=$((PHASE_FAIL + 1))
    PHASE_FAILED+=("Dual-Device")
fi
echo ""

# --- SD Regression Suites ---
echo -e "${CYAN}=== SD Regression Suites ===${NC}"
if ./run_sd_regression.sh "${SD_ARGS[@]}"; then
    PHASE_PASS=$((PHASE_PASS + 1))
else
    PHASE_FAIL=$((PHASE_FAIL + 1))
    PHASE_FAILED+=("SD Regression")
fi
echo ""

# --- Flash Regression Suites ---
echo -e "${CYAN}=== Flash Regression Suites ===${NC}"
if ./run_flash_regression.sh "${FLASH_ARGS[@]}"; then
    PHASE_PASS=$((PHASE_PASS + 1))
else
    PHASE_FAIL=$((PHASE_FAIL + 1))
    PHASE_FAILED+=("Flash Regression")
fi
echo ""

# --- Cross-Device Tests ---
echo -e "${CYAN}=== Cross-Device Tests (21 tests) ===${NC}"
if run_single_test "DFS_RT_cross_device_tests.spin2" 120 "Cross-Device"; then
    PHASE_PASS=$((PHASE_PASS + 1))
else
    PHASE_FAIL=$((PHASE_FAIL + 1))
    PHASE_FAILED+=("Cross-Device")
fi
echo ""

# --- Final Summary ---
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  Full Regression Summary${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""
echo -e "  Suite groups passed: ${GREEN}${PHASE_PASS}${NC}"
echo -e "  Suite groups failed: ${RED}${PHASE_FAIL}${NC}"
echo ""

if [[ $PHASE_FAIL -gt 0 ]]; then
    echo -e "${RED}Failed suites:${NC}"
    for p in "${PHASE_FAILED[@]}"; do
        echo "  - $p"
    done
    echo ""
    exit 1
fi

echo -e "${GREEN}All regression tests passed!${NC}"
exit 0
