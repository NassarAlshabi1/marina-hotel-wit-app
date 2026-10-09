#!/usr/bin/env python3
"""
📋 Appwrite Schema - Marina Hotel Mobile
=========================================

This file contains the complete schema for all Appwrite Collections.

Generated: 2026-06-26
Project: Marina Hotel Mobile
Database: hotel_db

Collections (21 total):
  1. rooms                   - الغرف
  2. bookings               - الحجوزات
  3. payments               - المدفوعات
  4. expenses               - المصروفات
  5. sync_logs              - سجل المزامنة
  6. employees              - الموظفين
  7. guest_infos            - معلومات النزلاء
  8. debts                  - الديون
  9. devices                - الأجهزة
 10. cash_transactions      - المعاملات النقدية
 11. booking_notes         - ملاحظات الحجوزات
 12. booking_nights        - ليالي الحجوزات
 13. salary_cycles          - دورات الرواتب
 14. salary_payments        - مدفوعات الرواتب
 15. salary_withdrawals     - سحوبات الرواتب
 16. booking_price_adjustments - تعديلات أسعار الحجوزات
 17. hotel_day_ledger       - دفتر يوم الفندق
 18. outbox                 - الصندوق الصادر (محلي)
 19. sync_state             - حالة المزامنة (محلي)
 20. shift_notes            - ملاحظات الورديات
 21. blacklist              - القائمة السوداء
"""

# =============================================================================
# SYNC FIELDS (Present in all collections)
# =============================================================================
SYNC_FIELDS = {
    "createdAt": {"type": "integer", "required": True, "description": "تاريخ الإنشاء (epoch)"},
    "updatedAt": {"type": "integer", "required": True, "description": "تاريخ التحديث (epoch)"},
    "deletedAt": {"type": "integer", "required": False, "description": "تاريخ الحذف (epoch)"},
    "lastModified": {"type": "integer", "required": True, "description": "آخر تعديل (epoch)"},
    "createdAtIso": {"type": "string", "required": False, "description": "تاريخ ISO"},
    "updatedAtIso": {"type": "string", "required": False, "description": "تحديث ISO"},
    "deletedAtIso": {"type": "string", "required": False, "description": "حذف ISO"},
    "createdAtEpoch": {"type": "integer", "required": False, "description": "epoch الإنشاء"},
    "lastModifiedEpoch": {"type": "integer", "required": False, "description": "epoch التعديل"},
    "version": {"type": "integer", "required": False, "description": "رقم الإصدار"},
    "origin": {"type": "string", "required": False, "description": "مصدر البيانات"},
    "vectorClock": {"type": "string", "required": False, "description": "ساعة المتجهات"},
    "deviceId": {"type": "string", "required": False, "description": "معرف الجهاز"},
}

# =============================================================================
# COLLECTIONS SCHEMA (17 Collections on Appwrite Cloud)
# =============================================================================

COLLECTIONS = {
    # -------------------------------------------------------------------------
    # 1. ROOMS (الغرف) - 24 attributes
    # -------------------------------------------------------------------------
    "rooms": {
        "collection_id": "rooms",
        "name": "Rooms",
        "description": "إدارة الغرف الفندقية",
        "cloud_fields": 25,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            "roomNumber": {"type": "string", "size": 50, "required": True, "description": "رقم الغرفة"},
            "floor": {"type": "integer", "required": False, "description": "الطابق"},
            "roomType": {"type": "string", "size": 100, "required": False, "description": "نوع الغرفة"},
            "status": {"type": "string", "size": 50, "required": True, "description": "الحالة"},
            "capacity": {"type": "integer", "required": False, "description": "السعة"},
            "basePrice": {"type": "double", "required": False, "description": "السعر الأساسي"},
            "currentPrice": {"type": "double", "required": False, "description": "السعر الحالي"},
            "features": {"type": "string", "size": 500, "required": False, "description": "المميزات"},
            "notes": {"type": "string", "size": 500, "required": False, "description": "ملاحظات"},
            "lastCleanedAt": {"type": "string", "size": 50, "required": False, "description": "آخر تنظيف"},
            "cleaningStatus": {"type": "string", "size": 50, "required": False, "description": "حالة التنظيف"},
            # Sync Fields
            "idempotencyKey": {"type": "string", "size": 255, "required": False, "description": "مفتاح idempotency للمزامنة"},
            # Maintenance
            "needsMaintenance": {"type": "boolean", "required": False, "description": "تحتاج صيانة"},
            "maintenanceReason": {"type": "string", "size": 255, "required": False, "description": "سبب الصيانة"},
            "maintenanceStartedAt": {"type": "integer", "required": False, "description": "بداية الصيانة"},
            # Booking Info
            "currentBookingUuid": {"type": "string", "size": 100, "required": False, "description": "UUID الحجز الحالي"},
            "currentGuestName": {"type": "string", "size": 200, "required": False, "description": "اسم النزيل الحالي"},
            "checkoutDate": {"type": "string", "size": 50, "required": False, "description": "تاريخ الخروج المتوقع"},
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "roomNumber", "type": "unique"},
            {"attribute": "status", "type": "key"},
            {"attribute": "floor", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 2. BOOKINGS (الحجوزات) - 45 attributes
    # -------------------------------------------------------------------------
    "bookings": {
        "collection_id": "bookings",
        "name": "Bookings",
        "description": "حجوزات الضيوف",
        "cloud_fields": 45,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            "roomNumber": {"type": "string", "size": 50, "required": True, "description": "رقم الغرفة"},
            "guestName": {"type": "string", "size": 200, "required": True, "description": "اسم النزيل"},
            "guestPhone": {"type": "string", "size": 20, "required": True, "description": "هاتف النزيل"},
            # Sync Fields
            "idempotencyKey": {"type": "string", "size": 255, "required": False, "description": "مفتاح idempotency للمزامنة"},
            "guestIdType": {"type": "string", "size": 100, "required": False, "description": "نوع الهوية"},
            "guestIdNumber": {"type": "string", "size": 50, "required": False, "description": "رقم الهوية"},
            "guestIdIssueDate": {"type": "string", "size": 50, "required": False, "description": "تاريخ إصدار الهوية"},
            "guestIdIssuePlace": {"type": "string", "size": 200, "required": False, "description": "مكان إصدار الهوية"},
            "guestNationality": {"type": "string", "size": 100, "required": True, "description": "الجنسية"},
            "guestEmail": {"type": "string", "size": 200, "required": False, "description": "البريد الإلكتروني"},
            "guestAddress": {"type": "string", "size": 500, "required": False, "description": "العنوان"},
            # Dates
            "checkinDate": {"type": "string", "size": 50, "required": True, "description": "تاريخ تسجيل الدخول"},
            "checkoutDate": {"type": "string", "size": 50, "required": False, "description": "تاريخ تسجيل الخروج المتوقع"},
            "actualCheckout": {"type": "string", "size": 50, "required": False, "description": "تاريخ الخروج الفعلي"},
            "stayDurationIso": {"type": "string", "size": 50, "required": False, "description": "مدة الإقامة ISO"},
            "lastNightEpoch": {"type": "integer", "required": False, "description": "آخر ليلة (epoch)"},
            # Status
            "status": {"type": "string", "size": 50, "required": True, "description": "الحالة"},
            "notes": {"type": "string", "size": 1000, "required": False, "description": "ملاحظات"},
            "isOverdue": {"type": "boolean", "required": False, "description": "متأخر"},
            "needsCheckoutReview": {"type": "boolean", "required": False, "description": "يحتاج مراجعة خروج"},
            "isFullyPaid": {"type": "boolean", "required": False, "description": "مكتمل الدفع"},
            # Hotel Day
            "hotelDayCheckin": {"type": "string", "size": 50, "required": False, "description": "يوم الفندق للدخول"},
            "hotelDayCheckout": {"type": "string", "size": 50, "required": False, "description": "يوم الفندق للخروج"},
            # Server IDs
            "serverBookingId": {"type": "integer", "required": False, "description": "معرف الحجز على السيرفر"},
            "serverRoomId": {"type": "integer", "required": False, "description": "معرف الغرفة على السيرفر"},
            # Pricing
            "totalAmount": {"type": "double", "required": False, "description": "المبلغ الإجمالي"},
            "paidAmount": {"type": "double", "required": False, "description": "المبلغ المدفوع"},
            "remainingAmount": {"type": "double", "required": False, "description": "المبلغ المتبقي"},
            "discountAmount": {"type": "double", "required": False, "description": "خصم"},
            "discountReason": {"type": "string", "size": 255, "required": False, "description": "سبب الخصم"},
            # Guest Info
            "guestInfoLocalUuid": {"type": "string", "size": 100, "required": False, "description": "UUID معلومات النزيل"},
            "serverGuestInfoId": {"type": "integer", "required": False, "description": "معرف معلومات النزيل"},
            # Additional
            "paymentStatus": {"type": "string", "size": 50, "required": False, "description": "حالة الدفع"},
            "autoFixApplied": {"type": "boolean", "required": False, "description": "تم تطبيق الإصلاح التلقائي"},
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "roomNumber", "type": "key"},
            {"attribute": "status", "type": "key"},
            {"attribute": "checkinDate", "type": "key"},
            {"attribute": "guestPhone", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 3. PAYMENTS (المدفوعات) - 32 attributes
    # -------------------------------------------------------------------------
    "payments": {
        "collection_id": "payments",
        "name": "Payments",
        "description": "مدفوعات الحجوزات والإيرادات",
        "cloud_fields": 32,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            # Sync Fields
            "idempotencyKey": {"type": "string", "size": 255, "required": False, "description": "مفتاح idempotency للمزامنة"},
            "serverPaymentId": {"type": "integer", "required": False, "description": "معرف الدفع على السيرفر"},
            "bookingLocalId": {"type": "integer", "required": False, "description": "معرف الحجز المحلي"},
            "serverBookingId": {"type": "integer", "required": False, "description": "معرف الحجز على السيرفر"},
            "roomNumber": {"type": "string", "size": 50, "required": False, "description": "رقم الغرفة"},
            "amount": {"type": "double", "required": True, "description": "المبلغ"},
            "paymentDate": {"type": "string", "size": 50, "required": True, "description": "تاريخ الدفع"},
            "notes": {"type": "string", "size": 500, "required": False, "description": "ملاحظات"},
            "paymentMethod": {"type": "string", "size": 100, "required": True, "description": "طريقة الدفع"},
            "revenueType": {"type": "string", "size": 100, "required": True, "description": "نوع الإيراد"},
            # Cash Transaction
            "cashTransactionLocalId": {"type": "integer", "required": False, "description": "معرف المعاملة النقدية"},
            "cashTransactionServerId": {"type": "integer", "required": False, "description": "معرف المعاملة على السيرفر"},
            "referenceNumber": {"type": "string", "size": 100, "required": False, "description": "رقم المرجع"},
            "hotelDayKey": {"type": "string", "size": 50, "required": False, "description": "يوم الفندق"},
            # Financial
            "isPendingBalance": {"type": "boolean", "required": False, "description": "أرصدة معلقة"},
            "linkedDebtUuid": {"type": "string", "size": 100, "required": False, "description": "UUID الدين المرتبط"},
            "bookingUuidCache": {"type": "string", "size": 100, "required": False, "description": "كاشف UUID الحجز"},
            # Void Fields
            "isVoided": {"type": "boolean", "required": False, "description": "ملغى"},
            "voidedAt": {"type": "integer", "required": False, "description": "وقت الإلغاء"},
            "voidedBy": {"type": "string", "size": 100, "required": False, "description": "من ألغى"},
            "voidReason": {"type": "string", "size": 255, "required": False, "description": "سبب الإلغاء"},
            "isImmutable": {"type": "boolean", "required": False, "description": "غير قابل للتعديل"},
            # Discount
            "discountAmount": {"type": "double", "required": False, "description": "مبلغ الخصم"},
            "discountStartDate": {"type": "datetime", "required": False, "description": "تاريخ بدء الخصم"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "bookingLocalId", "type": "key"},
            {"attribute": "paymentDate", "type": "key"},
            {"attribute": "hotelDayKey", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 4. EXPENSES (المصروفات) - 26 attributes
    # -------------------------------------------------------------------------
    "expenses": {
        "collection_id": "expenses",
        "name": "Expenses",
        "description": "مصروفات الفندق",
        "cloud_fields": 26,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            # Sync Fields
            "idempotencyKey": {"type": "string", "size": 255, "required": False, "description": "مفتاح idempotency للمزامنة"},
            "description": {"type": "string", "size": 500, "required": True, "description": "الوصف"},
            "amount": {"type": "double", "required": True, "description": "المبلغ"},
            "category": {"type": "string", "size": 100, "required": True, "description": "الفئة"},
            "expenseDate": {"type": "string", "size": 50, "required": True, "description": "تاريخ المصروف"},
            "vendor": {"type": "string", "size": 200, "required": False, "description": "المورد"},
            "notes": {"type": "string", "size": 500, "required": False, "description": "ملاحظات"},
            "receiptNumber": {"type": "string", "size": 100, "required": False, "description": "رقم الإيصال"},
            # Status
            "status": {"type": "string", "size": 50, "required": False, "description": "الحالة"},
            "isApproved": {"type": "boolean", "required": False, "description": "موافق عليه"},
            "approvedBy": {"type": "string", "size": 100, "required": False, "description": "موافق من"},
            "approvedAt": {"type": "integer", "required": False, "description": "وقت الموافقة"},
            # Payment
            "paymentMethod": {"type": "string", "size": 50, "required": False, "description": "طريقة الدفع"},
            "isPaid": {"type": "boolean", "required": False, "description": "مدفوع"},
            "paidAt": {"type": "integer", "required": False, "description": "وقت الدفع"},
            # Hotel Day
            "hotelDayKey": {"type": "string", "size": 50, "required": False, "description": "يوم الفندق"},
            "shiftId": {"type": "integer", "required": False, "description": "معرف الوردية"},
            # Cash Transaction
            "cashTransactionLocalId": {"type": "integer", "required": False, "description": "معرف المعاملة النقدية"},
            "cashTransactionServerId": {"type": "integer", "required": False, "description": "معرف المعاملة على السيرفر"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "category", "type": "key"},
            {"attribute": "expenseDate", "type": "key"},
            {"attribute": "hotelDayKey", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 5. SYNC LOGS (سجل المزامنة) - 28 attributes
    # -------------------------------------------------------------------------
    "sync_logs": {
        "collection_id": "sync_logs",
        "name": "Sync Logs",
        "description": "سجلات المزامنة",
        "cloud_fields": 28,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            "syncType": {"type": "string", "size": 50, "required": True, "description": "نوع المزامنة"},
            "direction": {"type": "string", "size": 50, "required": False, "description": "الاتجاه"},
            "status": {"type": "string", "size": 50, "required": True, "description": "الحالة"},
            "startedAt": {"type": "integer", "required": False, "description": "وقت البدء"},
            "completedAt": {"type": "integer", "required": False, "description": "وقت الانتهاء"},
            "duration": {"type": "integer", "required": False, "description": "المدة (ms)"},
            "recordsProcessed": {"type": "integer", "required": False, "description": "السجلات المعالجة"},
            "recordsFailed": {"type": "integer", "required": False, "description": "السجلات الفاشلة"},
            "errorMessage": {"type": "string", "size": 1000, "required": False, "description": "رسالة الخطأ"},
            "deviceId": {"type": "string", "size": 100, "required": False, "description": "معرف الجهاز"},
            "hotelDayKey": {"type": "string", "size": 50, "required": False, "description": "يوم الفندق"},
            "changesSummary": {"type": "string", "size": 2000, "required": False, "description": "ملخص التغييرات"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "startedAt", "type": "key"},
            {"attribute": "status", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 6. EMPLOYEES (الموظفون) - 22 attributes
    # -------------------------------------------------------------------------
    "employees": {
        "collection_id": "employees",
        "name": "Employees",
        "description": "موظفو الفندق",
        "cloud_fields": 22,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            # Sync Fields
            "idempotencyKey": {"type": "string", "size": 255, "required": False, "description": "مفتاح idempotency للمزامنة"},
            "name": {"type": "string", "size": 200, "required": True, "description": "الاسم"},
            "basicSalary": {"type": "double", "required": True, "description": "الراتب الأساسي"},
            "position": {"type": "string", "size": 100, "required": False, "description": "المنصب"},
            "phone": {"type": "string", "size": 20, "required": False, "description": "الهاتف"},
            "email": {"type": "string", "size": 200, "required": False, "description": "البريد الإلكتروني"},
            "address": {"type": "string", "size": 500, "required": False, "description": "العنوان"},
            "hireDate": {"type": "string", "size": 50, "required": False, "description": "تاريخ التعيين"},
            "terminationDate": {"type": "string", "size": 50, "required": False, "description": "تاريخ الإنهاء"},
            "status": {"type": "string", "size": 50, "required": True, "description": "الحالة"},
            "notes": {"type": "string", "size": 500, "required": False, "description": "ملاحظات"},
            # Personal Info
            "dateOfBirth": {"type": "string", "size": 50, "required": False, "description": "تاريخ الميلاد"},
            "nationality": {"type": "string", "size": 100, "required": False, "description": "الجنسية"},
            "idNumber": {"type": "string", "size": 50, "required": False, "description": "رقم الهوية"},
            "emergencyContact": {"type": "string", "size": 200, "required": False, "description": "جهة اتصال طارئة"},
            # Financial
            "totalPaid": {"type": "double", "required": False, "description": "إجمالي المدفوع"},
            "remainingSalary": {"type": "double", "required": False, "description": "الراتب المتبقي"},
            "allowances": {"type": "double", "required": False, "description": "البدلات"},
            "deductions": {"type": "double", "required": False, "description": "الخصومات"},
            # Work Schedule
            "workShift": {"type": "string", "size": 50, "required": False, "description": "الوردية"},
            "workDays": {"type": "string", "size": 50, "required": False, "description": "أيام العمل"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "phone", "type": "unique"},
            {"attribute": "status", "type": "key"},
            {"attribute": "position", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 7. GUEST INFOS (معلومات النزلاء) - 25 attributes
    # -------------------------------------------------------------------------
    "guest_infos": {
        "collection_id": "guest_infos",
        "name": "Guest Infos",
        "description": "معلومات النزلاء",
        "cloud_fields": 25,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            "name": {"type": "string", "size": 200, "required": True, "description": "الاسم"},
            "phone": {"type": "string", "size": 20, "required": False, "description": "الهاتف"},
            "idType": {"type": "string", "size": 100, "required": False, "description": "نوع الهوية"},
            "idNumber": {"type": "string", "size": 50, "required": False, "description": "رقم الهوية"},
            "nationality": {"type": "string", "size": 100, "required": False, "description": "الجنسية"},
            "email": {"type": "string", "size": 200, "required": False, "description": "البريد الإلكتروني"},
            "address": {"type": "string", "size": 500, "required": False, "description": "العنوان"},
            "notes": {"type": "string", "size": 500, "required": False, "description": "ملاحظات"},
            # ID Details
            "idIssueDate": {"type": "string", "size": 50, "required": False, "description": "تاريخ إصدار الهوية"},
            "idIssuePlace": {"type": "string", "size": 200, "required": False, "description": "مكان إصدار الهوية"},
            "dateOfBirth": {"type": "string", "size": 50, "required": False, "description": "تاريخ الميلاد"},
            # Stats
            "totalBookings": {"type": "integer", "required": False, "description": "إجمالي الحجوزات"},
            "totalSpent": {"type": "double", "required": False, "description": "إجمالي المصروف"},
            "totalNights": {"type": "integer", "required": False, "description": "إجمالي الليالي"},
            # Preferences
            "preferredRoomType": {"type": "string", "size": 100, "required": False, "description": "نوع الغرفة المفضل"},
            "specialRequests": {"type": "string", "size": 500, "required": False, "description": "طلبات خاصة"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "phone", "type": "key"},
            {"attribute": "idNumber", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 7. DEBTS (الديون) - 35 attributes
    # -------------------------------------------------------------------------
    "debts": {
        "collection_id": "debts",
        "name": "Debts",
        "description": "سجل الديون",
        "cloud_fields": 35,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            # Sync Fields
            "idempotencyKey": {"type": "string", "size": 255, "required": False, "description": "مفتاح idempotency للمزامنة"},
            "bookingUuid": {"type": "string", "size": 100, "required": False, "description": "UUID الحجز"},
            "bookingLocalId": {"type": "integer", "required": False, "description": "معرف الحجز المحلي"},
            "roomNumber": {"type": "string", "size": 50, "required": False, "description": "رقم الغرفة"},
            "guestName": {"type": "string", "size": 200, "required": False, "description": "اسم المدين"},
            "guestPhone": {"type": "string", "size": 20, "required": False, "description": "هاتف المدين"},
            "guestNationality": {"type": "string", "size": 100, "required": False, "description": "جنسية المدين"},
            # Guest ID
            "guestIdType": {"type": "string", "size": 100, "required": False, "description": "نوع هوية المدين"},
            "guestIdNumber": {"type": "string", "size": 50, "required": False, "description": "رقم هوية المدين"},
            # Debt Info
            "originalAmount": {"type": "double", "required": True, "description": "المبلغ الأصلي"},
            "remainingAmount": {"type": "double", "required": True, "description": "المبلغ المتبقي"},
            "paidAmount": {"type": "double", "required": False, "description": "المبلغ المدفوع"},
            "debtDate": {"type": "string", "size": 50, "required": True, "description": "تاريخ الدين"},
            "dueDate": {"type": "string", "size": 50, "required": False, "description": "تاريخ الاستحقاق"},
            "status": {"type": "string", "size": 50, "required": True, "description": "الحالة"},
            "debtType": {"type": "string", "size": 50, "required": False, "description": "نوع الدين"},
            "notes": {"type": "string", "size": 500, "required": False, "description": "ملاحظات"},
            # Hotel Day
            "hotelDayKey": {"type": "string", "size": 50, "required": False, "description": "يوم الفندق"},
            # Payment Tracking
            "lastPaymentDate": {"type": "string", "size": 50, "required": False, "description": "آخر تاريخ دفع"},
            "paymentCount": {"type": "integer", "required": False, "description": "عدد الدفعات"},
            # Payment Reference
            "lastPaymentAmount": {"type": "double", "required": False, "description": "آخر مبلغ مدفوع"},
            "lastPaymentMethod": {"type": "string", "size": 50, "required": False, "description": "آخر طريقة دفع"},
            # Server IDs
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            "serverBookingId": {"type": "integer", "required": False, "description": "معرف الحجز على السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "bookingUuid", "type": "key"},
            {"attribute": "status", "type": "key"},
            {"attribute": "guestPhone", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 8. DEVICES (الأجهزة) - 21 attributes
    # -------------------------------------------------------------------------
    "devices": {
        "collection_id": "devices",
        "name": "Devices",
        "description": "الأجهزة المسجلة",
        "cloud_fields": 21,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            "deviceId": {"type": "string", "size": 200, "required": True, "description": "معرف الجهاز"},
            "deviceName": {"type": "string", "size": 200, "required": False, "description": "اسم الجهاز"},
            "deviceType": {"type": "string", "size": 50, "required": False, "description": "نوع الجهاز"},
            "os": {"type": "string", "size": 50, "required": False, "description": "نظام التشغيل"},
            "appVersion": {"type": "string", "size": 50, "required": False, "description": "إصدار التطبيق"},
            "lastSyncTime": {"type": "integer", "required": False, "description": "آخر وقت مزامنة"},
            "isActive": {"type": "boolean", "required": False, "description": "نشط"},
            "registeredAt": {"type": "integer", "required": False, "description": "تاريخ التسجيل"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "deviceId", "type": "unique"},
        ],
    },

    # -------------------------------------------------------------------------
    # 9. CASH TRANSACTIONS (المعاملات النقدية) - 24 attributes
    # -------------------------------------------------------------------------
    "cash_transactions": {
        "collection_id": "cash_transactions",
        "name": "Cash Transactions",
        "description": "المعاملات النقدية",
        "cloud_fields": 24,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            # Sync Fields
            "idempotencyKey": {"type": "string", "size": 255, "required": False, "description": "مفتاح idempotency للمزامنة"},
            "registerId": {"type": "integer", "required": False, "description": "معرف الدرج"},
            "transactionType": {"type": "string", "size": 50, "required": True, "description": "نوع المعاملة"},
            "amount": {"type": "double", "required": True, "description": "المبلغ"},
            "referenceType": {"type": "string", "size": 50, "required": False, "description": "نوع المرجع"},
            "referenceId": {"type": "integer", "required": False, "description": "معرف المرجع"},
            "description": {"type": "string", "size": 500, "required": False, "description": "الوصف"},
            "transactionTime": {"type": "string", "size": 50, "required": True, "description": "وقت المعاملة"},
            "createdBy": {"type": "integer", "required": False, "description": "منشئ المعاملة"},
            # Hotel Day
            "hotelDayKey": {"type": "string", "size": 50, "required": False, "description": "يوم الفندق"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "hotelDayKey", "type": "key"},
            {"attribute": "transactionType", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 10. BOOKING NOTES (ملاحظات الحجوزات) - 21 attributes
    # -------------------------------------------------------------------------
    "booking_notes": {
        "collection_id": "booking_notes",
        "name": "Booking Notes",
        "description": "ملاحظات الحجوزات",
        "cloud_fields": 21,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            # Sync Fields
            "idempotencyKey": {"type": "string", "size": 255, "required": False, "description": "مفتاح idempotency للمزامنة"},
            "bookingLocalUuid": {"type": "string", "size": 100, "required": False, "description": "UUID الحجز"},
            "bookingLocalId": {"type": "integer", "required": False, "description": "معرف الحجز المحلي"},
            "noteText": {"type": "string", "size": 1000, "required": True, "description": "نص الملاحظة"},
            "noteType": {"type": "string", "size": 50, "required": False, "description": "نوع الملاحظة"},
            "alertType": {"type": "string", "size": 50, "required": False, "description": "نوع التنبيه"},
            "alertUntil": {"type": "string", "size": 50, "required": False, "description": "صلاحية التنبيه"},
            "isActive": {"type": "boolean", "required": False, "description": "نشط"},
            "createdBy": {"type": "string", "size": 100, "required": False, "description": "منشئ الملاحظة"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "bookingLocalId", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 11. BOOKING NIGHTS (ليالي الحجوزات) - 22 attributes
    # -------------------------------------------------------------------------
    "booking_nights": {
        "collection_id": "booking_nights",
        "name": "Booking Nights",
        "description": "ليالي الحجوزات",
        "cloud_fields": 22,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            "bookingLocalUuid": {"type": "string", "size": 100, "required": False, "description": "UUID الحجز"},
            "bookingLocalId": {"type": "integer", "required": False, "description": "معرف الحجز المحلي"},
            "roomNumber": {"type": "string", "size": 50, "required": False, "description": "رقم الغرفة"},
            "hotelDayKey": {"type": "string", "size": 50, "required": True, "description": "يوم الفندق"},
            "nightDate": {"type": "string", "size": 50, "required": False, "description": "تاريخ الليلة"},
            "nightStart": {"type": "string", "size": 50, "required": False, "description": "بداية الليلة"},
            "nightEnd": {"type": "string", "size": 50, "required": False, "description": "نهاية الليلة"},
            "sequence": {"type": "integer", "required": False, "description": "التسلسل"},
            # Pricing
            "baseRate": {"type": "double", "required": False, "description": "السعر الأساسي"},
            "nightlyRate": {"type": "double", "required": False, "description": "السعر الليلي"},
            "adjustment": {"type": "double", "required": False, "description": "التعديل"},
            "finalRate": {"type": "double", "required": False, "description": "السعر النهائي"},
            # Adjustments
            "appliedAdjustmentUuid": {"type": "string", "size": 100, "required": False, "description": "UUID التعديل المطبق"},
            "appliedAdjustmentsJson": {"type": "string", "size": 1000, "required": False, "description": "JSON التعديلات"},
            # Status
            "isProcessedByAutoFix": {"type": "boolean", "required": False, "description": "معالج بواسطة الإصلاح التلقائي"},
            "status": {"type": "string", "size": 50, "required": False, "description": "الحالة"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "bookingLocalId", "type": "key"},
            {"attribute": "hotelDayKey", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 12. SALARY CYCLES (دورات الرواتب) - 23 attributes
    # -------------------------------------------------------------------------
    "salary_cycles": {
        "collection_id": "salary_cycles",
        "name": "Salary Cycles",
        "description": "دورات الرواتب",
        "cloud_fields": 23,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            "employeeLocalUuid": {"type": "string", "size": 100, "required": False, "description": "UUID الموظف"},
            "employeeId": {"type": "integer", "required": True, "description": "معرف الموظف"},
            "cycleKey": {"type": "string", "size": 50, "required": True, "description": "مفتاح الدورة"},
            "hotelDayStart": {"type": "string", "size": 50, "required": False, "description": "بداية الدورة"},
            "hotelDayEnd": {"type": "string", "size": 50, "required": False, "description": "نهاية الدورة"},
            "expectedAmount": {"type": "integer", "required": False, "description": "المبلغ المتوقع"},
            "actualPaid": {"type": "integer", "required": False, "description": "المبلغ الفعلي"},
            "remainingAmount": {"type": "integer", "required": False, "description": "المبلغ المتبقي"},
            "status": {"type": "string", "size": 50, "required": True, "description": "الحالة"},
            "notes": {"type": "string", "size": 500, "required": False, "description": "ملاحظات"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "employeeId", "type": "key"},
            {"attribute": "cycleKey", "type": "unique"},
        ],
    },

    # -------------------------------------------------------------------------
    # 13. SALARY PAYMENTS (مدفوعات الرواتب) - 22 attributes
    # -------------------------------------------------------------------------
    "salary_payments": {
        "collection_id": "salary_payments",
        "name": "Salary Payments",
        "description": "مدفوعات الرواتب",
        "cloud_fields": 22,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            # Sync Fields
            "idempotencyKey": {"type": "string", "size": 255, "required": False, "description": "مفتاح idempotency للمزامنة"},
            "cycleLocalUuid": {"type": "string", "size": 100, "required": False, "description": "UUID الدورة"},
            "cycleId": {"type": "integer", "required": True, "description": "معرف دورة الراتب"},
            "employeeId": {"type": "integer", "required": False, "description": "معرف الموظف"},
            "amount": {"type": "integer", "required": True, "description": "المبلغ"},
            "hotelDayKey": {"type": "string", "size": 50, "required": False, "description": "يوم الفندق"},
            "paymentDateIso": {"type": "string", "size": 50, "required": True, "description": "تاريخ الدفع"},
            "method": {"type": "string", "size": 50, "required": False, "description": "طريقة الدفع"},
            "notes": {"type": "string", "size": 500, "required": False, "description": "ملاحظات"},
            "isAutoGenerated": {"type": "boolean", "required": False, "description": "مُنشأ تلقائياً"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "cycleId", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 14. SALARY WITHDRAWALS (سحوبات الرواتب) - 24 attributes
    # -------------------------------------------------------------------------
    "salary_withdrawals": {
        "collection_id": "salary_withdrawals",
        "name": "Salary Withdrawals",
        "description": "سحوبات الرواتب",
        "cloud_fields": 24,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            "employeeLocalUuid": {"type": "string", "size": 100, "required": False, "description": "UUID الموظف"},
            "employeeId": {"type": "integer", "required": True, "description": "معرف الموظف"},
            "amount": {"type": "double", "required": True, "description": "المبلغ"},
            "reason": {"type": "string", "size": 500, "required": False, "description": "السبب"},
            "withdrawalDate": {"type": "string", "size": 50, "required": True, "description": "تاريخ السحب"},
            "hotelDayKey": {"type": "string", "size": 50, "required": False, "description": "يوم الفندق"},
            "requestedBy": {"type": "string", "size": 100, "required": False, "description": "مطلوب من"},
            "approvedBy": {"type": "string", "size": 100, "required": False, "description": "موافق من"},
            "status": {"type": "string", "size": 50, "required": False, "description": "الحالة"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "employeeId", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 15. BOOKING PRICE ADJUSTMENTS (تعديلات أسعار الحجوزات) - 18 attributes
    # -------------------------------------------------------------------------
    "booking_price_adjustments": {
        "collection_id": "booking_price_adjustments",
        "name": "Booking Price Adjustments",
        "description": "تعديلات أسعار الحجوزات",
        "cloud_fields": 18,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            "bookingLocalUuid": {"type": "string", "size": 100, "required": False, "description": "UUID الحجز"},
            "bookingLocalId": {"type": "integer", "required": False, "description": "معرف الحجز"},
            "roomNumber": {"type": "string", "size": 50, "required": False, "description": "رقم الغرفة"},
            "adjustmentType": {"type": "integer", "required": True, "description": "نوع التعديل"},
            "adjustmentMode": {"type": "string", "size": 50, "required": False, "description": "وضع التعديل"},
            "amount": {"type": "double", "required": True, "description": "المبلغ"},
            "effectiveHotelDay": {"type": "string", "size": 50, "required": True, "description": "يوم الفندق الفعال"},
            "endHotelDay": {"type": "string", "size": 50, "required": False, "description": "يوم انتهاء الصلاحية"},
            "isActive": {"type": "boolean", "required": False, "description": "نشط"},
            "reason": {"type": "string", "size": 255, "required": False, "description": "السبب"},
            "appliedBy": {"type": "string", "size": 100, "required": False, "description": "من طبّق"},
            "appliedAt": {"type": "integer", "required": False, "description": "وقت التطبيق"},
            "cancelledAt": {"type": "integer", "required": False, "description": "تاريخ الإلغاء"},
            "cancelledBy": {"type": "string", "size": 100, "required": False, "description": "من ألغى"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "bookingLocalId", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 16. HOTEL DAY LEDGER (دفتر يوم الفندق) - 25 attributes
    # -------------------------------------------------------------------------
    "hotel_day_ledger": {
        "collection_id": "hotel_day_ledger",
        "name": "Hotel Day Ledger",
        "description": "دفتر يوم الفندق",
        "cloud_fields": 25,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            "hotelDayKey": {"type": "string", "size": 50, "required": True, "description": "مفتاح يوم الفندق"},
            "hotelDayDate": {"type": "string", "size": 50, "required": False, "description": "تاريخ يوم الفندق"},
            # Financial
            "totalIncome": {"type": "double", "required": False, "description": "إجمالي الدخل"},
            "totalExpenses": {"type": "double", "required": False, "description": "إجمالي المصروفات"},
            "pendingBalances": {"type": "double", "required": False, "description": "الأرصدة المعلقة"},
            "netProfit": {"type": "double", "required": False, "description": "صافي الربح"},
            # Occupancy
            "totalRooms": {"type": "integer", "required": False, "description": "إجمالي الغرف"},
            "occupiedRooms": {"type": "integer", "required": False, "description": "الغرف المشغولة"},
            "vacantRooms": {"type": "integer", "required": False, "description": "الغرف الشاغرة"},
            "occupancyRate": {"type": "double", "required": False, "description": "نسبة الإشغال"},
            # Counts
            "bookingsProcessed": {"type": "integer", "required": False, "description": "عدد الحجز المعالجة"},
            "checkins": {"type": "integer", "required": False, "description": "تسجيلات الدخول"},
            "checkouts": {"type": "integer", "required": False, "description": "تسجيلات الخروج"},
            "cancelledBookings": {"type": "integer", "required": False, "description": "الحجوزات الملغاة"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "hotelDayKey", "type": "unique"},
        ],
    },

    # -------------------------------------------------------------------------
    # 15. OUTBOX (الصندوق الصادر) - 12 attributes (Local Only)
    # -------------------------------------------------------------------------
    "outbox": {
        "collection_id": "outbox",
        "name": "Outbox",
        "description": "صندوق المزامنة المحلي (محلي فقط)",
        "cloud_fields": 12,
        "fields": {
            # Local Only Fields (not synced to cloud)
            "id": {"type": "integer", "required": True, "description": "معرف محلي"},
            "entity": {"type": "string", "size": 50, "required": True, "description": "نوع الكيان"},
            "op": {"type": "string", "size": 20, "required": True, "description": "العملية (create/update/delete)"},
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID المحلي"},
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            "payload": {"type": "string", "size": 10000, "required": False, "description": "البيانات"},
            "clientTs": {"type": "integer", "required": True, "description": "وقت العميل"},
            "serverTs": {"type": "integer", "required": False, "description": "وقت السيرفر"},
            "status": {"type": "string", "size": 50, "required": True, "description": "الحالة"},
            "attempts": {"type": "integer", "required": False, "description": "عدد المحاولات"},
            "lastError": {"type": "string", "size": 1000, "required": False, "description": "آخر خطأ"},
            "processingStatus": {"type": "string", "size": 50, "required": False, "description": "حالة المعالجة"},
            "processingStartedAt": {"type": "integer", "required": False, "description": "بداية المعالجة"},
            "processingWorker": {"type": "string", "size": 100, "required": False, "description": "عامل المعالجة"},
        },
        "indexes": [
            {"attribute": "id", "type": "unique"},
            {"attribute": "status", "type": "key"},
            {"attribute": "clientTs", "type": "key"},
        ],
        "note": "هذا الجدول محلي فقط ولا يُزامن للكلاود",
    },

    # -------------------------------------------------------------------------
    # 16. SYNC STATE (حالة المزامنة) - 10 attributes (Local Only)
    # -------------------------------------------------------------------------
    "sync_state": {
        "collection_id": "sync_state",
        "name": "Sync State",
        "description": "حالة المزامنة (محلي فقط)",
        "cloud_fields": 10,
        "fields": {
            # Basic Fields
            "id": {"type": "integer", "required": True, "description": "معرف"},
            "entityType": {"type": "string", "size": 50, "required": True, "description": "نوع الكيان"},
            "lastSyncedAt": {"type": "integer", "required": False, "description": "آخر مزامنة"},
            "lastSyncedClientTs": {"type": "integer", "required": False, "description": "آخر وقت عميل"},
            "lastSyncedServerTs": {"type": "integer", "required": False, "description": "آخر وقت سيرفر"},
            "pendingCount": {"type": "integer", "required": False, "description": "عدد المعلق"},
            "failedCount": {"type": "integer", "required": False, "description": "عدد الفاشل"},
            "lastError": {"type": "string", "size": 500, "required": False, "description": "آخر خطأ"},
            "vectorClock": {"type": "string", "size": 500, "required": False, "description": "ساعة المتجهات"},
        },
        "indexes": [
            {"attribute": "id", "type": "unique"},
            {"attribute": "entityType", "type": "unique"},
        ],
        "note": "هذا الجدول محلي فقط ولا يُزامن للكلاود",
    },

    # -------------------------------------------------------------------------
    # 18. SHIFT NOTES (ملاحظات الورديات) - 23 attributes
    # -------------------------------------------------------------------------
    "shift_notes": {
        "collection_id": "shift_notes",
        "name": "Shift Notes",
        "description": "ملاحظات الورديات",
        "cloud_fields": 23,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            # Sync Fields
            "idempotencyKey": {"type": "string", "size": 255, "required": False, "description": "مفتاح idempotency للمزامنة"},
            "title": {"type": "string", "size": 200, "required": True, "description": "العنوان"},
            "content": {"type": "string", "size": 2000, "required": False, "description": "المحتوى"},
            "priority": {"type": "string", "size": 50, "required": False, "description": "الأولوية"},
            "shiftType": {"type": "string", "size": 50, "required": False, "description": "نوع الوردية"},
            "shiftId": {"type": "integer", "required": False, "description": "معرف الوردية"},
            "isRead": {"type": "boolean", "required": False, "description": "مقروء"},
            "expiresAt": {"type": "string", "size": 50, "required": False, "description": "تاريخ الانتهاء"},
            "createdBy": {"type": "string", "size": 100, "required": True, "description": "منشئ الملاحظة"},
            "category": {"type": "string", "size": 100, "required": False, "description": "الفئة"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "shiftId", "type": "key"},
            {"attribute": "priority", "type": "key"},
        ],
    },

    # -------------------------------------------------------------------------
    # 19. BLACKLIST (القائمة السوداء) - 11 attributes
    # -------------------------------------------------------------------------
    "blacklist": {
        "collection_id": "blacklist",
        "name": "Blacklist",
        "description": "القائمة السوداء للنزلاء",
        "cloud_fields": 11,
        "fields": {
            # Basic Fields
            "localUuid": {"type": "string", "size": 100, "required": True, "description": "UUID فريد"},
            "name": {"type": "string", "size": 200, "required": True, "description": "الاسم"},
            "phone": {"type": "string", "size": 20, "required": False, "description": "الهاتف"},
            "nationalId": {"type": "string", "size": 50, "required": False, "description": "رقم الهوية"},
            "nationality": {"type": "string", "size": 100, "required": False, "description": "الجنسية"},
            "reason": {"type": "string", "size": 500, "required": False, "description": "السبب"},
            "notes": {"type": "string", "size": 1000, "required": False, "description": "ملاحظات"},
            "reportedBy": {"type": "string", "size": 100, "required": True, "description": "المُبلّغ"},
            "active": {"type": "boolean", "required": False, "description": "نشط"},
            "createdAt": {"type": "integer", "required": False, "description": "تاريخ الإنشاء"},
            # Server
            "serverId": {"type": "integer", "required": False, "description": "معرف السيرفر"},
            # Sync Fields (included)
        },
        "indexes": [
            {"attribute": "localUuid", "type": "unique"},
            {"attribute": "phone", "type": "key"},
            {"attribute": "nationalId", "type": "key"},
        ],
    },
}


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def get_collection_fields(collection_name: str) -> dict:
    """Get all fields for a collection including SyncFields"""
    collection = COLLECTIONS.get(collection_name, {})
    fields = collection.get("fields", {}).copy()
    # Add sync fields to all collections except outbox and sync_state
    if collection_name not in ["outbox", "sync_state"]:
        fields.update(SYNC_FIELDS)
    return fields


def get_collection_field_count(collection_name: str) -> int:
    """Get total field count including sync fields"""
    return len(get_collection_fields(collection_name))


def print_collection_summary():
    """Print summary of all collections"""
    print("=" * 70)
    print("📋 Appwrite Schema Summary - Marina Hotel Mobile")
    print("=" * 70)
    print()
    
    for name, info in COLLECTIONS.items():
        field_count = get_collection_field_count(name)
        index_count = len(info.get("indexes", []))
        print(f"  📦 {name:30} | {field_count:3} fields | {index_count:2} indexes")
    
    print()
    print("=" * 70)
    print(f"Total Collections: {len(COLLECTIONS)}")
    print(f"Sync Fields per Collection: {len(SYNC_FIELDS)}")
    print("=" * 70)


def generate_create_collection_script():
    """Generate Appwrite CLI script for creating collections"""
    script = []
    for name, info in COLLECTIONS.items():
        script.append(f"# Create {name} collection")
        script.append(f"appwrite databases create-collection \\\\\n  --databaseId hotel_db \\\\\n  --collectionId {info['collection_id']} \\\\\n  --name \"{info['name']}\" \\\\\n  --documentSecurity false")
        script.append("")
    return "\n".join(script)


# =============================================================================
# MAIN
# =============================================================================

if __name__ == "__main__":
    print_collection_summary()
    print()
    print("To generate Appwrite CLI script, run:")
    print("  python appwrite_schema.py --generate-cli")
