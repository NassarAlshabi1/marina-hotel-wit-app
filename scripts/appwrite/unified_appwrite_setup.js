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
    previousValue: 'integer',
    newValue: 'integer',
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
    amountImpact: 'integer',
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
    // حقول زمنية يُرسلها _pushUserToCloud فعلياً (epoch seconds) — مفقودة سابقاً
    // فكان الرفع يفشل على مجموعة مُهيّأة حديثاً. تُضاف هنا لتقبلها المجموعة.
    createdAt: 'integer',
    updatedAt: 'integer',
    lastModified: 'integer',
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
    api_key: 2000,
    wa_api_token: 2000,
    telegram_bot_token: 2000,
    wa_sendzen_api_key: 2000,
    wa_custom_url_template: 2000,
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

const stats = {
  collectionsCreated: 0,
  collectionsExisting: 0,
  attributesCreated: 0,
  attributesExisting: 0,
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

async function waitForAttributes(collectionId, expected) {
  for (let i = 0; i < 30; i++) {
    try {
      const coll = await databases.getCollection(DATABASE_ID, collectionId);
      const ready = coll.attributes.filter((a) => a.status === 'available').length;
      if (ready >= expected) return true;
    } catch (_) { /* تجاهل */ }
    await sleep(1500);
  }
  console.log(`   ⚠️  انتهت مهلة انتظار جاهزية الحقول في ${collectionId} — أتابع`);
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
    const actualKeys = new Set(actual.attributes.map((a) => a.key));
    const missing = Object.keys(wanted).filter((k) => !actualKeys.has(k));
    if (missing.length === 0) {
      console.log(`✅ ${collectionId}: كل الحقول موجودة (${Object.keys(wanted).length})`);
    } else {
      console.log(`⚠️  ${collectionId}: ناقص ${missing.length} حقل → ${missing.join(', ')}`);
      missingAttributes += missing.length;
    }
  }

  console.log('\n══════════════════════════════════════════');
  console.log(`ملخّص الفحص: مجموعات مفقودة=${missingCollections}, حقول مفقودة=${missingAttributes}`);
  console.log('══════════════════════════════════════════');
  process.exit(missingCollections + missingAttributes > 0 ? 2 : 0);
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
  console.log(`Mode     : ${VERIFY_ONLY ? 'VERIFY (قراءة فقط)' : 'SETUP (إنشاء/تحديث)'}`);
  console.log(`Targets  : ${targets.length} مجموعة${ONLY ? ' (مُصفّاة)' : ''}`);
  console.log('═══════════════════════════════════════════════════════════');

  initClient();

  if (VERIFY_ONLY) {
    await verify(targets);
    return;
  }

  await ensureDatabase();

  for (const collectionId of targets) {
    const fields = SCHEMA[collectionId];
    await ensureCollection(collectionId);

    for (const [key, type] of Object.entries(fields)) {
      await ensureAttribute(collectionId, key, type);
    }

    // انتظر جاهزية الحقول قبل بناء الفهارس (الفهرس يتطلب حقولاً available).
    await waitForAttributes(collectionId, Object.keys(fields).length);
    await ensureStandardIndexes(collectionId, fields);
  }

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('✅ اكتمل الإعداد الموحّد');
  console.log('───────────────────────────────────────────────────────────');
  console.log(`المجموعات : أُنشئت ${stats.collectionsCreated} / موجودة ${stats.collectionsExisting}`);
  console.log(`الحقول    : أُنشئت ${stats.attributesCreated} / موجودة ${stats.attributesExisting}`);
  console.log(`الفهارس   : أُنشئت ${stats.indexesCreated} / موجودة ${stats.indexesExisting}`);
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
