# Marina Hotel Mobile - Code Quality Reports Guide
# ====================================================

> **F4DD Last Updated:** 2026-08-04  
> **F4BB Maintainer:** Marina Hotel Dev Team  
> **F4A1 Version:** 1.0.0  
> **F4F0 Status:** F534 **ACTIVE** F534

---

## F4C8 Table of Contents

1. [F4AF Introduction](#-introduction)
2. [F4B0 Report Types](#-report-types)
3. [F4D1 How to Generate Reports](#-how-to-generate-reports)
4. [F4E6 Report Generation Script](#-report-generation-script)
5. [F4BB Quality Reports](#-quality-reports)
6. [F4BC Test Reports](#-test-reports)
7. [F4BD Coverage Reports](#-coverage-reports)
8. [F4BE Security Reports](#-security-reports)
9. [F4BF Final Comprehensive Report](#-final-comprehensive-report)
10. [F4C0 Configuration](#-configuration)
11. [F4C1 CI/CD Integration](#-cicd-integration)
12. [F4C2 Best Practices](#-best-practices)
13. [F4C4 Troubleshooting](#-troubleshooting)

---

## F4AF Introduction

This guide explains the **Code Quality Reports System** for **Marina Hotel Mobile**. The system generates **comprehensive reports** to help maintain **high code quality, security, and test coverage** throughout the development lifecycle.

---

## F4B0 Report Types

### F469 Available Reports

| Report Type | Command | Description | Output Files |
|-------------|---------|-------------|--------------|
| **Quality Reports** | `make quality-report` | Static analysis, linting, formatting, complexity | `quality_reports/` |
| **Test Reports** | `make test-report` | Unit, widget, integration test results | `test_results/` |
| **Coverage Reports** | `make coverage-report` | Code coverage analysis | `coverage/` |
| **Security Reports** | `make security-report` | Security scanning results | `security_reports/` |
| **Final Report** | `make final-report` | Comprehensive summary of all reports | `reports/` |
| **All Reports** | `make reports` | Generate all reports | All of the above |

### F469 Report Structure

```
reports/
├── code_quality_final_report.md          # Final comprehensive report
└── quality_reports/
    ├── analysis_report.json              # Static analysis results
    ├── lint_report.json                  # Linting results
    ├── format_report.json                # Formatting results
    ├── complexity_report.json             # Complexity analysis
    └── quality_summary.md                # Quality summary

coverage/
├── combined.lcov                         # Combined coverage data
├── coverage_summary.md                   # Coverage summary
├── html/                                 # HTML coverage report
│   ├── index.html                       # Main coverage page
│   └── ...                              # Supporting files
└── *.lcov                               # Individual coverage files

test_results/
├── test_report.md                        # Test summary
├── unit_tests.json                      # Unit test results
├── widget_tests.json                    # Widget test results
└── integration_tests.json               # Integration test results

security_reports/
├── security_report.json                 # Security scan results
└── gitleaks_report.json                 # GitLeaks scan results
```

---

## F4D1 How to Generate Reports

### F469 Using Makefile (Recommended)

```bash
# Generate all reports
make reports

# Generate specific report types
make quality-report    # Quality reports only
make test-report       # Test reports only
make coverage-report   # Coverage reports only
make security-report   # Security reports only
make final-report      # Final comprehensive report

# Clean all reports
make clean-reports
```

### F469 Using Script Directly

```bash
# Make script executable (one-time setup)
chmod +x scripts/generate_reports.sh

# Generate all reports
./scripts/generate_reports.sh all

# Generate specific report types
./scripts/generate_reports.sh quality
./scripts/generate_reports.sh test
./scripts/generate_reports.sh coverage
./scripts/generate_reports.sh security

# Clean reports
./scripts/generate_reports.sh clean
```

### F469 In CI/CD

The reports are **automatically generated** in the CI/CD pipeline:
- **On every push** to `main`, `A`, `develop`, `release/*`
- **On every pull request** to `main`, `A`
- **Reports are uploaded as artifacts**

---

## F4E6 Report Generation Script

### F469 Script Overview

**File:** `scripts/generate_reports.sh`

**Features:**
- Generate **quality reports** (analysis, lint, format, complexity)
- Generate **test reports** (unit, widget, integration)
- Generate **coverage reports** (combined, HTML)
- Generate **security reports** (GitLeaks, secrets scanning)
- Generate **final comprehensive report** (summary of all)
- **Color-coded output** for easy reading
- **Error handling** for missing dependencies
- **Progress tracking** during generation

### F469 Script Commands

| Command | Description |
|---------|-------------|
| `./scripts/generate_reports.sh` | Generate all reports |
| `./scripts/generate_reports.sh quality` | Generate quality reports only |
| `./scripts/generate_reports.sh test` | Generate test reports only |
| `./scripts/generate_reports.sh coverage` | Generate coverage reports only |
| `./scripts/generate_reports.sh security` | Generate security reports only |
| `./scripts/generate_reports.sh clean` | Clean all reports |

---

## F4BB Quality Reports

### F469 Static Analysis Report

**File:** `quality_reports/analysis_report.json`

**Generated by:** `flutter analyze --format=json`

**Contains:**
- Type errors
- Null safety issues
- Undefined identifiers
- Argument type mismatches
- Return type errors

**Example Output:**
```json
{
  "issues": [
    {
      "severity": "error",
      "message": "The argument type 'String' can't be assigned to the parameter type 'int'",
      "file": "lib/features/booking/booking_service.dart",
      "line": 42,
      "column": 15
    }
  ],
  "errors": [],
  "warnings": []
}
```

### F469 Lint Report

**File:** `quality_reports/lint_report.json`

**Generated by:** `flutter lint --format=json`

**Contains:**
- Code style violations
- Best practice violations
- Naming convention issues
- Documentation requirements

**Example Output:**
```json
[
  {
    "severity": "warning",
    "rule": "avoid_print",
    "message": "Avoid print calls in production code",
    "file": "lib/features/debug/debug_service.dart",
    "line": 25,
    "column": 5
  }
]
```

### F469 Format Report

**File:** `quality_reports/format_report.json`

**Generated by:** `flutter format --output=json`

**Contains:**
- Files that need formatting
- Formatting issues
- Line and column information

### F469 Complexity Report

**File:** `quality_reports/complexity_report.json`

**Generated by:** `dart_code_metrics analyze`

**Contains:**
- Cyclomatic complexity metrics
- Lines of code per file
- Number of parameters per function
- Nesting depth
- Anti-patterns detected

**Example Output:**
```json
{
  "metrics": {
    "averageCyclomaticComplexity": 12.5,
    "averageLinesOfCode": 85.2,
    "averageNumberOfParameters": 2.1
  },
  "files": [
    {
      "path": "lib/features/booking/booking_service.dart",
      "metrics": {
        "cyclomaticComplexity": 15,
        "linesOfCode": 120,
        "numberOfParameters": 4
      }
    }
  ]
}
```

### F469 Quality Summary

**File:** `quality_reports/quality_summary.md`

**Contains:**
- Overall quality score (0-100)
- Grade (A+, A, B, C, D)
- Summary of all quality checks
- Recommendations for improvement

**Example Output:**
```markdown
# Code Quality Summary Report

**Generated:** 2026-08-04

## Static Analysis
- **Status:** ✅ PASSED
- **Errors:** 0
- **Warnings:** 2
- **Total Issues:** 2

## Linting
- **Status:** ⚠️ WARNINGS
- **Issues:** 8

## Code Formatting
- **Status:** ✅ PASSED
- **Files to format:** 0

## Code Complexity
- **Files analyzed:** 45
- **Avg. complexity:** 12.5
- **Avg. lines/file:** 85.2
- **Status:** ✅ GOOD COMPLEXITY

## Overall Quality Score
- **Quality Score:** 92/100
- **Total Issues:** 10
- **Grade:** 🌟 A (Good)
```

---

## F4BC Test Reports

### F469 Test Report

**File:** `test_results/test_report.md`

**Generated by:** Running all tests with `--reporter=json`

**Contains:**
- Test counts (total, passed, failed)
- Success rate (%)
- Time taken
- Summary by test type
- Recommendations

**Example Output:**
```markdown
# Test Report

**Generated:** 2026-08-04

## Test Summary

| Test Type | Total | Passed | Failed | Success Rate |
|------------|-------|--------|--------|--------------|
| Unit Tests | 125 | 120 | 5 | 96% |
| Widget Tests | 85 | 80 | 5 | 94% |
| Integration Tests | 35 | 30 | 5 | 86% |
| **Total** | **245** | **230** | **15** | **94%** |

## Overall Status
- **Status:** ✅ GOOD (94% pass rate)
- **Total Tests:** 245
- **Passed:** 230
- **Failed:** 15
- **Total Time:** 125s

## Recommendations
- ❌ **Fix failing tests** before merging
- ⚠️ **Improve test coverage** - aim for 80%+ pass rate
- ℹ️ **Consider adding more tests** - currently only 245 tests
```

### F469 Individual Test Results

**Files:**
- `test_results/unit_tests.json` - Unit test results
- `test_results/widget_tests.json` - Widget test results
- `test_results/integration_tests.json` - Integration test results

**Format:** JSON with test names, results, times, and messages

---

## F4BD Coverage Reports

### F469 Coverage Summary

**File:** `coverage/coverage_summary.md`

**Generated by:** `lcov` + `genhtml`

**Contains:**
- Total lines of code
- Covered lines
- Coverage percentage
- Status (✅/⚠️/❌)
- HTML report location

**Example Output:**
```markdown
# Coverage Report

**Generated:** 2026-08-04

## Coverage Summary
- **Total Lines:** 5248
- **Covered Lines:** 4520
- **Coverage Percentage:** 86%

- **Status:** ✅ EXCELLENT (>= 80% required)

## Coverage Details
Run the following to see detailed coverage:
```bash
lcov --list coverage/combined.lcov
```

Or open the HTML report:
```bash
xdg-open coverage/html/index.html  # Linux
open coverage/html/index.html      # macOS
```
```

### F469 HTML Coverage Report

**Location:** `coverage/html/index.html`

**Features:**
- Interactive coverage visualization
- File-by-file breakdown
- Line-by-line coverage
- Branch coverage
- Color-coded (green = covered, red = not covered)

**How to View:**
```bash
# Linux
xdg-open coverage/html/index.html

# macOS
open coverage/html/index.html

# Windows
start coverage/html/index.html
```

### F469 Combined Coverage File

**File:** `coverage/combined.lcov`

**Format:** LCOV format for coverage data

**Used for:**
- Generating HTML reports
- Calculating coverage percentages
- Integration with CI/CD

---

## F4BE Security Reports

### F469 Security Report

**File:** `security_reports/security_report.json`

**Generated by:** GitLeaks + custom scans

**Contains:**
- GitLeaks scan results
- Hardcoded API keys
- Hardcoded passwords
- Hardcoded tokens/secrets
- Overall security status

**Example Output:**
```json
{
  "gitleaks_scan": {
    "status": "PASSED",
    "secrets_found": 0
  },
  "hardcoded_checks": {
    "api_keys": 0,
    "passwords": 0,
    "tokens": 0
  },
  "overall_status": "PASSED"
}
```

### F469 GitLeaks Report

**File:** `security_reports/gitleaks_report.json`

**Generated by:** `gitleaks detect`

**Contains:**
- All secrets found
- File locations
- Line numbers
- Secret types

---

## F4BF Final Comprehensive Report

### F469 Final Report

**File:** `reports/code_quality_final_report.md`

**Generated by:** Combining all reports

**Contains:**
- **Code Quality Summary**
- **Test Results Summary**
- **Coverage Summary**
- **Security Analysis**
- **Project Health Overview**
- **Overall Health Score** (0-100)
- **Health Grade** (A+, A, B, C, D)
- **Recommendations**

**Example Output:**
```markdown
# Marina Hotel Mobile - Code Quality Final Report

**Generated:** 2026-08-04

---

## Code Quality

- **Status:** ✅ PASSED
- **Quality Score:** 92/100
- **Grade:** 🌟 A (Good)
- **Total Issues:** 10

## Test Results

- **Status:** ✅ GOOD
- **Success Rate:** 94%
- **Total Tests:** 245
- **Passed:** 230
- **Failed:** 15

## Code Coverage

- **Status:** ✅ EXCELLENT
- **Coverage Percentage:** 86%
- **Total Lines:** 5248
- **Covered Lines:** 4520

## Security Analysis

- **Status:** ✅ PASSED
- **GitLeaks Scan:** PASSED
- **Hardcoded Secrets:** 0

## Project Health Overview

| Metric | Score | Grade |
|--------|-------|-------|
| Code Quality | 92% | ✅ |
| Test Results | 94% | ✅ |
| Code Coverage | 86% | ✅ |
| Security | 100% | ✅ |
| **Overall Health** | **93%** | **🌟 A+ (Excellent)** |

## Recommendations

- ⚠️ **Improve code quality** - aim for 80%+ score
- ⚠️ **Fix failing tests** - aim for 80%+ pass rate
- ⚠️ **Improve test coverage** - aim for 80%+ coverage

## How to Improve

1. **Fix Critical Issues:** Address all errors and security issues
2. **Improve Code Quality:** Follow best practices and refactor complex code
3. **Add More Tests:** Increase test coverage for untested code
4. **Review Copilot Feedback:** Address suggestions from GitHub Copilot
5. **Run Quality Checks:** Use `make quality` before committing
```

---

## F4C0 Configuration

### F469 Configuration File

**File:** `code_quality_config.yaml`

**Contains:**
- Global configuration
- Static analysis settings
- Linting rules
- Formatting options
- Complexity thresholds
- Testing configuration
- Security settings
- Code generation settings
- Reporting configuration
- CI/CD integration
- Local development settings
- Production configuration

### F469 Customizing Configuration

Edit `code_quality_config.yaml` to:
- Change quality thresholds
- Modify test timeouts
- Add custom lint rules
- Configure security scans
- Set up notifications

---

## F4C1 CI/CD Integration

### F469 Automatic Report Generation

Reports are **automatically generated** in CI/CD:

1. **On every push** to `main`, `A`, `develop`, `release/*`
2. **On every pull request** to `main`, `A`
3. **Reports are uploaded as artifacts**

### F469 CI/CD Workflow Jobs

| Job | Description | Reports Generated |
|-----|-------------|-------------------|
| **code_quality** | Static analysis, linting, formatting | Quality reports |
| **unit_widget_tests** | Unit and widget tests | Test reports, Coverage |
| **integration_tests** | Integration tests | Test reports, Coverage |
| **coverage** | Combine coverage, generate HTML | Coverage reports |
| **security_scan** | GitLeaks, secrets scanning | Security reports |
| **copilot_review** | Copilot code review | N/A |

### F469 Artifacts Uploaded

| Artifact Name | Contains | Available On |
|---------------|---------|--------------|
| `test-results` | Test logs and JSON reports | All runs |
| `coverage-report` | Coverage data and HTML report | All runs |
| `quality-reports` | Quality analysis reports | All runs |
| `security-reports` | Security scan results | All runs |
| `final-report` | Comprehensive final report | All runs |

---

## F4C2 Best Practices

### F469 For Developers

#### F44B Before Committing Code

```bash
# 1. Run quality checks
make quality

# 2. Run tests
make test

# 3. Generate reports (optional)
make reports

# 4. Review reports
cat reports/code_quality_final_report.md
```

#### F44B After Generating Reports

1. **Review the Final Report**
   - Check the **Overall Health Score**
   - Review **recommendations**
   - Address **critical issues**

2. **Fix Issues**
   - Fix **static analysis errors**
   - Fix **failing tests**
   - Fix **security issues**
   - Improve **code coverage**

3. **Improve Code Quality**
   - Reduce **code complexity**
   - Fix **linting warnings**
   - Improve **formatting**

### F469 For Reviewers

#### F44B Using Reports in Code Review

1. **Start with the Final Report**
   - Get an **overview** of code quality
   - Identify **critical issues**

2. **Review Detailed Reports**
   - Check **static analysis** for type errors
   - Review **test results** for failing tests
   - Examine **coverage report** for untested code
   - Check **security report** for vulnerabilities

3. **Provide Feedback**
   - Reference **specific reports** in comments
   - Ask developers to **fix critical issues**
   - Suggest **improvements** based on reports

### F469 For Project Maintainers

#### F44B Monitoring Project Health

1. **Track Health Score Over Time**
   - Monitor **Overall Health Score**
   - Set **improvement goals**

2. **Set Quality Gates**
   - Require **minimum quality score** (e.g., 80)
   - Require **minimum test pass rate** (e.g., 80%)
   - Require **minimum coverage** (e.g., 80%)

3. **Review Reports Regularly**
   - Check **weekly reports**
   - Identify **trends**
   - Address **systemic issues**

---

## F4C4 Troubleshooting

### F44E Reports Not Generating

**Problem:** Reports are not being generated.

**Solutions:**

1. **Check Dependencies**
   ```bash
   # Check if Flutter is installed
   flutter --version
   
   # Check if lcov is installed
   lcov --version
   
   # Check if genhtml is installed
   genhtml --version
   
   # Check if gitleaks is installed
   gitleaks --version
   ```

2. **Install Missing Dependencies**
   ```bash
   # Ubuntu/Debian
   sudo apt-get install -y lcov gitleaks
   
   # macOS
   brew install lcov gitleaks
   
   # dart_code_metrics
   dart pub global activate dart_code_metrics
   ```

3. **Check Script Permissions**
   ```bash
   chmod +x scripts/generate_reports.sh
   ```

4. **Run with Verbose Output**
   ```bash
   bash -x scripts/generate_reports.sh
   ```

---

### F44E Reports Contain Errors

**Problem:** Reports show errors or warnings.

**Solutions:**

1. **Review Error Messages**
   - Check the **console output**
   - Review the **report files**

2. **Fix Static Analysis Errors**
   ```bash
   flutter analyze
   ```

3. **Fix Linting Warnings**
   ```bash
   flutter lint
   ```

4. **Fix Formatting Issues**
   ```bash
   flutter format .
   ```

5. **Fix Failing Tests**
   ```bash
   flutter test
   ```

---

### F44E Coverage Below Threshold

**Problem:** Code coverage is below 80%.

**Solutions:**

1. **Identify Uncovered Code**
   ```bash
   lcov --list coverage/combined.lcov
   ```

2. **Add Tests for Uncovered Code**
   - Write **unit tests** for business logic
   - Write **widget tests** for UI components
   - Write **integration tests** for user journeys

3. **Exclude Generated Files**
   - Update `.lcovrc` to exclude generated files
   - Update `code_quality_config.yaml`

---

### F44E Security Issues Found

**Problem:** Security report shows issues.

**Solutions:**

1. **Review Security Report**
   ```bash
   cat security_reports/security_report.json
   ```

2. **Fix Hardcoded Secrets**
   - Remove **hardcoded API keys**
   - Remove **hardcoded passwords**
   - Remove **hardcoded tokens**
   - Use **environment variables** or **secure storage**

3. **Update GitLeaks Configuration**
   - Edit `.gitleaks.toml`
   - Add **false positive exclusions**

---

### F44E Reports Take Too Long

**Problem:** Report generation is slow.

**Solutions:**

1. **Run Specific Reports**
   ```bash
   # Instead of all reports
   make quality-report  # Faster
   ```

2. **Reduce Test Scope**
   ```bash
   # Run specific test types
   make test-unit
   ```

3. **Use Caching**
   - CI/CD already uses **caching** for dependencies
   - Ensure **cache is working**

---

## F4C4 Additional Resources

- [Flutter Testing Documentation](https://docs.flutter.dev/testing)
- [Flutter Code Analysis](https://docs.flutter.dev/development/tools/analyzer)
- [Flutter Linting](https://docs.flutter.dev/development/tools/linter)
- [Flutter Formatting](https://docs.flutter.dev/development/tools/formatter)
- [Code Coverage with Flutter](https://docs.flutter.dev/testing/code-coverage)
- [GitLeaks Documentation](https://github.com/gitleaks/gitleaks)
- [LCOV Documentation](http://ltp.sourceforge.net/coverage/lcov.php)
- [dart_code_metrics](https://pub.dev/packages/dart_code_metrics)

---

## F4C4 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-08-04 | Initial reports system setup |

---

> **F44D Note:** This guide will be updated as the reports system evolves and new features are added.

---

## F4C4 Support

For questions or issues with the reports system:

1. **Check this guide** for common issues
2. **Review script logs** for errors
3. **Check CI/CD workflow logs** in GitHub Actions
4. **Contact the Marina Hotel Dev Team** for project-specific questions

---

**F44B Happy Reporting! F389**
