#!/bin/bash

# Marina Hotel Mobile - Production Build Script
# ==============================================
# F4DD Automated Production Build Script
# F4BB Maintainer: Marina Hotel Dev Team
# F4D1 Last Updated: 2026-08-03
#
# F4D1 Usage:
#   ./scripts/build_production.sh          # Full production build
#   ./scripts/build_production.sh apk      # Build APK only
#   ./scripts/build_production.sh appbundle # Build AppBundle only
#   ./scripts/build_production.sh clean    # Clean build artifacts

# ============================================
# CONFIGURATION
# ============================================

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Build configuration
BUILD_TYPE="release"
FLUTTER_VERSION="3.35.7"
FLUTTER_CHANNEL="stable"

# Directories
BUILD_DIR="build"
DEBUG_SYMBOLS_DIR="debug_symbols"
OUTPUT_APK_DIR="build/app/outputs/flutter-apk"
OUTPUT_BUNDLE_DIR="build/app/outputs/bundle/release"

# ============================================
# FUNCTIONS
# ============================================

# Print header
print_header() {
    echo ""
    echo "${BLUE}============================================${NC}"
    echo "${BLUE}  Marina Hotel Mobile - Production Build${NC}"
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

# Clean build artifacts
clean_build() {
    print_section "Cleaning Build Artifacts"
    
    # Remove build directory
    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
        print_success "Removed build directory"
    fi
    
    # Remove debug symbols
    if [ -d "$DEBUG_SYMBOLS_DIR" ]; then
        rm -rf "$DEBUG_SYMBOLS_DIR"
        print_success "Removed debug symbols directory"
    fi
    
    # Remove pub cache
    if [ -d ".pub-cache" ]; then
        rm -rf ".pub-cache"
        print_success "Removed pub cache"
    fi
    
    # Remove generated files
    if [ -d "generated" ]; then
        rm -rf "generated"
        print_success "Removed generated directory"
    fi
    
    # Run flutter clean
    print_info "Running flutter clean..."
    if flutter clean; then
        print_success "Flutter clean completed"
    else
        print_error "Flutter clean failed"
        return 1
    fi
    
    print_success "Build artifacts cleaned!"
}

# Install dependencies
install_dependencies() {
    print_section "Installing Dependencies"
    
    print_info "Running flutter pub get..."
    if flutter pub get; then
        print_success "Dependencies installed"
    else
        print_error "Failed to install dependencies"
        return 1
    fi
    
    # Check for outdated dependencies
    print_info "Checking for outdated dependencies..."
    flutter pub outdated 2>&1 | tee outdated_dependencies.txt
    
    if [ -s "outdated_dependencies.txt" ]; then
        print_error "Outdated dependencies found!"
        print_info "See outdated_dependencies.txt for details"
        print_info "Run 'flutter pub upgrade' to update dependencies"
    else
        print_success "All dependencies are up to date"
    fi
    
    return 0
}

# Generate code
generate_code() {
    print_section "Generating Code"
    
    print_info "Running build_runner..."
    if flutter pub run build_runner build --delete-conflicting-outputs; then
        print_success "Code generation completed"
    else
        print_error "Code generation failed"
        return 1
    fi
    
    return 0
}

# Run quality checks
run_quality_checks() {
    print_section "Running Quality Checks"
    
    local all_passed=true
    
    # Run static analysis
    print_info "Running static analysis..."
    if ! flutter analyze --fatal-infos --fatal-warnings .; then
        print_error "Static analysis failed"
        all_passed=false
    else
        print_success "Static analysis passed"
    fi
    
    # Check formatting
    print_info "Checking code formatting..."
    if ! flutter format --set-exit-if-changed .; then
        print_error "Code formatting check failed"
        all_passed=false
    else
        print_success "Code formatting check passed"
    fi
    
    # Run linter
    print_info "Running linter..."
    if ! flutter lint; then
        print_error "Linting failed"
        all_passed=false
    else
        print_success "Linting passed"
    fi
    
    if [ "$all_passed" = true ]; then
        print_success "All quality checks passed"
        return 0
    else
        print_error "Quality checks failed"
        return 1
    fi
}

# Build APK
build_apk() {
    print_section "Building Production APK"
    
    print_info "Building APK for all architectures..."
    
    if flutter build apk \
        --$BUILD_TYPE \
        --split-per-abi \
        --no-tree-shake-icons \
        --obfuscate \
        --split-debug-info=./$DEBUG_SYMBOLS_DIR; then
        
        print_success "APK build completed"
        
        # Rename APK files
        print_info "Renaming APK files..."
        
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local git_sha=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        
        if [ -f "$OUTPUT_APK_DIR/app-armeabi-v7a-release.apk" ]; then
            mv "$OUTPUT_APK_DIR/app-armeabi-v7a-release.apk" "$OUTPUT_APK_DIR/marina_hotel_armeabi-v7a_${git_sha}_${timestamp}.apk"
            print_success "Renamed armeabi-v7a APK"
        fi
        
        if [ -f "$OUTPUT_APK_DIR/app-arm64-v8a-release.apk" ]; then
            mv "$OUTPUT_APK_DIR/app-arm64-v8a-release.apk" "$OUTPUT_APK_DIR/marina_hotel_arm64-v8a_${git_sha}_${timestamp}.apk"
            print_success "Renamed arm64-v8a APK"
        fi
        
        if [ -f "$OUTPUT_APK_DIR/app-x86_64-release.apk" ]; then
            mv "$OUTPUT_APK_DIR/app-x86_64-release.apk" "$OUTPUT_APK_DIR/marina_hotel_x86_64_${git_sha}_${timestamp}.apk"
            print_success "Renamed x86_64 APK"
        fi
        
        # List APK files
        print_info "APK files generated:"
        ls -lh "$OUTPUT_APK_DIR"/*.apk 2>/dev/null || echo "No APK files found"
        
        return 0
    else
        print_error "APK build failed"
        return 1
    fi
}

# Build AppBundle
build_appbundle() {
    print_section "Building Production AppBundle"
    
    print_info "Building AppBundle for Google Play..."
    
    if flutter build appbundle \
        --$BUILD_TYPE \
        --no-tree-shake-icons \
        --obfuscate \
        --split-debug-info=./$DEBUG_SYMBOLS_DIR; then
        
        print_success "AppBundle build completed"
        
        # Rename AppBundle
        print_info "Renaming AppBundle..."
        
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local git_sha=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        
        if [ -f "$OUTPUT_BUNDLE_DIR/app-release.aab" ]; then
            mv "$OUTPUT_BUNDLE_DIR/app-release.aab" "$OUTPUT_BUNDLE_DIR/marina_hotel_${git_sha}_${timestamp}.aab"
            print_success "Renamed AppBundle"
        fi
        
        # List AppBundle files
        print_info "AppBundle files generated:"
        ls -lh "$OUTPUT_BUNDLE_DIR"/*.aab 2>/dev/null || echo "No AppBundle files found"
        
        return 0
    else
        print_error "AppBundle build failed"
        return 1
    fi
}

# Verify build
verify_build() {
    print_section "Verifying Build"
    
    local all_passed=true
    
    # Check APK files
    if [ "$1" = "apk" ] || [ "$1" = "all" ] || [ -z "$1" ]; then
        print_info "Checking APK files..."
        
        if [ -f "$OUTPUT_APK_DIR/app-armeabi-v7a-release.apk" ] || \
           [ -f "$OUTPUT_APK_DIR/marina_hotel_armeabi-v7a_*.apk" ]; then
            print_success "armeabi-v7a APK exists"
        else
            print_error "armeabi-v7a APK not found"
            all_passed=false
        fi
        
        if [ -f "$OUTPUT_APK_DIR/app-arm64-v8a-release.apk" ] || \
           [ -f "$OUTPUT_APK_DIR/marina_hotel_arm64-v8a_*.apk" ]; then
            print_success "arm64-v8a APK exists"
        else
            print_error "arm64-v8a APK not found"
            all_passed=false
        fi
        
        if [ -f "$OUTPUT_APK_DIR/app-x86_64-release.apk" ] || \
           [ -f "$OUTPUT_APK_DIR/marina_hotel_x86_64_*.apk" ]; then
            print_success "x86_64 APK exists"
        else
            print_error "x86_64 APK not found"
            all_passed=false
        fi
    fi
    
    # Check AppBundle
    if [ "$1" = "appbundle" ] || [ "$1" = "all" ] || [ -z "$1" ]; then
        print_info "Checking AppBundle..."
        
        if [ -f "$OUTPUT_BUNDLE_DIR/app-release.aab" ] || \
           [ -f "$OUTPUT_BUNDLE_DIR/marina_hotel_*.aab" ]; then
            print_success "AppBundle exists"
        else
            print_error "AppBundle not found"
            all_passed=false
        fi
    fi
    
    # Check debug symbols
    print_info "Checking debug symbols..."
    if [ -d "$DEBUG_SYMBOLS_DIR" ] && [ -n "$(ls -A "$DEBUG_SYMBOLS_DIR" 2>/dev/null)" ]; then
        print_success "Debug symbols generated"
    else
        print_error "Debug symbols not found"
        all_passed=false
    fi
    
    if [ "$all_passed" = true ]; then
        print_success "Build verification passed"
        return 0
    else
        print_error "Build verification failed"
        return 1
    fi
}

# Package build artifacts
package_artifacts() {
    print_section "Packaging Build Artifacts"
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local artifact_dir="build_artifacts_$timestamp"
    
    print_info "Creating artifact directory: $artifact_dir"
    mkdir -p "$artifact_dir"
    
    # Copy APKs
    if [ -d "$OUTPUT_APK_DIR" ]; then
        cp "$OUTPUT_APK_DIR"/*.apk "$artifact_dir/" 2>/dev/null || true
    fi
    
    # Copy AppBundle
    if [ -d "$OUTPUT_BUNDLE_DIR" ]; then
        cp "$OUTPUT_BUNDLE_DIR"/*.aab "$artifact_dir/" 2>/dev/null || true
    fi
    
    # Copy debug symbols
    if [ -d "$DEBUG_SYMBOLS_DIR" ]; then
        cp -r "$DEBUG_SYMBOLS_DIR" "$artifact_dir/"
    fi
    
    # Create zip archive
    print_info "Creating zip archive..."
    zip -r "$artifact_dir.zip" "$artifact_dir" 2>/dev/null || true
    
    print_success "Artifacts packaged: $artifact_dir.zip"
    
    # Clean up
    rm -rf "$artifact_dir"
}

# Full production build
full_production_build() {
    print_header
    
    local all_passed=true
    
    # Clean
    if ! clean_build; then
        all_passed=false
    fi
    
    # Install dependencies
    if ! install_dependencies; then
        all_passed=false
    fi
    
    # Generate code
    if ! generate_code; then
        all_passed=false
    fi
    
    # Run quality checks
    if ! run_quality_checks; then
        all_passed=false
    fi
    
    # Build APK
    if ! build_apk; then
        all_passed=false
    fi
    
    # Build AppBundle
    if ! build_appbundle; then
        all_passed=false
    fi
    
    # Verify build
    if ! verify_build "all"; then
        all_passed=false
    fi
    
    # Package artifacts
    if [ "$all_passed" = true ]; then
        package_artifacts
    fi
    
    # Summary
    print_section "Build Summary"
    
    if [ "$all_passed" = true ]; then
        print_success "Production build completed successfully! ✓"
        print_info ""
        print_info "Artifacts:"
        print_info "  - APKs: $OUTPUT_APK_DIR/"
        print_info "  - AppBundle: $OUTPUT_BUNDLE_DIR/"
        print_info "  - Debug Symbols: $DEBUG_SYMBOLS_DIR/"
        return 0
    else
        print_error "Production build failed! ✗"
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

# Check Flutter version
FLUTTER_CURRENT_VERSION=$(flutter --version | head -1 | awk '{print $2}')
print_info "Current Flutter version: $FLUTTER_CURRENT_VERSION"
print_info "Required Flutter version: $FLUTTER_VERSION"

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    print_error "pubspec.yaml not found!"
    print_info "Please run this script from the project root directory."
    exit 1
fi

# Parse command line arguments
case "$1" in
    "clean")
        clean_build
        ;;
    "apk")
        clean_build
        install_dependencies
        generate_code
        run_quality_checks
        build_apk
        verify_build "apk"
        ;;
    "appbundle")
        clean_build
        install_dependencies
        generate_code
        run_quality_checks
        build_appbundle
        verify_build "appbundle"
        ;;
    "verify")
        verify_build "all"
        ;;
    "all")
        full_production_build
        ;;
    "")
        full_production_build
        ;;
    *)
        print_error "Unknown command: $1"
        print_info "Available commands: all, apk, appbundle, clean, verify"
        exit 1
        ;;
esac

# Exit with appropriate status
exit $?
