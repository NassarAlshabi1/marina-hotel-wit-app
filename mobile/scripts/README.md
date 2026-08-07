# Marina Hotel Mobile - Scripts Documentation
# ================================================

> **F4DD Last Updated:** 2026-08-03  
> **F4BB Maintainer:** Marina Hotel Dev Team  
> **F4A1 Version:** 1.2.0+3  

---

## F4C8 Table of Contents

1. [F4AF Introduction](#-introduction)
2. [F4B0 Available Scripts](#-available-scripts)
   - [run_tests.sh](#run_testssh)
   - [check_quality.sh](#check_qualitysh)
   - [build_production.sh](#build_productionsh)
3. [F4D1 Usage Examples](#-usage-examples)
4. [F4BB Makefile Integration](#-makefile-integration)
5. [F4BC Customization](#-customization)
6. [F4B8 Troubleshooting](#-troubleshooting)

---

## F4AF Introduction

This directory contains **automation scripts** for the **Marina Hotel Mobile** project. These scripts help automate common development tasks such as:

- F499 Running tests (unit, widget, integration, performance)
- F499 Checking code quality (analysis, linting, formatting)
- F499 Building production artifacts (APK, AppBundle)
- F499 Security scanning
- F499 Code generation

---

## F4B0 Available Scripts

### F469 run_tests.sh

**Purpose:** Automate test execution with coverage reporting

**Location:** `scripts/run_tests.sh`

**Features:**
- Run unit tests
- Run widget tests
- Run integration tests
- Run performance tests
- Generate combined coverage reports
- Check minimum coverage requirements (80%)
- Generate HTML coverage reports

**Usage:**
```bash
# Make executable (one-time setup)
chmod +x scripts/run_tests.sh

# Run all tests with coverage
./scripts/run_tests.sh

# Run specific test types
./scripts/run_tests.sh unit      # Unit tests only
./scripts/run_tests.sh widget    # Widget tests only
./scripts/run_tests.sh integration # Integration tests only
./scripts/run_tests.sh performance # Performance tests only
./scripts/run_tests.sh coverage  # All tests with coverage

# Clean test artifacts
./scripts/run_tests.sh clean
```

**Outputs:**
- `test_results_*.txt` - Test execution logs
- `coverage/*.lcov` - Coverage data files
- `coverage/combined.lcov` - Combined coverage data
- `coverage/html/` - HTML coverage report
- `performance_report.json` - Performance test results

---

### F469 check_quality.sh

**Purpose:** Automate code quality checks

**Location:** `scripts/check_quality.sh`

**Features:**
- Static analysis (`flutter analyze`)
- Code formatting check (`flutter format`)
- Linting (`flutter lint`)
- TODO/FIXME/XXX/HACK comment detection
- Security scanning (GitLeaks)
- Hardcoded API key detection
- Hardcoded password detection
- Hardcoded token/secret detection
- File size checking
- Code complexity analysis (if dart_code_metrics is installed)

**Usage:**
```bash
# Make executable (one-time setup)
chmod +x scripts/check_quality.sh

# Run all quality checks
./scripts/check_quality.sh

# Run specific checks
./scripts/check_quality.sh analyze    # Static analysis only
./scripts/check_quality.sh format    # Formatting check only
./scripts/check_quality.sh lint      # Linting only
./scripts/check_quality.sh security  # Security scan only
./scripts/check_quality.sh todos    # TODO comment check only
./scripts/check_quality.sh complexity # Complexity check only
./scripts/check_quality.sh sizes    # File size check only
```

**Outputs:**
- `analyze_report.txt` - Static analysis results
- `format_report.txt` - Formatting check results
- `lint_report.txt` - Linting results
- `security_report.txt` - Security scan results
- `complexity_report.txt` - Complexity analysis results

---

### F469 build_production.sh

**Purpose:** Automate production build process

**Location:** `scripts/build_production.sh`

**Features:**
- Clean build artifacts
- Install and update dependencies
- Generate code (Freezed, JSON Serializable, Riverpod, Drift)
- Run quality checks
- Build production APK (all architectures)
- Build production AppBundle
- Verify build outputs
- Package build artifacts
- Obfuscation enabled
- Debug symbols separated

**Usage:**
```bash
# Make executable (one-time setup)
chmod +x scripts/build_production.sh

# Full production build
./scripts/build_production.sh

# Build specific artifacts
./scripts/build_production.sh apk       # APK only
./scripts/build_production.sh appbundle # AppBundle only

# Clean build artifacts
./scripts/build_production.sh clean

# Verify existing build
./scripts/build_production.sh verify
```

**Outputs:**
- `build/app/outputs/flutter-apk/*.apk` - Production APKs
- `build/app/outputs/bundle/release/*.aab` - Production AppBundle
- `debug_symbols/` - Debug symbols for crash reporting
- `build_artifacts_*.zip` - Packaged build artifacts
- `outdated_dependencies.txt` - List of outdated dependencies

---

## F4D1 Usage Examples

### F44B Daily Development Workflow

```bash
# 1. Run tests for your changes
./scripts/run_tests.sh unit

# 2. Check code quality
./scripts/check_quality.sh

# 3. Fix any issues and commit
```

---

### F44B Before Creating a Pull Request

```bash
# 1. Run all tests
./scripts/run_tests.sh

# 2. Run all quality checks
./scripts/check_quality.sh

# 3. Generate code
flutter pub run build_runner build --delete-conflicting-outputs

# 4. Verify everything passes
```

---

### F44B Before Production Release

```bash
# 1. Clean and prepare
./scripts/build_production.sh clean

# 2. Full production build
./scripts/build_production.sh

# 3. Verify build
./scripts/build_production.sh verify

# 4. Deploy to Firebase App Distribution
# (Requires FIREBASE_APP_ID and FIREBASE_TOKEN environment variables)
make deploy-firebase
```

---

### F44B Continuous Integration (CI) Workflow

The GitHub Actions workflow (`.github/workflows/flutter_ci_cd.yml`) automatically runs:

```bash
# Code Quality Job
- flutter analyze
- flutter format --set-exit-if-changed
- flutter lint
- TODO comment check

# Unit & Widget Tests Job
- flutter test test/unit/ --coverage
- flutter test test/widget/ --coverage

# Integration Tests Job
- flutter test integration_test/ --coverage

# Coverage Report Job
- Combine all coverage files
- Generate HTML report
- Check minimum 80% coverage

# Build Jobs (on main/A/release branches)
- Build production APK
- Build production AppBundle

# Security Job
- GitLeaks scan
- Hardcoded secrets check

# Performance Job
- Performance tests
- Generate performance report
```

---

## F4BB Makefile Integration

The project includes a **Makefile** that wraps these scripts for easier execution:

| Make Command | Script Equivalent | Description |
|--------------|-------------------|-------------|
| `make test` | `./scripts/run_tests.sh` | Run all tests |
| `make test-unit` | `./scripts/run_tests.sh unit` | Run unit tests |
| `make test-widget` | `./scripts/run_tests.sh widget` | Run widget tests |
| `make test-integration` | `./scripts/run_tests.sh integration` | Run integration tests |
| `make test-coverage` | `./scripts/run_tests.sh coverage` | Run tests with coverage |
| `make lint` | `./scripts/check_quality.sh` | Run all quality checks |
| `make analyze` | `./scripts/check_quality.sh analyze` | Run static analysis |
| `make format` | `./scripts/check_quality.sh format` | Check formatting |
| `make quality` | `./scripts/check_quality.sh` | Full quality check |
| `make build` | `./scripts/build_production.sh` | Full production build |
| `make build-apk` | `./scripts/build_production.sh apk` | Build APK only |
| `make build-appbundle` | `./scripts/build_production.sh appbundle` | Build AppBundle only |
| `make clean` | `./scripts/build_production.sh clean` | Clean build artifacts |
| `make generate` | `flutter pub run build_runner build` | Generate code |

---

## F4BC Customization

### F44B Modifying Test Configuration

Edit `scripts/run_tests.sh` to:
- Change test directories
- Modify coverage thresholds
- Add custom test reporters
- Change output directories

---

### F44B Modifying Quality Checks

Edit `scripts/check_quality.sh` to:
- Add custom lint rules
- Modify security scan patterns
- Change file size limits
- Add new quality checks

---

### F44B Modifying Build Configuration

Edit `scripts/build_production.sh` to:
- Change build types (debug/release)
- Modify build options
- Add custom build steps
- Change output directories

---

### F44B Adding New Scripts

To add a new script:

1. Create the script file in `scripts/`
2. Make it executable: `chmod +x scripts/your_script.sh`
3. Add a corresponding Makefile target
4. Document it in this README

Example template:

```bash
#!/bin/bash

# Script Name - Description
# ========================

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Functions
print_success() {
    echo "${GREEN}✓ $1${NC}"
}

print_error() {
    echo "${RED}✗ $1${NC}"
}

# Main execution
print_success "Script executed successfully!"
```

---

## F4B8 Troubleshooting

### F44E Script Permissions

**Problem:** `Permission denied` when running scripts

**Solution:**
```bash
# Make all scripts executable
chmod +x scripts/*.sh

# Or make specific script executable
chmod +x scripts/run_tests.sh
```

---

### F44E Missing Dependencies

**Problem:** Script fails with `command not found`

**Solutions:**

#### Flutter not found
```bash
# Install Flutter
https://flutter.dev/docs/get-started/install
```

#### lcov not found
```bash
# Ubuntu/Debian
sudo apt-get install -y lcov

# macOS
brew install lcov
```

#### genhtml not found
```bash
# Ubuntu/Debian (included with lcov)
sudo apt-get install -y lcov

# macOS (included with lcov)
brew install lcov
```

#### gitleaks not found
```bash
# macOS
brew install gitleaks

# Linux
sudo snap install gitleaks

# Or download from GitHub
https://github.com/gitleaks/gitleaks/releases
```

#### dart_code_metrics not found
```bash
dart pub global activate dart_code_metrics
```

---

### F44E Tests Failing

**Problem:** Tests are failing in scripts but passing locally

**Solutions:**
- Ensure you're using the same Flutter version
- Run `flutter pub get` to update dependencies
- Check for platform-specific code
- Verify test environment setup

```bash
# Run tests with verbose output
flutter test -v test/unit/your_test.dart
```

---

### F44E Build Failing

**Problem:** Build is failing in scripts

**Solutions:**
- Check Flutter version compatibility
- Verify all dependencies are compatible
- Check for platform-specific issues
- Ensure code generation is complete

```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter build apk
```

---

### F44E Coverage Below Threshold

**Problem:** Coverage is below 80%

**Solutions:**
- Add more tests for untested code
- Check if tests are actually running
- Verify coverage files are being generated
- Exclude generated files from coverage

```bash
# Check which files have low coverage
lcov --list coverage/combined.lcov
```

---

## F4C4 Best Practices

### F44B Script Development

1. **Use consistent naming:** Use lowercase with underscores (e.g., `run_tests.sh`)
2. **Add documentation:** Include usage instructions in comments
3. **Handle errors gracefully:** Check for command existence and dependencies
4. **Use colors for output:** Makes logs easier to read
5. **Provide meaningful messages:** Help users understand what's happening
6. **Return proper exit codes:** 0 for success, non-zero for failure

---

### F44B Script Execution

1. **Always check prerequisites:** Verify Flutter, dependencies, etc.
2. **Run from project root:** Most scripts expect to be run from the project root
3. **Check exit codes:** Use `$?` to check if previous command succeeded
4. **Use tee for logging:** Saves output to files for debugging
5. **Clean up after failures:** Remove temporary files

---

### F44B Security

1. **Never commit secrets:** Use environment variables for sensitive data
2. **Scan for secrets:** Run security scans regularly
3. **Review scripts:** Ensure scripts don't expose sensitive information
4. **Use .gitignore:** Exclude generated files and sensitive data

---

## F4C4 Additional Resources

- [Bash Scripting Tutorial](https://ryanstutorials.net/bash-scripting-tutorial/)
- [ShellCheck - Static Analysis for Shell Scripts](https://www.shellcheck.net/)
- [Flutter CLI Documentation](https://docs.flutter.dev/reference/flutter-cli)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

---

## F4C4 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-01 | Initial scripts (run_tests.sh, check_quality.sh) |
| 1.1.0 | 2026-06-01 | Added build_production.sh |
| 1.2.0 | 2026-08-03 | Updated all scripts for production readiness |

---

> **F44D Note:** This documentation is a living document. Please update it as new scripts are added or existing ones are modified.

---

**F44B Happy Scripting! F389**
