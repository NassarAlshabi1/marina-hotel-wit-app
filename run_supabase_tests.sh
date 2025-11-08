#!/bin/bash

# ============================================================================
# Marina Hotel - Supabase Test Runner
# سكريبت تشغيل اختبارات Supabase
# Script to run Supabase sync tests
# ============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

print_header "التحقق من المتطلبات | Checking Prerequisites"

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    print_error "Flutter غير مثبت | Flutter is not installed"
    print_info "تثبيت Flutter من | Install Flutter from: https://flutter.dev/docs/get-started/install"
    exit 1
else
    print_success "Flutter مثبت | Flutter is installed"
    flutter --version | head -n 1
fi

# Check if we're in the right directory
if [ ! -f "test/supabase_sync_test.dart" ]; then
    print_error "يجب تشغيل هذا السكريبت من جذر المشروع"
    print_error "This script must be run from the project root"
    exit 1
fi

# Check if mobile directory exists
if [ ! -d "mobile" ]; then
    print_error "مجلد mobile غير موجود | mobile directory not found"
    exit 1
fi

print_success "الدليل صحيح | Directory is correct"

# ============================================================================
# Check Configuration
# ============================================================================

print_header "التحقق من الإعدادات | Checking Configuration"

# Check if supabase_config.dart has been updated
if grep -q "YOUR_SUPABASE_URL" mobile/lib/utils/supabase_config.dart; then
    print_warning "يجب تحديث supabase_config.dart بـ credentials الحقيقية"
    print_warning "Please update supabase_config.dart with real credentials"
    print_info "راجع SUPABASE_SETUP_GUIDE.md للتفاصيل"
    read -p "هل تريد المتابعة؟ (y/n) Continue anyway? " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    print_success "تم تكوين supabase_config.dart | supabase_config.dart is configured"
fi

# Check if test config has been updated
if grep -q "YOUR_PROJECT_ID" test/supabase_sync_test.dart; then
    print_warning "يجب تحديث TestConfig في supabase_sync_test.dart"
    print_warning "Please update TestConfig in supabase_sync_test.dart"
    read -p "هل تريد المتابعة؟ (y/n) Continue anyway? " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    print_success "تم تكوين TestConfig | TestConfig is configured"
fi

# ============================================================================
# Install Dependencies
# ============================================================================

print_header "تثبيت المكتبات | Installing Dependencies"

cd mobile

# Check if pubspec.yaml contains supabase_flutter
if grep -q "supabase_flutter:" pubspec.yaml; then
    print_success "مكتبة supabase_flutter موجودة في pubspec.yaml"
    print_success "supabase_flutter is in pubspec.yaml"
else
    print_error "مكتبة supabase_flutter غير موجودة في pubspec.yaml"
    print_error "supabase_flutter is not in pubspec.yaml"
    exit 1
fi

print_info "تشغيل flutter pub get..."
flutter pub get

if [ $? -eq 0 ]; then
    print_success "تم تثبيت المكتبات بنجاح | Dependencies installed successfully"
else
    print_error "فشل تثبيت المكتبات | Failed to install dependencies"
    exit 1
fi

cd ..

# ============================================================================
# Run Tests
# ============================================================================

print_header "تشغيل الاختبارات | Running Tests"

# Parse command line arguments
TEST_NAME=""
VERBOSE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --name)
            TEST_NAME="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE="--verbose"
            shift
            ;;
        --help|-h)
            echo "الاستخدام | Usage: $0 [options]"
            echo ""
            echo "الخيارات | Options:"
            echo "  --name <test_name>   تشغيل اختبار محدد | Run specific test"
            echo "  --verbose, -v        إخراج مفصل | Verbose output"
            echo "  --help, -h           عرض هذه المساعدة | Show this help"
            echo ""
            echo "أمثلة | Examples:"
            echo "  $0"
            echo "  $0 --name 'Should push CREATE'"
            echo "  $0 --verbose"
            exit 0
            ;;
        *)
            print_error "خيار غير معروف | Unknown option: $1"
            echo "استخدم --help للمساعدة | Use --help for help"
            exit 1
            ;;
    esac
done

# Build test command
TEST_CMD="flutter test test/supabase_sync_test.dart"

if [ -n "$TEST_NAME" ]; then
    TEST_CMD="$TEST_CMD --name \"$TEST_NAME\""
    print_info "تشغيل اختبار: $TEST_NAME"
    print_info "Running test: $TEST_NAME"
fi

if [ -n "$VERBOSE" ]; then
    TEST_CMD="$TEST_CMD $VERBOSE"
fi

print_info "الأمر | Command: $TEST_CMD"
echo ""

# Run the tests
eval $TEST_CMD

# Check test results
if [ $? -eq 0 ]; then
    print_header "النتيجة | Result"
    print_success "جميع الاختبارات نجحت! 🎉"
    print_success "All tests passed! 🎉"
else
    print_header "النتيجة | Result"
    print_error "بعض الاختبارات فشلت ❌"
    print_error "Some tests failed ❌"
    print_info "راجع الأخطاء أعلاه | Check errors above"
    print_info "راجع SUPABASE_TEST_REPORT.md للمساعدة"
    print_info "Check SUPABASE_TEST_REPORT.md for help"
    exit 1
fi

# ============================================================================
# Summary
# ============================================================================

print_header "الملخص | Summary"

echo -e "${GREEN}✅ Flutter: مثبت | Installed${NC}"
echo -e "${GREEN}✅ Dependencies: مثبتة | Installed${NC}"
echo -e "${GREEN}✅ Configuration: محدثة | Updated${NC}"
echo -e "${GREEN}✅ Tests: نجحت | Passed${NC}"

echo ""
print_info "الخطوات التالية | Next Steps:"
echo "  1. راجع البيانات في Supabase Dashboard"
echo "     Check data in Supabase Dashboard"
echo "  2. دمج SupabaseSyncService في التطبيق"
echo "     Integrate SupabaseSyncService into the app"
echo "  3. اختبار على أجهزة حقيقية"
echo "     Test on real devices"

echo ""
print_success "تم الانتهاء بنجاح! | Completed successfully!"
