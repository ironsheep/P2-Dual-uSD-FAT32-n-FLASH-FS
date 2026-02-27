#!/bin/bash
#
# run_test.sh - Compile, download, run, and monitor P2 test files
#
# Usage: ./run_test.sh <test-file> [-t timeout]
#
# Examples:
#   ./run_test.sh ../regression-tests/SD_RT_mount_tests.spin2
#   ./run_test.sh ../TestCard/SD_RT_testcard_validation.spin2 -t 120
#   ./run_test.sh ../TestCard/SD_Test_Suite.spin2
#
# The script must be run from the tools/ directory.
# It automatically includes ../src for the SD card driver.
#
# Exit codes:
#   0 - Test completed successfully (END_SESSION found)
#   1 - Compilation failed
#   2 - Download/run failed
#   3 - Timeout expired (END_SESSION not found in time)
#   4 - Usage error
#
# Requirements:
#   - Test source MUST output END_SESSION via debug() when complete
#   - Uses 2 Mbaud debug serial
#

set +e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Verify we're in tools directory ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR_NAME="$(basename "$SCRIPT_DIR")"

if [[ "$TOOLS_DIR_NAME" != "tools" ]]; then
    echo -e "${RED}Error: This script must be run from the tools/ directory${NC}"
    echo "Current directory: $(pwd)"
    exit 4
fi

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Functions ---

usage() {
    echo "Usage: $0 <test-file> [-t timeout]"
    echo ""
    echo "Examples:"
    echo "  $0 ../regression-tests/SD_RT_mount_tests.spin2"
    echo "  $0 ../TestCard/SD_RT_testcard_validation.spin2 -t 120"
    echo ""
    echo "Arguments:"
    echo "  test-file  - Path to .spin2 test file (relative to tools/)"
    echo "  -t <sec>   - Timeout in seconds (default: 60)"
    echo ""
    echo "Exit codes:"
    echo "  0 - Test passed (END_SESSION found)"
    echo "  1 - Compilation failed"
    echo "  2 - Download/run failed"
    echo "  3 - Timeout (END_SESSION not found)"
    echo "  4 - Usage error"
    exit 4
}

# --- Parse Arguments ---

if [[ $# -lt 1 ]]; then
    usage
fi

TEST_FILE="$1"
shift

TIMEOUT_SECS="60"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo -e "${RED}Error: -t requires a timeout value in seconds${NC}"
                usage
            fi
            TIMEOUT_SECS="$2"
            shift 2
            ;;
        -h|--help) usage ;;
        *) echo -e "${RED}Error: Unknown option: $1${NC}"; usage ;;
    esac
done

# --- Validate Arguments ---

# Resolve to absolute path
if [[ "$TEST_FILE" == /* ]]; then
    ABS_TEST_FILE="$TEST_FILE"
else
    ABS_TEST_FILE="$(cd "$(dirname "$TEST_FILE")" 2>/dev/null && pwd)/$(basename "$TEST_FILE")"
fi

if [[ ! -f "$ABS_TEST_FILE" ]]; then
    echo -e "${RED}Error: Test file does not exist: $TEST_FILE${NC}"
    exit 4
fi

if [[ ! "$ABS_TEST_FILE" == *.spin2 ]]; then
    echo -e "${RED}Error: Test file must be a .spin2 file${NC}"
    exit 4
fi

# Extract directory and basename
TEST_DIR="$(dirname "$ABS_TEST_FILE")"
BASENAME="$(basename "$ABS_TEST_FILE" .spin2)"

# Validate timeout is numeric
if ! [[ "$TIMEOUT_SECS" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: Timeout must be a positive integer${NC}"
    usage
fi

echo -e "${CYAN}Test: $BASENAME${NC}"
echo -e "${CYAN}From: $TEST_DIR${NC}"
echo -e "${CYAN}Timeout: ${TIMEOUT_SECS}s${NC}"
echo ""

# --- Setup log directory ---

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# --- Compilation ---

echo -e "${GREEN}=== Compiling $BASENAME.spin2 ===${NC}"

cd "$TEST_DIR"

# Include paths: src/ for driver, src/UTILS/ for utilities, regression-tests/ for test utilities
# pnut-ts requires relative paths (does not support absolute -I paths)
# Compute relative paths from TEST_DIR to project directories
_relpath() {
    python3 -c "import os; print(os.path.relpath('$1', '$2'))"
}
SRC_PATH="$(_relpath "$PROJECT_ROOT/src" "$TEST_DIR")/"
UTILS_PATH="$(_relpath "$PROJECT_ROOT/src/UTILS" "$TEST_DIR")/"
DEMO_PATH="$(_relpath "$PROJECT_ROOT/src/DEMO" "$TEST_DIR")/"
REGTEST_PATH="$(_relpath "$PROJECT_ROOT/regression-tests" "$TEST_DIR")/"
COMPILE_CMD="pnut-ts -d -I $SRC_PATH -I $UTILS_PATH -I $DEMO_PATH -I $REGTEST_PATH $BASENAME.spin2"
echo "  Command: $COMPILE_CMD"

if ! $COMPILE_CMD; then
    echo -e "${RED}=== Compilation FAILED ===${NC}"
    exit 1
fi

BIN_FILE="$BASENAME.bin"
if [[ ! -f "$BIN_FILE" ]]; then
    echo -e "${RED}Error: Binary file not generated: $BIN_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}=== Compilation successful ===${NC}"

# --- Run Test with Headless Mode ---

echo ""
echo -e "${GREEN}=== Running test (headless mode) ===${NC}"
echo "  Binary:  $BIN_FILE"
echo "  Timeout: ${TIMEOUT_SECS} seconds"
echo "  Baud:    2000000"
echo ""

# Create logs subdirectory in test location for pnut-term-ts
mkdir -p "./logs"

# Record time before running (to find new log files)
BEFORE_TIME=$(date +%s)

# Run pnut-term-ts in headless mode
RUN_START=$(date +%s)
pnut-term-ts --headless -r "$BIN_FILE" -b 2000000 --end-marker --timeout "$TIMEOUT_SECS"
PNUT_EXIT_CODE=$?
RUN_END=$(date +%s)
RUN_ELAPSED=$((RUN_END - RUN_START))

echo ""

# --- Find and copy the log file ---

LOG_FILE=""
if [[ -d "./logs" ]]; then
    for f in $(ls -t ./logs/headless_*.log 2>/dev/null); do
        if [[ "$(uname)" == "Darwin" ]]; then
            FILE_TIME=$(stat -f %m "$f" 2>/dev/null)
        else
            FILE_TIME=$(stat -c %Y "$f" 2>/dev/null)
        fi
        if [[ "$FILE_TIME" -ge "$BEFORE_TIME" ]]; then
            LOG_FILE="$f"
            # Copy to tools/logs with descriptive name
            DEST_LOG="$LOG_DIR/${BASENAME}_$(date +%y%m%d-%H%M%S).log"
            cp "$LOG_FILE" "$DEST_LOG"
            LOG_FILE="$DEST_LOG"
            break
        fi
    done
fi

# --- Report Results ---

case $PNUT_EXIT_CODE in
    0)
        echo -e "${GREEN}=== TEST PASSED (END_SESSION detected) [${RUN_ELAPSED}s elapsed] ===${NC}"
        ;;
    124)
        echo -e "${RED}=== TEST FAILED (Timeout after ${TIMEOUT_SECS}s) [${RUN_ELAPSED}s elapsed] ===${NC}"
        ;;
    *)
        echo -e "${RED}=== TEST FAILED (Exit code: $PNUT_EXIT_CODE) [${RUN_ELAPSED}s elapsed] ===${NC}"
        ;;
esac

if [[ -n "$LOG_FILE" ]]; then
    echo ""
    echo -e "${CYAN}Log file: $LOG_FILE${NC}"
    echo ""
    echo "Last 20 lines:"
    echo "----------------------------------------"
    tail -20 "$LOG_FILE"
    echo "----------------------------------------"
else
    echo ""
    echo -e "${YELLOW}No log file found${NC}"
fi

# Exit with appropriate code
case $PNUT_EXIT_CODE in
    0)   exit 0 ;;
    124) exit 3 ;;
    *)   exit 2 ;;
esac
