# Marina Hotel Mobile - Makefile
# ===================================
# Build & Test Automation
# Maintainer: Marina Hotel Dev Team
# Last Updated: 2026-08-04
#
# Usage:
#   make help          - Show all available commands
#   make setup         - Install dependencies
#   make build         - Build production APK
#   make test          - Run all tests
#   make lint          - Check code quality
#   make clean         - Clean build artifacts
#   make run           - Run the app
#   make reports       - Generate all code quality reports

.PHONY: help setup build test lint clean run analyze format watch generate reports quality coverage security

# ============================================
# CONFIGURATION
# ============================================

# Flutter version
FLUTTER_VERSION := 3.35.7
FLUTTER_CHANNEL := stable

# Build types
BUILD_TYPE := release
TARGET_PLATFORM := android

# Test types
TEST_TYPES := unit widget integration

# ============================================
# COLORS FOR OUTPUT
# ============================================

GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
BLUE := \033[0;34m
PURPLE := \033[0;35m
NC := \033[0m

# ============================================
# HELP COMMAND
# ============================================

help: ## Show this help message
	@printf '%b\n' "${BLUE}============================================${NC}"
	@printf '%b\n' "${BLUE}  Marina Hotel Mobile - Build & Test Automation${NC}"
	@printf '%b\n' "${BLUE}============================================${NC}"
	@echo ""
	@echo "${BLUE}Available Commands:${NC}"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  ${GREEN}%-20s${NC} %s\n", $$1, $$2}'
	@echo ""
	@echo "${BLUE}Report Generation Commands:${NC}"
	@printf '%b\n' "  ${GREEN}reports${NC}          - Generate all code quality reports"
	@printf '%b\n' "  ${GREEN}quality-report${NC} - Generate quality reports only"
	@printf '%b\n' "  ${GREEN}test-report${NC}    - Generate test reports only"
	@printf '%b\n' "  ${GREEN}coverage-report${NC} - Generate coverage reports only"
	@printf '%b\n' "  ${GREEN}security-report${NC} - Generate security reports only"
	@printf '%b\n' "  ${GREEN}final-report${NC}   - Generate final comprehensive report"
	@echo ""
	@echo "${BLUE}Environment:${NC}"
	@echo "  Flutter Version: $(FLUTTER_VERSION)"
	@echo "  Flutter Channel: $(FLUTTER_CHANNEL)"
	@echo ""

# ============================================
# SETUP COMMAND
# ============================================

setup: ## Install all dependencies
	@printf '%b\n' "${YELLOW}Setting up Marina Hotel Mobile project...${NC}"
	flutter clean
	flutter pub get
	@printf '%b\n' "${GREEN}Dependencies installed successfully!${NC}"

# ============================================
# BUILD COMMANDS
# ============================================

build: build-apk build-appbundle ## Build production APK and AppBundle

build-apk: ## Build production APK (all architectures)
	@printf '%b\n' "${YELLOW}Building production APK...${NC}"
	flutter build apk \
		--$(BUILD_TYPE) \
		--split-per-abi \
		--no-tree-shake-icons \
		--obfuscate \
		--split-debug-info=./debug_symbols
	@printf '%b\n' "${GREEN}APK build complete!${NC}"
	@echo "  Output: build/app/outputs/flutter-apk/"

build-appbundle: ## Build production AppBundle (Google Play)
	@printf '%b\n' "${YELLOW}Building production AppBundle...${NC}"
	flutter build appbundle \
		--$(BUILD_TYPE) \
		--no-tree-shake-icons \
		--obfuscate \
		--split-debug-info=./debug_symbols
	@printf '%b\n' "${GREEN}AppBundle build complete!${NC}"
	@echo "  Output: build/app/outputs/bundle/release/"

build-debug: ## Build debug APK for testing
	@printf '%b\n' "${YELLOW}Building debug APK...${NC}"
	flutter build apk --debug
	@printf '%b\n' "${GREEN}Debug APK build complete!${NC}"

build-ios: ## Build iOS app (requires macOS)
	@printf '%b\n' "${YELLOW}Building iOS app...${NC}"
	flutter build ios --$(BUILD_TYPE)
	@printf '%b\n' "${GREEN}iOS build complete!${NC}"

build-web: ## Build web app
	@printf '%b\n' "${YELLOW}Building web app...${NC}"
	flutter build web --$(BUILD_TYPE)
	@printf '%b\n' "${GREEN}Web build complete!${NC}"

# ============================================
# TEST COMMANDS
# ============================================

test: test-all ## Run all tests (unit, widget, integration)

test-all: test-unit test-widget test-integration ## Run all tests

test-unit: ## Run unit tests
	@printf '%b\n' "${YELLOW}Running unit tests...${NC}"
	dart test test/unit/ --coverage --coverage-path=coverage/unit.lcov
	@printf '%b\n' "${GREEN}Unit tests complete!${NC}"

test-widget: ## Run widget tests
	@printf '%b\n' "${YELLOW}Running widget tests...${NC}"
	dart test test/widget/ --coverage --coverage-path=coverage/widget.lcov
	@printf '%b\n' "${GREEN}Widget tests complete!${NC}"

test-integration: ## Run integration tests
	@printf '%b\n' "${YELLOW}Running integration tests...${NC}"
	dart test integration_test/ --coverage --coverage-path=coverage/integration.lcov
	@printf '%b\n' "${GREEN}Integration tests complete!${NC}"

test-performance: ## Run performance tests
	@printf '%b\n' "${YELLOW}Running performance tests...${NC}"
	dart test test/performance/
	@printf '%b\n' "${GREEN}Performance tests complete!${NC}"

test-coverage: ## Generate code coverage report
	@printf '%b\n' "${YELLOW}Generating code coverage report...${NC}"
	@if [ ! -f "coverage/unit.lcov" ] && [ ! -f "coverage/widget.lcov" ] && [ ! -f "coverage/integration.lcov" ]; then \
		make test-all; \
	fi
	lcov --rc lcov_branch_coverage=1 -c -i -d . -o coverage/combined.lcov
	for file in coverage/*.lcov; do \
		if [ -f "$$file" ]; then \
			lcov --rc lcov_branch_coverage=1 -a "$$file" -o coverage/combined.lcov; \
		fi \
	done
	genhtml coverage/combined.lcov --output-directory coverage/html
	@printf '%b\n' "${GREEN}Coverage report generated!${NC}"
	@echo "  Open: coverage/html/index.html"

# ============================================
# CODE QUALITY COMMANDS
# ============================================

lint: analyze format ## Check code quality (analyze + format)

analyze: ## Run static analysis
	@printf '%b\n' "${YELLOW}Running static analysis...${NC}"
	dart analyze --fatal-infos --fatal-warnings .
	@printf '%b\n' "${GREEN}Static analysis complete!${NC}"

format: ## Format all Dart files
	@printf '%b\n' "${YELLOW}Formatting code...${NC}"
	dart format .
	@printf '%b\n' "${GREEN}Code formatting complete!${NC}"

quality: ## Full quality check (analyze + format)
	@printf '%b\n' "${YELLOW}Running full quality check...${NC}"
	make analyze && make format
	@printf '%b\n' "${GREEN}Quality check passed!${NC}"

# ============================================
# CODE GENERATION COMMANDS
# ============================================

generate: generate-all ## Generate all code (Freezed, JSON, Riverpod, etc.)

generate-all: ## Generate all code using build_runner
	@printf '%b\n' "${YELLOW}Generating code...${NC}"
	flutter pub run build_runner build --delete-conflicting-outputs
	@printf '%b\n' "${GREEN}Code generation complete!${NC}"

watch: ## Watch for changes and regenerate code
	@printf '%b\n' "${YELLOW}Watching for code changes...${NC}"
	flutter pub run build_runner watch

clean-generated: ## Clean generated files
	@printf '%b\n' "${YELLOW}Cleaning generated files...${NC}"
	flutter pub run build_runner clean
	@printf '%b\n' "${GREEN}Generated files cleaned!${NC}"

# ============================================
# CLEAN COMMANDS
# ============================================

clean: ## Clean all build artifacts
	@printf '%b\n' "${YELLOW}Cleaning build artifacts...${NC}"
	flutter clean
	rm -rf build/
	rm -rf .dart_tool/
	rm -rf generated/
	rm -rf coverage/
	rm -rf debug_symbols/
	@printf '%b\n' "${GREEN}Clean complete!${NC}"

clean-test: ## Clean test artifacts
	@printf '%b\n' "${YELLOW}Cleaning test artifacts...${NC}"
	rm -rf coverage/
	rm -rf test_results_*.txt
	rm -rf performance_report.json
	@printf '%b\n' "${GREEN}Test artifacts cleaned!${NC}"

clean-reports: ## Clean all reports
	@printf '%b\n' "${YELLOW}Cleaning all reports...${NC}"
	rm -rf reports/
	rm -rf coverage/
	rm -rf test_results/
	rm -rf security_reports/
	rm -rf quality_reports/
	@printf '%b\n' "${GREEN}All reports cleaned!${NC}"

# ============================================
# RUN COMMANDS
# ============================================

run: ## Run the app on default device
	@printf '%b\n' "${YELLOW}Running app...${NC}"
	flutter run

run-android: ## Run the app on Android
	@printf '%b\n' "${YELLOW}Running app on Android...${NC}"
	flutter run -d android

run-ios: ## Run the app on iOS
	@printf '%b\n' "${YELLOW}Running app on iOS...${NC}"
	flutter run -d ios

run-web: ## Run the app on Web
	@printf '%b\n' "${YELLOW}Running app on Web...${NC}"
	flutter run -d chrome

run-release: ## Run the app in release mode
	@printf '%b\n' "${YELLOW}Running app in release mode...${NC}"
	flutter run --release

# ============================================
# REPORT GENERATION COMMANDS
# ============================================

reports: reports-all ## Generate all code quality reports

reports-all: quality-report test-report coverage-report security-report final-report ## Generate all reports

quality-report: ## Generate quality reports (analysis, lint, format, complexity)
	@printf '%b\n' "${YELLOW}Generating quality reports...${NC}"
	./scripts/generate_reports.sh quality
	@printf '%b\n' "${GREEN}Quality reports generated!${NC}"

 test-report: ## Generate test reports
	@printf '%b\n' "${YELLOW}Generating test reports...${NC}"
	./scripts/generate_reports.sh test
	@printf '%b\n' "${GREEN}Test reports generated!${NC}"

coverage-report: ## Generate coverage reports
	@printf '%b\n' "${YELLOW}Generating coverage reports...${NC}"
	./scripts/generate_reports.sh coverage
	@printf '%b\n' "${GREEN}Coverage reports generated!${NC}"

security-report: ## Generate security reports
	@printf '%b\n' "${YELLOW}Generating security reports...${NC}"
	./scripts/generate_reports.sh security
	@printf '%b\n' "${GREEN}Security reports generated!${NC}"

final-report: ## Generate final comprehensive report
	@printf '%b\n' "${YELLOW}Generating final comprehensive report...${NC}"
	./scripts/generate_reports.sh all
	@printf '%b\n' "${GREEN}Final report generated!${NC}"

# ============================================
# DEPLOY COMMANDS
# ============================================

deploy-firebase: ## Deploy to Firebase App Distribution
	@printf '%b\n' "${YELLOW}Deploying to Firebase App Distribution...${NC}"
	@if [ -z "$$FIREBASE_APP_ID" ] || [ -z "$$FIREBASE_TOKEN" ]; then \
		@printf '%b\n' "${RED}Error: FIREBASE_APP_ID and FIREBASE_TOKEN must be set!${NC}"; \
		@echo "  Export them first: export FIREBASE_APP_ID=your_app_id"; \
		@echo "  Export them first: export FIREBASE_TOKEN=your_token"; \
		exit 1; \
	fi
	make build-apk
	flutter firebase deploy \
		--app-id=$$FIREBASE_APP_ID \
		--token=$$FIREBASE_TOKEN \
		--platform=android \
		--file=build/app/outputs/flutter-apk/app-release.apk \
		--groups=testers \
		--release-notes="Automated build from $$(git rev-parse --short HEAD)"
	@printf '%b\n' "${GREEN}Deployed to Firebase App Distribution!${NC}"

# ============================================
# SECURITY COMMANDS
# ============================================

security-scan: ## Scan for secrets and security issues
	@printf '%b\n' "${YELLOW}Scanning for security issues...${NC}"
	@if [ -f ".gitleaks.toml" ]; then \
		gitleaks detect --source . --config .gitleaks.toml --verbose; \
	else \
		gitleaks detect --source . --verbose; \
	fi
	@printf '%b\n' "${GREEN}Security scan complete!${NC}"

# ============================================
# DOCUMENTATION COMMANDS
# ============================================

docs: ## Generate documentation
	@printf '%b\n' "${YELLOW}Generating documentation...${NC}"
	dartdoc --input lib/ --output docs/api/
	@printf '%b\n' "${GREEN}Documentation generated!${NC}"

# ============================================
# UTILITY COMMANDS
# ============================================

upgrade: ## Upgrade Flutter and dependencies
	@printf '%b\n' "${YELLOW}Upgrading Flutter and dependencies...${NC}"
	flutter upgrade
	flutter pub upgrade --major-versions
	@printf '%b\n' "${GREEN}Upgrade complete!${NC}"

check-updates: ## Check for dependency updates
	@printf '%b\n' "${YELLOW}Checking for dependency updates...${NC}"
	flutter pub outdated
	@printf '%b\n' "${GREEN}Dependency check complete!${NC}"

# ============================================
# CI/CD COMMANDS
# ============================================

ci: ci-setup ci-test ci-build ## Run full CI pipeline locally

ci-setup: ## CI setup (dependencies)
	make setup

ci-test: ## CI test (all tests)
	make test-all
	make analyze

ci-build: ## CI build (production)
	make build-apk
	make build-appbundle

# ============================================
# PRODUCTION COMMANDS
# ============================================

production: production-build production-test production-deploy ## Full production pipeline

production-build: ## Production build (APK + AppBundle)
	make clean
	make setup
	make generate-all
	make quality
	make build-apk
	make build-appbundle

production-test: ## Production testing
	make test-all
	make test-coverage
	make security-scan

production-deploy: ## Production deployment
	@printf '%b\n' "${YELLOW}Production deployment...${NC}"
	@echo "${RED}This command requires manual confirmation for production deployment${NC}"
	@echo "  Run: make deploy-firebase"

# ============================================
# DEBUG COMMANDS
# ============================================

debug: debug-run debug-profile debug-build ## Debug commands

debug-run: ## Run in debug mode with hot reload
	flutter run --debug

debug-profile: ## Run in profile mode for performance testing
	flutter run --profile

debug-build: ## Build in debug mode
	flutter build apk --debug

# ============================================
# PERFORMANCE COMMANDS
# ============================================

performance: performance-test performance-report ## Performance analysis

performance-test: ## Run performance tests
	make test-performance

performance-report: ## Generate performance report
	@printf '%b\n' "${YELLOW}Generating performance report...${NC}"
	@if [ -f "performance_report.txt" ]; then \
		cat performance_report.txt; \
	else \
		make test-performance; \
		cat performance_report.txt; \
	fi
	@printf '%b\n' "${GREEN}Performance report generated!${NC}"

# ============================================
# FINAL TARGETS
# ============================================

all: setup generate-all quality test-all build

.default: help
