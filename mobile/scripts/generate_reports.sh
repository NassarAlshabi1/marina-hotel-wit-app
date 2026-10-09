#!/bin/bash

# Marina Hotel Mobile - Code Quality Reports Generator
# ====================================================
# Generate Comprehensive Code Quality Reports
# Maintainer: Marina Hotel Dev Team
# Last Updated: 2026-08-04
#
# Usage:
#   ./scripts/generate_reports.sh          # Generate all reports
#   ./scripts/generate_reports.sh quality  # Generate quality reports only
#   ./scripts/generate_reports.sh test     # Generate test reports only
#   ./scripts/generate_reports.sh coverage # Generate coverage reports only
#   ./scripts/generate_reports.sh security # Generate security reports only
#   ./scripts/generate_reports.sh all      # Generate all reports

# ============================================
# CONFIGURATION
# ============================================

# Colors for output (use printf for proper escape handling)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Directories
REPORTS_DIR="reports"
COVERAGE_DIR="coverage"
TEST_RESULTS_DIR="test_results"
SECURITY_DIR="security_reports"
QUALITY_DIR="quality_reports"

# File paths
ANALYSIS_REPORT="$QUALITY_DIR/analysis_report.txt"
LINT_REPORT="$QUALITY_DIR/lint_report.txt"
FORMAT_REPORT="$QUALITY_DIR/format_report.txt"
COMPLEXITY_REPORT="$QUALITY_DIR/complexity_report.txt"
TEST_REPORT="$TEST_RESULTS_DIR/test_report.md"
COVERAGE_REPORT="$COVERAGE_DIR/coverage_report.html"
SECURITY_REPORT="$SECURITY_DIR/security_report.md"
FINAL_REPORT="$REPORTS_DIR/code_quality_final_report.md"

# ============================================
# FUNCTIONS
# ============================================

# Print header
print_header() {
    printf '%b\n' "${BLUE}============================================${NC}"
    printf '%b\n' "${BLUE}  Marina Hotel Mobile - Code Quality Reports${NC}"
    printf '%b\n' "${BLUE}============================================${NC}"
    echo ""
}

# Print section
print_section() {
    printf '%b\n' "${YELLOW}=== $1 ===${NC}"
    echo ""
}

# Print success
print_success() {
    printf '%b\n' "${GREEN}✓ $1${NC}"
}

# Print error
print_error() {
    printf '%b\n' "${RED}✗ $1${NC}"
}

# Print info
print_info() {
    printf '%b\n' "${BLUE}ℹ $1${NC}"
}

# Print warning
print_warning() {
    printf '%b\n' "${YELLOW}⚠ $1${NC}"
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

# Clean old reports
clean_reports() {
    print_section "Cleaning Old Reports"
    
    rm -rf "$REPORTS_DIR" "$COVERAGE_DIR" "$TEST_RESULTS_DIR" "$SECURITY_DIR" "$QUALITY_DIR"
    
    ensure_dir "$REPORTS_DIR"
    ensure_dir "$COVERAGE_DIR"
    ensure_dir "$TEST_RESULTS_DIR"
    ensure_dir "$SECURITY_DIR"
    ensure_dir "$QUALITY_DIR"
    
    print_success "Old reports cleaned"
}

# ============================================
# QUALITY REPORTS
# ============================================

# Generate analysis report
generate_analysis_report() {
    print_section "Generating Static Analysis Report"
    
    ensure_dir "$QUALITY_DIR"
    
    print_info "Running dart analyze..."
    
    if dart analyze --fatal-infos --fatal-warnings . > "$ANALYSIS_REPORT" 2>&1; then
        print_success "Analysis report generated: $ANALYSIS_REPORT"
        
        # Count issues
        local issue_count=$(grep -c "\!\|error\|warning" "$ANALYSIS_REPORT" 2>/dev/null || echo "0")
        local error_count=$(grep -c "error" "$ANALYSIS_REPORT" 2>/dev/null || echo "0")
        local warning_count=$(grep -c "warning" "$ANALYSIS_REPORT" 2>/dev/null || echo "0")
        
        print_info "Issues found: $issue_count (Errors: $error_count, Warnings: $warning_count)"
        
        if [ "$error_count" -gt 0 ]; then
            print_error "Static analysis found errors!"
            return 1
        fi
        
        return 0
    else
        print_error "Failed to generate analysis report"
        return 1
    fi
}

# Generate lint report (lints are part of dart analyze)
generate_lint_report() {
    print_section "Generating Lint Report"
    
    ensure_dir "$QUALITY_DIR"
    
    print_info "Running dart analyze for linting..."
    
    # Lints are checked via dart analyze with analysis_options.yaml
    if dart analyze . > "$LINT_REPORT" 2>&1; then
        print_success "Lint report generated: $LINT_REPORT"
        
        # Count lint issues
        local lint_count=$(grep -c "\!\|warning" "$LINT_REPORT" 2>/dev/null || echo "0")
        print_info "Lint issues found: $lint_count"
        
        if [ "$lint_count" -gt 0 ]; then
            print_warning "Lint issues found (non-blocking)"
        fi
        
        return 0
    else
        print_error "Failed to generate lint report"
        return 1
    fi
}

# Generate format report
generate_format_report() {
    print_section "Generating Format Report"
    
    ensure_dir "$QUALITY_DIR"
    
    print_info "Checking code formatting..."
    
    if dart format --output=none --set-exit-if-changed . > "$FORMAT_REPORT" 2>&1; then
        print_success "Format report generated: $FORMAT_REPORT"
        
        # Count files that need formatting
        local format_count=$(grep -c "Formatted" "$FORMAT_REPORT" 2>/dev/null || echo "0")
        print_info "Files needing formatting: $format_count"
        
        if [ "$format_count" -gt 0 ]; then
            print_warning "Some files need formatting"
        fi
        
        return 0
    else
        print_error "Files need formatting!"
        return 1
    fi
}

# Generate complexity report (using dart analyze metrics)
generate_complexity_report() {
    print_section "Generating Code Complexity Report"
    
    ensure_dir "$QUALITY_DIR"
    
    print_info "Analyzing code complexity..."
    
    # Use dart analyze to get metrics
    # For now, create a basic complexity report
    local report="Code Complexity Analysis\n\n"
    report+="This report will be enhanced with proper complexity analysis tools.\n"
    report+="For now, use: dart analyze --fatal-infos --fatal-warnings .\n"
    
    printf '%b' "$report" > "$COMPLEXITY_REPORT"
    print_success "Complexity report generated: $COMPLEXITY_REPORT"
    
    return 0
}

# Generate quality summary report
generate_quality_summary() {
    print_section "Generating Quality Summary Report"
    
    ensure_dir "$QUALITY_DIR"
    
    local summary="# Code Quality Summary Report\n\n"
    summary+="**Generated:** $(date)\n\n"
    summary+="## Static Analysis\n\n"
    
    if [ -f "$ANALYSIS_REPORT" ]; then
        local issue_count=$(grep -c "\!\|error\|warning" "$ANALYSIS_REPORT" 2>/dev/null || echo "0")
        local error_count=$(grep -c "error" "$ANALYSIS_REPORT" 2>/dev/null || echo "0")
        local warning_count=$(grep -c "warning" "$ANALYSIS_REPORT" 2>/dev/null || echo "0")
        
        summary+="- **Status:** $(if [ "$error_count" -gt 0 ]; then echo "FAILED"; else echo "PASSED"; fi)\n"
        summary+="- **Errors:** $error_count\n"
        summary+="- **Warnings:** $warning_count\n"
        summary+="- **Total Issues:** $issue_count\n\n"
    else
        summary+="- **Status:** NOT RUN\n\n"
    fi
    
    summary+="## Linting\n\n"
    if [ -f "$LINT_REPORT" ]; then
        local lint_count=$(grep -c "\!\|warning" "$LINT_REPORT" 2>/dev/null || echo "0")
        summary+="- **Status:** $(if [ "$lint_count" -gt 0 ]; then echo "WARNINGS"; else echo "PASSED"; fi)\n"
        summary+="- **Issues:** $lint_count\n\n"
    else
        summary+="- **Status:** NOT RUN\n\n"
    fi
    
    summary+="## Code Formatting\n\n"
    if [ -f "$FORMAT_REPORT" ]; then
        local format_count=$(grep -c "Formatted" "$FORMAT_REPORT" 2>/dev/null || echo "0")
        summary+="- **Status:** $(if [ "$format_count" -gt 0 ]; then echo "NEEDS FORMATTING"; else echo "PASSED"; fi)\n"
        summary+="- **Files to format:** $format_count\n\n"
    else
        summary+="- **Status:** NOT RUN\n\n"
    fi
    
    summary+="## Overall Quality Score\n\n"
    
    local score=100
    local issues=0
    
    if [ -f "$ANALYSIS_REPORT" ]; then
        local error_count=$(grep -c "error" "$ANALYSIS_REPORT" 2>/dev/null || echo "0")
        if [ "$error_count" -gt 0 ]; then
            score=$((score - 40))
            issues=$((issues + error_count))
        fi
    fi
    
    if [ -f "$LINT_REPORT" ]; then
        local lint_count=$(grep -c "warning" "$LINT_REPORT" 2>/dev/null || echo "0")
        if [ "$lint_count" -gt 10 ]; then
            score=$((score - 20))
        elif [ "$lint_count" -gt 5 ]; then
            score=$((score - 10))
        fi
        issues=$((issues + lint_count))
    fi
    
    if [ -f "$FORMAT_REPORT" ]; then
        local format_count=$(grep -c "Formatted" "$FORMAT_REPORT" 2>/dev/null || echo "0")
        if [ "$format_count" -gt 0 ]; then
            score=$((score - 10))
            issues=$((issues + format_count))
        fi
    fi
    
    summary+="- **Quality Score:** $score/100\n"
    summary+="- **Total Issues:** $issues\n"
    
    if [ "$score" -ge 90 ]; then
        summary+="- **Grade:** A+ (Excellent)\n"
    elif [ "$score" -ge 80 ]; then
        summary+="- **Grade:** A (Good)\n"
    elif [ "$score" -ge 70 ]; then
        summary+="- **Grade:** B (Fair)\n"
    elif [ "$score" -ge 60 ]; then
        summary+="- **Grade:** C (Needs Improvement)\n"
    else
        summary+="- **Grade:** D (Poor)\n"
    fi
    
    summary+="\n---\n\n"
    summary+="*Generated by Marina Hotel Mobile Code Quality Reports Generator*\n"
    
    printf '%b' "$summary" > "$QUALITY_DIR/quality_summary.md"
    
    print_success "Quality summary report generated: $QUALITY_DIR/quality_summary.md"
    
    # Print summary to console
    echo ""
    print_section "CODE QUALITY SUMMARY"
    echo "$summary"
}

# ============================================
# TEST REPORTS
# ============================================

# Run all tests and generate reports
run_all_tests() {
    print_section "Running All Tests"
    
    ensure_dir "$TEST_RESULTS_DIR"
    ensure_dir "$COVERAGE_DIR"
    
    local all_passed=true
    
    # Run unit tests
    print_info "Running unit tests..."
    if dart test test/unit/ --coverage --coverage-path="$COVERAGE_DIR/unit.lcov" 2>&1 | tee "$TEST_RESULTS_DIR/unit_tests.txt"; then
        print_success "Unit tests passed"
    else
        print_error "Unit tests failed"
        all_passed=false
    fi
    
    # Run widget tests
    print_info "Running widget tests..."
    if dart test test/widget/ --coverage --coverage-path="$COVERAGE_DIR/widget.lcov" 2>&1 | tee "$TEST_RESULTS_DIR/widget_tests.txt"; then
        print_success "Widget tests passed"
    else
        print_error "Widget tests failed"
        all_passed=false
    fi
    
    # Run integration tests
    print_info "Running integration tests..."
    if dart test integration_test/ --coverage --coverage-path="$COVERAGE_DIR/integration.lcov" 2>&1 | tee "$TEST_RESULTS_DIR/integration_tests.txt"; then
        print_success "Integration tests passed"
    else
        print_error "Integration tests failed"
        all_passed=false
    fi
    
    # Generate combined test report
    generate_test_report
    
    if [ "$all_passed" = true ]; then
        return 0
    else
        return 1
    fi
}

# Generate combined test report
generate_test_report() {
    print_section "Generating Test Report"
    
    ensure_dir "$TEST_RESULTS_DIR"
    
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    # Process unit test results
    if [ -f "$TEST_RESULTS_DIR/unit_tests.txt" ]; then
        local unit_passed=$(grep -c "PASSED" "$TEST_RESULTS_DIR/unit_tests.txt" 2>/dev/null || echo "0")
        local unit_failed=$(grep -c "FAILED" "$TEST_RESULTS_DIR/unit_tests.txt" 2>/dev/null || echo "0")
        local unit_tests=$((unit_passed + unit_failed))
        
        total_tests=$((total_tests + unit_tests))
        passed_tests=$((passed_tests + unit_passed))
        failed_tests=$((failed_tests + unit_failed))
    fi
    
    # Process widget test results
    if [ -f "$TEST_RESULTS_DIR/widget_tests.txt" ]; then
        local widget_passed=$(grep -c "PASSED" "$TEST_RESULTS_DIR/widget_tests.txt" 2>/dev/null || echo "0")
        local widget_failed=$(grep -c "FAILED" "$TEST_RESULTS_DIR/widget_tests.txt" 2>/dev/null || echo "0")
        local widget_tests=$((widget_passed + widget_failed))
        
        total_tests=$((total_tests + widget_tests))
        passed_tests=$((passed_tests + widget_passed))
        failed_tests=$((failed_tests + widget_failed))
    fi
    
    # Process integration test results
    if [ -f "$TEST_RESULTS_DIR/integration_tests.txt" ]; then
        local integration_passed=$(grep -c "PASSED" "$TEST_RESULTS_DIR/integration_tests.txt" 2>/dev/null || echo "0")
        local integration_failed=$(grep -c "FAILED" "$TEST_RESULTS_DIR/integration_tests.txt" 2>/dev/null || echo "0")
        local integration_tests=$((integration_passed + integration_failed))
        
        total_tests=$((total_tests + integration_tests))
        passed_tests=$((passed_tests + integration_passed))
        failed_tests=$((failed_tests + integration_failed))
    fi
    
    # Calculate pass rate (guard against division by zero)
    local pass_rate=0
    if [ "$total_tests" -gt 0 ]; then
        pass_rate=$(( (passed_tests * 100) / total_tests ))
    fi
    
    # Generate test report
    local report="# Test Report\n\n"
    report+="**Generated:** $(date)\n\n"
    report+="## Test Summary\n\n"
    report+="| Test Type | Total | Passed | Failed | Success Rate |\n"
    report+="|------------|-------|--------|--------|--------------|\n"
    
    # Unit tests
    if [ -f "$TEST_RESULTS_DIR/unit_tests.txt" ]; then
        local unit_tests=$((unit_passed + unit_failed))
        local unit_rate=0
        if [ "$unit_tests" -gt 0 ]; then
            unit_rate=$(( (unit_passed * 100) / unit_tests ))
        fi
        report+="| Unit Tests | $unit_tests | $unit_passed | $unit_failed | ${unit_rate}% |\n"
    fi
    
    # Widget tests
    if [ -f "$TEST_RESULTS_DIR/widget_tests.txt" ]; then
        local widget_tests=$((widget_passed + widget_failed))
        local widget_rate=0
        if [ "$widget_tests" -gt 0 ]; then
            widget_rate=$(( (widget_passed * 100) / widget_tests ))
        fi
        report+="| Widget Tests | $widget_tests | $widget_passed | $widget_failed | ${widget_rate}% |\n"
    fi
    
    # Integration tests
    if [ -f "$TEST_RESULTS_DIR/integration_tests.txt" ]; then
        local integration_tests=$((integration_passed + integration_failed))
        local integration_rate=0
        if [ "$integration_tests" -gt 0 ]; then
            integration_rate=$(( (integration_passed * 100) / integration_tests ))
        fi
        report+="| Integration Tests | $integration_tests | $integration_passed | $integration_failed | ${integration_rate}% |\n"
    fi
    
    report+="| **Total** | **$total_tests** | **$passed_tests** | **$failed_tests** | **${pass_rate}%** |\n\n"
    
    report+="## Overall Status\n\n"
    if [ "$pass_rate" -ge 90 ]; then
        report+="- **Status:** PASSED EXCELLENT (${pass_rate}% pass rate)\n"
    elif [ "$pass_rate" -ge 80 ]; then
        report+="- **Status:** PASSED GOOD (${pass_rate}% pass rate)\n"
    elif [ "$pass_rate" -ge 70 ]; then
        report+="- **Status:** FAIR (${pass_rate}% pass rate)\n"
    else
        report+="- **Status:** FAILED POOR (${pass_rate}% pass rate)\n"
    fi
    
    report+="- **Total Tests:** $total_tests\n"
    report+="- **Passed:** $passed_tests\n"
    report+="- **Failed:** $failed_tests\n\n"
    
    report+="## Recommendations\n\n"
    
    if [ "$failed_tests" -gt 0 ]; then
        report+="- Fix failing tests before merging\n"
    fi
    
    if [ "$pass_rate" -lt 80 ]; then
        report+="- Improve test coverage - aim for 80%+ pass rate\n"
    fi
    
    if [ "$total_tests" -lt 50 ]; then
        report+="- Consider adding more tests - currently only $total_tests tests\n"
    fi
    
    report+="\n---\n\n"
    report+="*Generated by Marina Hotel Mobile Test Reports Generator*\n"
    
    printf '%b' "$report" > "$TEST_REPORT"
    
    print_success "Test report generated: $TEST_REPORT"
    
    # Print summary to console
    echo ""
    print_section "TEST REPORT SUMMARY"
    echo "Total Tests: $total_tests"
    echo "Passed: $passed_tests"
    echo "Failed: $failed_tests"
    echo "Success Rate: ${pass_rate}%"
}

# ============================================
# COVERAGE REPORTS
# ============================================

# Generate coverage report
generate_coverage_report() {
    print_section "Generating Coverage Report"
    
    ensure_dir "$COVERAGE_DIR"
    
    # Check if lcov is installed
    if ! command_exists lcov; then
        print_error "lcov is not installed!"
        print_info "Install with: sudo apt-get install -y lcov (Ubuntu/Debian)"
        print_info "Or: brew install lcov (macOS)"
        return 1
    fi
    
    # Check if genhtml is installed
    if ! command_exists genhtml; then
        print_error "genhtml is not installed!"
        print_info "Install with: sudo apt-get install -y lcov (Ubuntu/Debian)"
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
        print_success "HTML report generated: $COVERAGE_DIR/html/index.html"
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
            
            # Generate coverage summary
            local coverage_report="# Coverage Report\n\n"
            coverage_report+="**Generated:** $(date)\n\n"
            coverage_report+="## Coverage Summary\n\n"
            coverage_report+="- **Total Lines:** $TOTAL_LINES\n"
            coverage_report+="- **Covered Lines:** $COVERED_LINES\n"
            coverage_report+="- **Coverage Percentage:** $COVERAGE_PERCENT%\n\n"
            
            if [ "$COVERAGE_PERCENT" -ge 80 ]; then
                coverage_report+="- **Status:** PASSED EXCELLENT (>= 80% required)\n"
            elif [ "$COVERAGE_PERCENT" -ge 70 ]; then
                coverage_report+="- **Status:** GOOD (70-79%)\n"
            elif [ "$COVERAGE_PERCENT" -ge 60 ]; then
                coverage_report+="- **Status:** FAIR (60-69%)\n"
            else
                coverage_report+="- **Status:** FAILED POOR (< 60%)\n"
            fi
            
            coverage_report+="\n"
            coverage_report+="## Coverage Details\n\n"
            coverage_report+="Run the following to see detailed coverage:\n"
            coverage_report+="\`\`\`bash\n"
            coverage_report+="lcov --list $COVERAGE_DIR/combined.lcov\n"
            coverage_report+="\`\`\`\n\n"
            coverage_report+="Or open the HTML report:\n"
            coverage_report+="\`\`\`bash\n"
            coverage_report+="xdg-open $COVERAGE_DIR/html/index.html  # Linux\n"
            coverage_report+="open $COVERAGE_DIR/html/index.html      # macOS\n"
            coverage_report+="\`\`\`\n\n"
            coverage_report+="---\n\n"
            coverage_report+="*Generated by Marina Hotel Mobile Coverage Reports Generator*\n"
            
            printf '%b' "$coverage_report" > "$COVERAGE_DIR/coverage_summary.md"
            
            print_success "Coverage summary generated: $COVERAGE_DIR/coverage_summary.md"
            
            # Print summary to console
            echo ""
            print_section "COVERAGE REPORT SUMMARY"
            echo "Total Lines: $TOTAL_LINES"
            echo "Covered Lines: $COVERED_LINES"
            echo "Coverage: $COVERAGE_PERCENT%"
            
            if [ "$COVERAGE_PERCENT" -lt 80 ]; then
                print_error "Coverage is below 80%!"
                return 1
            fi
            
            return 0
        fi
    fi
    
    print_error "Could not calculate coverage percentage"
    return 1
}

# ============================================
# SECURITY REPORTS
# ============================================

# Generate security report
generate_security_report() {
    print_section "Generating Security Report"
    
    ensure_dir "$SECURITY_DIR"
    
    local report="# Security Report\n\n"
    report+="**Generated:** $(date)\n\n"
    
    # Check for secrets using gitleaks
    if command_exists gitleaks; then
        print_info "Running GitLeaks scan..."
        
        if [ -f ".gitleaks.toml" ]; then
            if gitleaks detect --source . --config .gitleaks.toml --report-path="$SECURITY_DIR/gitleaks_report.json" --verbose 2>&1 | tee "$SECURITY_DIR/gitleaks_scan.log"; then
                report+="## GitLeaks Scan\n\n"
                report+="- **Status:** PASSED\n"
                report+="- **Secrets Found:** 0\n\n"
            else
                report+="## GitLeaks Scan\n\n"
                report+="- **Status:** FAILED\n"
                report+="- **Secrets Found:** See $SECURITY_DIR/gitleaks_report.json\n\n"
                print_error "GitLeaks found potential secrets!"
            fi
        else
            if gitleaks detect --source . --report-path="$SECURITY_DIR/gitleaks_report.json" --verbose 2>&1 | tee "$SECURITY_DIR/gitleaks_scan.log"; then
                report+="## GitLeaks Scan\n\n"
                report+="- **Status:** PASSED\n"
                report+="- **Secrets Found:** 0\n\n"
            else
                report+="## GitLeaks Scan\n\n"
                report+="- **Status:** FAILED\n"
                report+="- **Secrets Found:** See $SECURITY_DIR/gitleaks_report.json\n\n"
                print_error "GitLeaks found potential secrets!"
            fi
        fi
    else
        report+="## GitLeaks Scan\n\n"
        report+="- **Status:** SKIPPED (GitLeaks not installed)\n"
        report+="- **Install:** brew install gitleaks (macOS) or sudo snap install gitleaks (Linux)\n\n"
    fi
    
    # Check for hardcoded API keys
    print_info "Checking for hardcoded API keys..."
    local api_key_count=$(grep -r "apiKey\|api_key\|API_KEY" lib/ --include="*.dart" --exclude-dir=generated 2>/dev/null | grep -v "const String" | wc -l || echo "0")
    
    if [ "$api_key_count" -gt 0 ]; then
        report+="## Hardcoded API Keys\n\n"
        report+="- **Status:** FAILED\n"
        report+="- **Count:** $api_key_count\n"
        report+="- **Action Required:** Remove hardcoded API keys\n\n"
        print_error "Found $api_key_count potential hardcoded API keys!"
    else
        report+="## Hardcoded API Keys\n\n"
        report+="- **Status:** PASSED\n"
        report+="- **Count:** 0\n\n"
    fi
    
    # Check for hardcoded passwords
    print_info "Checking for hardcoded passwords..."
    local password_count=$(grep -r "password\|passwd" lib/ --include="*.dart" --exclude-dir=generated 2>/dev/null | grep -v "const String" | wc -l || echo "0")
    
    if [ "$password_count" -gt 0 ]; then
        report+="## Hardcoded Passwords\n\n"
        report+="- **Status:** FAILED\n"
        report+="- **Count:** $password_count\n"
        report+="- **Action Required:** Remove hardcoded passwords\n\n"
        print_error "Found $password_count potential hardcoded passwords!"
    else
        report+="## Hardcoded Passwords\n\n"
        report+="- **Status:** PASSED\n"
        report+="- **Count:** 0\n\n"
    fi
    
    # Check for hardcoded tokens
    print_info "Checking for hardcoded tokens..."
    local token_count=$(grep -r "token\|secret" lib/ --include="*.dart" --exclude-dir=generated 2>/dev/null | grep -v "const String" | wc -l || echo "0")
    
    if [ "$token_count" -gt 0 ]; then
        report+="## Hardcoded Tokens/Secrets\n\n"
        report+="- **Status:** FAILED\n"
        report+="- **Count:** $token_count\n"
        report+="- **Action Required:** Remove hardcoded tokens/secrets\n\n"
        print_error "Found $token_count potential hardcoded tokens/secrets!"
    else
        report+="## Hardcoded Tokens/Secrets\n\n"
        report+="- **Status:** PASSED\n"
        report+="- **Count:** 0\n\n"
    fi
    
    # Overall security status
    local security_status="PASSED"
    if [ "$api_key_count" -gt 0 ] || [ "$password_count" -gt 0 ] || [ "$token_count" -gt 0 ]; then
        security_status="FAILED"
    fi
    
    report+="## Overall Security Status\n\n"
    report+="- **Status:** $security_status\n"
    report+="- **Recommendation:** $(if [ "$security_status" = "FAILED" ]; then echo "Fix security issues before merging"; else echo "Code is secure"; fi)\n\n"
    
    report+="---\n\n"
    report+="*Generated by Marina Hotel Mobile Security Reports Generator*\n"
    
    printf '%b' "$report" > "$SECURITY_REPORT"
    
    print_success "Security report generated: $SECURITY_REPORT"
    
    # Print summary to console
    echo ""
    print_section "SECURITY REPORT SUMMARY"
    echo "Status: $security_status"
    echo "API Keys Found: $api_key_count"
    echo "Passwords Found: $password_count"
    echo "Tokens Found: $token_count"
    
    if [ "$security_status" = "FAILED" ]; then
        return 1
    fi
    
    return 0
}

# ============================================
# FINAL REPORT
# ============================================

# Generate final comprehensive report
generate_final_report() {
    print_section "Generating Final Comprehensive Report"
    
    ensure_dir "$REPORTS_DIR"
    
    local final_report="# Marina Hotel Mobile - Code Quality Final Report\n\n"
    final_report+="**Generated:** $(date)\n\n"
    final_report+="---\n\n"
    
    # Add quality summary
    if [ -f "$QUALITY_DIR/quality_summary.md" ]; then
        final_report+="## Code Quality\n\n"
        final_report+="$(cat "$QUALITY_DIR/quality_summary.md" | sed '1,/^##/d' | sed '/^---/,$d')\n\n"
    fi
    
    # Add test summary
    if [ -f "$TEST_REPORT" ]; then
        final_report+="## Test Results\n\n"
        final_report+="$(cat "$TEST_REPORT" | sed '1,/^##/d' | sed '/^---/,$d')\n\n"
    fi
    
    # Add coverage summary
    if [ -f "$COVERAGE_DIR/coverage_summary.md" ]; then
        final_report+="## Code Coverage\n\n"
        final_report+="$(cat "$COVERAGE_DIR/coverage_summary.md" | sed '1,/^##/d' | sed '/^---/,$d')\n\n"
    fi
    
    # Add security summary
    if [ -f "$SECURITY_REPORT" ]; then
        final_report+="## Security Analysis\n\n"
        final_report+="$(cat "$SECURITY_REPORT" | sed '1,/^##/d' | sed '/^---/,$d')\n\n"
    fi
    
    # Overall project health
    final_report+="## Project Health Overview\n\n"
    
    local health_score=100
    local issues=0
    
    # Quality score
    if [ -f "$QUALITY_DIR/quality_summary.md" ]; then
        local quality_score=$(grep "Quality Score:" "$QUALITY_DIR/quality_summary.md" | awk '{print $3}' | tr -d '%')
        health_score=$((health_score + quality_score)) / 2
    fi
    
    # Test pass rate
    if [ -f "$TEST_REPORT" ]; then
        local pass_rate=$(grep "Success Rate:" "$TEST_REPORT" | awk '{print $3}' | tr -d '%')
        health_score=$(( (health_score + pass_rate) / 2 ))
    fi
    
    # Coverage percentage
    if [ -f "$COVERAGE_DIR/coverage_summary.md" ]; then
        local coverage=$(grep "Coverage Percentage:" "$COVERAGE_DIR/coverage_summary.md" | awk '{print $3}' | tr -d '%')
        health_score=$(( (health_score + coverage) / 2 ))
    fi
    
    # Security status
    if [ -f "$SECURITY_REPORT" ]; then
        if grep -q "FAILED" "$SECURITY_REPORT"; then
            health_score=$((health_score - 30))
        fi
    fi
    
    # Determine health grade
    local health_grade="A+ (Excellent)"
    if [ "$health_score" -ge 90 ]; then
        health_grade="A+ (Excellent)"
    elif [ "$health_score" -ge 80 ]; then
        health_grade="A (Good)"
    elif [ "$health_score" -ge 70 ]; then
        health_grade="B (Fair)"
    elif [ "$health_score" -ge 60 ]; then
        health_grade="C (Needs Improvement)"
    else
        health_grade="D (Poor)"
    fi
    
    final_report+="| Metric | Score | Grade |\n"
    final_report+="|--------|-------|-------|\n"
    final_report+="| Code Quality | ${quality_score:-N/A}% | $(if [ -n "$quality_score" ]; then echo "$(if [ "$quality_score" -ge 80 ]; then echo "PASSED"; else echo "WARNING"; fi)"; else echo "N/A"; fi) |\n"
    final_report+="| Test Results | ${pass_rate:-N/A}% | $(if [ -n "$pass_rate" ]; then echo "$(if [ "$pass_rate" -ge 80 ]; then echo "PASSED"; else echo "WARNING"; fi)"; else echo "N/A"; fi) |\n"
    final_report+="| Code Coverage | ${coverage:-N/A}% | $(if [ -n "$coverage" ]; then echo "$(if [ "$coverage" -ge 80 ]; then echo "PASSED"; else echo "WARNING"; fi)"; else echo "N/A"; fi) |\n"
    final_report+="| Security | $(if grep -q "PASSED" "$SECURITY_REPORT" 2>/dev/null; then echo "100%"; else echo "0%"; fi) | $(if grep -q "PASSED" "$SECURITY_REPORT" 2>/dev/null; then echo "PASSED"; else echo "FAILED"; fi) |\n"
    final_report+="| **Overall Health** | **${health_score}%** | **$health_grade** |\n\n"
    
    # Recommendations
    final_report+="## Recommendations\n\n"
    
    if [ "$health_score" -lt 80 ]; then
        final_report+="- Address critical issues before merging\n"
    fi
    
    if [ "$quality_score" -lt 80 ] 2>/dev/null; then
        final_report+="- Improve code quality - aim for 80%+ score\n"
    fi
    
    if [ "$pass_rate" -lt 80 ] 2>/dev/null; then
        final_report+="- Fix failing tests - aim for 80%+ pass rate\n"
    fi
    
    if [ "$coverage" -lt 80 ] 2>/dev/null; then
        final_report+="- Improve test coverage - aim for 80%+ coverage\n"
    fi
    
    if grep -q "FAILED" "$SECURITY_REPORT" 2>/dev/null; then
        final_report+="- Fix security issues before merging\n"
    fi
    
    final_report+="\n"
    final_report+="## How to Improve\n\n"
    final_report+="1. **Fix Critical Issues:** Address all errors and security issues\n"
    final_report+="2. **Improve Code Quality:** Follow best practices and refactor complex code\n"
    final_report+="3. **Add More Tests:** Increase test coverage for untested code\n"
    final_report+="4. **Review Copilot Feedback:** Address suggestions from GitHub Copilot\n"
    final_report+="5. **Run Quality Checks:** Use `make quality` before committing\n\n"
    
    final_report+="---\n\n"
    final_report+="*Generated by Marina Hotel Mobile Code Quality Reports Generator*\n"
    
    printf '%b' "$final_report" > "$FINAL_REPORT"
    
    print_success "Final report generated: $FINAL_REPORT"
    
    # Print summary to console
    echo ""
    print_section "FINAL CODE QUALITY REPORT"
    echo "Project Health Score: ${health_score}%"
    echo "Health Grade: $health_grade"
    echo ""
    echo "Quality Score: ${quality_score:-N/A}%"
    echo "Test Pass Rate: ${pass_rate:-N/A}%"
    echo "Coverage: ${coverage:-N/A}%"
    echo "Security: $(if grep -q "PASSED" "$SECURITY_REPORT" 2>/dev/null; then echo "PASSED"; else echo "FAILED"; fi)"
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
    "quality")
        clean_reports
        generate_analysis_report
        generate_lint_report
        generate_format_report
        generate_complexity_report
        generate_quality_summary
        ;;
    "test")
        clean_reports
        run_all_tests
        ;;
    "coverage")
        clean_reports
        run_all_tests
        generate_coverage_report
        ;;
    "security")
        clean_reports
        generate_security_report
        ;;
    "all")
        clean_reports
        
        print_section "Generating All Reports"
        
        # Quality reports
        generate_analysis_report
        generate_lint_report
        generate_format_report
        generate_complexity_report
        generate_quality_summary
        
        # Test reports
        run_all_tests
        
        # Coverage reports
        generate_coverage_report
        
        # Security reports
        generate_security_report
        
        # Final report
        generate_final_report
        ;;
    "clean")
        clean_reports
        ;;
    "")
        clean_reports
        
        print_section "Generating All Reports"
        
        # Quality reports
        generate_analysis_report
        generate_lint_report
        generate_format_report
        generate_complexity_report
        generate_quality_summary
        
        # Test reports
        run_all_tests
        
        # Coverage reports
        generate_coverage_report
        
        # Security reports
        generate_security_report
        
        # Final report
        generate_final_report
        ;;
    *)
        print_error "Unknown command: $1"
        print_info "Available commands: all, quality, test, coverage, security, clean"
        exit 1
        ;;
esac

# Exit with appropriate status
exit 0
