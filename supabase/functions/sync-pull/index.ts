// ============================================================================
// Marina Hotel - Sync Pull Edge Function
// دالة المزامنة (Pull) - سحب التغييرات من Supabase إلى العميل
// Pulls changes from Supabase and sends to mobile app
// ============================================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

// Types - أنواع البيانات
interface PullRequest {
  last_pull_ts: string
  limit?: number
}

interface SyncRecord {
  entity: string
  op: string
  server_id: number
  server_ts: string
  data: Record<string, any>
}

interface PullResponse {
  success: boolean
  data: {
    data: SyncRecord[]
    new_server_ts: string
  }
}

// Helper: تحويل timestamptz إلى ISO string
const timestamptzToIso = (timestamp: string): string => {
  return new Date(timestamp).toISOString()
}

serve(async (req) => {
  try {
    // التحقق من طريقة الطلب
    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ success: false, error: 'Method not allowed' }),
        { status: 405, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // إنشاء Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // الحصول على JWT token من headers
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing authorization header' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // التحقق من صحة المستخدم
    const jwt = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabase.auth.getUser(jwt)
    if (authError || !user) {
      return new Response(
        JSON.stringify({ success: false, error: 'Unauthorized' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // قراءة البيانات من الطلب
    const body: PullRequest = await req.json()
    const lastPullTs = body.last_pull_ts || '1970-01-01T00:00:00.000Z'
    const limit = body.limit || 1000

    console.log(`📥 Pulling changes since ${lastPullTs} for user ${user.id}`)

    // جمع جميع التغييرات من كل الجداول
    const allChanges: SyncRecord[] = []

    // قائمة الجداول المراد سحب التغييرات منها
    const entities = [
      'rooms',
      'bookings',
      'booking_notes',
      'employees',
      'expenses',
      'cash_transactions',
      'payments',
      'debts'
    ]

    // سحب التغييرات من كل جدول
    for (const entity of entities) {
      try {
        const changes = await pullEntityChanges(supabase, entity, lastPullTs, limit)
        allChanges.push(...changes)
      } catch (error) {
        console.error(`❌ Error pulling ${entity}:`, error)
        // نستمر في سحب باقي الجداول حتى لو فشل أحدها
      }
    }

    // ترتيب التغييرات حسب last_modified
    allChanges.sort((a, b) => {
      const aTime = new Date(a.server_ts).getTime()
      const bTime = new Date(b.server_ts).getTime()
      return aTime - bTime
    })

    // تحديد آخر وقت مزامنة
    const newServerTs = allChanges.length > 0
      ? allChanges[allChanges.length - 1].server_ts
      : new Date().toISOString()

    console.log(`✅ Pulled ${allChanges.length} changes, new server_ts: ${newServerTs}`)

    // إرجاع النتائج
    const response: PullResponse = {
      success: true,
      data: {
        data: allChanges,
        new_server_ts: newServerTs
      }
    }

    return new Response(
      JSON.stringify(response),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('❌ Fatal error in sync-pull:', error)
    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})

// ============================================================================
// Pull Entity Changes - سحب التغييرات من جدول واحد
// ============================================================================
async function pullEntityChanges(
  supabase: any,
  entity: string,
  sinceTs: string,
  limit: number
): Promise<SyncRecord[]> {
  console.log(`🔄 Pulling ${entity} changes since ${sinceTs}`)

  // سحب السجلات المحدثة بعد sinceTs
  const { data, error } = await supabase
    .from(entity)
    .select('*')
    .gt('last_modified', sinceTs)
    .order('last_modified', { ascending: true })
    .limit(limit)

  if (error) {
    console.error(`❌ Error pulling ${entity}:`, error)
    throw error
  }

  if (!data || data.length === 0) {
    return []
  }

  // تحويل السجلات إلى SyncRecord format
  const changes: SyncRecord[] = []

  for (const record of data) {
    const syncRecord = convertToSyncRecord(entity, record)
    if (syncRecord) {
      changes.push(syncRecord)
    }
  }

  console.log(`✅ Pulled ${changes.length} changes from ${entity}`)

  return changes
}

// ============================================================================
// Convert To Sync Record - تحويل السجل إلى SyncRecord format
// ============================================================================
function convertToSyncRecord(entity: string, record: Record<string, any>): SyncRecord | null {
  // تحديد نوع العملية
  let op = 'update'
  if (record.deleted_at) {
    op = 'delete'
  } else if (record.created_at === record.last_modified) {
    op = 'create'
  }

  // تحديد server_id حسب نوع الجدول
  let serverId = record.server_id || record.id

  // جداول خاصة لها server_id مختلف
  if (entity === 'bookings') {
    serverId = record.server_booking_id || record.server_id || record.id
  } else if (entity === 'payments') {
    serverId = record.server_payment_id || record.server_id || record.id
  }

  // إنشاء data object
  const data = extractEntityData(entity, record)

  return {
    entity,
    op,
    server_id: serverId,
    server_ts: timestamptzToIso(record.last_modified),
    data
  }
}

// ============================================================================
// Extract Entity Data - استخراج بيانات الجدول
// ============================================================================
function extractEntityData(entity: string, record: Record<string, any>): Record<string, any> {
  // إزالة الحقول الداخلية
  const internalFields = [
    'id',
    'local_uuid',
    'created_at',
    'updated_at',
    'last_modified',
    'version',
    'origin'
  ]

  const data: Record<string, any> = {}

  for (const key in record) {
    if (!internalFields.includes(key)) {
      data[key] = record[key]
    }
  }

  // إضافة deleted_at إذا كان موجوداً
  if (record.deleted_at) {
    data.deleted_at = timestamptzToIso(record.deleted_at)
  }

  // معالجة خاصة لكل entity
  switch (entity) {
    case 'rooms':
      return extractRoomsData(record, data)
    case 'bookings':
      return extractBookingsData(record, data)
    case 'booking_notes':
      return extractBookingNotesData(record, data)
    case 'employees':
      return extractEmployeesData(record, data)
    case 'expenses':
      return extractExpensesData(record, data)
    case 'cash_transactions':
      return extractCashTransactionsData(record, data)
    case 'payments':
      return extractPaymentsData(record, data)
    case 'debts':
      return extractDebtsData(record, data)
    default:
      return data
  }
}

// ============================================================================
// Extract Rooms Data - استخراج بيانات الغرف
// ============================================================================
function extractRoomsData(record: Record<string, any>, data: Record<string, any>): Record<string, any> {
  return {
    room_number: record.room_number,
    type: record.type,
    price: record.price,
    status: record.status,
    image_url: record.image_url,
    server_id: record.server_id || record.id,
    deleted_at: data.deleted_at
  }
}

// ============================================================================
// Extract Bookings Data - استخراج بيانات الحجوزات
// ============================================================================
function extractBookingsData(record: Record<string, any>, data: Record<string, any>): Record<string, any> {
  return {
    booking_id: record.server_booking_id || record.id,
    room_number: record.room_number,
    guest_name: record.guest_name,
    guest_phone: record.guest_phone,
    guest_id_type: record.guest_id_type,
    guest_id_number: record.guest_id_number,
    guest_id_issue_date: record.guest_id_issue_date,
    guest_id_issue_place: record.guest_id_issue_place,
    guest_nationality: record.guest_nationality,
    guest_email: record.guest_email,
    guest_address: record.guest_address,
    checkin_date: timestamptzToIso(record.checkin_date),
    checkout_date: record.checkout_date ? timestamptzToIso(record.checkout_date) : null,
    actual_checkout: record.actual_checkout ? timestamptzToIso(record.actual_checkout) : null,
    status: record.status,
    notes: record.notes,
    expected_nights: record.expected_nights,
    calculated_nights: record.calculated_nights,
    server_id: record.server_booking_id || record.server_id || record.id,
    deleted_at: data.deleted_at
  }
}

// ============================================================================
// Extract Booking Notes Data - استخراج بيانات ملاحظات الحجوزات
// ============================================================================
function extractBookingNotesData(record: Record<string, any>, data: Record<string, any>): Record<string, any> {
  return {
    note_id: record.server_id || record.id,
    booking_id: record.booking_id,
    note_text: record.note_text,
    alert_type: record.alert_type,
    alert_until: record.alert_until ? timestamptzToIso(record.alert_until) : null,
    is_active: record.is_active,
    server_id: record.server_id || record.id,
    deleted_at: data.deleted_at
  }
}

// ============================================================================
// Extract Employees Data - استخراج بيانات الموظفين
// ============================================================================
function extractEmployeesData(record: Record<string, any>, data: Record<string, any>): Record<string, any> {
  return {
    id: record.server_id || record.id,
    name: record.name,
    basic_salary: record.basic_salary,
    position: record.position,
    phone: record.phone,
    hire_date: record.hire_date,
    status: record.status,
    server_id: record.server_id || record.id,
    deleted_at: data.deleted_at
  }
}

// ============================================================================
// Extract Expenses Data - استخراج بيانات المصروفات
// ============================================================================
function extractExpensesData(record: Record<string, any>, data: Record<string, any>): Record<string, any> {
  return {
    id: record.server_id || record.id,
    expense_type: record.expense_type,
    related_id: record.related_id,
    description: record.description,
    amount: record.amount,
    date: record.date,
    cash_transaction_id: record.cash_transaction_id,
    server_id: record.server_id || record.id,
    deleted_at: data.deleted_at
  }
}

// ============================================================================
// Extract Cash Transactions Data - استخراج بيانات المعاملات النقدية
// ============================================================================
function extractCashTransactionsData(record: Record<string, any>, data: Record<string, any>): Record<string, any> {
  return {
    id: record.server_id || record.id,
    register_id: record.register_id,
    transaction_type: record.transaction_type,
    amount: record.amount,
    reference_type: record.reference_type,
    reference_id: record.reference_id,
    description: record.description,
    transaction_time: timestamptzToIso(record.transaction_time),
    created_by: record.created_by,
    server_id: record.server_id || record.id,
    deleted_at: data.deleted_at
  }
}

// ============================================================================
// Extract Payments Data - استخراج بيانات الدفعات
// ============================================================================
function extractPaymentsData(record: Record<string, any>, data: Record<string, any>): Record<string, any> {
  return {
    payment_id: record.server_payment_id || record.id,
    booking_id: record.server_booking_id,
    room_number: record.room_number,
    amount: record.amount,
    payment_date: timestamptzToIso(record.payment_date),
    notes: record.notes,
    payment_method: record.payment_method,
    revenue_type: record.revenue_type,
    cash_transaction_id: record.cash_transaction_server_id,
    reference_number: record.reference_number,
    server_id: record.server_payment_id || record.server_id || record.id,
    deleted_at: data.deleted_at
  }
}

// ============================================================================
// Extract Debts Data - استخراج بيانات الديون
// ============================================================================
function extractDebtsData(record: Record<string, any>, data: Record<string, any>): Record<string, any> {
  return {
    id: record.server_id || record.id,
    booking_local_id: record.booking_local_id,
    guest_name: record.guest_name,
    checkin_date: record.checkin_date,
    checkout_date: record.checkout_date,
    date_recorded: record.date_recorded,
    debt_reason: record.debt_reason,
    total_amount: record.total_amount,
    paid_amount: record.paid_amount,
    remaining_amount: record.remaining_amount,
    payment_date: record.payment_date,
    is_settled: record.is_settled,
    pledge: record.pledge,
    pledge_type: record.pledge_type,
    note: record.note,
    server_id: record.server_id || record.id,
    deleted_at: data.deleted_at
  }
}

// ============================================================================
// END OF SYNC-PULL FUNCTION
// ============================================================================
