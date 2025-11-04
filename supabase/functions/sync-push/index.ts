// ============================================================================
// Marina Hotel - Sync Push Edge Function
// دالة المزامنة (Push) - إرسال التغييرات من العميل إلى Supabase
// Processes outbox changes from mobile app and syncs to Supabase
// ============================================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

// Types - أنواع البيانات
interface SyncChange {
  entity: string
  op: 'create' | 'update' | 'delete'
  uuid: string
  server_id?: number
  data: Record<string, any>
  client_ts: string
}

interface SyncResult {
  success: boolean
  server_id?: number
  error?: string
}

interface PushResponse {
  success: boolean
  data: {
    results: SyncResult[]
  }
}

// Helper: تحويل epoch timestamp إلى timestamptz
const epochToTimestamptz = (epoch: number): string => {
  if (!epoch) return new Date().toISOString()
  return new Date(epoch * 1000).toISOString()
}

// Helper: تحويل string UUID إلى UUID format
const ensureUUID = (uuid: string): string => {
  // إذا كان UUID صحيحاً، أعده كما هو
  // إذا لم يكن، حاول تحويله أو أنشئ واحداً جديداً
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  if (uuidPattern.test(uuid)) return uuid
  
  // إذا كان UUID بدون شرطات، أضف الشرطات
  if (uuid.length === 32) {
    return `${uuid.slice(0, 8)}-${uuid.slice(8, 12)}-${uuid.slice(12, 16)}-${uuid.slice(16, 20)}-${uuid.slice(20)}`
  }
  
  // إذا فشل كل شيء، أنشئ UUID جديد
  return crypto.randomUUID()
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
    const body = await req.json()
    const changes: SyncChange[] = body.changes || []

    if (!Array.isArray(changes) || changes.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          data: { results: [] }
        } as PushResponse),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      )
    }

    console.log(`📤 Processing ${changes.length} changes for user ${user.id}`)

    // معالجة كل تغيير
    const results: SyncResult[] = []

    for (const change of changes) {
      try {
        const result = await processChange(supabase, change, user.id)
        results.push(result)
      } catch (error) {
        console.error(`❌ Error processing change:`, error)
        results.push({
          success: false,
          error: error instanceof Error ? error.message : 'Unknown error'
        })
      }
    }

    // إرجاع النتائج
    const response: PushResponse = {
      success: true,
      data: { results }
    }

    return new Response(
      JSON.stringify(response),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('❌ Fatal error in sync-push:', error)
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
// Process Single Change - معالجة تغيير واحد
// ============================================================================
async function processChange(
  supabase: any,
  change: SyncChange,
  userId: string
): Promise<SyncResult> {
  const { entity, op, uuid, server_id, data, client_ts } = change

  console.log(`🔄 Processing ${op} on ${entity} (uuid: ${uuid})`)

  // تحويل البيانات
  const augmentedData = augmentData(data, uuid, client_ts)

  switch (entity) {
    case 'rooms':
      return await processRoomsChange(supabase, op, uuid, server_id, augmentedData)
    case 'bookings':
      return await processBookingsChange(supabase, op, uuid, server_id, augmentedData)
    case 'booking_notes':
      return await processBookingNotesChange(supabase, op, uuid, server_id, augmentedData)
    case 'employees':
      return await processEmployeesChange(supabase, op, uuid, server_id, augmentedData)
    case 'expenses':
      return await processExpensesChange(supabase, op, uuid, server_id, augmentedData)
    case 'cash_transactions':
      return await processCashTransactionsChange(supabase, op, uuid, server_id, augmentedData)
    case 'payments':
      return await processPaymentsChange(supabase, op, uuid, server_id, augmentedData)
    case 'debts':
      return await processDebtsChange(supabase, op, uuid, server_id, augmentedData)
    default:
      return {
        success: false,
        error: `Unknown entity: ${entity}`
      }
  }
}

// ============================================================================
// Augment Data - إضافة حقول المزامنة
// ============================================================================
function augmentData(data: Record<string, any>, uuid: string, clientTs: string): Record<string, any> {
  const now = new Date().toISOString()
  
  return {
    ...data,
    local_uuid: ensureUUID(uuid),
    last_modified: now,
    updated_at: now,
    origin: 'server'
  }
}

// ============================================================================
// ROOMS - معالجة الغرف
// ============================================================================
async function processRoomsChange(
  supabase: any,
  op: string,
  uuid: string,
  serverId: number | undefined,
  data: Record<string, any>
): Promise<SyncResult> {
  const table = 'rooms'
  const cleanedUuid = ensureUUID(uuid)

  if (op === 'delete') {
    // Soft delete
    const { error } = await supabase
      .from(table)
      .update({ deleted_at: new Date().toISOString(), last_modified: new Date().toISOString() })
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: serverId }
  }

  // البحث عن السجل الموجود
  const { data: existing } = await supabase
    .from(table)
    .select('id, server_id')
    .eq('local_uuid', cleanedUuid)
    .maybeSingle()

  if (op === 'create' || !existing) {
    // إنشاء سجل جديد
    const insertData = {
      room_number: data.room_number,
      type: data.type || '',
      price: data.price || 0,
      status: data.status || 'شاغرة',
      image_url: data.image_url || null,
      local_uuid: cleanedUuid,
      origin: 'server',
      last_modified: new Date().toISOString()
    }

    const { data: inserted, error } = await supabase
      .from(table)
      .insert(insertData)
      .select('id, server_id')
      .single()

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: inserted.id }
  } else {
    // تحديث سجل موجود
    const updateData: Record<string, any> = {
      last_modified: new Date().toISOString(),
      origin: 'server'
    }

    if (data.room_number) updateData.room_number = data.room_number
    if (data.type) updateData.type = data.type
    if (data.price !== undefined) updateData.price = data.price
    if (data.status) updateData.status = data.status
    if (data.image_url !== undefined) updateData.image_url = data.image_url

    const { error } = await supabase
      .from(table)
      .update(updateData)
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: existing.server_id || existing.id }
  }
}

// ============================================================================
// BOOKINGS - معالجة الحجوزات
// ============================================================================
async function processBookingsChange(
  supabase: any,
  op: string,
  uuid: string,
  serverId: number | undefined,
  data: Record<string, any>
): Promise<SyncResult> {
  const table = 'bookings'
  const cleanedUuid = ensureUUID(uuid)

  if (op === 'delete') {
    // Soft delete
    const { error } = await supabase
      .from(table)
      .update({ deleted_at: new Date().toISOString(), last_modified: new Date().toISOString() })
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: serverId }
  }

  // البحث عن السجل الموجود
  const { data: existing } = await supabase
    .from(table)
    .select('id, server_id, server_booking_id')
    .eq('local_uuid', cleanedUuid)
    .maybeSingle()

  if (op === 'create' || !existing) {
    // إنشاء سجل جديد
    const insertData = {
      room_number: data.room_number,
      guest_name: data.guest_name || '',
      guest_phone: data.guest_phone || '',
      guest_id_type: data.guest_id_type || 'بطاقة شخصية',
      guest_id_number: data.guest_id_number || '',
      guest_id_issue_date: data.guest_id_issue_date || null,
      guest_id_issue_place: data.guest_id_issue_place || null,
      guest_nationality: data.guest_nationality || '',
      guest_email: data.guest_email || null,
      guest_address: data.guest_address || null,
      checkin_date: data.checkin_date || new Date().toISOString(),
      checkout_date: data.checkout_date || null,
      actual_checkout: data.actual_checkout || null,
      status: data.status || 'محجوزة',
      notes: data.notes || null,
      expected_nights: data.expected_nights || 1,
      calculated_nights: data.calculated_nights || 1,
      local_uuid: cleanedUuid,
      origin: 'server',
      last_modified: new Date().toISOString()
    }

    const { data: inserted, error } = await supabase
      .from(table)
      .insert(insertData)
      .select('id, server_id, server_booking_id')
      .single()

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: inserted.server_booking_id || inserted.id }
  } else {
    // تحديث سجل موجود
    const updateData: Record<string, any> = {
      last_modified: new Date().toISOString(),
      origin: 'server'
    }

    if (data.room_number) updateData.room_number = data.room_number
    if (data.guest_name) updateData.guest_name = data.guest_name
    if (data.guest_phone) updateData.guest_phone = data.guest_phone
    if (data.guest_id_type) updateData.guest_id_type = data.guest_id_type
    if (data.guest_id_number !== undefined) updateData.guest_id_number = data.guest_id_number
    if (data.guest_id_issue_date !== undefined) updateData.guest_id_issue_date = data.guest_id_issue_date
    if (data.guest_id_issue_place !== undefined) updateData.guest_id_issue_place = data.guest_id_issue_place
    if (data.guest_nationality) updateData.guest_nationality = data.guest_nationality
    if (data.guest_email !== undefined) updateData.guest_email = data.guest_email
    if (data.guest_address !== undefined) updateData.guest_address = data.guest_address
    if (data.checkin_date) updateData.checkin_date = data.checkin_date
    if (data.checkout_date !== undefined) updateData.checkout_date = data.checkout_date
    if (data.actual_checkout !== undefined) updateData.actual_checkout = data.actual_checkout
    if (data.status) updateData.status = data.status
    if (data.notes !== undefined) updateData.notes = data.notes
    if (data.expected_nights !== undefined) updateData.expected_nights = data.expected_nights
    if (data.calculated_nights !== undefined) updateData.calculated_nights = data.calculated_nights

    const { error } = await supabase
      .from(table)
      .update(updateData)
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: existing.server_booking_id || existing.server_id || existing.id }
  }
}

// ============================================================================
// BOOKING_NOTES - معالجة ملاحظات الحجوزات
// ============================================================================
async function processBookingNotesChange(
  supabase: any,
  op: string,
  uuid: string,
  serverId: number | undefined,
  data: Record<string, any>
): Promise<SyncResult> {
  const table = 'booking_notes'
  const cleanedUuid = ensureUUID(uuid)

  if (op === 'delete') {
    const { error } = await supabase
      .from(table)
      .update({ deleted_at: new Date().toISOString(), last_modified: new Date().toISOString() })
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: serverId }
  }

  const { data: existing } = await supabase
    .from(table)
    .select('id, server_id')
    .eq('local_uuid', cleanedUuid)
    .maybeSingle()

  if (op === 'create' || !existing) {
    const insertData = {
      booking_id: data.booking_id || 0,
      note_text: data.note_text || '',
      alert_type: data.alert_type || 'low',
      alert_until: data.alert_until || null,
      is_active: data.is_active !== undefined ? data.is_active : 1,
      local_uuid: cleanedUuid,
      origin: 'server',
      last_modified: new Date().toISOString()
    }

    const { data: inserted, error } = await supabase
      .from(table)
      .insert(insertData)
      .select('id, server_id')
      .single()

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: inserted.id }
  } else {
    const updateData: Record<string, any> = {
      last_modified: new Date().toISOString(),
      origin: 'server'
    }

    if (data.booking_id !== undefined) updateData.booking_id = data.booking_id
    if (data.note_text) updateData.note_text = data.note_text
    if (data.alert_type) updateData.alert_type = data.alert_type
    if (data.alert_until !== undefined) updateData.alert_until = data.alert_until
    if (data.is_active !== undefined) updateData.is_active = data.is_active

    const { error } = await supabase
      .from(table)
      .update(updateData)
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: existing.server_id || existing.id }
  }
}

// ============================================================================
// EMPLOYEES - معالجة الموظفين
// ============================================================================
async function processEmployeesChange(
  supabase: any,
  op: string,
  uuid: string,
  serverId: number | undefined,
  data: Record<string, any>
): Promise<SyncResult> {
  const table = 'employees'
  const cleanedUuid = ensureUUID(uuid)

  if (op === 'delete') {
    const { error } = await supabase
      .from(table)
      .update({ deleted_at: new Date().toISOString(), last_modified: new Date().toISOString() })
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: serverId }
  }

  const { data: existing } = await supabase
    .from(table)
    .select('id, server_id')
    .eq('local_uuid', cleanedUuid)
    .maybeSingle()

  if (op === 'create' || !existing) {
    const insertData = {
      name: data.name || '',
      basic_salary: data.basic_salary || 0,
      position: data.position || 'موظف',
      phone: data.phone || '',
      hire_date: data.hire_date || '',
      status: data.status || 'active',
      local_uuid: cleanedUuid,
      origin: 'server',
      last_modified: new Date().toISOString()
    }

    const { data: inserted, error } = await supabase
      .from(table)
      .insert(insertData)
      .select('id, server_id')
      .single()

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: inserted.id }
  } else {
    const updateData: Record<string, any> = {
      last_modified: new Date().toISOString(),
      origin: 'server'
    }

    if (data.name) updateData.name = data.name
    if (data.basic_salary !== undefined) updateData.basic_salary = data.basic_salary
    if (data.position) updateData.position = data.position
    if (data.phone !== undefined) updateData.phone = data.phone
    if (data.hire_date !== undefined) updateData.hire_date = data.hire_date
    if (data.status) updateData.status = data.status

    const { error } = await supabase
      .from(table)
      .update(updateData)
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: existing.server_id || existing.id }
  }
}

// ============================================================================
// EXPENSES - معالجة المصروفات
// ============================================================================
async function processExpensesChange(
  supabase: any,
  op: string,
  uuid: string,
  serverId: number | undefined,
  data: Record<string, any>
): Promise<SyncResult> {
  const table = 'expenses'
  const cleanedUuid = ensureUUID(uuid)

  if (op === 'delete') {
    const { error } = await supabase
      .from(table)
      .update({ deleted_at: new Date().toISOString(), last_modified: new Date().toISOString() })
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: serverId }
  }

  const { data: existing } = await supabase
    .from(table)
    .select('id, server_id')
    .eq('local_uuid', cleanedUuid)
    .maybeSingle()

  if (op === 'create' || !existing) {
    const insertData = {
      expense_type: data.expense_type || 'other',
      related_id: data.related_id || null,
      description: data.description || '',
      amount: data.amount || 0,
      date: data.date || new Date().toISOString().split('T')[0],
      cash_transaction_id: data.cash_transaction_id || null,
      local_uuid: cleanedUuid,
      origin: 'server',
      last_modified: new Date().toISOString()
    }

    const { data: inserted, error } = await supabase
      .from(table)
      .insert(insertData)
      .select('id, server_id')
      .single()

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: inserted.id }
  } else {
    const updateData: Record<string, any> = {
      last_modified: new Date().toISOString(),
      origin: 'server'
    }

    if (data.expense_type) updateData.expense_type = data.expense_type
    if (data.related_id !== undefined) updateData.related_id = data.related_id
    if (data.description) updateData.description = data.description
    if (data.amount !== undefined) updateData.amount = data.amount
    if (data.date) updateData.date = data.date
    if (data.cash_transaction_id !== undefined) updateData.cash_transaction_id = data.cash_transaction_id

    const { error } = await supabase
      .from(table)
      .update(updateData)
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: existing.server_id || existing.id }
  }
}

// ============================================================================
// CASH_TRANSACTIONS - معالجة المعاملات النقدية
// ============================================================================
async function processCashTransactionsChange(
  supabase: any,
  op: string,
  uuid: string,
  serverId: number | undefined,
  data: Record<string, any>
): Promise<SyncResult> {
  const table = 'cash_transactions'
  const cleanedUuid = ensureUUID(uuid)

  if (op === 'delete') {
    const { error } = await supabase
      .from(table)
      .update({ deleted_at: new Date().toISOString(), last_modified: new Date().toISOString() })
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: serverId }
  }

  const { data: existing } = await supabase
    .from(table)
    .select('id, server_id')
    .eq('local_uuid', cleanedUuid)
    .maybeSingle()

  if (op === 'create' || !existing) {
    const insertData = {
      register_id: data.register_id || null,
      transaction_type: data.transaction_type || 'income',
      amount: data.amount || 0,
      reference_type: data.reference_type || null,
      reference_id: data.reference_id || null,
      description: data.description || null,
      transaction_time: data.transaction_time || new Date().toISOString(),
      created_by: data.created_by || null,
      local_uuid: cleanedUuid,
      origin: 'server',
      last_modified: new Date().toISOString()
    }

    const { data: inserted, error } = await supabase
      .from(table)
      .insert(insertData)
      .select('id, server_id')
      .single()

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: inserted.id }
  } else {
    const updateData: Record<string, any> = {
      last_modified: new Date().toISOString(),
      origin: 'server'
    }

    if (data.register_id !== undefined) updateData.register_id = data.register_id
    if (data.transaction_type) updateData.transaction_type = data.transaction_type
    if (data.amount !== undefined) updateData.amount = data.amount
    if (data.reference_type !== undefined) updateData.reference_type = data.reference_type
    if (data.reference_id !== undefined) updateData.reference_id = data.reference_id
    if (data.description !== undefined) updateData.description = data.description
    if (data.transaction_time) updateData.transaction_time = data.transaction_time
    if (data.created_by !== undefined) updateData.created_by = data.created_by

    const { error } = await supabase
      .from(table)
      .update(updateData)
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: existing.server_id || existing.id }
  }
}

// ============================================================================
// PAYMENTS - معالجة الدفعات
// ============================================================================
async function processPaymentsChange(
  supabase: any,
  op: string,
  uuid: string,
  serverId: number | undefined,
  data: Record<string, any>
): Promise<SyncResult> {
  const table = 'payments'
  const cleanedUuid = ensureUUID(uuid)

  if (op === 'delete') {
    const { error } = await supabase
      .from(table)
      .update({ deleted_at: new Date().toISOString(), last_modified: new Date().toISOString() })
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: serverId }
  }

  const { data: existing } = await supabase
    .from(table)
    .select('id, server_id, server_payment_id')
    .eq('local_uuid', cleanedUuid)
    .maybeSingle()

  if (op === 'create' || !existing) {
    const insertData = {
      booking_local_id: data.booking_local_id || null,
      server_booking_id: data.server_booking_id || null,
      room_number: data.room_number || null,
      amount: data.amount || 0,
      payment_date: data.payment_date || new Date().toISOString(),
      notes: data.notes || null,
      payment_method: data.payment_method || 'نقدي',
      revenue_type: data.revenue_type || 'room',
      cash_transaction_local_id: data.cash_transaction_local_id || null,
      cash_transaction_server_id: data.cash_transaction_server_id || null,
      reference_number: data.reference_number || null,
      local_uuid: cleanedUuid,
      origin: 'server',
      last_modified: new Date().toISOString()
    }

    const { data: inserted, error } = await supabase
      .from(table)
      .insert(insertData)
      .select('id, server_id, server_payment_id')
      .single()

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: inserted.server_payment_id || inserted.id }
  } else {
    const updateData: Record<string, any> = {
      last_modified: new Date().toISOString(),
      origin: 'server'
    }

    if (data.booking_local_id !== undefined) updateData.booking_local_id = data.booking_local_id
    if (data.server_booking_id !== undefined) updateData.server_booking_id = data.server_booking_id
    if (data.room_number !== undefined) updateData.room_number = data.room_number
    if (data.amount !== undefined) updateData.amount = data.amount
    if (data.payment_date) updateData.payment_date = data.payment_date
    if (data.notes !== undefined) updateData.notes = data.notes
    if (data.payment_method) updateData.payment_method = data.payment_method
    if (data.revenue_type) updateData.revenue_type = data.revenue_type
    if (data.cash_transaction_local_id !== undefined) updateData.cash_transaction_local_id = data.cash_transaction_local_id
    if (data.cash_transaction_server_id !== undefined) updateData.cash_transaction_server_id = data.cash_transaction_server_id
    if (data.reference_number !== undefined) updateData.reference_number = data.reference_number

    const { error } = await supabase
      .from(table)
      .update(updateData)
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: existing.server_payment_id || existing.server_id || existing.id }
  }
}

// ============================================================================
// DEBTS - معالجة الديون
// ============================================================================
async function processDebtsChange(
  supabase: any,
  op: string,
  uuid: string,
  serverId: number | undefined,
  data: Record<string, any>
): Promise<SyncResult> {
  const table = 'debts'
  const cleanedUuid = ensureUUID(uuid)

  if (op === 'delete') {
    const { error } = await supabase
      .from(table)
      .update({ deleted_at: new Date().toISOString(), last_modified: new Date().toISOString() })
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: serverId }
  }

  const { data: existing } = await supabase
    .from(table)
    .select('id, server_id')
    .eq('local_uuid', cleanedUuid)
    .maybeSingle()

  if (op === 'create' || !existing) {
    const insertData = {
      booking_local_id: data.booking_local_id || null,
      guest_name: data.guest_name || '',
      checkin_date: data.checkin_date || '',
      checkout_date: data.checkout_date || '',
      date_recorded: data.date_recorded || '',
      debt_reason: data.debt_reason || '',
      total_amount: data.total_amount || 0,
      paid_amount: data.paid_amount || 0,
      remaining_amount: data.remaining_amount || 0,
      payment_date: data.payment_date || '',
      is_settled: data.is_settled || 0,
      pledge: data.pledge || null,
      pledge_type: data.pledge_type || null,
      note: data.note || null,
      local_uuid: cleanedUuid,
      origin: 'server',
      last_modified: new Date().toISOString()
    }

    const { data: inserted, error } = await supabase
      .from(table)
      .insert(insertData)
      .select('id, server_id')
      .single()

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: inserted.id }
  } else {
    const updateData: Record<string, any> = {
      last_modified: new Date().toISOString(),
      origin: 'server'
    }

    if (data.booking_local_id !== undefined) updateData.booking_local_id = data.booking_local_id
    if (data.guest_name) updateData.guest_name = data.guest_name
    if (data.checkin_date) updateData.checkin_date = data.checkin_date
    if (data.checkout_date) updateData.checkout_date = data.checkout_date
    if (data.date_recorded !== undefined) updateData.date_recorded = data.date_recorded
    if (data.debt_reason !== undefined) updateData.debt_reason = data.debt_reason
    if (data.total_amount !== undefined) updateData.total_amount = data.total_amount
    if (data.paid_amount !== undefined) updateData.paid_amount = data.paid_amount
    if (data.remaining_amount !== undefined) updateData.remaining_amount = data.remaining_amount
    if (data.payment_date) updateData.payment_date = data.payment_date
    if (data.is_settled !== undefined) updateData.is_settled = data.is_settled
    if (data.pledge !== undefined) updateData.pledge = data.pledge
    if (data.pledge_type !== undefined) updateData.pledge_type = data.pledge_type
    if (data.note !== undefined) updateData.note = data.note

    const { error } = await supabase
      .from(table)
      .update(updateData)
      .eq('local_uuid', cleanedUuid)

    if (error) {
      return { success: false, error: error.message }
    }

    return { success: true, server_id: existing.server_id || existing.id }
  }
}

// ============================================================================
// END OF SYNC-PUSH FUNCTION
// ============================================================================
