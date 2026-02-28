#!/bin/bash
#
# run_all_regression.sh - Run Phase 1-3 verification + Phase 4 SD + Phase 5 Flash regression
#
# Usage: ./run_all_regression.sh [--include-format] [--include-testcard] [--include-8cog] [--compile-only]
#
# Runs in order:
#   1. Phase 1 SD verification (25 tests)
#   2. Phase 2 dual-device verification (27 tests)
#   3. Phase 3 Flash file ops verification (43 tests)
#   4. Phase 4 SD regression suites (345+ tests)
#   5. Phase 5 Flash regression suites (849+ tests)
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

# Parse arguments and build per-phase arg lists
COMPILE_ONLY=false
PHASE4_ARGS=()
PHASE5_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --compile-only)
            COMPILE_ONLY=true
            PHASE4_ARGS+=("$arg")
            PHASE5_ARGS+=("$arg")
            ;;
        --include-format|--include-testcard)
            PHASE4_ARGS+=("$arg")
            ;;
        --include-8cog)
            PHASE5_ARGS+=("$arg")
            ;;
    esac
done

echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  Full Regression Suite (Phase 1-5)${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""

PHASE_PASS=0
PHASE_FAIL=0
PHASE_FAILED=()

# --- Phase 1: SD verification ---
echo -e "${CYAN}=== Phase 1: SD Verification (25 tests) ===${NC}"
if [[ "$COMPILE_ONLY" == true ]]; then
    cd "$PROJECT_ROOT/src"
    if pnut-ts -d DFS_SD_RT_phase1_verify.spin2 >/dev/null 2>&1; then
        echo -e "  ${GREEN}OK${NC}: DFS_SD_RT_phase1_verify.spin2"
        PHASE_PASS=$((PHASE_PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}: DFS_SD_RT_phase1_verify.spin2"
        PHASE_FAIL=$((PHASE_FAIL + 1))
        PHASE_FAILED+=("Phase 1")
    fi
    cd "$SCRIPT_DIR"
else
    if ./run_test.sh ../src/DFS_SD_RT_phase1_verify.spin2 -t 120; then
        PHASE_PASS=$((PHASE_PASS + 1))
    else
        PHASE_FAIL=$((PHASE_FAIL + 1))
        PHASE_FAILED+=("Phase 1")
    fi
fi
echo ""

# --- Phase 2: Dual-device verification ---
echo -e "${CYAN}=== Phase 2: Dual-Device Verification (27 tests) ===${NC}"
if [[ "$COMPILE_ONLY" == true ]]; then
    cd "$PROJECT_ROOT/src"
    if pnut-ts -d DFS_RT_phase2_verify.spin2 >/dev/null 2>&1; then
        echo -e "  ${GREEN}OK${NC}: DFS_RT_phase2_verify.spin2"
        PHASE_PASS=$((PHASE_PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}: DFS_RT_phase2_verify.spin2"
        PHASE_FAIL=$((PHASE_FAIL + 1))
        PHASE_FAILED+=("Phase 2")
    fi
    cd "$SCRIPT_DIR"
else
    if ./run_test.sh ../src/DFS_RT_phase2_verify.spin2 -t 120; then
        PHASE_PASS=$((PHASE_PASS + 1))
    else
        PHASE_FAIL=$((PHASE_FAIL + 1))
        PHASE_FAILED+=("Phase 2")
    fi
fi
echo ""

# --- Phase 3: Flash file ops verification ---
echo -e "${CYAN}=== Phase 3: Flash File Ops Verification (43 tests) ===${NC}"
if [[ "$COMPILE_ONLY" == true ]]; then
    cd "$PROJECT_ROOT/src"
    if pnut-ts -d DFS_RT_phase3_verify.spin2 >/dev/null 2>&1; then
        echo -e "  ${GREEN}OK${NC}: DFS_RT_phase3_verify.spin2"
        PHASE_PASS=$((PHASE_PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}: DFS_RT_phase3_verify.spin2"
        PHASE_FAIL=$((PHASE_FAIL + 1))
        PHASE_FAILED+=("Phase 3")
    fi
    cd "$SCRIPT_DIR"
else
    if ./run_test.sh ../src/DFS_RT_phase3_verify.spin2 -t 120; then
        PHASE_PASS=$((PHASE_PASS + 1))
    else
        PHASE_FAIL=$((PHASE_FAIL + 1))
        PHASE_FAILED+=("Phase 3")
    fi
fi
echo ""

# --- Phase 4: SD regression suites ---
echo -e "${CYAN}=== Phase 4: SD Regression Suites ===${NC}"
if ./run_phase4_regression.sh "${PHASE4_ARGS[@]}"; then
    PHASE_PASS=$((PHASE_PASS + 1))
else
    PHASE_FAIL=$((PHASE_FAIL + 1))
    PHASE_FAILED+=("Phase 4")
fi
echo ""

# --- Phase 5: Flash regression suites ---
echo -e "${CYAN}=== Phase 5: Flash Regression Suites ===${NC}"
if ./run_phase5_regression.sh "${PHASE5_ARGS[@]}"; then
    PHASE_PASS=$((PHASE_PASS + 1))
else
    PHASE_FAIL=$((PHASE_FAIL + 1))
    PHASE_FAILED+=("Phase 5")
fi
echo ""

# --- Final Summary ---
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  Full Regression Summary${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""
echo -e "  Phase groups passed: ${GREEN}${PHASE_PASS}${NC}"
echo -e "  Phase groups failed: ${RED}${PHASE_FAIL}${NC}"
echo ""

if [[ $PHASE_FAIL -gt 0 ]]; then
    echo -e "${RED}Failed phases:${NC}"
    for p in "${PHASE_FAILED[@]}"; do
        echo "  - $p"
    done
    echo ""
    exit 1
fi

echo -e "${GREEN}All regression tests passed!${NC}"
exit 0
