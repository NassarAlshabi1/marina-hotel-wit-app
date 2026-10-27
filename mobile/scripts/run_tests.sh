#!/bin/bash

# Marina Hotel Mobile - Test Runner Script
# ==========================================
# Automated Test Execution Script
# Maintainer: Marina Hotel Dev Team
# Last Updated: 2026-08-04
#
# Usage:
#   ./scripts/run_tests.sh          # Run all tests
#   ./scripts/run_tests.sh unit     # Run unit tests only
#   ./scripts/run_tests.sh widget   # Run widget tests only
#   ./scripts/run_tests.sh integration # Run integration tests only
#   ./scripts/run_tests.sh coverage # Run tests with coverage
#   ./scripts/run_tests.sh clean    # Clean test artifacts

# ============================================
# CONFIGURATION
# ============================================

# Colors for output (use printf for proper escape handling)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Directories
TEST_DIR="test"
COVERAGE_DIR="coverage"

# Test types
UNIT_TESTS="test/unit/"
WIDGET_TESTS="test/widget/"
INTEGRATION_TESTS="integration_test/"
PERFORMANCE_TESTS="test/performance/"

# ============================================
# FUNCTIONS
# ============================================

# Print header
print_header() {
    printf '%b\n' "${BLUE}============================================${NC}"
    printf '%b\n' "${BLUE}  Marina Hotel Mobile - Test Runner${NC}"
    printf '%b\n' "${BLUE}============================================${NC}"
    echo ""
}

# Print section
print_section() {
    printf '%b\n' "${YELLOW}--- $1 ---${NC}"
    echo ""
}

# Print success
print_success() {
    printf '%b\n' "${GREEN} $1${NC}"
}

# Print error
print_error() {
    printf '%b\n' "${RED} $1${NC}"
}

# Print info
print_info() {
    printf '%b\n' "${BLUE} $1${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Create directory if not exists
ensure_dir() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
    fi
}

# Clean test artifacts
clean_artifacts() {
    print_section "Cleaning Test Artifacts"
    
    # Remove coverage directory
    if [ -d "$COVERAGE_DIR" ]; then
        rm -rf "$COVERAGE_DIR"
        print_success "Removed coverage directory"
    fi
    
    # Remove test result files
    rm -f test_results_*.txt performance_report.json
    print_success "Removed test result files"
    
    print_success "Test artifacts cleaned!"
}

# Run unit tests
run_unit_tests() {
    print_section "Running Unit Tests"
    
    ensure_dir "$COVERAGE_DIR"
    
    if [ -d "$UNIT_TESTS" ]; then
        print_info "Running unit tests in $UNIT_TESTS"
        
        if dart test "$UNIT_TESTS" --coverage --coverage-path="$COVERAGE_DIR/unit.lcov" 2>&1 | tee "test_results_unit.txt"; then
            print_success "Unit tests passed!"
        else
            print_error "Unit tests failed!"
            return 1
        fi
    else
        print_error "Unit test directory not found: $UNIT_TESTS"
        return 1
    fi
}

# Run widget tests
run_widget_tests() {
    print_section "Running Widget Tests"
    
    ensure_dir "$COVERAGE_DIR"
    
    if [ -d "$WIDGET_TESTS" ]; then
        print_info "Running widget tests in $WIDGET_TESTS"
        
        if dart test "$WIDGET_TESTS" --coverage --coverage-path="$COVERAGE_DIR/widget.lcov" 2>&1 | tee "test_results_widget.txt"; then
            print_success "Widget tests passed!"
        else
            print_error "Widget tests failed!"
            return 1
        fi
    else
        print_error "Widget test directory not found: $WIDGET_TESTS"
        return 1
    fi
}

# Run integration tests
run_integration_tests() {
    print_section "Running Integration Tests"
    
    ensure_dir "$COVERAGE_DIR"
    
    if [ -d "$INTEGRATION_TESTS" ]; then
        print_info "Running integration tests in $INTEGRATION_TESTS"
        
        if dart test "$INTEGRATION_TESTS" --coverage --coverage-path="$COVERAGE_DIR/integration.lcov" 2>&1 | tee "test_results_integration.txt"; then
            print_success "Integration tests passed!"
        else
            print_error "Integration tests failed!"
            return 1
        fi
    else
        print_error "Integration test directory not found: $INTEGRATION_TESTS"
        return 1
    fi
}

# Run performance tests
run_performance_tests() {
    print_section "Running Performance Tests"
    
    if [ -d "$PERFORMANCE_TESTS" ]; then
        print_info "Running performance tests in $PERFORMANCE_TESTS"
        
        if dart test "$PERFORMANCE_TESTS" 2>&1 | tee "performance_report.txt"; then
            print_success "Performance tests passed!"
        else
            print_error "Performance tests failed!"
            return 1
        fi
    else
        print_error "Performance test directory not found: $PERFORMANCE_TESTS"
        return 1
    fi
}

# Generate coverage report
generate_coverage_report() {
    print_section "Generating Coverage Report"
    
    # Check if lcov is installed
    if ! command_exists lcov; then
        print_error "lcov is not installed!"
        print_info "Install it with: sudo apt-get install -y lcov (Ubuntu/Debian)"
        print_info "Or: brew install lcov (macOS)"
        return 1
    fi
    
    # Check if genhtml is installed
    if ! command_exists genhtml; then
        print_error "genhtml is not installed!"
        print_info "Install it with: sudo apt-get install -y lcov (Ubuntu/Debian)"
        print_info "Or: brew install lcov (macOS)"
        return 1
    fi
    
    # Initialize combined coverage file
    print_info "Combining coverage files..."
    lcov --rc lcov_branch_coverage=1 -c -i -d . -o "$COVERAGE_DIR/combined.lcov" 2>/dev/null
    
    # Add all coverage files
    for file in "$COVERAGE_DIR"/*.lcov; do
        if [ -f "$file" ]; then
            print_info "Adding $file"
            lcov --rc lcov_branch_coverage=1 -a "$file" -o "$COVERAGE_DIR/combined.lcov" 2>/dev/null
        fi
    done
    
    # Generate HTML report
    if [ -f "$COVERAGE_DIR/combined.lcov" ]; then
        print_info "Generating HTML report..."
        genhtml "$COVERAGE_DIR/combined.lcov" --output-directory "$COVERAGE_DIR/html" 2>/dev/null
        print_success "HTML report generated at: $COVERAGE_DIR/html/index.html"
    else
        print_error "No combined coverage file found!"
        return 1
    fi
    
    # Calculate coverage percentage
    if [ -f "$COVERAGE_DIR/combined.lcov" ]; then
        TOTAL_LINES=$(lcov --summary "$COVERAGE_DIR/combined.lcov" | grep -oP '\d+(?=% of all lines)' | head -1)
        COVERED_LINES=$(lcov --summary "$COVERAGE_DIR/combined.lcov" | grep -oP '\d+(?= lines)' | head -1)
        
        if [ -n "$TOTAL_LINES" ] && [ -n "$COVERED_LINES" ] && [ "$TOTAL_LINES" -ne 0 ]; then
            COVERAGE_PERCENT=$(( (COVERED_LINES * 100) / TOTAL_LINES ))
            print_success "Code Coverage: $COVERAGE_PERCENT%"
            
            # Check minimum coverage
            if [ "$COVERAGE_PERCENT" -lt 80 ]; then
                print_error "Coverage is below 80% ($COVERAGE_PERCENT%)!"
                return 1
            else
                print_success "Coverage meets minimum requirement (80%)"
            fi
        fi
    fi
    
    print_success "Coverage report generated!"
}

# Run all tests
run_all_tests() {
    print_header
    
    local all_passed=true
    
    # Run unit tests
    if ! run_unit_tests; then
        all_passed=false
    fi
    
    # Run widget tests
    if ! run_widget_tests; then
        all_passed=false
    fi
    
    # Run integration tests
    if ! run_integration_tests; then
        all_passed=false
    fi
    
    # Run performance tests
    if ! run_performance_tests; then
        all_passed=false
    fi
    
    # Generate coverage report
    if ! generate_coverage_report; then
        all_passed=false
    fi
    
    # Summary
    print_section "Test Summary"
    
    if [ "$all_passed" = true ]; then
        print_success "All tests passed!"
        return 0
    else
        print_error "Some tests failed!"
        return 1
    fi
}

# ============================================
# MAIN EXECUTION
# ============================================

# Print header
print_header

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    print_error "pubspec.yaml not found!"
    print_info "Please run this script from the project root directory."
    exit 1
fi

# Parse command line arguments
case "$1" in
    "clean")
        clean_artifacts
        ;;
    "unit")
        run_unit_tests
        ;;
    "widget")
        run_widget_tests
        ;;
    "integration")
        run_integration_tests
        ;;
    "performance")
        run_performance_tests
        ;;
    "coverage")
        run_all_tests
        ;;
    "all")
        run_all_tests
        ;;
    "")
        run_all_tests
        ;;
    *)
        print_error "Unknown command: $1"
        print_info "Available commands: all, unit, widget, integration, performance, coverage, clean"
        exit 1
        ;;
esac

# Exit with appropriate status
exit $?
