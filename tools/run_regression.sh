#!/bin/bash
#
# run_regression.sh - Unified regression runner for dual-FS driver
#
# Usage: ./run_regression.sh [options]
#
# Runs all regression suites in dependency order (foundational-first),
# with stop-on-first-failure, per-file progress, and a final summary table.
#
# Options:
#   --from <name>      Resume from a specific suite (substring match on basename).
#                      Compiles only that suite and remaining, then runs from there.
#   --include-8cog     Include 8-cog stress test (long runtime)
#   --include-format   Include format test (WARNING: erases SD card!)
#   --compile-only     Only compile all tests, do not run on hardware
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
LOG_DIR="$SCRIPT_DIR/logs"

# --- Parse Arguments ---
INCLUDE_8COG=false
INCLUDE_FORMAT=false
COMPILE_ONLY=false
FROM_SUITE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo -e "${RED}Error: --from requires a suite name (substring match)${NC}"
                exit 1
            fi
            FROM_SUITE="$2"
            shift 2
            ;;
        --include-8cog)    INCLUDE_8COG=true; shift ;;
        --include-format)  INCLUDE_FORMAT=true; shift ;;
        --compile-only)    COMPILE_ONLY=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--from <name>] [--include-8cog] [--include-format] [--compile-only]"
            echo ""
            echo "Options:"
            echo "  --from <name>      Resume from suite matching <name> (substring match)"
            echo "  --include-8cog     Include 8-cog stress test (long runtime)"
            echo "  --include-format   Include format test (WARNING: erases SD card!)"
            echo "  --compile-only     Only compile, do not run on hardware"
            echo ""
            echo "Examples:"
            echo "  $0                              # Full regression"
            echo "  $0 --from cwd                   # Resume from DFS_FL_RT_cwd_tests"
            echo "  $0 --from dual_device           # Resume from DFS_RT_dual_device_tests"
            echo "  $0 --compile-only               # Compile check only"
            exit 0
            ;;
        *) echo -e "${RED}Error: Unknown option: $1${NC}"; exit 1 ;;
    esac
done

# --- Define test suites in dependency order ---
# Format: "filename:timeout_secs"
# Ordered foundational-first so failures in lower layers are caught early.

# Layer 1: Mount/Init
SUITES=(
    "DFS_SD_RT_mount_tests.spin2:60"
    "DFS_FL_RT_mount_handle_basics_tests.spin2:120"
)

# Layer 2: Raw I/O (below filesystem)
SUITES+=(
    "DFS_SD_RT_raw_sector_tests.spin2:60"
    "DFS_SD_RT_multiblock_tests.spin2:90"
    "DFS_FL_RT_rw_block_tests.spin2:90"
)

# Layer 3: Hardware features
SUITES+=(
    "DFS_SD_RT_register_tests.spin2:60"
    "DFS_SD_RT_speed_tests.spin2:60"
    "DFS_SD_RT_crc_diag_tests.spin2:60"
)

# Layer 4: Basic file I/O
SUITES+=(
    "DFS_SD_RT_error_handling_tests.spin2:60"
    "DFS_SD_RT_multihandle_tests.spin2:60"
    "DFS_SD_RT_file_ops_tests.spin2:60"
    "DFS_SD_RT_read_write_tests.spin2:90"
    "DFS_FL_RT_rw_tests.spin2:120"
    "DFS_FL_RT_rw_modify_tests.spin2:90"
)

# Layer 5: File operations
SUITES+=(
    "DFS_SD_RT_subdir_ops_tests.spin2:60"
    "DFS_SD_RT_seek_tests.spin2:60"
    "DFS_SD_RT_volume_tests.spin2:90"
    "DFS_SD_RT_timestamp_tests.spin2:60"
    "DFS_SD_RT_async_tests.spin2:60"
    "DFS_SD_RT_parity_tests.spin2:90"
    "DFS_SD_RT_defrag_tests.spin2:120"
    "DFS_FL_RT_append_tests.spin2:120"
    "DFS_FL_RT_seek_tests.spin2:90"
)

# Layer 6: Directory operations
SUITES+=(
    "DFS_SD_RT_directory_tests.spin2:60"
    "DFS_SD_RT_dirhandle_tests.spin2:60"
    "DFS_FL_RT_cwd_tests.spin2:90"
    "DFS_FL_RT_dirhandle_tests.spin2:90"
)

# Layer 7: Complex features (order matters: circular_compat depends on circular data)
SUITES+=(
    "DFS_FL_RT_circular_tests.spin2:120"
    "DFS_FL_RT_circular_compat_tests.spin2:120"
)

# Layer 8: Cross-device
SUITES+=(
    "DFS_RT_dual_device_tests.spin2:120"
    "DFS_RT_cross_device_tests.spin2:120"
)

# Layer 9: Multi-cog stress
SUITES+=(
    "DFS_SD_RT_multicog_tests.spin2:120"
)

# Optional suites
if [[ "$INCLUDE_8COG" == true ]]; then
    SUITES+=("DFS_FL_RT_8cog_tests.spin2:180")
fi
if [[ "$INCLUDE_FORMAT" == true ]]; then
    SUITES+=("DFS_SD_RT_format_tests.spin2:300")
fi

TOTAL_SUITES=${#SUITES[@]}

# --- Resolve --from to a starting index ---
START_INDEX=0

if [[ -n "$FROM_SUITE" ]]; then
    FOUND_FROM=false
    for i in "${!SUITES[@]}"; do
        FILE="${SUITES[$i]%%:*}"
        if [[ "$FILE" == *"$FROM_SUITE"* ]]; then
            START_INDEX=$i
            FOUND_FROM=true
            break
        fi
    done

    if [[ "$FOUND_FROM" == false ]]; then
        echo -e "${RED}Error: No suite matching '$FROM_SUITE'${NC}"
        echo ""
        echo "Available suites:"
        for entry in "${SUITES[@]}"; do
            echo "  ${entry%%:*}"
        done
        exit 1
    fi

    SKIP_COUNT=$START_INDEX
    RUN_COUNT=$((TOTAL_SUITES - START_INDEX))
    echo -e "${YELLOW}Resuming from: ${SUITES[$START_INDEX]%%:*}${NC}"
    echo -e "${YELLOW}Skipping $SKIP_COUNT suites, running $RUN_COUNT${NC}"
    echo ""
fi

# --- Banner ---
echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  Unified Regression Suite${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""
if [[ -n "$FROM_SUITE" ]]; then
    echo "  Total suites: ${TOTAL_SUITES} (running ${RUN_COUNT} from #$((START_INDEX + 1)))"
else
    echo "  Test suites: ${TOTAL_SUITES}"
fi
echo "  8-cog test: $([[ "$INCLUDE_8COG" == true ]] && echo "INCLUDED" || echo "excluded")"
echo "  Format test: $([[ "$INCLUDE_FORMAT" == true ]] && echo "INCLUDED (destructive!)" || echo "excluded")"
echo "  Mode: $([[ "$COMPILE_ONLY" == true ]] && echo "COMPILE ONLY" || echo "COMPILE + RUN")"
echo ""

# --- Compute include paths once ---
_relpath() {
    python3 -c "import os; print(os.path.relpath('$1', '$2'))"
}
SRC_PATH="$(_relpath "$PROJECT_ROOT/src" "$REGTEST_DIR")"
UTILS_PATH="$(_relpath "$PROJECT_ROOT/src/UTILS" "$REGTEST_DIR")"
DEMO_PATH="$(_relpath "$PROJECT_ROOT/src/DEMO" "$REGTEST_DIR")"
REF_SD_SRC="$(_relpath "$PROJECT_ROOT/REF-FLASH-uSD/uSD-FAT32/src" "$REGTEST_DIR")"
REF_SD_UTILS="$(_relpath "$PROJECT_ROOT/REF-FLASH-uSD/uSD-FAT32/src/UTILS" "$REGTEST_DIR")"
REF_SD_DEMO="$(_relpath "$PROJECT_ROOT/REF-FLASH-uSD/uSD-FAT32/src/DEMO" "$REGTEST_DIR")"

# --- Dependency-aware compilation ---
# Shared source dependencies (transitive): if ANY of these change, ALL tests need recompilation.
# Standard tests: test.spin2 + DFS_RT_utilities + dual_sd_fat32_flash_fs + isp_stack_check
# Format test adds: isp_format_utility + isp_string_fifo + isp_mem_strings
SHARED_DEPS=(
    "$PROJECT_ROOT/src/dual_sd_fat32_flash_fs.spin2"
    "$REGTEST_DIR/DFS_RT_utilities.spin2"
    "$PROJECT_ROOT/src/isp_stack_check.spin2"
)
FORMAT_EXTRA_DEPS=(
    "$PROJECT_ROOT/src/UTILS/isp_format_utility.spin2"
    "$PROJECT_ROOT/src/UTILS/isp_string_fifo.spin2"
    "$PROJECT_ROOT/src/UTILS/isp_mem_strings.spin2"
)

# Check if binary is up-to-date vs all its source dependencies
_needs_compile() {
    local bin_file="$1"
    local test_file="$2"

    # No binary? Must compile.
    [[ ! -f "$bin_file" ]] && return 0

    # Check test file itself
    [[ "$test_file" -nt "$bin_file" ]] && return 0

    # Check shared dependencies
    for dep in "${SHARED_DEPS[@]}"; do
        [[ -f "$dep" && "$dep" -nt "$bin_file" ]] && return 0
    done

    # Format test has extra dependencies
    if [[ "$test_file" == *"format_tests"* ]]; then
        for dep in "${FORMAT_EXTRA_DEPS[@]}"; do
            [[ -f "$dep" && "$dep" -nt "$bin_file" ]] && return 0
        done
    fi

    return 1  # Binary is up-to-date
}

# --- Phase 1: Compile tests (from START_INDEX onward) ---
echo -e "${CYAN}--- Phase 1: Compiling test suites ---${NC}"
echo ""

COMPILE_PASS=0
COMPILE_FAIL=0
COMPILE_SKIP=0
COMPILE_FAILED_FILES=()

cd "$REGTEST_DIR"

for i in "${!SUITES[@]}"; do
    if [[ $i -lt $START_INDEX ]]; then
        continue
    fi

    entry="${SUITES[$i]}"
    FILE="${entry%%:*}"
    if [[ ! -f "$FILE" ]]; then
        echo -e "  ${RED}MISSING${NC}: $FILE"
        COMPILE_FAIL=$((COMPILE_FAIL + 1))
        COMPILE_FAILED_FILES+=("$FILE")
        continue
    fi

    BASENAME="${FILE%.spin2}"
    BIN_FILE="${BASENAME}.bin"

    if ! _needs_compile "$BIN_FILE" "$FILE"; then
        SIZE=$(wc -c < "$BIN_FILE" | tr -d ' ')
        echo -e "  ${GREEN}SKIP${NC}: $FILE (${SIZE} bytes, up-to-date)"
        COMPILE_SKIP=$((COMPILE_SKIP + 1))
        COMPILE_PASS=$((COMPILE_PASS + 1))
        continue
    fi

    if pnut-ts -d -I "$SRC_PATH" -I "$UTILS_PATH" -I "$DEMO_PATH" -I "$REF_SD_SRC" -I "$REF_SD_UTILS" -I "$REF_SD_DEMO" "$FILE" >/dev/null 2>&1; then
        SIZE=$(wc -c < "$BIN_FILE" | tr -d ' ')
        echo -e "  ${GREEN}OK${NC}: $FILE (${SIZE} bytes)"
        COMPILE_PASS=$((COMPILE_PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}: $FILE"
        pnut-ts -d -I "$SRC_PATH" -I "$UTILS_PATH" -I "$DEMO_PATH" -I "$REF_SD_SRC" -I "$REF_SD_UTILS" -I "$REF_SD_DEMO" "$FILE" 2>&1 | grep -i error || true
        COMPILE_FAIL=$((COMPILE_FAIL + 1))
        COMPILE_FAILED_FILES+=("$FILE")
    fi
done

cd "$SCRIPT_DIR"

echo ""
if [[ $COMPILE_SKIP -gt 0 ]]; then
    echo -e "  Compile results: ${GREEN}${COMPILE_PASS} pass${NC} (${COMPILE_SKIP} skipped, up-to-date), ${RED}${COMPILE_FAIL} fail${NC}"
else
    echo -e "  Compile results: ${GREEN}${COMPILE_PASS} pass${NC}, ${RED}${COMPILE_FAIL} fail${NC}"
fi
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

# --- Phase 2: Run tests on hardware (from START_INDEX onward) ---
echo -e "${CYAN}--- Phase 2: Running tests on hardware ---${NC}"
echo ""

# Arrays to store per-suite results for summary table
declare -a RESULT_NAMES=()
declare -a RESULT_PASS=()
declare -a RESULT_FAIL=()
declare -a RESULT_TIME=()
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_TIME=0
SUITES_RUN=0
FAILED_SUITE=""

for i in "${!SUITES[@]}"; do
    if [[ $i -lt $START_INDEX ]]; then
        continue
    fi

    entry="${SUITES[$i]}"
    FILE="${entry%%:*}"
    TIMEOUT="${entry##*:}"
    BASENAME="${FILE%.spin2}"
    SUITES_RUN=$((SUITES_RUN + 1))
    SUITE_NUM=$((i + 1))

    START_TIME=$(date +%s)

    # Run the test via run_test.sh
    set +e
    ./run_test.sh "../src/regression-tests/$FILE" -t "$TIMEOUT" > /dev/null 2>&1
    RUN_EXIT=$?
    set -e

    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))

    # Parse log for pass/fail counts
    SUITE_PASS=0
    SUITE_FAIL=0

    LATEST_LOG=$(ls -t "$LOG_DIR/${BASENAME}_"*.log 2>/dev/null | head -1)

    if [[ -n "$LATEST_LOG" ]]; then
        # pnut-term-ts timestamps can split summary lines mid-word.
        # Strip timestamps, CRs, and NULs, join everything, then re-split on "Cog"
        # boundaries to reconstruct logical lines.
        CLEAN_LOG=$(sed -E 's/^\[[-0-9T:.]+\] //' "$LATEST_LOG" | tr -d '\r\0' | tr -d '\n' | sed $'s/Cog/\\\nCog/g')

        # Try ALL COGS line first (multi-cog tests), then regular summary
        SUMMARY_LINE=$(echo "$CLEAN_LOG" | grep -a "ALL COGS.*Tests - Pass:" 2>/dev/null | tail -1)
        if [[ -z "$SUMMARY_LINE" ]]; then
            SUMMARY_LINE=$(echo "$CLEAN_LOG" | grep -a "Tests - Pass:" 2>/dev/null | tail -1)
        fi

        if [[ -n "$SUMMARY_LINE" ]]; then
            SUITE_PASS=$(echo "$SUMMARY_LINE" | sed -E 's/.*Pass: *([0-9]+).*/\1/')
            SUITE_FAIL=$(echo "$SUMMARY_LINE" | sed -E 's/.*Fail: *([0-9]+).*/\1/')
        fi
    fi

    # Determine if this suite failed
    SUITE_FAILED=false
    if [[ $RUN_EXIT -ne 0 ]]; then
        SUITE_FAILED=true
    elif [[ $SUITE_FAIL -gt 0 ]]; then
        SUITE_FAILED=true
    fi

    # Store results
    RESULT_NAMES+=("$BASENAME")
    RESULT_PASS+=("$SUITE_PASS")
    RESULT_FAIL+=("$SUITE_FAIL")
    RESULT_TIME+=("$ELAPSED")
    TOTAL_PASS=$((TOTAL_PASS + SUITE_PASS))
    TOTAL_FAIL=$((TOTAL_FAIL + SUITE_FAIL))
    TOTAL_TIME=$((TOTAL_TIME + ELAPSED))

    # Print progress line
    if [[ "$SUITE_FAILED" == true ]]; then
        printf "  ${RED}[%2d/%d] %-38s %4d pass, %3d fail  [%3ds]${NC}\n" \
            "$SUITE_NUM" "$TOTAL_SUITES" "$BASENAME" "$SUITE_PASS" "$SUITE_FAIL" "$ELAPSED"
        FAILED_SUITE="$BASENAME"
        break
    else
        printf "  ${GREEN}[%2d/%d]${NC} %-38s %4d pass, %3d fail  [%3ds]\n" \
            "$SUITE_NUM" "$TOTAL_SUITES" "$BASENAME" "$SUITE_PASS" "$SUITE_FAIL" "$ELAPSED"
    fi
done

# --- Summary Table ---
echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  Regression Results${NC}"
echo -e "${BOLD}============================================================${NC}"
printf "  %-4s %-38s %5s %5s %5s\n" "#" "Suite" "Pass" "Fail" "Time"
printf "  %-4s %-38s %5s %5s %5s\n" "--" "--------------------------------------" "----" "----" "----"

for j in "${!RESULT_NAMES[@]}"; do
    IDX=$((START_INDEX + j + 1))
    if [[ "${RESULT_FAIL[$j]}" -gt 0 ]] || { [[ -n "$FAILED_SUITE" ]] && [[ "${RESULT_NAMES[$j]}" == "$FAILED_SUITE" ]]; }; then
        printf "  ${RED}%2d  %-38s %5d %5d %4ds${NC}\n" \
            "$IDX" "${RESULT_NAMES[$j]}" "${RESULT_PASS[$j]}" "${RESULT_FAIL[$j]}" "${RESULT_TIME[$j]}"
    else
        printf "  %2d  %-38s %5d %5d %4ds\n" \
            "$IDX" "${RESULT_NAMES[$j]}" "${RESULT_PASS[$j]}" "${RESULT_FAIL[$j]}" "${RESULT_TIME[$j]}"
    fi
done

printf "  %-4s %-38s %5s %5s %5s\n" "--" "--------------------------------------" "----" "----" "----"
printf "  %-4s %-38s %5d %5d %4ds\n" "" "TOTAL" "$TOTAL_PASS" "$TOTAL_FAIL" "$TOTAL_TIME"
echo ""

if [[ -n "$FAILED_SUITE" ]]; then
    echo -e "  ${RED}STOPPED: $FAILED_SUITE failed (suite $SUITE_NUM of $TOTAL_SUITES)${NC}"
    if [[ -n "$LATEST_LOG" ]]; then
        echo -e "  ${CYAN}Log: $LATEST_LOG${NC}"
    fi
    echo ""
    exit 1
fi

if [[ -n "$FROM_SUITE" ]]; then
    echo -e "  ${GREEN}Result: ALL $SUITES_RUN SUITES PASSED (resumed from #$((START_INDEX + 1)))${NC}"
else
    echo -e "  ${GREEN}Result: ALL $TOTAL_SUITES SUITES PASSED${NC}"
fi
echo ""
exit 0
