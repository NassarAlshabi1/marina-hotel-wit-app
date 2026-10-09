#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  Marina Hotel — سكربت إجراءات التنقل لاختبار الأداء على 1GB RAM
#  يُستدعى من android_low_ram_memory_test.sh لكل دورة:
#      android_low_ram_navigation_actions.sh <adb> <package> <cycle>
#
#  ✅ v2 (2026-09-25): إصلاح العيب القاتل الذي كشفته المراجعة:
#     «Login credentials missing → Navigation skipped → Dashboard لم
#     يُختبر». الدخول الآن يحدث فعلياً:
#       1. MARINA_TEST_USERNAME/MARINA_TEST_PASSWORD من GitHub Secrets
#          (MARINA_TEST_EMAIL/MARINA_TEST_PASSWORD) — لا يُخزَّن شيء
#          في المستودع.
#       2. رجوع آمن للحساب المحلي الثابت admin/admin (موجود في
#          AuthLocalStore ويعمل دون شبكة على أي تثبيت نظيف) —
#          فلا يعود التنقل يُتخطى أبداً.
#     بعدها تنقل حقيقي عبر القائمة الجانبية: لوحة التحكم → الحجوزات
#     (+ تفاصيل حجز إن وُجدت بيانات) → المدفوعات → المصروفات →
#     الغرف → التقارير.
#
#  هذا السكربت لا يفشل أبداً برمز خروج غير صفر — الفشل يُسجَّل
#  كأحداث في navigation_events.csv و navigation_actions.log، ويقرر
#  البوابة النهائية (android_perf_gate.py) نجاحها أو فشلها.
# ═══════════════════════════════════════════════════════════════════
# ⚠️ بلا set -e/-u عمداً: أي فشل adb عابر لا يجوز أن يقتل دورة
# القياس الأم (android_low_ram_memory_test.sh تحت set -e) —
# الأحداث المسجّلة تكفي للبوابة النهائية للحكم.
set -o pipefail

ADB_BIN="${1:?adb binary is required}"
PACKAGE="${2:?package name is required}"
CYCLE="${3:?cycle number is required}"
UI_XML="/sdcard/marina_low_ram_ui_${CYCLE}.xml"
LOG_FILE="${LOW_RAM_ACTION_LOG:-/tmp/marina_low_ram_navigation_actions.log}"
EVENTS_CSV="${LOW_RAM_NAV_EVENTS_CSV:-/tmp/marina_low_ram_navigation_events.csv}"

# بيانات الدخول: من Secrets إن مُرِّرت، وإلا الحساب المحلي الثابت.
MARINA_TEST_USERNAME="${MARINA_TEST_USERNAME:-admin}"
MARINA_TEST_PASSWORD="${MARINA_TEST_PASSWORD:-admin}"
CRED_MODE="${MARINA_TEST_CRED_MODE:-local-fallback}"
LOGIN_WAIT_SEC="${LOW_RAM_LOGIN_WAIT_SEC:-120}"
SETTLE_SEC="${LOW_RAM_ACTION_SETTLE_SEC:-2}"
SCREEN_SETTLE_SEC="${LOW_RAM_SCREEN_SETTLE_SEC:-3}"

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$EVENTS_CSV")"
if [[ ! -f "$EVENTS_CSV" ]]; then
  printf 'cycle,event,target,detail\n' > "$EVENTS_CSV"
fi

# ✅ لقطات تشخيصية: الـ dump الخام يُحفظ عند خطوات الدخول الحاسمة
# حتى يكشف الـ artifact القادم الشكل الفعلي لشجرة الوصولية.
DEBUG_DIR="${LOW_RAM_DEBUG_DIR:-$(dirname "$EVENTS_CSV")/ui_dumps}"
mkdir -p "$DEBUG_DIR"
DRAWER_FAIL_COUNT=0
save_debug_dump() {
  local name="$1" xml
  xml="$(dump_ui || true)"
  if [[ -n "$xml" ]]; then
    printf '%s' "$xml" > "$DEBUG_DIR/${name}.xml" 2>/dev/null || true
  fi
}

log() {
  printf 'cycle=%s event=%s\n' "$CYCLE" "$1" | tee -a "$LOG_FILE"
}

# حدث مُهيكل للبوابة النهائية: cycle,event,target,detail
event() {
  local ev="$1" target="${2:--}" detail="${3:--}"
  printf '%s,%s,%s,%s\n' "$CYCLE" "$ev" "$target" "$detail" >> "$EVENTS_CSV"
  printf 'cycle=%s event=%s target=%s detail=%s\n' \
    "$CYCLE" "$ev" "$target" "$detail" | tee -a "$LOG_FILE"
}

sleep_for_ui() {
  sleep "$SETTLE_SEC"
}

dump_ui() {
  "$ADB_BIN" shell uiautomator dump "$UI_XML" >/dev/null 2>&1 || return 1
  "$ADB_BIN" shell cat "$UI_XML" 2>/dev/null | tr -d '\r\n'
}

# استخراج حدود عنصر من الـ dump — بثلاث مستويات:
# 1) مطابقة حرفية text="X" — 2) مطابقة حرفية content-desc="X"
# 3) سلسلة جزئية داخل أي صفة — لأن Flutter يدمج عقد البطاقات في
# قيمة واحدة مثل "0&#10;مدفوعات اليوم" (القيمة + التسمية معاً)
# فتفشل المطابقة الحرفية وحدها (أثبتها الـ dump الحقيقي من CI).
extract_bounds() {
  local xml="$1" requested="$2" bounds
  bounds=$(printf '%s' "$xml" | grep -o "text=\"$requested\"[^>]*bounds=\"\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]\"" | sed -n '1p' | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]"/\1 \2 \3 \4/p')
  if [[ -z "$bounds" ]]; then
    bounds=$(printf '%s' "$xml" | grep -o "content-desc=\"$requested\"[^>]*bounds=\"\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]\"" | sed -n '1p' | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]"/\1 \2 \3 \4/p')
  fi
  if [[ -z "$bounds" ]]; then
    # سلسلة جزئية: التسمية داخل قيمة مدمجة (بطاقات لوحة التحكم)
    bounds=$(printf '%s' "$xml" | grep -o "[a-z-]*=\"[^\"]*$requested[^\"]*\"[^>]*bounds=\"\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]\"" | sed -n '1p' | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]"/\1 \2 \3 \4/p')
  fi
  printf '%s' "$bounds"
}

tap_xy() {
  local x="$1" y="$2"
  "$ADB_BIN" shell input tap "$x" "$y"
}

# النقر على عنصر نصي (ثلاث محاولات: الشاشة قد تكون مشغولة
# بالإطارات/لوحة المفاتيح فيفشل uiautomator dump مؤقتاً).
tap_text() {
  local requested="$1" xml bounds x1 y1 x2 y2 x y attempt
  for attempt in 1 2 3; do
    xml="$(dump_ui || true)"
    [[ -n "$xml" ]] || { sleep_for_ui; continue; }
    bounds="$(extract_bounds "$xml" "$requested")"
    if [[ -n "$bounds" ]]; then
      read -r x1 y1 x2 y2 <<< "$bounds"
      x=$(( (x1 + x2) / 2 ))
      y=$(( (y1 + y2) / 2 ))
      tap_xy "$x" "$y"
      log "tap:$requested"
      sleep_for_ui
      return 0
    fi
    sleep_for_ui
  done
  return 1
}

tap_text_quiet() {
  local requested="$1"
  local xml bounds x1 y1 x2 y2 x y
  xml="$(dump_ui || true)"
  [[ -n "$xml" ]] || return 1
  bounds="$(extract_bounds "$xml" "$requested")"
  [[ -n "$bounds" ]] || return 1
  read -r x1 y1 x2 y2 <<< "$bounds"
  x=$(( (x1 + x2) / 2 ))
  y=$(( (y1 + y2) / 2 ))
  tap_xy "$x" "$y"
  sleep_for_ui
  return 0
}

# ── حقول الإدخال ─────────────────────────────────────────────
# Flutter يُظهر حقول النص في شجرة الوصولية كـ android.widget.EditText.
# استخراج حدود الحقل رقم N (0=اسم المستخدم، 1=كلمة المرور).
find_edittext_bounds() {
  local index="$1" xml
  xml="$(dump_ui || true)"
  [[ -n "$xml" ]] || return 1
  printf '%s' "$xml" \
    | grep -o 'class="android.widget.EditText"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' \
    | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]"/\1 \2 \3 \4/p' \
    | sed -n "$((index + 1))p"
}

tap_edittext() {
  local index="$1" bounds x1 y1 x2 y2
  bounds="$(find_edittext_bounds "$index")"
  [[ -n "$bounds" ]] || return 1
  read -r x1 y1 x2 y2 <<< "$bounds"
  tap_xy "$(( (x1 + x2) / 2 ))" "$(( (y1 + y2) / 2 ))"
  sleep 1
  return 0
}

# adb shell input text لا يقبل كل الرموز: ننظّف ما يكسر الأمر.
# (إن احتوت بيانات Secret على رموز خاصة فستُحذف — يُسجَّل تحذير بدون
# تسريب القيمة نفسها.)
sanitize_for_input() {
  local value="$1"
  value="${value// /%s}"
  printf '%s' "$value" | tr -cd 'A-Za-z0-9@._%:-'
}

type_text() {
  local value="$1" sanitized
  sanitized="$(sanitize_for_input "$value")"
  if [[ "$sanitized" != "$value" ]]; then
    log 'login_input_sanitized:credentials_contain_special_chars'
  fi
  "$ADB_BIN" shell input text "$sanitized"
  sleep 1
}

# ── كشف الشاشات ──────────────────────────────────────────────
# ⚠️ بصمة متعددة العناصر: عناوين الشاشات في هذا التطبيق هي نفسها
# أسماء عناصر القائمة (شاشة الحجوزات عنوانها «إدارة الحجوزات»)
# فأي فحص بعنصر واحد يعطي false positive — مثله حدث فعلًا في
# الاختبار التكاملي. القائمة المفتوحة تعرض 6+ عناصر معاً، ولوحة
# التحكم تعرض بطاقاتها معاً؛ نطلب عدة علامات للتأكيد.
DRAWER_MARKERS=('لوحة التحكم' 'إدارة الغرف' 'إدارة الحجوزات' 'إدارة المدفوعات' 'الديون' 'إدارة المصروفات' 'الصندوق والمالية' 'تسجيل الخروج')
DASHBOARD_MARKERS=('مدفوعات اليوم' 'المصروفات' 'حالة الغرف')

is_drawer_open() {
  local ui count marker
  ui="$(dump_ui || true)"
  [[ -n "$ui" ]] || return 1
  count=0
  for marker in "${DRAWER_MARKERS[@]}"; do
    # مطابقة بالسلسلة الجزئية: Flutter يدمج العقد (القيمة+التسمية
    # في قيمة واحدة بـ &#10;) فالمطابقة الحرفية تفشل — وعتبة 3 علامات
    # متزامنة تمنع ال false positive (شاشة واحدة = عنوان واحد حداً).
    printf '%s' "$ui" | grep -q "$marker" && count=$((count + 1))
  done
  (( count >= 3 ))
}

is_login_screen() {
  local ui
  ui="$(dump_ui || true)"
  [[ -n "$ui" ]] || return 1
  # ⚠️ بدون «تسجيل الدخول» عمداً: شاشة onboarding الخاصة بـ Google
  # Drive تحمل نفس العبارة (اكتشفها الـ dump الحقيقي من CI — كل
  # الدورات كانت على شاشة GDrive وليس شاشة الدخول أصلاً).
  printf '%s' "$ui" | grep -q 'اسم المستخدم\|كلمة المرور\|text="دخول"\|content-desc="دخول"'
}

# شاشة onboarding الخاصة بتسجيل دخول Google Drive — تظهر قبل شاشة
# الدخول على أي تثبيت نظيف (root_router: !isAuthenticated &&
# requiresDriveLogin). زر «تخطي» يفتح حوار تأكيد بزر «المتابعة بدون
# مزامنة» ثم يستمر التخطي عبر SharedPreferences فلا يتكرر.
is_gdrive_prompt() {
  local ui
  ui="$(dump_ui || true)"
  [[ -n "$ui" ]] || return 1
  printf '%s' "$ui" | grep -q 'Google Drive' \
    && printf '%s' "$ui" | grep -q 'تخطي\|المتابعة بدون مزامنة'
}

gdrive_prompt_skip() {
  log 'gdrive_prompt_detected'
  if tap_text 'تخطي'; then
    sleep "$SCREEN_SETTLE_SEC"
    # حوار التأكيد — «المتابعة بدون مزامنة»
    if tap_text 'المتابعة بدون مزامنة'; then
      event 'gdrive_prompt_skipped' 'login' 'confirmed'
      sleep "$SCREEN_SETTLE_SEC"
      return 0
    fi
    # الحوار لم يظهر؟ قد يكون التخطي مباشراً
    if ! is_gdrive_prompt; then
      event 'gdrive_prompt_skipped' 'login' 'direct'
      sleep "$SCREEN_SETTLE_SEC"
      return 0
    fi
    event 'gdrive_skip_dialog_failed' 'login' '-'
    return 1
  fi
  event 'gdrive_skip_tap_failed' 'login' '-'
  return 1
}

is_dashboard_visible() {
  local ui count marker
  ui="$(dump_ui || true)"
  [[ -n "$ui" ]] || return 1
  count=0
  for marker in "${DASHBOARD_MARKERS[@]}"; do
    # سلسلة جزئية: البطاقات الحقيقية مدمجة مثل "0&#10;مدفوعات اليوم"
    printf '%s' "$ui" | grep -q "$marker" && count=$((count + 1))
  done
  (( count >= 2 ))
}

# ── تسجيل الدخول الحقيقي ─────────────────────────────────────
# الترتيب: نقر الحقول عبر EditText (ثم إحداثيات تقريبية كرجوع)،
# الكتابة، إغلاق لوحة المفاتيح (BACK فقط إن كانت مفتوحة فعلاً —
# BACK دون لوحة يُخرج التطبيق كله من الشاشة فيتعطل التنقل!)،
# ثم نقر زر «دخول» وانتظار لوحة التحكم حتى LOGIN_WAIT_SEC.
# كل خطوة تُوثَّق بلقطة dump تشخيصية تُرفع مع الـ artifact.
keyboard_open() {
  "$ADB_BIN" shell dumpsys input_method 2>/dev/null | tr -d '\r\n' | grep -q 'mInputShown=true'
}

process_alive() {
  "$ADB_BIN" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r' | grep -q '[0-9]'
}

attempt_login() {
  local kind="${1:-label}"
  log "login_attempt:mode=$CRED_MODE:fields=$kind"
  save_debug_dump "cycle${CYCLE}_login_initial"

  # 1) حقل اسم المستخدم
  if ! tap_edittext 0; then
    tap_text 'اسم المستخدم' \
      || tap_text 'أدخل اسم المستخدم' \
      || tap_xy 540 880
  fi
  type_text "$MARINA_TEST_USERNAME"

  # 2) حقل كلمة المرور (يُعاد dump لأن الحدود تتغير بفتح اللوحة)
  if ! tap_edittext 1; then
    tap_text 'كلمة المرور' \
      || tap_text 'أدخل كلمة المرور' \
      || tap_xy 540 985
  fi
  type_text "$MARINA_TEST_PASSWORD"

  # 3) إغلاق لوحة المفاتيح — فقط إن كانت مفتوحة فعلاً (dumpsys
  #    input_method). إرسال BACK دون لوحة مفتوحة على شاشة الدخول
  #    يُخرج التطبيق فيصبح كل ما بعده على شاشة النظام — وهو عطل
  #    حدث فعلاً في أول تشغيل حقيقي على CI.
  if keyboard_open; then
    log 'login_keyboard_closing'
    "$ADB_BIN" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
    sleep 2
  else
    log 'login_keyboard_not_open_after_typing'
  fi
  save_debug_dump "cycle${CYCLE}_login_before_submit"

  # 4) زر الدخول — بالنص/content-desc، ثم بإحداثية مشتقة من حدود
  #    حقل كلمة المرور نفسه (أدق من إحداثية ثابتة)، ثم ENTER.
  if ! tap_text 'دخول'; then
    local field_bounds x1 y1 x2 y2 btn_y
    field_bounds="$(find_edittext_bounds 1)"
    if [[ -n "$field_bounds" ]]; then
      read -r x1 y1 x2 y2 <<< "$field_bounds"
      btn_y=$(( y2 + 110 ))
      tap_xy 540 "$btn_y"
      log "login_button_tap_by_field_bounds:y=$btn_y"
    else
      tap_xy 540 1140
      log 'login_button_tap_fixed_fallback'
    fi
  fi
  log "login_submit:mode=$CRED_MODE"
  sleep 3

  # 4-ب) إن لم يُظهر زر الدخول أثراً — محاولة ENTER على الحقل الأخير
  if ! is_dashboard_visible && is_login_screen; then
    "$ADB_BIN" shell input keyevent KEYCODE_ENTER >/dev/null 2>&1 || true
    log 'login_enter_key_fallback'
    sleep 3
  fi

  # 5) انتظار لوحة التحكم (بصمة متعددة العناصر) — مع كشف خروج
  #    التطبيق/انهياره مبكراً بدل إهدار كامل المهلة.
  local deadline=$(( $(date +%s) + LOGIN_WAIT_SEC ))
  while (( $(date +%s) < deadline )); do
    if is_dashboard_visible; then
      event 'login_success' 'login' "mode=$CRED_MODE"
      return 0
    fi
    local ui
    ui="$(dump_ui || true)"
    if [[ -n "$ui" ]] && printf '%s' "$ui" | grep -q 'غير صحيحة'; then
      event 'login_failed' 'login' "reason=invalid_credentials mode=$CRED_MODE"
      log 'login_failed:invalid_credentials'
      return 0
    fi
    if ! process_alive; then
      save_debug_dump "cycle${CYCLE}_login_app_died"
      event 'login_timeout' 'login' "reason=process_gone_early mode=$CRED_MODE"
      log 'login_process_gone'
      return 0
    fi
    sleep 3
  done
  save_debug_dump "cycle${CYCLE}_login_timeout_final"
  event 'login_timeout' 'login' "mode=$CRED_MODE waited_sec=$LOGIN_WAIT_SEC"
  log "login_timeout:${LOGIN_WAIT_SEC}s"
  return 0
}

# ── القائمة الجانبية (Drawer) ────────────────────────────────
# التطبيق RTL: القائمة تُفتح من الحافة اليمنى أو من زر الهامبرغر
# (tooltip مُترجم عربياً: «افتح قائمة التنقل»).
# ⚠️ التحقق بالإصبع المتعدد (is_drawer_open): عنوان أي شاشة قسم
# يطابق اسم عنصر قائمة — فحص عنصر واحد = false positive.
open_drawer() {
  if is_drawer_open; then
    return 0
  fi
  tap_text_quiet 'افتح قائمة التنقل' || true
  is_drawer_open && return 0
  # سحب من الحافة اليمنى (RTL) ثم من اليسى كرجوع
  "$ADB_BIN" shell input swipe 1060 960 400 960 250
  sleep_for_ui
  is_drawer_open && return 0
  "$ADB_BIN" shell input swipe 20 960 700 960 250
  sleep_for_ui
  is_drawer_open
}

# فتح القائمة والنقر على عنصر (مع تمرير القائمة إن كان العنصر أسفل
# الشاشة، ثم إعادة التمرير للأعلى).
drawer_tap() {
  local label="$1"
  # محاولة ثم تحقق — لا العكس: حتى لو أخفق تحقق فتح القائمة قد
  # تكون مفتوحة فعلاً (فحص العلامات هش تجاه دمج عقد Flutter).
  open_drawer || true
  if tap_text "$label"; then return 0; fi
  "$ADB_BIN" shell input swipe 540 1500 540 700 300
  sleep_for_ui
  if tap_text "$label"; then return 0; fi
  "$ADB_BIN" shell input swipe 540 700 540 1500 300
  sleep_for_ui
  event 'not_found' "$label" 'drawer'
  # لقطة تشخيصية للفشل — تكشف الشاشة الفعلية في الـ artifact
  DRAWER_FAIL_COUNT=$(( DRAWER_FAIL_COUNT + 1 ))
  save_debug_dump "cycle${CYCLE}_drawer_fail_${DRAWER_FAIL_COUNT}"
  # إغلاق القائمة إن كانت ما تزال مفتوحة — BACK على قائمة مفتوحة
  # يغلقها فقط؛ أما إرساله على شاشة قسم فقد يُخرج التطبيق.
  if is_drawer_open; then
    "$ADB_BIN" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
    sleep_for_ui
  fi
  return 1
}

navigate_target() {
  local name="$1" label="$2"
  if drawer_tap "$label"; then
    event 'target' "$name" 'visited'
    sleep "$SCREEN_SETTLE_SEC"
    # تمريرة واقعية: تحميل عرض القوائم (حمل رسم حقيقي على الـ renderer)
    "$ADB_BIN" shell input swipe 540 1600 540 500 400 >/dev/null 2>&1 || true
    sleep 1
    "$ADB_BIN" shell input swipe 540 500 540 1600 400 >/dev/null 2>&1 || true
    sleep 1
    return 0
  fi
  event 'target' "$name" 'not_found'
  return 0
}

goto_dashboard() {
  drawer_tap 'لوحة التحكم' || true
  sleep_for_ui
}

# ✅ المُنقذ العام من أي حالة عالقة: إطلاق النشاط بتكبير مهمة
# جديدة يعيد الجلسة المحفوظة (rememberMe) إلى لوحة التحكم من أي
# شاشة — بما فيها شاشات push التي لا تحمل AppBar القائمة
# (تفاصيل الحجز مثلاً: زر القائمة/حافتها غير موجودين عليها أصلاً).
restore_app_state() {
  "$ADB_BIN" shell am start -W -n "$PACKAGE/.MainActivity" \
    -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
    -f 0x10008000 >/dev/null 2>&1 || true
  sleep "$SCREEN_SETTLE_SEC"
  if is_dashboard_visible; then
    event 'app_state_restored' 'navigation' 'relaunch'
    return 0
  fi
  return 1
}

# ضمان العودة للوحة التحكم: قائمة → إعادة إطلاق
ensure_dashboard() {
  is_dashboard_visible && return 0
  goto_dashboard
  is_dashboard_visible && return 0
  restore_app_state || true
  is_dashboard_visible
}

# تفاصيل الحجز — best-effort: نقر أول عنصر في قائمة الحجوزات
# (إحداثية إرشادية) والتحقق من تغيّر الواجهة. تثبيت نظيف = لا
# حجوزات محلياً؛ مع حساب سحابي (Secrets) وبيانات فعلية يفتح
# التفاصيل فعلاً. تُسجَّل الحقيقة كما هي.
attempt_booking_details() {
  local before after
  before="$(dump_ui || true)"
  tap_xy 540 520
  sleep "$SCREEN_SETTLE_SEC"
  after="$(dump_ui || true)"
  if [[ -n "$before" && -n "$after" && "$before" != "$after" ]]; then
    event 'target' 'booking_details' 'visited:coordinate_heuristic'
    sleep "$SCREEN_SETTLE_SEC"
    # BACK واحد فقط — قد يستهلكه حقل نص مركز (بلا IME مع لوحة
    # أصلية) فلا يغلق الشاشة؛ لذا يليه ensure_dashboard فوراً
    "$ADB_BIN" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
    sleep_for_ui
    # شاشة التفاصيل شاشة push بلا AppBar للقائمة — لا يمكن فتح
    # القائمة منها؛ المُنقذ: إعادة الإطلاق عبر ensure_dashboard
    ensure_dashboard || event 'state_stuck_after_booking_details' 'navigation' '-'
  else
    event 'target' 'booking_details' 'not_found:no_data_or_list_empty'
  fi
}

# ═══════════════════ التنفيذ لكل دورة ═══════════════════
log "cycle_start:credentials_mode=$CRED_MODE"

# 1) تخطي شاشة onboarding الخاصة بـ Google Drive ثم الدخول/استعادة الجلسة
if is_gdrive_prompt; then
  if gdrive_prompt_skip; then
    log 'gdrive_prompt_handled'
  else
    event 'gdrive_prompt_blocking' 'login' 'skip_failed'
  fi
fi

if is_gdrive_prompt; then
  # الشاشة ما تزال تحجب الدخول — لا تُهدر مهلة الدخول (تُسجَّل
  # كفشل دخول عند البوابة النهائية مباشرة)
  event 'login_blocked' 'login' 'gdrive_prompt_still_visible'
elif is_login_screen; then
  log 'login_screen_detected'
  attempt_login 'auto'
else
  event 'session_restored' 'login' "mode=$CRED_MODE"
fi

# 2) لوحة التحكم
if is_dashboard_visible; then
  event 'target' 'dashboard' 'visited'
else
  event 'target' 'dashboard' 'not_found'
fi

# 3) بطاقات لوحة التحكم (تنقل push + BACK)
if tap_text 'مدفوعات اليوم'; then
  event 'target' 'payments_card' 'visited'
  sleep "$SCREEN_SETTLE_SEC"
  "$ADB_BIN" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
  sleep_for_ui
  is_dashboard_visible || goto_dashboard
else
  event 'not_found' 'مدفوعات اليوم' 'dashboard_card'
fi

if tap_text 'المصروفات'; then
  event 'target' 'expenses_card' 'visited'
  sleep "$SCREEN_SETTLE_SEC"
  "$ADB_BIN" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
  sleep_for_ui
  is_dashboard_visible || goto_dashboard
else
  event 'not_found' 'المصروفات' 'dashboard_card'
fi

# 4) أقسام القائمة الجانبية — المسار الأساسي للتغطية
navigate_target 'bookings' 'إدارة الحجوزات'
attempt_booking_details
navigate_target 'payments' 'إدارة المدفوعات'
navigate_target 'expenses' 'إدارة المصروفات'
navigate_target 'rooms' 'إدارة الغرف'
navigate_target 'reports' 'التقارير'

# 5) بطاقات الغرف (تفاصيل غرفة) — على لوحة التحكم
ensure_dashboard
for room in 101 102 103 104; do
  if tap_text "$room"; then
    event 'target' 'room_details' "visited:room_$room"
    sleep "$SCREEN_SETTLE_SEC"
    "$ADB_BIN" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
    sleep_for_ui
    ensure_dashboard
    break
  fi
done

# 6) العودة للوحة التحكم
ensure_dashboard
event 'navigation_cycle_complete' 'navigation' "mode=$CRED_MODE"

# مخرج مضمون: القياس الأم لا يُقتل أبداً بسبب التنقل.
exit 0
