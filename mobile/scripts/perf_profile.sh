#!/usr/bin/env bash
# ============================================================================
#  Marina Hotel — Performance Profiling Script
#  ============================================================
#  يُشغِّل التطبيق في profile mode + يفتح DevTools + يُصدِّر تقرير JSON
#
#  الاستخدام:
#    ./scripts/perf_profile.sh                 # default (android)
#    ./scripts/perf_profile.sh android         # android فقط
#    ./scripts/perf_profile.sh web             # web (Chrome)
#    ./scripts/perf_profile.sh windows         # windows desktop
#    ./scripts/perf_profile.sh --no-devtools   # بدون فتح DevTools
#    ./scripts/perf_profile.sh --report        # يحفظ تقرير JSON بعد الإغلاق
#
#  المتطلبات:
#    - Flutter SDK مثبَّت في PATH
#    - Android emulator يعمل (لـ android) أو Chrome (لـ web)
# ============================================================================

set -e  # exit on error

# ═══════════════════════════════════════════════════════════════════════
#  إعداد
# ═══════════════════════════════════════════════════════════════════════
cd "$(dirname "$0")/.."

PLATFORM="${1:-android}"
OPEN_DEVTOOLS=true
SAVE_REPORT=false
REPORT_DIR="${REPORT_DIR:-build/performance}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="${REPORT_DIR}/perf_report_${TIMESTAMP}.json"

# parse args
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-devtools) OPEN_DEVTOOLS=false; shift ;;
    --report) SAVE_REPORT=true; shift ;;
    --report-dir=*) REPORT_DIR="${1#*=}"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ألوان للـ output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  🚀 Marina Hotel — Performance Profiling${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "  Platform:     ${YELLOW}${PLATFORM}${NC}"
  echo -e "  DevTools:     ${YELLOW}${OPEN_DEVTOOLS}${NC}"
  echo -e "  Save report:  ${YELLOW}${SAVE_REPORT}${NC}"
  if [ "${SAVE_REPORT}" = true ]; then
    echo -e "  Report file:  ${YELLOW}${REPORT_FILE}${NC}"
  fi
  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo ""
}

# ═══════════════════════════════════════════════════════════════════════
#  فحص المتطلبات
# ═══════════════════════════════════════════════════════════════════════
check_requirements() {
  echo -e "${BLUE}✓ فحص المتطلبات...${NC}"

  if ! command -v flutter &> /dev/null; then
    echo -e "${RED}✗ Flutter غير مثبَّت في PATH${NC}"
    exit 1
  fi

  FLUTTER_VERSION=$(flutter --version 2>&1 | head -1)
  echo -e "  ${GREEN}✓${NC} ${FLUTTER_VERSION}"

  # فحص Flutter analyze
  echo -e "${BLUE}✓ فحص flutter analyze...${NC}"
  if ! flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | tail -3; then
    echo -e "${YELLOW}⚠ يوجد issues — يُنصح بإصلاحها قبل الـ profiling${NC}"
  fi

  # فحص الأجهزة المتاحة
  echo -e "${BLUE}✓ فحص الأجهزة المتاحة...${NC}"
  case "${PLATFORM}" in
    android)
      if ! flutter devices 2>&1 | grep -q "android"; then
        echo -e "${RED}✗ لا يوجد جهاز Android متصل أو emulator يعمل${NC}"
        echo -e "${YELLOW}  شغِّل emulator: flutter emulators --launch <emulator_id>${NC}"
        echo -e "${YELLOW}  أو اعرض القائمة: flutter emulators${NC}"
        exit 1
      fi
      ;;
    web)
      if ! command -v google-chrome &> /dev/null && ! command -v chromium &> /dev/null; then
        echo -e "${YELLOW}⚠ Chrome/Chromium غير مثبَّت — قد يفشل flutter run -d web${NC}"
      fi
      ;;
  esac
  echo -e "  ${GREEN}✓ الجهاز متاح${NC}"
  echo ""
}

# ═══════════════════════════════════════════════════════════════════════
#  بناء الـ app في profile mode
# ═══════════════════════════════════════════════════════════════════════
build_app() {
  echo -e "${BLUE}✓ بناء التطبيق في profile mode...${NC}"
  echo -e "  ${YELLOW}قد يستغرق هذا 2-5 دقائق${NC}"

  # توليد drift/freezed files أولاً
  if [ -f "pubspec.yaml" ]; then
    echo -e "  ${BLUE}→ توليد build_runner files...${NC}"
    dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -5 || true
  fi

  echo -e "  ${GREEN}✓ build_runner اكتمل${NC}"
}

# ═══════════════════════════════════════════════════════════════════════
#  تشغيل Flutter profile mode + DevTools
# ═══════════════════════════════════════════════════════════════════════
run_profile() {
  echo -e "${BLUE}✓ تشغيل التطبيق في profile mode...${NC}"
  echo -e "  ${YELLOW}اضغط 'q' للإغلاق وحفظ التقرير${NC}"
  echo ""

  # إنشاء مجلد التقارير
  mkdir -p "${REPORT_DIR}"

  # تشغيل flutter run --profile مع DevTools
  local DEVTOOLS_FLAG=""
  if [ "${OPEN_DEVTOOLS}" = true ]; then
    DEVTOOLS_FLAG="--devtools"
    echo -e "${CYAN}  DevTools URL سيظهر بعد بدء التشغيل${NC}"
    echo -e "${CYAN}  افتح Performance tab لرؤية FPS/timeline${NC}"
    echo ""
  fi

  # تشغيل flutter run --profile
  # --verbose يعطي معلومات أداء إضافية
  # --trace-startup يحفظ timeline عند البدء
  flutter run --profile \
    --verbose \
    --trace-startup \
    ${DEVTOOLS_FLAG} \
    -d "${PLATFORM}" \
    2>&1 | tee "${REPORT_DIR}/flutter_run_${TIMESTAMP}.log" || true

  # استخراج startup timeline
  local STARTUP_TRACE="${REPORT_DIR}/startup_timeline_${TIMESTAMP}.json"
  if [ -f "build/start_up_info.json" ]; then
    cp "build/start_up_info.json" "${STARTUP_TRACE}"
    echo -e "${GREEN}✓ Startup timeline saved: ${STARTUP_TRACE}${NC}"
  fi
}

# ═══════════════════════════════════════════════════════════════════════
#  حفظ تقرير الأداء من logs
# ═══════════════════════════════════════════════════════════════════════
save_report() {
  if [ "${SAVE_REPORT}" = false ]; then
    return
  fi

  echo ""
  echo -e "${BLUE}✓ حفظ تقرير الأداء...${NC}"

  local LOG="${REPORT_DIR}/flutter_run_${TIMESTAMP}.log"
  local METRICS_FILE="${REPORT_DIR}/metrics_${TIMESTAMP}.json"

  # استخراج المقاييس من flutter run log
  python3 - "${LOG}" "${METRICS_FILE}" "${TIMESTAMP}" << 'PYTHON_SCRIPT' || true
import json
import re
import sys
import os
from datetime import datetime

log_path = sys.argv[1]
metrics_path = sys.argv[2]
timestamp = sys.argv[3]

try:
    with open(log_path, 'r', encoding='utf-8', errors='replace') as f:
        log_content = f.read()
except FileNotFoundError:
    print(f"Log file not found: {log_path}")
    sys.exit(1)

# استخراج مقاييس من الـ log
metrics = {
    'timestamp': timestamp,
    'generated_at': datetime.now().isoformat(),
    'platform': os.uname().sysname if hasattr(os, 'uname') else 'unknown',
    'extracted_metrics': {},
    'warnings': [],
}

# FPS references
fps_mentions = re.findall(r'FPS[:\s]+(\d+(?:\.\d+)?)', log_content)
if fps_mentions:
    metrics['extracted_metrics']['fps_samples'] = [float(f) for f in fps_mentions]
    metrics['extracted_metrics']['fps_avg'] = sum(float(f) for f in fps_mentions) / len(fps_mentions)

# Memory mentions (KB/MB)
mem_mentions = re.findall(r'(\d+(?:\.\d+)?)\s*(KB|MB)\s*(?:RSS|resident|memory)', log_content, re.IGNORECASE)
if mem_mentions:
    metrics['extracted_metrics']['memory_samples'] = [
        {'value': float(v), 'unit': u} for v, u in mem_mentions
    ]

# Frame timing
frame_mentions = re.findall(r'frame[^\d]*(\d+)\s*ms', log_content, re.IGNORECASE)
if frame_mentions:
    metrics['extracted_metrics']['frame_times_ms'] = [int(f) for f in frame_mentions[:50]]

# Startup time
startup_match = re.search(r'startup[^\d]*(\d+(?:\.\d+)?)\s*(ms|s)', log_content, re.IGNORECASE)
if startup_match:
    metrics['extracted_metrics']['startup_time'] = {
        'value': float(startup_match.group(1)),
        'unit': startup_match.group(2),
    }

# Errors/warnings من الـ log
errors = re.findall(r'(?:Error|Exception|FATAL)[^\n]{0,200}', log_content)
metrics['warnings'] = errors[:10]

# كشف jank
jank_count = len(re.findall(r'jank|skipped frame|dropped frame', log_content, re.IGNORECASE))
metrics['extracted_metrics']['jank_mentions'] = jank_count

# حفظ الـ metrics
with open(metrics_path, 'w', encoding='utf-8') as f:
    json.dump(metrics, f, indent=2, ensure_ascii=False)

print(f"✓ Metrics saved to: {metrics_path}")
print(f"  FPS samples: {len(metrics['extracted_metrics'].get('fps_samples', []))}")
print(f"  Frame times: {len(metrics['extracted_metrics'].get('frame_times_ms', []))}")
print(f"  Jank mentions: {jank_count}")
print(f"  Errors found: {len(metrics['warnings'])}")
PYTHON_SCRIPT

  echo -e "${GREEN}✓ تقرير الأداء حفظ في: ${REPORT_DIR}/${NC}"
  echo ""
  echo -e "${CYAN}ملفات التقرير:${NC}"
  ls -lh "${REPORT_DIR}"/*"${TIMESTAMP}"* 2>/dev/null | while read -r line; do
    echo -e "  ${YELLOW}${line}${NC}"
  done
}

# ═══════════════════════════════════════════════════════════════════════
#  طباعة ملخص نهائي
# ═══════════════════════════════════════════════════════════════════════
print_summary() {
  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  🎯 ملخص جلسة الـ Profiling${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "  ${GREEN}✓${NC} تم تشغيل التطبيق في profile mode"
  if [ "${SAVE_REPORT}" = true ]; then
    echo -e "  ${GREEN}✓${NC} التقارير حُفظت في: ${YELLOW}${REPORT_DIR}/${NC}"
  fi
  echo ""
  echo -e "${YELLOW}الخطوات التالية:${NC}"
  echo -e "  1. راجع flutter_run log لاكتشاف بطء في build/raster"
  echo -e "  2. افتح startup_timeline.json لتحليل زمن البدء"
  echo -e "  3. شغِّل اختبارات الـ benchmark:"
  echo -e "     ${CYAN}flutter test test/performance/ --reporter expanded${NC}"
  echo -e "  4. أو شغِّل CI workflow:"
  echo -e "     ${CYAN}gh workflow run performance-benchmark.yml${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

# ═══════════════════════════════════════════════════════════════════════
#  تنفيذ
# ═══════════════════════════════════════════════════════════════════════
trap 'echo ""; echo -e "${YELLOW}تم الإيقاف بواسطة المستخدم${NC}"; save_report; print_summary; exit 0' INT TERM

print_header
check_requirements
build_app
run_profile
save_report
print_summary
