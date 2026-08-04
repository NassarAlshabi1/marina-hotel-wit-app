#!/bin/bash

# Marina Hotel Mobile - Quality Check Script
# ============================================
# F4DD Automated Quality Check Script
# F4BB Maintainer: Marina Hotel Dev Team
# F4D1 Last Updated: 2026-08-03
#
# F4D1 Usage:
#   ./scripts/check_quality.sh          # Run all quality checks
#   ./scripts/check_quality.sh analyze  # Run static analysis only
#   ./scripts/check_quality.sh format   # Check formatting only
#   ./scripts/check_quality.sh lint     # Run linter only
#   ./scripts/check_quality.sh security # Run security scan only
#   ./scripts/check_quality.sh todos   # Check for TODO comments only

# ============================================
# CONFIGURATION
# ============================================

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories
LIB_DIR="lib"
TEST_DIR="test"

# ============================================
# FUNCTIONS
# ============================================

# Print header
print_header() {
    echo ""
    echo "${BLUE}============================================${NC}"
    echo "${BLUE}  Marina Hotel Mobile - Quality Check${NC}"
    echo "${BLUE}============================================${NC}"
    echo ""
}

# Print section
print_section() {
    echo ""
    echo "${YELLOW}--- $1 ---${NC}"
    echo ""
}

# Print success
print_success() {
    echo "${GREEN}✓ $1${NC}"
}

# Print error
print_error() {
    echo "${RED}✗ $1${NC}"
}

# Print info
print_info() {
    echo "${BLUE}ℹ $1${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Run static analysis
run_analysis() {
    print_section "Running Static Analysis"
    
    print_info "Checking for type errors, null safety issues, and more..."
    
    if flutter analyze --fatal-infos --fatal-warnings . 2>&1 | tee analyze_report.txt; then
        print_success "Static analysis passed!"
        return 0
    else
        print_error "Static analysis failed!"
        print_info "See analyze_report.txt for details"
        return 1
    fi
}

# Check code formatting
check_formatting() {
    print_section "Checking Code Formatting"
    
    print_info "Verifying code follows Dart formatting standards..."
    
    if flutter format --set-exit-if-changed . 2>&1 | tee format_report.txt; then
        print_success "Code formatting is correct!"
        return 0
    else
        print_error "Code formatting issues found!"
        print_info "Run 'flutter format .' to fix formatting"
        print_info "See format_report.txt for details"
        return 1
    fi
}

# Run linter
run_linter() {
    print_section "Running Linter"
    
    print_info "Checking for code style violations and best practices..."
    
    if flutter lint 2>&1 | tee lint_report.txt; then
        print_success "Linting passed!"
        return 0
    else
        print_error "Linting failed!"
        print_info "See lint_report.txt for details"
        return 1
    fi
}

# Check for TODO comments
check_todos() {
    print_section "Checking for TODO Comments"
    
    print_info "Scanning for TODO, FIXME, XXX, HACK comments in production code..."
    
    local todo_count=0
    local todos_found=""
    
    # Find TODO comments in lib directory
    while IFS= read -r line; do
        if [[ "$line" == *"TODO"* ]] || [[ "$line" == *"FIXME"* ]] || [[ "$line" == *"XXX"* ]] || [[ "$line" == *"HACK"* ]]; then
            todo_count=$((todo_count + 1))
            todos_found+="$line\n"
        fi
    done < <(grep -r "TODO\|FIXME\|XXX\|HACK" "$LIB_DIR/" --include="*.dart" --exclude-dir=generated 2>/dev/null || true)
    
    if [ "$todo_count" -eq 0 ]; then
        print_success "No TODO comments found in production code!"
        return 0
    else
        print_error "Found $todo_count TODO/FIXME/XXX/HACK comments in production code!"
        print_info "Please resolve all TODOs before merging to main:"
        echo "$todos_found"
        return 1
    fi
}

# Run security scan
run_security_scan() {
    print_section "Running Security Scan"
    
    local all_passed=true
    
    # Check for secrets using gitleaks
    if command_exists gitleaks; then
        print_info "Scanning for secrets using GitLeaks..."
        
        if [ -f ".gitleaks.toml" ]; then
            if gitleaks detect --source . --config .gitleaks.toml --verbose 2>&1 | tee security_report.txt; then
                print_success "GitLeaks scan passed!"
            else
                print_error "GitLeaks scan found potential secrets!"
                print_info "See security_report.txt for details"
                all_passed=false
            fi
        else
            if gitleaks detect --source . --verbose 2>&1 | tee security_report.txt; then
                print_success "GitLeaks scan passed!"
            else
                print_error "GitLeaks scan found potential secrets!"
                print_info "See security_report.txt for details"
                all_passed=false
            fi
        fi
    else
        print_info "GitLeaks not installed, skipping secret scan"
        print_info "Install with: brew install gitleaks (macOS) or sudo snap install gitleaks (Linux)"
    fi
    
    # Check for hardcoded API keys
    print_info "Checking for hardcoded API keys..."
    
    local api_key_count=0
    local api_keys_found=""
    
    while IFS= read -r line; do
        if [[ "$line" == *"apiKey"* ]] || [[ "$line" == *"api_key"* ]] || [[ "$line" == *"API_KEY"* ]]; then
            # Skip const declarations (these are OK)
            if [[ ! "$line" == *"const String"* ]]; then
                api_key_count=$((api_key_count + 1))
                api_keys_found+="$line\n"
            fi
        fi
    done < <(grep -r "apiKey\|api_key\|API_KEY" "$LIB_DIR/" --include="*.dart" --exclude-dir=generated 2>/dev/null || true)
    
    if [ "$api_key_count" -gt 0 ]; then
        print_error "Found $api_key_count potential hardcoded API keys!"
        print_info "Potential API keys:"
        echo "$api_keys_found"
        all_passed=false
    else
        print_success "No hardcoded API keys found!"
    fi
    
    # Check for passwords
    print_info "Checking for hardcoded passwords..."
    
    local password_count=0
    local passwords_found=""
    
    while IFS= read -r line; do
        if [[ "$line" == *"password"* ]] || [[ "$line" == *"passwd"* ]]; then
            # Skip const declarations and test files
            if [[ ! "$line" == *"const String"* ]] && [[ ! "$line" == *"test"* ]]; then
                password_count=$((password_count + 1))
                passwords_found+="$line\n"
            fi
        fi
    done < <(grep -r "password\|passwd" "$LIB_DIR/" --include="*.dart" --exclude-dir=generated 2>/dev/null || true)
    
    if [ "$password_count" -gt 0 ]; then
        print_error "Found $password_count potential hardcoded passwords!"
        print_info "Potential passwords:"
        echo "$passwords_found"
        all_passed=false
    else
        print_success "No hardcoded passwords found!"
    fi
    
    # Check for tokens
    print_info "Checking for hardcoded tokens..."
    
    local token_count=0
    local tokens_found=""
    
    while IFS= read -r line; do
        if [[ "$line" == *"token"* ]] || [[ "$line" == *"secret"* ]]; then
            # Skip const declarations
            if [[ ! "$line" == *"const String"* ]]; then
                token_count=$((token_count + 1))
                tokens_found+="$line\n"
            fi
        fi
    done < <(grep -r "token\|secret" "$LIB_DIR/" --include="*.dart" --exclude-dir=generated 2>/dev/null || true)
    
    if [ "$token_count" -gt 0 ]; then
        print_error "Found $token_count potential hardcoded tokens/secrets!"
        print_info "Potential tokens/secrets:"
        echo "$tokens_found"
        all_passed=false
    else
        print_success "No hardcoded tokens/secrets found!"
    fi
    
    if [ "$all_passed" = true ]; then
        print_success "Security scan passed!"
        return 0
    else
        print_error "Security scan failed!"
        return 1
    fi
}

# Check file sizes
check_file_sizes() {
    print_section "Checking File Sizes"
    
    print_info "Looking for excessively large files..."
    
    local large_files=0
    local max_size=1000  # 1000 lines
    
    while IFS= read -r file; do
        line_count=$(wc -l < "$file" | tr -d ' ')
        if [ "$line_count" -gt "$max_size" ]; then
            large_files=$((large_files + 1))
            print_info "Large file: $file ($line_count lines)"
        fi
    done < <(find "$LIB_DIR/" -name "*.dart" -type f ! -path "*/generated/*" 2>/dev/null)
    
    if [ "$large_files" -eq 0 ]; then
        print_success "All files are within reasonable size limits!"
        return 0
    else
        print_error "Found $large_files files exceeding $max_size lines!"
        print_info "Consider splitting large files into smaller modules"
        return 1
    fi
}

# Check cyclomatic complexity (using dart_code_metrics if available)
check_complexity() {
    print_section "Checking Code Complexity"
    
    if command_exists dart_code_metrics; then
        print_info "Running dart_code_metrics..."
        
        if dart_code_metrics analyze lib/ --reporter=console 2>&1 | tee complexity_report.txt; then
            print_success "Complexity check passed!"
            return 0
        else
            print_error "Complexity check failed!"
            print_info "See complexity_report.txt for details"
            return 1
        fi
    else
        print_info "dart_code_metrics not installed, skipping complexity check"
        print_info "Install with: dart pub global activate dart_code_metrics"
        return 0
    fi
}

# Run all quality checks
run_all_checks() {
    print_header
    
    local all_passed=true
    
    # Run static analysis
    if ! run_analysis; then
        all_passed=false
    fi
    
    # Check formatting
    if ! check_formatting; then
        all_passed=false
    fi
    
    # Run linter
    if ! run_linter; then
        all_passed=false
    fi
    
    # Check for TODO comments
    if ! check_todos; then
        all_passed=false
    fi
    
    # Run security scan
    if ! run_security_scan; then
        all_passed=false
    fi
    
    # Check file sizes
    if ! check_file_sizes; then
        all_passed=false
    fi
    
    # Check complexity
    if ! check_complexity; then
        all_passed=false
    fi
    
    # Summary
    print_section "Quality Check Summary"
    
    if [ "$all_passed" = true ]; then
        print_success "All quality checks passed! ✓"
        return 0
    else
        print_error "Some quality checks failed! ✗"
        return 1
    fi
}

# ============================================
# MAIN EXECUTION
# ============================================

# Print header
print_header

# Check if Flutter is installed
if ! command_exists flutter; then
    print_error "Flutter is not installed!"
    print_info "Install Flutter from: https://flutter.dev/docs/get-started/install"
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    print_error "pubspec.yaml not found!"
    print_info "Please run this script from the project root directory."
    exit 1
fi

# Parse command line arguments
case "$1" in
    "analyze")
        run_analysis
        ;;
    "format")
        check_formatting
        ;;
    "lint")
        run_linter
        ;;
    "security")
        run_security_scan
        ;;
    "todos")
        check_todos
        ;;
    "complexity")
        check_complexity
        ;;
    "sizes")
        check_file_sizes
        ;;
    "all")
        run_all_checks
        ;;
    "")
        run_all_checks
        ;;
    *)
        print_error "Unknown command: $1"
        print_info "Available commands: all, analyze, format, lint, security, todos, complexity, sizes"
        exit 1
        ;;
esac

# Exit with appropriate status
exit $?
