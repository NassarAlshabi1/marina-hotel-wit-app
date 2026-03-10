/**
 * ============================================
 * 🔧 سكربت تحديث حقول Appwrite من snake_case إلى camelCase
 * ============================================
 * 
 * هذا السكربت يقوم بـ:
 * 1. فحص جميع Collections في قاعدة البيانات
 * 2. تحديد الحقول بصيغة snake_case
 * 3. إضافة النسخ camelCase المقابلة
 * 4. التحقق من اكتمال العملية
 * 
 * ملاحظة: Appwrite لا يسمح بإعادة تسمية الحقول، لذا نضيف النسخ الجديدة
 */

const { Client, Databases } = require('node-appwrite');

// ============================================
// ⚙️ إعدادات الاتصال
// ============================================
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';
const DATABASE_ID = 'hotel_db';

// ============================================
// 📋 تعريف الـ Collections
// ============================================
const COLLECTIONS = [
    'rooms',
    'bookings',
    'payments',
    'expenses',
    'employees',
    'debts',
    'booking_notes',
    'booking_nights',
    'cash_transactions',
    'salary_cycles',
    'salary_payments',
    'shift_notes',
    'hotel_day_ledger',
    'devices',
    'sync_logs'
];

// ============================================
// 🔄 خريطة التحويل من snake_case إلى camelCase
// ============================================
const SNAKE_TO_CAMEL_MAP = {
    // Sync fields - الأكثر استخداماً
    'local_uuid': 'localUuid',
    'server_id': 'serverId',
    'created_at': 'createdAt',
    'updated_at': 'updatedAt',
    'deleted_at': 'deletedAt',
    'last_modified': 'lastModified',
    'last_modified_epoch': 'lastModifiedEpoch',
    'created_at_iso': 'createdAtIso',
    'updated_at_iso': 'updatedAtIso',
    'deleted_at_iso': 'deletedAtIso',
    'created_at_epoch': 'createdAtEpoch',
    'vector_clock': 'vectorClock',
    'idempotency_key': 'idempotencyKey',
    
    // Booking fields
    'server_booking_id': 'serverBookingId',
    'room_number': 'roomNumber',
    'guest_name': 'guestName',
    'guest_phone': 'guestPhone',
    'guest_id_type': 'guestIdType',
    'guest_id_number': 'guestIdNumber',
    'guest_id_issue_date': 'guestIdIssueDate',
    'guest_id_issue_place': 'guestIdIssuePlace',
    'guest_nationality': 'guestNationality',
    'guest_email': 'guestEmail',
    'guest_address': 'guestAddress',
    'checkin_date': 'checkinDate',
    'checkout_date': 'checkoutDate',
    'actual_checkout': 'actualCheckout',
    'hotel_day_checkin': 'hotelDayCheckin',
    'hotel_day_checkout': 'hotelDayCheckout',
    'stay_duration_iso': 'stayDurationIso',
    'last_night_epoch': 'lastNightEpoch',
    'is_overdue': 'isOverdue',
    'needs_checkout_review': 'needsCheckoutReview',
    'total_due_cached': 'totalDueCached',
    'total_paid_cached': 'totalPaidCached',
    'remaining_balance_cached': 'remainingBalanceCached',
    'is_fully_paid': 'isFullyPaid',
    'expected_nights': 'expectedNights',
    'calculated_nights': 'calculatedNights',
    'total_nights_cached': 'totalNightsCached',
    
    // Payment fields
    'server_payment_id': 'serverPaymentId',
    'booking_local_id': 'bookingLocalId',
    'server_booking_id': 'serverBookingId',
    'payment_date': 'paymentDate',
    'payment_method': 'paymentMethod',
    'revenue_type': 'revenueType',
    'cash_transaction_local_id': 'cashTransactionLocalId',
    'cash_transaction_server_id': 'cashTransactionServerId',
    'reference_number': 'referenceNumber',
    'hotel_day_key': 'hotelDayKey',
    'is_pending_balance': 'isPendingBalance',
    'linked_debt_uuid': 'linkedDebtUuid',
    'booking_uuid_cache': 'bookingUuidCache',
    
    // Room fields
    'room_number': 'roomNumber',
    'room_type': 'roomType',
    'image_url': 'imageUrl',
    'cleaning_status': 'cleaningStatus',
    'last_cleaned_hotel_day': 'lastCleanedHotelDay',
    'last_occupied_hotel_day': 'lastOccupiedHotelDay',
    'requires_maintenance': 'requiresMaintenance',
    'base_price': 'basePrice',
    'beds_count': 'bedsCount',
    'last_cleaning_time': 'lastCleaningTime',
    
    // Employee fields
    'employee_id': 'employeeId',
    'employee_name': 'employeeName',
    'phone_number': 'phoneNumber',
    'start_date': 'startDate',
    'end_date': 'endDate',
    'daily_salary': 'dailySalary',
    'monthly_salary': 'monthlySalary',
    
    // Debt fields
    'debt_uuid': 'debtUuid',
    'guest_name': 'guestName',
    'guest_phone': 'guestPhone',
    'total_amount': 'totalAmount',
    'paid_amount': 'paidAmount',
    'remaining_amount': 'remainingAmount',
    'start_date': 'startDate',
    'due_date': 'dueDate',
    'is_paid': 'isPaid',
    'booking_uuid': 'bookingUuid',
    
    // Expense fields
    'expense_id': 'expenseId',
    'expense_date': 'expenseDate',
    'expense_category': 'expenseCategory',
    'expense_amount': 'expenseAmount',
    
    // Device fields
    'device_id': 'deviceId',
    'device_name': 'deviceName',
    'device_type': 'deviceType',
    'last_active': 'lastActive',
    
    // Sync log fields
    'sync_id': 'syncId',
    'sync_type': 'syncType',
    'start_time': 'startTime',
    'end_time': 'endTime',
    'error_message': 'errorMessage',
    
    // Cash transaction fields
    'transaction_id': 'transactionId',
    'transaction_type': 'transactionType',
    'transaction_date': 'transactionDate',
    'transaction_time': 'transactionTime',
    'transaction_amount': 'transactionAmount',
    
    // Booking notes
    'note_id': 'noteId',
    'note_text': 'noteText',
    'note_date': 'noteDate',
    
    // Booking nights
    'night_date': 'nightDate',
    'night_price': 'nightPrice',
    'hotel_day': 'hotelDay',
    
    // Salary fields
    'salary_cycle_id': 'salaryCycleId',
    'salary_payment_id': 'salaryPaymentId',
    'cycle_start': 'cycleStart',
    'cycle_end': 'cycleEnd',
    'payment_date': 'paymentDate',
    'payment_amount': 'paymentAmount',
    'withdrawal_amount': 'withdrawalAmount',
    
    // Shift notes
    'shift_id': 'shiftId',
    'shift_date': 'shiftDate',
    'shift_notes': 'shiftNotes',
    
    // Hotel day ledger
    'ledger_id': 'ledgerId',
    'ledger_date': 'ledgerDate',
    'total_revenue': 'totalRevenue',
    'total_expenses': 'totalExpenses',
    'net_profit': 'netProfit',
    'room_revenue': 'roomRevenue',
    'occupancy_rate': 'occupancyRate'
};

// ============================================
// 🔧 دوال مساعدة
// ============================================

/**
 * تحويل snake_case إلى camelCase
 */
function snakeToCamel(str) {
    return str.replace(/_([a-z])/g, (match, letter) => letter.toUpperCase());
}

/**
 * التحقق من أن الحقل بصيغة snake_case
 */
function isSnakeCase(key) {
    return key.includes('_') && key === key.toLowerCase();
}

/**
 * الحصول على نوع الحقل من Appwrite
 */
function getAttributeType(attr) {
    if (attr.type === 'string') return 'string';
    if (attr.type === 'integer') return 'integer';
    if (attr.type === 'double' || attr.type === 'float') return 'double';
    if (attr.type === 'boolean') return 'boolean';
    if (attr.type === 'datetime') return 'datetime';
    return 'string';
}

// ============================================
// 📊 الفحص الرئيسي
// ============================================

const client = new Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new Databases(client);

async function scanCollections() {
    console.log('\n' + '='.repeat(80));
    console.log('🔍 فحص جميع Collections للبحث عن حقول snake_case');
    console.log('='.repeat(80) + '\n');
    
    const results = {
        totalCollections: 0,
        totalSnakeCaseFields: 0,
        totalCamelCaseMissing: 0,
        collections: []
    };
    
    for (const collectionId of COLLECTIONS) {
        try {
            const attrs = await databases.listAttributes(DATABASE_ID, collectionId);
            const available = attrs.attributes.filter(a => !a.status || a.status === 'available');
            const processing = attrs.attributes.filter(a => a.status === 'processing');
            
            const existingKeys = available.map(a => a.key);
            const snakeCaseFields = available.filter(a => isSnakeCase(a.key));
            
            const missingCamelCase = [];
            
            for (const snakeField of snakeCaseFields) {
                const camelKey = SNAKE_TO_CAMEL_MAP[snakeField.key] || snakeToCamel(snakeField.key);
                
                if (!existingKeys.includes(camelKey)) {
                    missingCamelCase.push({
                        snakeKey: snakeField.key,
                        camelKey: camelKey,
                        type: getAttributeType(snakeField),
                        size: snakeField.size || 255,
                        required: snakeField.required || false
                    });
                }
            }
            
            results.collections.push({
                id: collectionId,
                totalFields: available.length,
                processing: processing.length,
                snakeCaseCount: snakeCaseFields.length,
                missingCamelCase: missingCamelCase
            });
            
            results.totalCollections++;
            results.totalSnakeCaseFields += snakeCaseFields.length;
            results.totalCamelCaseMissing += missingCamelCase.length;
            
            // عرض النتائج
            const status = missingCamelCase.length === 0 ? '✅' : 
                          processing.length > 0 ? '⏳' : '⚠️';
            
            console.log(`${status} ${collectionId.padEnd(22)} | الحقول: ${String(available.length).padStart(3)} | snake_case: ${String(snakeCaseFields.length).padStart(2)} | مفقود camelCase: ${String(missingCamelCase.length).padStart(2)}`);
            
            if (processing.length > 0) {
                console.log(`   ⏳ قيد المعالجة: ${processing.map(a => a.key).join(', ')}`);
            }
            
            if (missingCamelCase.length > 0 && missingCamelCase.length <= 5) {
                console.log(`   📝 تحتاج: ${missingCamelCase.map(f => f.camelKey).join(', ')}`);
            } else if (missingCamelCase.length > 5) {
                console.log(`   📝 تحتاج: ${missingCamelCase.slice(0, 5).map(f => f.camelKey).join(', ')}... (+${missingCamelCase.length - 5} أكثر)`);
            }
            
        } catch (error) {
            console.log(`❌ ${collectionId.padEnd(22)} | خطأ: ${error.message}`);
        }
    }
    
    return results;
}

async function addMissingCamelCaseFields(results, dryRun = true) {
    console.log('\n' + '='.repeat(80));
    console.log(dryRun ? '📋 معاينة التغييرات (Dry Run)' : '🔧 إضافة الحقول المفقودة');
    console.log('='.repeat(80) + '\n');
    
    let totalToAdd = 0;
    let totalCreated = 0;
    let totalFailed = 0;
    
    for (const collection of results.collections) {
        if (collection.missingCamelCase.length === 0) continue;
        
        console.log(`\n📦 ${collection.id}:`);
        totalToAdd += collection.missingCamelCase.length;
        
        for (const field of collection.missingCamelCase) {
            if (dryRun) {
                console.log(`   📝 سيتم إضافة: ${field.camelKey} (${field.type})`);
            } else {
                try {
                    if (field.type === 'integer') {
                        await databases.createIntegerAttribute(
                            DATABASE_ID, collection.id, field.camelKey, field.required
                        );
                    } else if (field.type === 'double') {
                        await databases.createFloatAttribute(
                            DATABASE_ID, collection.id, field.camelKey, field.required
                        );
                    } else if (field.type === 'boolean') {
                        await databases.createBooleanAttribute(
                            DATABASE_ID, collection.id, field.camelKey, field.required
                        );
                    } else if (field.type === 'datetime') {
                        await databases.createDatetimeAttribute(
                            DATABASE_ID, collection.id, field.camelKey, field.required
                        );
                    } else {
                        await databases.createStringAttribute(
                            DATABASE_ID, collection.id, field.camelKey, field.size || 500, field.required
                        );
                    }
                    console.log(`   ✅ ${field.camelKey} - تم الإنشاء`);
                    totalCreated++;
                    await new Promise(r => setTimeout(r, 300)); // Rate limiting
                } catch (error) {
                    if (error.code === 409) {
                        console.log(`   ⏭️  ${field.camelKey} - موجود مسبقاً`);
                    } else {
                        console.log(`   ❌ ${field.camelKey} - خطأ: ${error.message}`);
                        totalFailed++;
                    }
                }
            }
        }
    }
    
    console.log('\n' + '-'.repeat(80));
    console.log(`📊 الملخص:`);
    console.log(`   - إجمالي الحقول للإضافة: ${totalToAdd}`);
    if (!dryRun) {
        console.log(`   - تم إنشاء: ${totalCreated}`);
        console.log(`   - فشل: ${totalFailed}`);
    }
    
    return { totalToAdd, totalCreated, totalFailed };
}

async function main() {
    console.log('\n╔══════════════════════════════════════════════════════════════════════════════╗');
    console.log('║  🔧 سكربت تحديث حقول Appwrite من snake_case إلى camelCase                    ║');
    console.log('║  📅 التاريخ: ' + new Date().toLocaleString('ar-EG') + '                                           ║');
    console.log('╚══════════════════════════════════════════════════════════════════════════════╝');
    
    // الخطوة 1: فحص Collections
    const scanResults = await scanCollections();
    
    console.log('\n' + '='.repeat(80));
    console.log('📊 ملخص الفحص:');
    console.log(`   - عدد Collections المفحوصة: ${scanResults.totalCollections}`);
    console.log(`   - إجمالي حقول snake_case: ${scanResults.totalSnakeCaseFields}`);
    console.log(`   - حقول camelCase مفقودة: ${scanResults.totalCamelCaseMissing}`);
    
    // الخطوة 2: عرض التغييرات المقترحة (Dry Run)
    if (scanResults.totalCamelCaseMissing > 0) {
        await addMissingCamelCaseFields(scanResults, true);
        
        console.log('\n' + '='.repeat(80));
        console.log('⚠️  هل تريد تطبيق التغييرات؟ (set APPLY_CHANGES=true)');
        console.log('='.repeat(80));
        
        // التحقق من متغير البيئة للتطبيق الفعلي
        if (process.env.APPLY_CHANGES === 'true') {
            console.log('\n🚀 جاري تطبيق التغييرات...\n');
            await addMissingCamelCaseFields(scanResults, false);
            
            console.log('\n⏳ انتظار 10 ثواني لمعالجة الحقول الجديدة...');
            await new Promise(r => setTimeout(r, 10000));
            
            // فحص نهائي
            console.log('\n🔄 فحص نهائي...');
            await scanCollections();
        }
    } else {
        console.log('\n✅ جميع الحقول camelCase موجودة! لا حاجة لتغييرات.');
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ انتهى السكربت بنجاح');
    console.log('='.repeat(80) + '\n');
}

// تشغيل السكربت
main().catch(console.error);
