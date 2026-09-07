# Mobile Quality Gate - Enhanced Workflow Guide

## 📋 Overview

This is a comprehensive, enterprise-grade GitHub Actions workflow specifically designed for the **mobile** folder of the Marina Hotel project. It provides a complete quality assurance pipeline with advanced code analysis, testing, performance benchmarks, and security scanning.

## 🎯 Features

### ✅ Core Quality Checks
- **Code Formatting**: Ensures consistent Dart/Flutter code style
- **Static Analysis**: Deep analysis using Flutter's analyzer
- **Unit Testing**: Runs all tests with coverage reporting
- **Performance Benchmarks**: Measures app performance metrics

### 🔍 Advanced Quality Metrics
- **Duplicate Code Detection**: Identifies code duplication using jscpd (Dart support)
- **Code Complexity Analysis**: Measures cyclomatic complexity with Lizard (Dart support)
- **Security & Dependency Audit**: `dart pub outdated` + dependency tree dump + known-vulnerable package scan
- **Code Metrics**: Tracks lines of code, test coverage, and component counts

> **Note**: Previous versions of this workflow included Python-specific scanners
> (`bandit`, `safety`, `radon`). These have been removed because they don't
> produce meaningful signal for a Dart/Flutter codebase. The remaining tools
> (`jscpd`, `lizard`) are language-agnostic and explicitly support Dart.

### 📊 Reporting
- **Detailed Summaries**: Comprehensive GitHub step summaries
- **Artifact Uploads**: All reports available as downloadable artifacts
- **Coverage Gates**: Configurable minimum coverage thresholds

## 🚀 Usage

### Basic Usage

The workflow runs automatically on:
- Every push to any branch (when mobile files change)
- Every pull request (when mobile files change)

### Manual Trigger

1. Go to **Actions** tab in your GitHub repository
2. Select **Mobile Quality Gate - Enhanced** workflow
3. Click **Run workflow**
4. Choose your options:
   - **Check Level**: quick, full, or performance
   - **Run Tests**: Enable/disable unit tests
   - **Minimum Coverage**: Set coverage threshold (default: 60%)
   - **Upload Reports**: Enable/disable artifact uploads
   - **Run Benchmarks**: Enable/disable performance benchmarks

## 📝 Input Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `check_level` | choice | `quick` | Level of analysis: quick, full, or performance |
| `run_tests` | boolean | `true` | Whether to run unit tests |
| `min_coverage` | number | `60` | Minimum test coverage percentage |
| `upload_reports` | boolean | `true` | Upload reports as artifacts |
| `run_benchmarks` | boolean | `true` | Run performance benchmarks |

### Check Levels Explained

| Level | Duration | Includes |
|-------|----------|----------|
| **quick** | ~5 min | Format check, static analysis, unit tests |
| **full** | ~15 min | All quick checks + duplicate detection, complexity analysis, security scanning, detailed reports |
| **performance** | ~8 min | Format check, static analysis, performance benchmarks only |

## 🏗️ Jobs Overview

### 1. Setup Environment
- **Purpose**: Prepare the build environment
- **Duration**: ~5 minutes
- **Tasks**:
  - Checkout code
  - Setup Flutter SDK
  - Setup Java (for Android)
  - Setup Node.js (for jscpd)
  - Install global tools (jscpd, lizard)
  - Run Flutter doctor
  - Install dependencies
  - Run build_runner

### 2. Code Analysis & Formatting
- **Purpose**: Validate code quality and style
- **Duration**: ~10 minutes
- **Tasks**:
  - Check code formatting (dart format)
  - Run static analysis (flutter analyze)
  - Generate analysis summary

### 3. Unit Tests & Coverage
- **Purpose**: Verify functionality and code coverage
- **Duration**: ~15 minutes
- **Tasks**:
  - Run unit tests with coverage
  - Process coverage reports
  - Check coverage threshold
  - Generate test summary
  - Upload coverage artifacts

### 4. Performance Benchmarks
- **Purpose**: Measure app performance
- **Duration**: ~15 minutes
- **Tasks**:
  - Run performance tests (if available)
  - Generate benchmark reports
  - Upload benchmark artifacts

### 5. Extended Quality Checks (Full Mode Only)
- **Purpose**: Deep quality analysis
- **Duration**: ~15 minutes
- **Tasks**:
  - Duplicate code detection (jscpd — Dart support)
  - Security & dependency audit (`dart pub outdated` + dependency tree)
  - Code complexity analysis (Lizard — Dart support)
  - Generate comprehensive metrics
  - Upload quality reports

### 6. Final Summary
- **Purpose**: Consolidate all results
- **Duration**: ~5 minutes
- **Tasks**:
  - Generate final report
  - Display success/failure notifications

## 📊 Outputs & Artifacts

### GitHub Step Summary
Each job generates a detailed summary that appears in the GitHub Actions log, including:
- Pass/fail status for each check
- Metrics and statistics
- Recommendations for improvement

### Downloadable Artifacts

When `upload_reports` is enabled, the following artifacts are available:

1. **coverage-report-<branch>-<run_id>**
   - Coverage reports (lcov.info)
   - HTML coverage visualization
   - Retention: 14 days

2. **benchmarks-<branch>-<run_id>**
   - Performance benchmark logs
   - Retention: 30 days

3. **quality-reports-<branch>-<run_id>** (Full mode only)
   - Duplicate code reports (jscpd)
   - Security scan results
   - Complexity analysis reports
   - Retention: 14 days

## 🎨 Badges

Add these badges to your README to show the workflow status:

```markdown
![Mobile Quality Gate](https://github.com/NassarAlshabi1/marina-hotel-wit-app/actions/workflows/mobile-quality-gate.yml/badge.svg)
```

## 🔧 Customization

### Environment Variables

You can customize the workflow by modifying these environment variables at the top of the file:

```yaml
env:
  FLUTTER_VERSION: '3.44.4'    # Flutter SDK version
  DART_VERSION: '3.8.0'        # Dart SDK version
  WORKING_DIRECTORY: 'mobile'  # Project directory
  MIN_COVERAGE: 60             # Default minimum coverage
```

### Adding Custom Checks

To add custom quality checks:

1. **Add a new step** in the appropriate job
2. **Generate output** that can be parsed and displayed
3. **Update the summary** to include your new check

Example:
```yaml
- name: Custom Quality Check
  run: |
    echo "Running custom check..."
    # Your custom check command
    echo "CUSTOM_CHECK_STATUS=✅ Passed" >> $GITHUB_ENV

- name: Update Summary
  run: |
    echo "| Custom Check | $CUSTOM_CHECK_STATUS |" >> $GITHUB_STEP_SUMMARY
```

## 📈 Best Practices

### For Developers

1. **Run locally before pushing**:
   ```bash
   cd mobile
   dart format lib test
   flutter analyze lib
   flutter test --coverage
   ```

2. **Fix formatting issues**:
   ```bash
   dart format lib test
   ```

3. **Address analysis warnings**:
   ```bash
   flutter analyze lib
   ```

4. **Write comprehensive tests**:
   - Aim for >80% code coverage
   - Test edge cases
   - Use mock objects for dependencies

5. **Optimize performance**:
   - Use `const` constructors
   - Implement `shouldRepaint` in custom widgets
   - Dispose controllers and streams
   - Use appropriate image sizes

### For Maintainers

1. **Monitor workflow runs**: Regularly check the Actions tab for failures
2. **Review artifacts**: Download and review reports from failed runs
3. **Update dependencies**: Keep Flutter and Dart versions current
4. **Adjust thresholds**: Modify coverage requirements as needed
5. **Add more checks**: Enhance the workflow with additional quality tools

## 🛠️ Troubleshooting

### Common Issues

#### 1. Flutter Setup Fails
**Symptoms**: Flutter command not found
**Solution**: Check the Flutter version in the workflow matches your project's requirements

#### 2. Coverage Below Threshold
**Symptoms**: Workflow fails with coverage error
**Solution**: 
- Write more tests
- Increase the `min_coverage` threshold
- Exclude generated files from coverage

#### 3. Formatting Issues
**Symptoms**: Workflow fails on format check
**Solution**: Run `dart format lib test` locally and commit the changes

#### 4. Analysis Errors
**Symptoms**: Static analysis reports errors
**Solution**: Fix the reported issues or add appropriate ignore comments

#### 5. Test Failures
**Symptoms**: Unit tests fail
**Solution**: Fix the failing tests or investigate test environment issues

### Debugging Tips

1. **Check workflow logs**: Review the detailed logs in GitHub Actions
2. **Download artifacts**: Examine the uploaded reports for more details
3. **Run locally**: Reproduce the issue in your local environment
4. **Check dependencies**: Ensure all required tools are installed

## 📚 Additional Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Dart Analysis Options](https://dart.dev/guides/language/analysis-options)
- [Very Good Analysis](https://pub.dev/packages/very_good_analysis)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [jscpd Documentation](https://github.com/kucherenko/jscpd) — supports Dart
- [Lizard Complexity Analyzer](https://github.com/terryyin/lizard) — supports Dart
- [dart pub outdated](https://dart.dev/tools/pub/cmd/pub-outdated) — dependency audit
- [dart_code_metrics](https://pub.dev/packages/dart_code_metrics) — optional Dart-specific metrics (not currently in dev_dependencies)

## 🔄 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-08-02 | Initial release - Enhanced mobile quality gate workflow |
| 1.1.0 | 2026-08-03 | Removed Python-specific scanners (bandit, safety, radon) and dart-sass. Replaced with Dart-native security audit (`dart pub outdated` + dependency tree + known-vulnerable package scan). Removed Python setup step. Updated documentation to reflect the actual stack being scanned. |

## 📝 License

This workflow is provided as-is and is part of the Marina Hotel project. Feel free to use, modify, and distribute it according to your needs.

---

**Maintained by**: Marina Hotel Development Team  
**Last Updated**: 2026-08-02  
**Workflow File**: `.github/workflows/mobile-quality-gate.yml`