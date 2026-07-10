#!/usr/bin/env node
/*
 * ════════════════════════════════════════════════════════════════════════════
 *  Marina Hotel — Unified Appwrite Setup   (سكربت Appwrite الموحّد)
 * ════════════════════════════════════════════════════════════════════════════
 *
 *  سكربت واحد يُهيّئ أي وجهة Appwrite (الأساسية Primary أو الثانوية Secondary)
 *  إلى **نفس** المخطط بالضبط: قاعدة البيانات + كل المجموعات + كل الحقول + الفهارس.
 *
 *  ▸ لماذا "موحّد"؟
 *    - مصدر حقيقة واحد للمخطط (SCHEMA أدناه) منقول حرفياً من
 *      `mobile/lib/services/appwrite_sync_utils.dart` → `collectionSchema`.
 *    - يعمل لكلا الوجهتين عبر متغيرات البيئة، فتضمن أن الثانوية مطابقة للأساسية
 *      حقلاً بحقل (وهو شرط نجاح المزامنة/النسخ الاحتياطي والـ failover).
 *    - Idempotent: يتخطّى ما هو موجود (409) — آمن لإعادة التشغيل مرّات عديدة.
 *
 *  ▸ الاستخدام:
 *
 *      # الوجهة الأساسية (القيم الافتراضية)
 *      APPWRITE_API_KEY=xxxxx node scripts/appwrite/unified_appwrite_setup.js
 *
 *      # الوجهة الثانوية (تمرير endpoint/project/db مختلفة)
 *      APPWRITE_ENDPOINT=https://sfo.cloud.appwrite.io/v1 \
 *      APPWRITE_PROJECT_ID=xxxxxxxxxxxx \
 *      APPWRITE_DATABASE_ID=hotel_db \
 *      APPWRITE_API_KEY=yyyyy \
 *      node scripts/appwrite/unified_appwrite_setup.js
 *
 *      # فحص فقط (بدون كتابة) — يقارن المخطط الفعلي بالمطلوب ويطبع النواقص
 *      APPWRITE_API_KEY=xxxxx node scripts/appwrite/unified_appwrite_setup.js --verify
 *
 *      # مجموعة واحدة فقط
 *      APPWRITE_API_KEY=xxxxx node scripts/appwrite/unified_appwrite_setup.js --only=bookings,payments
 *
 *      # ⚠️ حذف الحقول الزائدة غير الموجودة في SCHEMA (--prune)
 *      #   مهم لإزالة حقول مثل paymentLocalId و nightNumber من الثانوي
 *      #   التي تسبّب خطأ "Missing required attribute" عند المزامنة.
 *      APPWRITE_API_KEY=xxxxx node scripts/appwrite/unified_appwrite_setup.js --prune
 *
 *      # ⚠️ إصلاح أنواع الحقول الخاطئة (--fix-types)
 *      #   يحذف الحقل ذا النوع الخاطئ ويُنشئه بالمواصفات الصحيحة.
 *      #   مثال: createdAt = string في الثانوي → integer كما في SCHEMA.
 *      APPWRITE_API_KEY=xxxxx node scripts/appwrite/unified_appwrite_setup.js --fix-types
 *
 *      # دمج --prune + --fix-types لإصلاح شامل للثانوي
 *      APPWRITE_API_KEY=xxxxx node scripts/appwrite/unified_appwrite_setup.js --prune --fix-types
 *
 *  ▸ يتطلب مفتاح API بصلاحيات: databases.write / collections.write / attributes.write / indexes.write
 * ════════════════════════════════════════════════════════════════════════════
 */

'use strict';

const {
  Client,
  Databases,
  Permission,
  Role,
  IndexType,
} = require('node-appwrite');

// ─────────────────────────────────────────────────────────────────────────────
// 1) الإعدادات — كلها قابلة للتجاوز عبر البيئة (هذا ما يجعل السكربت "موحّداً")
// ─────────────────────────────────────────────────────────────────────────────
const ENDPOINT =
  process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = process.env.APPWRITE_PROJECT_ID || '690ff0da0025518570c1';
const DATABASE_ID = process.env.APPWRITE_DATABASE_ID || 'hotel_db';
const DATABASE_NAME = process.env.APPWRITE_DATABASE_NAME || 'Hotel DB';
const API_KEY = process.env.APPWRITE_API_KEY;

// أعلام سطر الأوامر
const ARGV = process.argv.slice(2);
const VERIFY_ONLY = ARGV.includes('--verify');
const PRUNE = ARGV.includes('--prune');        // حذف الحقول الزائدة غير الموجودة في SCHEMA
// إصلاح الأنواع: يحذف كل حقل نوعه الفعلي يختلف عن SCHEMA ويُعيد إنشاءه بالنوع
// الصحيح (Appwrite لا يسمح بتغيير نوع سمة في مكانها). ⚠️ عملية هدمية: تُفقد قيم
// ذلك العمود على السحابة وتُعاد من التخزين المحلي عند المزامنة التالية.
const FIX_TYPES = ARGV.includes('--fix-types'); // حذف الحقول ذات النوع الخاطئ وإعادة إنشائها
const MAKE_OPTIONAL = ARGV.includes('--make-optional'); // ✅ فقط حوّل required=true → required=false دون حذف الحقل أو بياناته
// ✅ تأكيد صريح لتفادي تشغيل --fix-types / --prune بالخطأ. عند غيابه، يُطبَع تحذير
// ويُنتظر 5 ثوانٍ مع عدّ تنازلي قبل البدء — يُلغى المستخدم بالـ Ctrl+C.
// تمرير --confirm أو -y يتخطّى الانتظار (مناسب للسكربتات الآلية / CI).
const CONFIRM = ARGV.includes('--confirm') || ARGV.includes('-y');
const ONLY_ARG = ARGV.find((a) => a.startsWith('--only='));
const ONLY = ONLY_ARG
  ? ONLY_ARG.replace('--only=', '').split(',').map((s) => s.trim()).filter(Boolean)
  : null;

// يُهيّأ داخل main() حتى يبقى require() لأغراض الاختبار/الفحص دون مفتاح API.
let databases = null;

function initClient() {
  if (!API_KEY) {
    console.error('❌ متغيّر البيئة APPWRITE_API_KEY مطلوب.');
    console.error('   مثال: APPWRITE_API_KEY=xxxx node scripts/appwrite/unified_appwrite_setup.js');
    process.exit(1);
  }
  const client = new Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);
  databases = new Databases(client);
}

// ─────────────────────────────────────────────────────────────────────────────
// 2) المخطط الموحّد — منقول حرفياً من collectionSchema (appwrite_sync_utils.dart)
//    الأنواع: 'string' | 'integer' | 'double' | 'boolean'
//    ⚠️ هذا هو المصدر الوحيد للحقيقة. عند تعديل collectionSchema في التطبيق،
//       يجب مزامنة هذا الكائن (شغّل --verify للكشف عن الفروق).
// ─────────────────────────────────────────────────────────────────────────────

// حقول المزامنة المشتركة (SyncFields) — موجودة في كل المجموعات المتزامنة.
const SYNC = {
  localUuid: 'string',
  serverId: 'integer',
  createdAt: 'integer',
  updatedAt: 'integer',
  deletedAt: 'integer',
  lastModified: 'integer',
  createdAtIso: 'string',
  updatedAtIso: 'string',
  deletedAtIso: 'string',
  createdAtEpoch: 'integer',
  lastModifiedEpoch: 'integer',
  version: 'integer',
  origin: 'string',
  vectorClock: 'string',
  deviceId: 'string',
  idempotencyKey: 'string',
  syncTimestamp: 'integer',
  sync_origin: 'string',
};

// دمج مساعد: حقول المزامنة + الحقول الخاصة بالكيان (الخاصة تتغلّب عند التعارض).
const withSync = (business) => ({ ...SYNC, ...business });

const SCHEMA = {
  rooms: withSync({
    roomNumber: 'string',
    type: 'string',
    price: 'double',
    status: 'string',
    imageUrl: 'string',
    cleaningStatus: 'string',
    lastCleanedHotelDay: 'string',
    lastOccupiedHotelDay: 'string',
    requiresMaintenance: 'boolean',
  }),

  bookings: withSync({
    serverBookingId: 'integer',
    roomNumber: 'string',
    guestName: 'string',
    guestPhone: 'string',
    guestIdType: 'string',
    guestIdNumber: 'string',
    guestIdIssueDate: 'string',
    guestIdIssuePlace: 'string',
    guestNationality: 'string',
    guestEmail: 'string',
    guestAddress: 'string',
    checkinDate: 'string',
    checkoutDate: 'string',
    actualCheckout: 'string',
    status: 'string',
    notes: 'string',
    expectedNights: 'integer',
    calculatedNights: 'integer',
    totalNightsCached: 'integer',
    stayDurationIso: 'string',
    lastNightEpoch: 'integer',
    isOverdue: 'boolean',
    needsCheckoutReview: 'boolean',
    totalDueCached: 'double',
    totalPaidCached: 'double',
    remainingBalanceCached: 'double',
    isFullyPaid: 'boolean',
    discount: 'double',
    amount: 'double',
    discountType: 'string',
    discountStartDate: 'string',
    hotelDayCheckin: 'string',
    hotelDayCheckout: 'string',
    financialFrozenAt: 'integer',
    financialHash: 'string',
  }),

  payments: withSync({
    serverPaymentId: 'integer',
    bookingLocalId: 'integer',
    serverBookingId: 'integer',
    roomNumber: 'string',
    amount: 'double',
    paymentDate: 'string',
    notes: 'string',
    paymentMethod: 'string',
    revenueType: 'string',
    cashTransactionLocalId: 'integer',
    cashTransactionServerId: 'integer',
    referenceNumber: 'string',
    hotelDayKey: 'string',
    isPendingBalance: 'boolean',
    linkedDebtUuid: 'string',
    bookingUuidCache: 'string',
    isVoided: 'boolean',
    voidedAt: 'integer',
    voidedBy: 'string',
    voidReason: 'string',
    isImmutable: 'boolean',
    discountAmount: 'double',
    discountStartDate: 'string',
  }),

  expenses: withSync({
    expenseType: 'string',
    relatedId: 'integer',
    description: 'string',
    amount: 'double',
    date: 'string',
    cashTransactionId: 'integer',
    hotelDayKey: 'string',
    categoryUuid: 'string',
    cashFlowUuid: 'string',
    isAutoGenerated: 'boolean',
    employeeUuid: 'string',
  }),

  debts: withSync({
    bookingLocalId: 'integer',
    bookingUuidCache: 'string',
    guestName: 'string',
    checkinDate: 'string',
    checkoutDate: 'string',
    dateRecorded: 'string',
    debtReason: 'string',
    totalAmount: 'double',
    paidAmount: 'double',
    remainingAmount: 'double',
    paymentDate: 'string',
    isSettled: 'boolean',
    pledge: 'string',
    pledgeType: 'string',
    note: 'string',
    debtUuid: 'string',
    hotelDayOpened: 'string',
    hotelDayClosed: 'string',
    isFromAutoFix: 'boolean',
    settlementConfirmed: 'boolean',
    amount: 'double',
    date: 'string',
    debtorName: 'string',
    description: 'string',
    dueDate: 'string',
    guestPhone: 'string',
    status: 'string',
  }),

  employees: withSync({
    name: 'string',
    basicSalary: 'double',
    salary: 'double',
    position: 'string',
    phone: 'string',
    hireDate: 'string',
    status: 'string',
    terminationDate: 'string',
    terminationReason: 'string',
    EmployeeID: 'string',
  }),

  booking_notes: withSync({
    bookingId: 'integer',
    noteText: 'string',
    alertType: 'string',
    alertUntil: 'string',
    isActive: 'boolean',
    bookingUuidCache: 'string',
  }),

  booking_nights: withSync({
    bookingLocalId: 'integer',
    bookingUuidCache: 'string',
    hotelDayKey: 'string',
    nightStart: 'string',
    nightEnd: 'string',
    nightlyRate: 'double',
    sequence: 'integer',
    isProcessedByAutoFix: 'boolean',
    baseRate: 'double',
    adjustment: 'double',
    finalRate: 'double',
    appliedAdjustmentUuid: 'string',
    appliedAdjustmentsJson: 'string',
    serverBookingId: 'integer',
  }),

  cash_transactions: withSync({
    registerId: 'integer',
    transactionType: 'string',
    amount: 'double',
    referenceType: 'string',
    referenceId: 'integer',
    description: 'string',
    transactionTime: 'string',
    createdBy: 'string',
  }),

  salary_cycles: withSync({
    employeeId: 'integer',
    cycleKey: 'string',
    hotelDayStart: 'string',
    hotelDayEnd: 'string',
    expectedAmount: 'integer',
    actualPaid: 'integer',
    remainingAmount: 'integer',
    status: 'string',
  }),

  salary_payments: withSync({
    cycleId: 'integer',
    amount: 'integer',
    hotelDayKey: 'string',
    paymentDateIso: 'string',
    method: 'string',
    isAutoGenerated: 'boolean',
  }),

  salary_withdrawals: withSync({
    employeeId: 'integer',
    employeeLocalUuid: 'string',
    employeeUuid: 'string',
    amount: 'double',
    withdrawDate: 'string',
    withdrawalDate: 'string',
    reason: 'string',
    hotelDayKey: 'string',
    withdrawalType: 'string',
    description: 'string',
    expenseId: 'integer',
    name: 'string',
    note: 'string',
    action: 'string',
    date: 'string',
  }),

  salary_carry_over_logs: withSync({
    employeeId: 'integer',
    amount: 'double',
    previousCycleStart: 'string',
    previousCycleEnd: 'string',
    newCycleStart: 'string',
    newCycleEnd: 'string',
    reason: 'string',
    carriedAt: 'integer',
  }),

  shift_notes: withSync({
    title: 'string',
    content: 'string',
    priority: 'string',
    shiftType: 'string',
    isRead: 'boolean',
    expiresAt: 'string',
    createdBy: 'string',
    note: 'string',
    shiftDate: 'string',
  }),

  price_adjustments: withSync({
    targetType: 'string',
    targetUuid: 'string',
    adjustmentType: 'string',
    // ✅ متطابق مع النشر الفعلي على الوجهتين (double)؛ محوّل السحب يحوّل
    // double→int بأمان (_asInt/.toInt) لعمود Drift الصحيح.
    previousValue: 'double',
    newValue: 'double',
    reason: 'string',
    effectiveDate: 'string',
    appliedBy: 'string',
    hotelDayKey: 'string',
    isReversed: 'boolean',
    reversedAt: 'string',
    reversedBy: 'string',
  }),

  booking_price_adjustments: withSync({
    bookingLocalUuid: 'string',
    bookingUuid: 'string',
    bookingLocalId: 'integer',
    roomNumber: 'string',
    adjustmentType: 'integer',
    adjustmentMode: 'string',
    amount: 'double',
    effectiveHotelDay: 'string',
    endHotelDay: 'string',
    isActive: 'boolean',
    reason: 'string',
    appliedBy: 'string',
    appliedAt: 'integer',
    cancelledAt: 'string',
    cancelledBy: 'string',
  }),

  audit_logs: withSync({
    operationType: 'string',
    entityType: 'string',
    entityUuid: 'string',
    entityId: 'integer',
    previousState: 'string',
    newState: 'string',
    changedFields: 'string',
    performedBy: 'string',
    ipAddress: 'string',
    hotelDayKey: 'string',
    timestamp: 'integer',
    timestampIso: 'string',
    isFinancial: 'boolean',
    // ✅ متطابق مع النشر الفعلي على الوجهتين (double)؛ محوّل السحب يحوّل double→int
    amountImpact: 'double',
    action: 'string',
  }),

  payment_voids: withSync({
    originalPaymentUuid: 'string',
    originalPaymentId: 'integer',
    bookingUuid: 'string',
    voidedAmount: 'integer',
    voidReason: 'string',
    voidedBy: 'string',
    voidedAt: 'integer',
    voidedAtIso: 'string',
    hotelDayKey: 'string',
    reversalPaymentUuid: 'string',
    approvedBy: 'string',
    note: 'string',
    originalAmount: 'double',
    paymentUuid: 'string',
  }),

  guest_infos: withSync({
    roomNumber: 'string',
    guestName: 'string',
    nationality: 'string',
    idNumber: 'string',
    idType: 'string',
    issueDate: 'string',
    issuePlace: 'string',
    governorate: 'string',
    notes: 'string',
  }),

  // app_settings مخزّن كمستند واحد (whatsapp_settings). حقوله snake_case في Appwrite.
  // منقول من validFieldsPerCollection['app_settings'] + باني _appSettingsToMap.
  app_settings: {
    localUuid: 'string',
    serverId: 'integer',
    createdAt: 'integer',
    updatedAt: 'integer',
    deletedAt: 'integer',
    lastModified: 'integer',
    createdAtIso: 'string',
    updatedAtIso: 'string',
    deletedAtIso: 'string',
    createdAtEpoch: 'integer',
    lastModifiedEpoch: 'integer',
    version: 'integer',
    origin: 'string',
    deviceId: 'string',
    idempotencyKey: 'string',
    syncTimestamp: 'integer',
    sync_origin: 'string',
    // إعدادات عامة
    hotel_name: 'string',
    hotel_cutoff_hour: 'integer',
    dark_mode: 'boolean',
    appwrite_sync_interval: 'integer',
    conflict_strategy: 'string',
    sync_performance_profile: 'string',
    wifi_only_sync: 'boolean',
    // إعدادات النسخ الاحتياطي
    auto_backup_frequency: 'string',
    auto_backup_time: 'string',
    scheduled_backup_enabled: 'boolean',
    secondary_appwrite_config: 'string',
    // اتصال Appwrite
    endpoint: 'string',
    project_id: 'string',
    database_id: 'string',
    enabled: 'boolean',
    push_enabled: 'boolean',
    pull_enabled: 'boolean',
    appwrite_auto_sync_on_connect: 'boolean',
    appwrite_log_console: 'boolean',
    appwrite_log_file: 'boolean',
    // ✅ الخيار 2: كل مفاتيح WhatsApp/Telegram/API النصية الحسّاسة مُجمّعة
    // في حقل JSON واحد (config_json) بدل ~11 عموداً نصياً منفصلاً — لتفادي
    // تجاوز حدّ حجم الصف (row-size) في Appwrite. يُنشأ بحجم كبير (TEXT خارج
    // الصف) فلا يستهلك من ميزانية الصف عملياً.
    config_json: 'string',
    // Telegram — المفاتيح المنطقية (bool) تبقى أعمدة؛ النصّية داخل config_json
    telegram_enabled: 'boolean',
    telegram_notifications_enabled: 'boolean',
    telegram_daily_report_enabled: 'boolean',
    telegram_daily_report_time: 'string',
  },

  // القائمة السوداء للنزلاء
  blacklist: withSync({
    name: 'string',
    nationalId: 'string',
    nationality: 'string',
    phone: 'string',
    reason: 'string',
    notes: 'string',
    reportedBy: 'string',
    active: 'boolean',
  }),

  // مستخدمو التطبيق (حسابات الدخول). مُضافة لجعل الثانوية مطابقة للأساسية.
  // منقولة حرفياً من collectionSchema['app_users'] (appwrite_sync_utils.dart).
  // ⚠️ ليس لها حقول SYNC قياسية (بلا localUuid) ولا فهارس — تُدار عبر upsert مباشر
  // في auth_local_store._pushUserToCloud. لذا لا نطبّق withSync ولا نبني فهرساً.
  app_users: {
    active: 'boolean',
    credentials_version: 'integer',
    fullName: 'string',
    full_name: 'string',
    lastLogin: 'integer',
    last_login: 'integer',
    password: 'string',
    permissions: 'string',
    sync_origin: 'string',
    userType: 'string',
    user_type: 'string',
    username: 'string',
    version: 'integer',
  },
};

// ─────────────────────────────────────────────────────────────────────────────
// 3) الصلاحيات — audit_logs غير قابل للتعديل/الحذف (سجلات دائمة)
// ─────────────────────────────────────────────────────────────────────────────
function permissionsFor(collectionId) {
  if (collectionId === 'audit_logs') {
    // للقراءة والإنشاء فقط — لا تحديث ولا حذف (سجلات تدقيق دائمة)
    return [Permission.read(Role.any()), Permission.create(Role.any())];
  }
  return [
    Permission.read(Role.any()),
    Permission.create(Role.any()),
    Permission.update(Role.any()),
    Permission.delete(Role.any()),
  ];
}

// حقل المفتاح — يجب أن يكون required حتى نبني عليه فهرساً فريداً.
const KEY_FIELD = 'localUuid';

// أحجام السلاسل — دالة تُقدّر حجماً مناسباً حسب اسم الحقل.
function stringSize(field) {
  const explicit = {
    previousState: 16000,
    newState: 16000,
    changedFields: 4000,
    vectorClock: 2000,
    secondary_appwrite_config: 8000,
    appliedAdjustmentsJson: 8000,
    // config_json: مُجمّع إعدادات app_settings — حجم كبير ليُخزَّن TEXT خارج
    // الصف (off-page) فلا يُحسب ضمن حدّ حجم صف Appwrite.
    config_json: 65535,
    permissions: 2000, // app_users: قائمة صلاحيات مُرمّزة JSON
    // ✅ تنظيف: حذف api_key, wa_api_token, telegram_bot_token, wa_sendzen_api_key,
    //    wa_custom_url_template — كلها انتقلت إلى config_json (الخيار 2) ولم تعد
    //    أعمدة منفصلة في أي SCHEMA. إبقاؤها هنا يُضلّل القارئ ويوحي بأنها مستخدمة.
    financialHash: 128,
  };
  if (explicit[field] != null) return explicit[field];

  const f = field.toLowerCase();
  // المعرّفات (UUID) + مفاتيح idempotency
  if (f === 'localuuid' || f.endsWith('uuid') || f === 'idempotencykey') return 64;
  // الطوابع/التواريخ النصية والمفاتيح اليومية
  if (f.endsWith('iso') || f.includes('date') || f.includes('time') ||
      f.includes('hotelday') || f === 'cyclekey') return 64;
  // الحقول النصية الطويلة
  if (f.includes('note') || f.includes('description') || f.includes('reason') ||
      f.includes('address') || f.includes('template') || f.includes('url') ||
      f.endsWith('json')) return 2000;
  // افتراضي آمن
  return 512;
}

// ─────────────────────────────────────────────────────────────────────────────
// 4) أدوات مساعدة idempotent
// ─────────────────────────────────────────────────────────────────────────────
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const isConflict = (e) => e && (e.code === 409 || /already exists/i.test(e.message || ''));

// خريطة أنواع Appwrite → مفاتيح الدوال
const TYPE_TO_APPWRITE = {
  string: 'string',
  integer: 'integer',
  double: 'double',
  boolean: 'boolean',
};

// تحويل نوع السمة في Appwrite إلى نوع SCHEMA الموحّد
function appwriteTypeToSchema(attr) {
  // attr.type قد يكون: 'string','integer','double','boolean'
  // (في node-appwrite الحديث يُعاد النوع في `type`، وفي القديم في `key`/`array`+`type`)
  if (!attr) return null;
  const t = (attr.type || '').toLowerCase();
  if (t === 'string' || t === 'integer' || t === 'double' || t === 'boolean') {
    return t;
  }
  // إصدارات أقدم تستخدم format (e.g. {type: 'string', format: 'datetime'})
  return null;
}

const stats = {
  collectionsCreated: 0,
  collectionsExisting: 0,
  attributesCreated: 0,
  attributesExisting: 0,
  attributesRecreated: 0, // عدد الحقول التي حُذِفت وأُعيد إنشاؤها (--fix-types)
  attributesPruned: 0,    // عدد الحقول الزائدة التي حُذِفت (--prune)
  attributesMadeOptional: 0, // عدد الحقول التي حُوِّلت من required=true إلى false (--make-optional)
  indexesCreated: 0,
  indexesExisting: 0,
  errors: [],
};

async function ensureDatabase() {
  try {
    await databases.get(DATABASE_ID);
    console.log(`✔️  قاعدة البيانات موجودة: ${DATABASE_ID}`);
    return;
  } catch (e) {
    if (e.code !== 404) {
      console.log(`ℹ️  تعذّر التحقق من قاعدة البيانات (${e.message}) — سأحاول الإنشاء`);
    }
  }
  try {
    await databases.create(DATABASE_ID, DATABASE_NAME);
    console.log(`✅ أُنشئت قاعدة البيانات: ${DATABASE_ID}`);
  } catch (e) {
    if (isConflict(e)) {
      console.log(`⏭️  قاعدة البيانات موجودة مسبقاً: ${DATABASE_ID}`);
    } else {
      console.error(`❌ فشل إنشاء قاعدة البيانات: ${e.message}`);
      throw e;
    }
  }
}

async function ensureCollection(collectionId) {
  try {
    await databases.createCollection(
      DATABASE_ID,
      collectionId,
      collectionId, // الاسم = المعرّف (نفس ما يستخدمه التطبيق)
      permissionsFor(collectionId),
    );
    console.log(`\n📦 أُنشئت المجموعة: ${collectionId}`);
    stats.collectionsCreated++;
    await sleep(400);
  } catch (e) {
    if (isConflict(e)) {
      console.log(`\n📦 المجموعة موجودة: ${collectionId}`);
      stats.collectionsExisting++;
    } else {
      throw e;
    }
  }
}

async function ensureAttribute(collectionId, key, type) {
  const required = key === KEY_FIELD; // فقط المفتاح مطلوب؛ الباقي اختياري (لأمان المزامنة الجزئية)

  // 1) إذا كان الحقل موجوداً مسبقاً، تحقّق من النوع وعلم required مع --fix-types
  try {
    const coll = await databases.getCollection(DATABASE_ID, collectionId);
    const existing = coll.attributes.find((a) => a.key === key);
    if (existing) {
      const actualType = appwriteTypeToSchema(existing);
      // علم required في الإصدار الحديث يأتي في `required`، وفي القديم قد يأتي في `isRequired`
      const actualRequired = !!(existing.required ?? existing.isRequired);
      const typeMismatch = actualType && actualType !== type;
      const requiredMismatch = actualRequired !== required;

      // ✅ إذا كان --make-optional مفعّلاً، تجاهل requiredMismatch تماماً
      // لأن makeAttributesOptional سيتعامل معه لاحقاً دون حذف الحقل.
      const effectiveRequiredMismatch = MAKE_OPTIONAL ? false : requiredMismatch;

      if (typeMismatch || effectiveRequiredMismatch) {
        if (FIX_TYPES) {
          const reason = [
            typeMismatch ? `${actualType}→${type}` : null,
            effectiveRequiredMismatch ? `required=${actualRequired}→${required}` : null,
          ].filter(Boolean).join(', ');
          console.log(`   🔧 ${key}: تعارض (${reason}) — حذف وإعادة إنشاء`);
          try {
            await deleteAttributeAndWait(collectionId, key);
            stats.attributesRecreated++;
          } catch (e) {
            console.error(`   ❌ فشل حذف ${key} (لإعادة الإنشاء): ${e.message}`);
            stats.errors.push(`${collectionId}.${key}: delete failed: ${e.message}`);
            return;
          }
          // سقط عمداً إلى الإنشاء أدناه
        } else {
          const reason = [
            typeMismatch ? `نوع=${actualType} (مطلوب ${type})` : null,
            effectiveRequiredMismatch ? `required=${actualRequired} (مطلوب ${required})` : null,
          ].filter(Boolean).join('، ');
          console.log(`   ⚠️  ${key}: ${reason} — شغّل --fix-types للإصلاح`);
          stats.errors.push(`${collectionId}.${key}: mismatch (${reason}). Run with --fix-types`);
          return;
        }
      } else {
        // متطابق — لا شيء للفعله
        stats.attributesExisting++;
        return;
      }
    }
  } catch (e) {
    // إذا فشل getCollection، أكمل لمحاولة الإنشاء
  }

  // 2) إنشاء الحقل بالمواصفات المطلوبة
  try {
    if (type === 'string') {
      await databases.createStringAttribute(
        DATABASE_ID, collectionId, key, stringSize(key), required,
      );
    } else if (type === 'integer') {
      await databases.createIntegerAttribute(
        DATABASE_ID, collectionId, key, required,
      );
    } else if (type === 'double') {
      await databases.createFloatAttribute(
        DATABASE_ID, collectionId, key, required,
      );
    } else if (type === 'boolean') {
      await databases.createBooleanAttribute(
        DATABASE_ID, collectionId, key, required,
      );
    } else {
      throw new Error(`نوع غير مدعوم للحقل ${key}: ${type}`);
    }
    console.log(`   ✅ ${key} (${type})`);
    stats.attributesCreated++;
    await sleep(250); // احترام حدود المعدل
  } catch (e) {
    if (isConflict(e)) {
      stats.attributesExisting++;
    } else {
      console.error(`   ❌ فشل الحقل ${key}: ${e.message}`);
      stats.errors.push(`${collectionId}.${key}: ${e.message}`);
    }
  }
}

// حذف الحقول الزائدة غير الموجودة في SCHEMA (--prune)
// مهم جداً لإزالة حقول مثل paymentLocalId و nightNumber من الثانوي
async function pruneExtraAttributes(collectionId, wantedFields) {
  let coll;
  try {
    coll = await databases.getCollection(DATABASE_ID, collectionId);
  } catch (e) {
    return; // المجموعة غير موجودة — لا شيء لحذفه
  }
  const wanted = new Set(Object.keys(wantedFields));
  for (const attr of coll.attributes) {
    if (!wanted.has(attr.key)) {
      try {
        // ✅ استخدم deleteAttributeAndWait بدلاً من databases.deleteAttribute + sleep(400)
        // — حذف السمة غير فوري على Appwrite، والـ sleep الثابت قد يسبب 409 Conflict
        // عند إعادة الإنشاء لاحقاً. deleteAttributeAndWait يتحقق فعلياً من اختفاء السمة.
        await deleteAttributeAndWait(collectionId, attr.key);
        console.log(`   🗑️  حقل زائد حُذف: ${attr.key} (كان ${appwriteTypeToSchema(attr) || attr.type || '?'})`);
        stats.attributesPruned++;
      } catch (e) {
        console.error(`   ❌ فشل حذف الحقل الزائد ${attr.key}: ${e.message}`);
        stats.errors.push(`${collectionId}.prune.${attr.key}: ${e.message}`);
      }
    }
  }
}

// ✅ تحويل الحقول المُعلَّمة كـ required=true إلى required=false دون حذف الحقل
// أو بياناته. يستخدم دوال updateXAttribute في Appwrite التي تُحدِّث علم required
// مباشرةً. هذا آمن تماماً للبيانات الموجودة.
//
// المنطق:
//   - يجلب الحقول الفعلية للمجموعة.
//   - لكل حقل موجود في SCHEMA:
//       إذا كان required=true في Appwrite والمطلوب في SCHEMA هو optional:
//           استدعِ updateXAttribute(required=false) حسب نوع الحقل.
//   - لا يحذف أي حقل ولا يُغيّر النوع.
//
// مثال:
//   bookings.createdAt: required=true → required=false (لا تتأثر البيانات)
async function makeAttributesOptional(collectionId, wantedFields) {
  let coll;
  try {
    coll = await databases.getCollection(DATABASE_ID, collectionId);
  } catch (e) {
    return; // المجموعة غير موجودة — لا شيء لفعله
  }

  for (const attr of coll.attributes) {
    const wantedType = wantedFields[attr.key];
    if (wantedType === undefined) continue; // حقل زائد — تجاهله (هذا وظيفة --prune)

    const actualRequired = !!(attr.required ?? attr.isRequired);
    const targetRequired = attr.key === KEY_FIELD; // فقط المفتاح مطلوب

    if (actualRequired && !targetRequired) {
      try {
        if (wantedType === 'string') {
          await databases.updateStringAttribute(
            DATABASE_ID, collectionId, attr.key,
            false, // required=false
            attr.default ?? undefined, // الحفاظ على القيمة الافتراضية إن وُجدت
          );
        } else if (wantedType === 'integer') {
          await databases.updateIntegerAttribute(
            DATABASE_ID, collectionId, attr.key, false,
            attr.default ?? undefined,
          );
        } else if (wantedType === 'double') {
          await databases.updateFloatAttribute(
            DATABASE_ID, collectionId, attr.key, false,
            attr.min ?? undefined, attr.max ?? undefined,
            attr.default ?? undefined,
          );
        } else if (wantedType === 'boolean') {
          await databases.updateBooleanAttribute(
            DATABASE_ID, collectionId, attr.key, false,
            attr.default ?? undefined,
          );
        } else {
          continue;
        }
        console.log(`   🔓 ${attr.key}: required=true → required=false`);
        stats.attributesMadeOptional++;
        await sleep(300);
      } catch (e) {
        console.error(`   ❌ فشل تحويل ${attr.key} إلى optional: ${e.message}`);
        stats.errors.push(`${collectionId}.${attr.key}.make-optional: ${e.message}`);
      }
    }
  }
}

async function waitForAttributes(collectionId, expected) {
  // ✅ الثوابت قابلة للتهيئة عبر env vars — مفيد للبيئات البطيئة (self-hosted Appwrite).
  const maxIter = process.env.WAIT_MAX_ITER ? parseInt(process.env.WAIT_MAX_ITER, 10) : 30;
  const sleepMs = process.env.WAIT_SLEEP_MS ? parseInt(process.env.WAIT_SLEEP_MS, 10) : 1500;
  for (let i = 0; i < maxIter; i++) {
    try {
      const coll = await databases.getCollection(DATABASE_ID, collectionId);
      const available = coll.attributes.filter((a) => a.status === 'available');
      // ✅ تسجيل granular: أي الحقول لم تُصر جاهزة بعد؟ يساعد في تشخيص التهيئة البطيئة.
      const notReady = coll.attributes
        .filter((a) => a.status !== 'available')
        .map((a) => `${a.key}(${a.status})`);
      if (available.length >= expected) return true;
      if (i === 0 || i % 5 === 4) {
        console.log(
          `   ⏳ ${collectionId}: ${available.length}/${expected} جاهز` +
            (notReady.length ? ` — بانتظار: ${notReady.join(', ')}` : ''),
        );
      }
    } catch (_) { /* تجاهل — نُعيد المحاولة */ }
    await sleep(sleepMs);
  }
  console.log(
    `   ⚠️  انتهت مهلة انتظار جاهزية الحقول في ${collectionId} (${maxIter * sleepMs / 1000}s) — أتابع`,
  );
  return false;
}

async function ensureIndex(collectionId, key, type, attributes, orders) {
  try {
    await databases.createIndex(DATABASE_ID, collectionId, key, type, attributes, orders);
    console.log(`   🔑 فهرس: ${key} [${attributes.join(', ')}]`);
    stats.indexesCreated++;
    await sleep(400);
  } catch (e) {
    if (isConflict(e)) {
      stats.indexesExisting++;
    } else {
      console.error(`   ❌ فشل الفهرس ${key}: ${e.message}`);
      stats.errors.push(`${collectionId}.index.${key}: ${e.message}`);
    }
  }
}

// الفهارس القياسية لكل مجموعة (فقط إن وُجد الحقل).
async function ensureStandardIndexes(collectionId, fields) {
  const has = (f) => Object.prototype.hasOwnProperty.call(fields, f);
  if (has('localUuid')) {
    await ensureIndex(collectionId, 'idx_local_uuid', IndexType.Unique, ['localUuid']);
  }
  if (has('lastModified')) {
    await ensureIndex(collectionId, 'idx_last_modified', IndexType.Key, ['lastModified'], ['DESC']);
  }
  if (has('syncTimestamp')) {
    await ensureIndex(collectionId, 'idx_sync_ts', IndexType.Key, ['syncTimestamp'], ['DESC']);
  }
  if (has('deletedAt')) {
    await ensureIndex(collectionId, 'idx_deleted_at', IndexType.Key, ['deletedAt']);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5) وضع الفحص (--verify): مقارنة المخطط الفعلي بالمطلوب
// ─────────────────────────────────────────────────────────────────────────────
async function verify(targetCollections) {
  let missingCollections = 0;
  let missingAttributes = 0;
  let typeMismatches = 0;

  for (const collectionId of targetCollections) {
    const wanted = SCHEMA[collectionId];
    let actual;
    try {
      actual = await databases.getCollection(DATABASE_ID, collectionId);
    } catch (e) {
      if (e.code === 404) {
        console.log(`❌ المجموعة مفقودة: ${collectionId}`);
        missingCollections++;
        continue;
      }
      throw e;
    }
    // خريطة الحقل الفعلي → نوعه، لمقارنة الوجود والنوع معاً.
    const actualByKey = new Map(actual.attributes.map((a) => [a.key, a]));
    const missing = Object.keys(wanted).filter((k) => !actualByKey.has(k));

    // ✅ فحص تطابق الأنواع — الحقل الموجود يجب أن يكون بنفس النوع المطلوب.
    // نوع Appwrite (a.type) أحد: string | integer | double | boolean، وهو
    // نفس مفردات SCHEMA. عدم التطابق هو ما يُنتج خطأ "invalid type" وقت الرفع.
    const mismatches = [];
    for (const [key, wantType] of Object.entries(wanted)) {
      const attr = actualByKey.get(key);
      if (attr && attr.type !== wantType) {
        mismatches.push(`${key}: فعلي=${attr.type} ≠ مطلوب=${wantType}`);
      }
    }

    if (missing.length === 0 && mismatches.length === 0) {
      console.log(`✅ ${collectionId}: كل الحقول موجودة وبأنواع متطابقة (${Object.keys(wanted).length})`);
    } else {
      if (missing.length > 0) {
        console.log(`⚠️  ${collectionId}: ناقص ${missing.length} حقل → ${missing.join(', ')}`);
        missingAttributes += missing.length;
      }
      if (mismatches.length > 0) {
        console.log(`❌ ${collectionId}: ${mismatches.length} عدم تطابق نوع → ${mismatches.join(' | ')}`);
        typeMismatches += mismatches.length;
      }
    }
  }

  console.log('\n══════════════════════════════════════════');
  console.log(
    `ملخّص الفحص: مجموعات مفقودة=${missingCollections}, ` +
      `حقول مفقودة=${missingAttributes}, عدم تطابق الأنواع=${typeMismatches}`,
  );
  console.log('══════════════════════════════════════════');
  process.exit(
    missingCollections + missingAttributes + typeMismatches > 0 ? 2 : 0,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 5.1) وضع إصلاح الأنواع (--fix-types): حذف كل حقل نوعه يختلف عن SCHEMA وإعادة
//      إنشائه بالنوع الصحيح. ⚠️ هدمي — تُفقد قيم العمود على السحابة (تُعاد محلياً).
// ─────────────────────────────────────────────────────────────────────────────
async function deleteAttributeAndWait(collectionId, key) {
  try {
    await databases.deleteAttribute(DATABASE_ID, collectionId, key);
  } catch (e) {
    if (e.code !== 404) throw e;
  }
  // حذف السمة غير فوري — ننتظر اختفاءها قبل إعادة الإنشاء بنفس المفتاح.
  for (let i = 0; i < 30; i++) {
    const coll = await databases.getCollection(DATABASE_ID, collectionId);
    if (!coll.attributes.some((a) => a.key === key)) return;
    await sleep(1000);
  }
  throw new Error(`لم يكتمل حذف السمة ${collectionId}.${key} خلال المهلة`);
}

async function fixTypes(targetCollections) {
  let fixed = 0;
  let failed = 0;
  for (const collectionId of targetCollections) {
    const wanted = SCHEMA[collectionId];
    let actual;
    try {
      actual = await databases.getCollection(DATABASE_ID, collectionId);
    } catch (e) {
      if (e.code === 404) {
        console.log(`❌ المجموعة مفقودة: ${collectionId}`);
        continue;
      }
      throw e;
    }
    const byKey = new Map(actual.attributes.map((a) => [a.key, a]));
    for (const [key, wantType] of Object.entries(wanted)) {
      const attr = byKey.get(key);
      if (attr && attr.type !== wantType) {
        console.log(
          `♻️  ${collectionId}.${key}: ${attr.type} → ${wantType} (حذف + إعادة إنشاء)`,
        );
        try {
          await deleteAttributeAndWait(collectionId, key);
          await ensureAttribute(collectionId, key, wantType);
          fixed++;
        } catch (e) {
          console.log(`   ❌ فشل إصلاح ${key}: ${e.message || e}`);
          failed++;
        }
      }
    }
  }
  console.log('\n══════════════════════════════════════════');
  console.log(`إصلاح الأنواع: مُصلَح=${fixed}, فشل=${failed}`);
  console.log('══════════════════════════════════════════');
  process.exit(failed > 0 ? 2 : 0);
}

// ─────────────────────────────────────────────────────────────────────────────
// 6) التشغيل
// ─────────────────────────────────────────────────────────────────────────────
async function main() {
  const allCollections = Object.keys(SCHEMA);
  const targets = ONLY
    ? allCollections.filter((c) => ONLY.includes(c))
    : allCollections;

  if (ONLY) {
    const unknown = ONLY.filter((c) => !allCollections.includes(c));
    if (unknown.length) {
      console.error(`❌ مجموعات غير معروفة في --only: ${unknown.join(', ')}`);
      process.exit(1);
    }
  }

  console.log('═══════════════════════════════════════════════════════════');
  console.log('🏨 Marina Hotel — Unified Appwrite Setup');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(`Endpoint : ${ENDPOINT}`);
  console.log(`Project  : ${PROJECT_ID}`);
  console.log(`Database : ${DATABASE_ID}`);
  const modeFlags = [];
  if (VERIFY_ONLY) modeFlags.push('VERIFY');
  if (PRUNE) modeFlags.push('PRUNE (حذف الزائد)');
  if (FIX_TYPES) modeFlags.push('FIX-TYPES (حذف+إعادة إنشاء)');
  if (MAKE_OPTIONAL) modeFlags.push('MAKE-OPTIONAL (تحويل required=false فقط)');
  if (!VERIFY_ONLY && !PRUNE && !FIX_TYPES && !MAKE_OPTIONAL) modeFlags.push('SETUP');
  console.log(`Mode     : ${modeFlags.join(' + ')}`);
  console.log(`Targets  : ${targets.length} مجموعة${ONLY ? ' (مُصفّاة)' : ''}`);
  console.log('═══════════════════════════════════════════════════════════');

  initClient();

  if (VERIFY_ONLY) {
    await verify(targets);
    return;
  }

  // ✅ تأكيد هدمي مشترك: --fix-types و --prune كلاهما يحذف أعمدة (يُفقد قيمها).
  // --make-optional غير هدمي (يحوّل required=true → false دون حذف)، فلا يحتاج تأكيداً.
  // إن لم يُمرَّر --confirm/-y، نُطبِع تحذيراً صريحاً وننتظر 5 ثوانٍ مع عدّ تنازلي.
  const DESTRUCTIVE_MODE = FIX_TYPES || PRUNE;
  if (DESTRUCTIVE_MODE && !CONFIRM) {
    const modes = [];
    if (FIX_TYPES) modes.push('FIX-TYPES');
    if (PRUNE) modes.push('PRUNE');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`⚠️  تحذير: وضع ${modes.join(' + ')} هدمي!`);
    if (FIX_TYPES) {
      console.log('   - FIX-TYPES: حذف كل سمة نوعها غير مطابق وإعادة إنشائها (قيمها تُفقد).');
    }
    if (PRUNE) {
      console.log('   - PRUNE: حذف كل حقل زائد عن SCHEMA (قيمه تُفقد).');
    }
    console.log('   للإلغاء اضغط Ctrl+C خلال 5 ثوانٍ...');
    console.log('   (لتخطّي هذا التحذير مستقبلاً: أضِف --confirm أو -y)');
    console.log('═══════════════════════════════════════════════════════════');
    for (let i = 5; i > 0; i--) {
      process.stdout.write(`\r   البدء خلال ${i} ثانية...  `);
      await sleep(1000);
    }
    process.stdout.write('\r   ▶ البدء الآن.                  \n');
  } else if (DESTRUCTIVE_MODE && CONFIRM) {
    const modes = [];
    if (FIX_TYPES) modes.push('FIX-TYPES');
    if (PRUNE) modes.push('PRUNE');
    console.log(`⚠️  ${modes.join(' + ')} (تم تخطّي التحذير عبر --confirm)`);
  }

  if (FIX_TYPES) {
    await fixTypes(targets);
    return;
  }

  await ensureDatabase();

  for (const collectionId of targets) {
    const fields = SCHEMA[collectionId];
    await ensureCollection(collectionId);

    for (const [key, type] of Object.entries(fields)) {
      await ensureAttribute(collectionId, key, type);
    }

    // ✅ حذف الحقول الزائدة عن SCHEMA (مثل paymentLocalId, nightNumber في الثانوي)
    // مهم لتطابق Primary والثانوي حقلاً بحقل.
    if (PRUNE) {
      await pruneExtraAttributes(collectionId, fields);
    }

    // ✅ تحويل الحقول required=true إلى required=false دون حذف الحقل أو بياناته.
    // هذا يحل خطأ "Missing required attribute" بشكل آمن تماماً للبيانات.
    if (MAKE_OPTIONAL) {
      await makeAttributesOptional(collectionId, fields);
    }

    // انتظر جاهزية الحقول قبل بناء الفهارس (الفهرس يتطلب حقولاً available).
    await waitForAttributes(collectionId, Object.keys(fields).length);
    await ensureStandardIndexes(collectionId, fields);
  }

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('✅ اكتمل الإعداد الموحّد');
  console.log('───────────────────────────────────────────────────────────');
  console.log(`المجموعات     : أُنشئت ${stats.collectionsCreated} / موجودة ${stats.collectionsExisting}`);
  console.log(`الحقول        : أُنشئت ${stats.attributesCreated} / موجودة ${stats.attributesExisting}`);
  if (stats.attributesPruned > 0) {
    console.log(`🗑️  حقول زائدة محذوفة (--prune): ${stats.attributesPruned}`);
  }
  if (stats.attributesRecreated > 0) {
    console.log(`🔧 حقول أُعيد إنشاؤها (--fix-types): ${stats.attributesRecreated}`);
  }
  if (stats.attributesMadeOptional > 0) {
    console.log(`🔓 حقول حُوِّلت إلى optional (--make-optional): ${stats.attributesMadeOptional}`);
  }
  console.log(`الفهارس       : أُنشئت ${stats.indexesCreated} / موجودة ${stats.indexesExisting}`);
  if (stats.errors.length) {
    console.log(`\n⚠️  أخطاء (${stats.errors.length}):`);
    stats.errors.forEach((er) => console.log(`   · ${er}`));
    process.exit(1);
  }
  console.log('═══════════════════════════════════════════════════════════');
}

// يُصدَّر المخطط للاختبار/الفحص البرمجي دون تشغيل الإعداد.
module.exports = { SCHEMA, SYNC, stringSize, permissionsFor };

// شغّل فقط عند الاستدعاء المباشر (وليس عند require).
if (require.main === module) {
  main().catch((e) => {
    console.error('\n❌ خطأ فادح:', e && e.message ? e.message : e);
    process.exit(1);
  });
}
