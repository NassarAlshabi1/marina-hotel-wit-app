# Marina Hotel Mobile - Testing & Quality Guide
# ================================================

> **F4DD Last Updated:** 2026-08-03  
> **F4BB Maintainer:** Marina Hotel Dev Team  
> **F4A1 Version:** 1.2.0+3  

---

## F4C8 Table of Contents

1. [F4AF Introduction](#-introduction)
2. [F4B0 Testing Strategy](#-testing-strategy)
3. [F4D1 Test Types](#-test-types)
   - [Unit Tests](#unit-tests)
   - [Widget Tests](#widget-tests)
   - [Integration Tests](#integration-tests)
   - [Performance Tests](#performance-tests)
4. [F4DD Code Quality](#-code-quality)
   - [Static Analysis](#static-analysis)
   - [Linting](#linting)
   - [Code Formatting](#code-formatting)
   - [Code Coverage](#code-coverage)
5. [F4E6 CI/CD Pipeline](#-cicd-pipeline)
6. [F4BB Local Development](#-local-development)
7. [F4BC Production Readiness](#-production-readiness)
8. [F4B8 Troubleshooting](#-troubleshooting)

---

## F4AF Introduction

This guide provides comprehensive information about **testing and code quality** for the **Marina Hotel Mobile** application. The project follows **best practices** for Flutter/Dart development to ensure **high quality, maintainability, and production readiness**.

---

## F4B0 Testing Strategy

Our testing strategy follows the **Testing Pyramid** approach:

```
                    +-----------------+
                    |   E2E Tests     |  (Integration)
                    +-----------------+
                           ^
                           |
              +-----------------------+
              |    Widget Tests       |  (UI Components)
              +-----------------------+
                      ^
                      |
        +-------------------------------+
        |         Unit Tests            |  (Business Logic)
        +-------------------------------+
```

### F4CA Test Coverage Goals

| Test Type | Coverage Target | Current Status |
|-----------|-----------------|----------------|
| Unit Tests | 80%+ | F534 Active |
| Widget Tests | 70%+ | F534 Active |
| Integration Tests | 60%+ | F534 Active |
| **Total Coverage** | **80%+** | F534 Required |

---

## F4D1 Test Types

### F781 Unit Tests

**Purpose:** Test individual functions, classes, and business logic in isolation.

**Location:** `test/unit/`

**Example Test Files:**
- `test/unit/booking_price_adjustment_test.dart`
- `test/unit/payment_models_test.dart`
- `test/unit/cost_calculation_test.dart`
- `test/unit/time_utils_test.dart`

**How to Run:**
```bash
# Run all unit tests
flutter test test/unit/

# Run with coverage
flutter test test/unit/ --coverage

# Run specific test file
flutter test test/unit/booking_price_adjustment_test.dart
```

**Best Practices:**
- F499 Test one thing per test
- F499 Use descriptive test names
- F499 Use `setUp` and `tearDown` for test fixtures
- F499 Mock external dependencies
- F499 Test both happy paths and error cases

---

### F781 Widget Tests

**Purpose:** Test individual widgets and their rendering behavior.

**Location:** `test/widget/`

**Example Test Files:**
- `test/widget/widget_test.dart`
- `test/widget/sidebar_permissions_test.dart`
- `test/widget/status_utils_test.dart`

**How to Run:**
```bash
# Run all widget tests
flutter test test/widget/

# Run with coverage
flutter test test/widget/ --coverage

# Run specific widget test
flutter test test/widget/widget_test.dart
```

**Best Practices:**
- F499 Use `testWidgets` for widget tests
- F499 Use `pumpWidget` to render widgets
- F499 Test widget appearance and behavior
- F499 Use `Finder` to locate widgets
- F499 Use `Matcher` to verify widget properties

---

### F781 Integration Tests

**Purpose:** Test the complete application flow and interactions between components.

**Location:** `integration_test/`

**Example Test Files:**
- `integration_test/app_test.dart`
- `integration_test/booking_payment_test.dart`

**How to Run:**
```bash
# Run all integration tests
flutter test integration_test/

# Run with coverage
flutter test integration_test/ --coverage

# Run specific integration test
flutter test integration_test/app_test.dart
```

**Best Practices:**
- F499 Use `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`
- F499 Test user journeys (e.g., login -> booking -> payment)
- F499 Use real devices or emulators
- F499 Test on multiple screen sizes
- F499 Test both portrait and landscape modes

---

### F781 Performance Tests

**Purpose:** Test application performance and identify bottlenecks.

**Location:** `test/performance/`

**Example Test Files:**
- `test/performance/performance_test.dart`

**How to Run:**
```bash
# Run performance tests
flutter test test/performance/ --reporter=json

# Generate performance report
flutter test test/performance/ --reporter=json > performance_report.json
```

**Best Practices:**
- F499 Measure widget build times
- F499 Test list scrolling performance
- F499 Measure API response times
- F499 Test memory usage
- F499 Identify and optimize slow operations

---

## F4DD Code Quality

### F469 Static Analysis

**Tool:** `flutter analyze`

**Configuration:** `analysis_options.yaml`

**How to Run:**
```bash
# Run static analysis
flutter analyze

# Run with fatal warnings (CI mode)
flutter analyze --fatal-infos --fatal-warnings .
```

**What it Checks:**
- F499 Type errors
- F499 Null safety issues
- F499 Unused variables
- F499 Dead code
- F499 Incorrect imports
- F499 Missing return types

---

### F469 Linting

**Tool:** `flutter lint`

**Configuration:** `analysis_options.yaml` (Linter Rules)

**How to Run:**
```bash
# Run linter
flutter lint

# Run with specific directory
flutter lint lib/
```

**What it Checks:**
- F499 Code style violations
- F499 Naming conventions
- F499 Best practices
- F499 Anti-patterns
- F499 Documentation requirements

---

### F469 Code Formatting

**Tool:** `flutter format`

**How to Run:**
```bash
# Format all files
flutter format .

# Format specific directory
flutter format lib/

# Check if formatting is needed (CI mode)
flutter format --set-exit-if-changed .
```

**Formatting Rules:**
- F499 2-space indentation
- F499 80-character line limit
- F499 Trailing commas
- F499 Consistent spacing
- F499 Proper line breaks

---

### F469 Code Coverage

**Tool:** `lcov` + `genhtml`

**How to Generate Coverage Report:**
```bash
# Run tests with coverage
flutter test --coverage

# Combine multiple coverage files
lcov --rc lcov_branch_coverage=1 -c -i -d . -o coverage/combined.lcov
for file in coverage/*.lcov; do
  lcov --rc lcov_branch_coverage=1 -a "$file" -o coverage/combined.lcov
done

# Generate HTML report
genhtml coverage/combined.lcov --output-directory coverage/html

# Open report in browser
xdg-open coverage/html/index.html  # Linux
open coverage/html/index.html      # macOS
```

**Coverage Requirements:**
- F534 **Minimum 80%** for production
- F4CA **Recommended 90%** for critical modules
- F4CA **100%** for core business logic

---

## F4E6 CI/CD Pipeline

### F468 GitHub Actions Workflow

**File:** `.github/workflows/flutter_ci_cd.yml`

**Pipeline Jobs:**

1. **F499 Code Quality & Analysis**
   - Static analysis
   - Code formatting check
   - Linting
   - TODO comment check

2. **F499 Unit & Widget Tests**
   - Run all unit tests
   - Run all widget tests
   - Generate coverage reports

3. **F499 Integration Tests**
   - Run all integration tests
   - Generate coverage reports

4. **F499 Code Coverage Report**
   - Combine all coverage files
   - Generate HTML report
   - Check minimum coverage (80%)

5. **F499 Build APK (Production)**
   - Build release APK
   - Split per ABI (armeabi-v7a, arm64-v8a, x86_64)
   - Obfuscation enabled
   - Debug symbols separated

6. **F499 Build AppBundle (Google Play)**
   - Build release AppBundle
   - Obfuscation enabled
   - Debug symbols separated

7. **F499 Security Scan**
   - Scan for secrets using GitLeaks
   - Check for hardcoded API keys
   - Check for sensitive data

8. **F499 Performance Audit**
   - Run performance tests
   - Generate performance report

9. **F499 Deploy to Firebase (Optional)**
   - Deploy APKs to Firebase App Distribution
   - Deploy AppBundle to Firebase App Distribution

---

### F468 Trigger Conditions

| Event | Branches | Jobs Executed |
|-------|----------|---------------|
| Push | `main`, `A`, `develop`, `release/*` | All jobs |
| Pull Request | `main`, `A` | Quality, Tests, Coverage |

---

### F468 Artifacts

All jobs generate artifacts that can be downloaded from GitHub Actions:

- **Test Results:** Test outputs and logs
- **Coverage Reports:** HTML coverage reports
- **APK Files:** Production APKs (armeabi-v7a, arm64-v8a, x86_64)
- **AppBundle:** Production AppBundle
- **Debug Symbols:** For crash reporting
- **Performance Reports:** Performance test results

---

## F4BB Local Development

### F468 Quick Start

```bash
# Clone the repository
git clone https://github.com/NassarAlshabi1/marina-hotel-wit-app.git
cd marina-hotel-wit-app/mobile

# Install dependencies
flutter pub get

# Generate code (Freezed, JSON Serializable, etc.)
flutter pub run build_runner build

# Run the app
flutter run
```

---

### F468 Using Makefile

The project includes a **Makefile** for easy command execution:

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands |
| `make setup` | Install dependencies |
| `make build` | Build production APK and AppBundle |
| `make test` | Run all tests |
| `make lint` | Check code quality |
| `make clean` | Clean build artifacts |
| `make run` | Run the app |
| `make analyze` | Run static analysis |
| `make format` | Format all code |
| `make generate` | Generate all code |
| `make quality` | Full quality check |
| `make coverage` | Generate coverage report |

---

### F468 Common Workflows

#### F44B Before Committing Code

```bash
# 1. Format your code
make format

# 2. Run linter
make lint-check

# 3. Run static analysis
make analyze

# 4. Run tests for affected files
flutter test test/unit/your_test_file.dart
```

#### F44B Before Creating a Pull Request

```bash
# 1. Run full quality check
make quality

# 2. Run all tests
make test

# 3. Generate coverage report
make test-coverage

# 4. Check for security issues
make security-scan
```

#### F44B Before Production Release

```bash
# 1. Run full production pipeline
make production

# 2. Verify all tests pass
make test

# 3. Verify coverage is >= 80%
make test-coverage

# 4. Build production APKs
make build

# 5. Deploy to Firebase App Distribution
make deploy-firebase
```

---

## F4BC Production Readiness

### F499 Checklist

- [ ] All tests pass (unit, widget, integration)
- [ ] Code coverage >= 80%
- [ ] Static analysis passes with no errors
- [ ] Linting passes with no warnings
- [ ] Code is properly formatted
- [ ] No TODO/FIXME comments in production code
- [ ] No hardcoded secrets or API keys
- [ ] All dependencies are up to date
- [ ] App builds successfully in release mode
- [ ] Obfuscation is enabled
- [ ] Debug symbols are separated
- [ ] App is tested on multiple devices
- [ ] Performance tests pass
- [ ] Security scan passes

---

### F499 Production Build Configuration

**Build Commands:**
```bash
# Build production APK (all architectures)
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=./debug_symbols

# Build production AppBundle
flutter build appbundle --release --obfuscate --split-debug-info=./debug_symbols
```

**Build Options:**
- `--release`: Build in release mode
- `--split-per-abi`: Generate separate APKs for each ABI
- `--obfuscate`: Enable code obfuscation
- `--split-debug-info`: Separate debug symbols
- `--no-tree-shake-icons`: Don't remove unused icons

---

### F499 Production Dependencies

**Required Tools:**
- Flutter 3.35.7+
- Dart 3.8.0+
- Java 17+ (for Android)
- CocoaPods (for iOS)
- lcov (for coverage)
- genhtml (for coverage reports)
- gitleaks (for security scanning)

**Installation:**
```bash
# Install Flutter
flutter upgrade

# Install lcov and genhtml (Ubuntu/Debian)
sudo apt-get install -y lcov

# Install gitleaks
brew install gitleaks  # macOS
# OR
sudo snap install gitleaks  # Linux
```

---

## F4B8 Troubleshooting

### F4A1 Common Issues

#### F44E Tests Failing

**Problem:** Tests are failing in CI but passing locally.

**Solutions:**
- F499 Ensure you're using the same Flutter version
- F499 Run `flutter pub get` to update dependencies
- F499 Check for platform-specific code
- F499 Verify test environment setup

```bash
# Run tests with verbose output
flutter test -v test/unit/your_test.dart
```

---

#### F44E Code Coverage Below 80%

**Problem:** Code coverage is below the required 80%.

**Solutions:**
- F499 Add more tests for untested code
- F499 Check if tests are actually running
- F499 Verify coverage files are being generated
- F499 Exclude generated files from coverage

```bash
# Check which files have low coverage
lcov --list coverage/combined.lcov
```

---

#### F44E Static Analysis Errors

**Problem:** `flutter analyze` is reporting errors.

**Solutions:**
- F499 Fix type errors
- F499 Add proper null checks
- F499 Ensure all variables are properly typed
- F499 Check for missing imports

```bash
# Run analysis with verbose output
flutter analyze -v .
```

---

#### F44E Linting Warnings

**Problem:** `flutter lint` is reporting warnings.

**Solutions:**
- F499 Follow naming conventions
- F499 Add proper documentation
- F499 Fix code style issues
- F499 Check `analysis_options.yaml` for disabled rules

```bash
# Run linter with verbose output
flutter lint -v .
```

---

#### F44E Build Failures

**Problem:** Build is failing in CI.

**Solutions:**
- F499 Check Flutter version compatibility
- F499 Verify all dependencies are compatible
- F499 Check for platform-specific issues
- F499 Ensure code generation is complete

```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter build apk
```

---

### F4A1 Debugging Tips

#### F44E Debug Test Execution

```bash
# Run tests with debug output
flutter test -v test/unit/your_test.dart

# Run tests with pause on failure
flutter test --pause-after-load test/unit/your_test.dart
```

---

#### F44E Debug Code Generation

```bash
# Run build_runner with verbose output
flutter pub run build_runner build -v

# Watch for changes with verbose output
flutter pub run build_runner watch -v
```

---

#### F44E Debug Coverage

```bash
# Check coverage file contents
cat coverage/combined.lcov

# List files with coverage
lcov --list coverage/combined.lcov
```

---

## F4C4 Additional Resources

- [Flutter Testing Documentation](https://docs.flutter.dev/testing)
- [Very Good Analysis](https://pub.dev/packages/very_good_analysis)
- [GitLeaks Documentation](https://github.com/gitleaks/gitleaks)
- [Code Coverage with Flutter](https://docs.flutter.dev/testing/code-coverage)
- [GitHub Actions for Flutter](https://github.com/marketplace?type=actions&query=flutter)

---

## F4C4 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-01 | Initial testing guide |
| 1.1.0 | 2026-06-01 | Added CI/CD pipeline documentation |
| 1.2.0 | 2026-08-03 | Updated for production readiness |

---

> **F44D Note:** This guide is a living document. Please update it as the project evolves and new testing practices are adopted.

---

**F44B Happy Testing! F389**
