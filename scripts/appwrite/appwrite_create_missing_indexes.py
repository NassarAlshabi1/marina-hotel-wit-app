#!/usr/bin/env python3
# =====================================================================
# إنشاء الفهارس الناقصة لكولكشنات المزامنة (idempotent — يتحقق من الموجود أولاً)
# ---------------------------------------------------------------------
# الاستخدام:
#   APPWRITE_API_KEY=standard_xxx python3 scripts/appwrite/appwrite_create_missing_indexes.py
#
# ماذا ينشئ؟
#   1) idx_updated_at [updatedAt ASC] في كل كولكشنات المزامنة الـ 23
#      (نوافذ الدلتا greaterThan كانت تعمل مسحاً جدولياً بلا هذا الفهرس)
#   2) idx_deleted_at [deletedAt ASC] في الكولكشنات الناقصة
#      (فلتر استبعاد tombstones في buildFullSyncQueries)
#
# آمن لإعادة التشغيل: يتخطى أي فهرس موجود، وينتظر وصول كل فهرس إلى
# الحالة available (poll)، ويطبع ملخصاً نهائياً.
# ---------------------------------------------------------------------
# 🔴 بلا أسرار: المفتاح يُقرأ من متغير البيئة APPWRITE_API_KEY فقط.
# =====================================================================
import json, time, urllib.request, urllib.error, urllib.parse, os, sys

ENDPOINT = os.environ.get('APPWRITE_ENDPOINT', 'https://fra.cloud.appwrite.io/v1')
PROJECT = os.environ.get('APPWRITE_PROJECT_ID', '6a4408f300217885fd7b')
DB = os.environ.get('APPWRITE_DATABASE_ID', '6a4409b50019dd39dde5')
KEY = os.environ.get('APPWRITE_API_KEY', '')
if not KEY:
    sys.exit('❌ مرّر APPWRITE_API_KEY=... (Server key بصلاحية databases.write)')

SYNC_COLLECTIONS = [
    'rooms', 'bookings', 'payments', 'expenses', 'employees', 'debts',
    'booking_notes', 'shift_notes', 'cash_transactions', 'booking_nights',
    'salary_cycles', 'salary_payments', 'salary_withdrawals',
    'salary_carry_over_logs', 'blacklist', 'price_adjustments',
    'booking_price_adjustments', 'audit_logs', 'payment_voids', 'guest_infos',
    'inventory_items', 'inventory_transactions', 'app_settings',
]
# كولكشنات بلا فهرس deletedAt (تاريخياً: booking_price_adjustments بلا أي فهارس
# أصلاً، وinventory_* ناقصان) — التخطي تلقائي إن وُجد الفهرس
NEED_DELETED_AT = ['booking_price_adjustments', 'inventory_items', 'inventory_transactions']


def req(path, method='GET', body=None):
    data = json.dumps(body).encode() if body else None
    r = urllib.request.Request(ENDPOINT + path, data=data, method=method, headers={
        'X-Appwrite-Project': PROJECT, 'X-Appwrite-Key': KEY,
        'Content-Type': 'application/json',
    })
    try:
        with urllib.request.urlopen(r, timeout=25) as resp:
            return resp.status, json.load(resp)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.load(e)
        except Exception:
            return e.code, {}


created, failed = [], []


def ensure_index(col, key_name, attributes):
    code, idxs = req(f'/databases/{DB}/collections/{col}/indexes')
    existing = {i['key'] for i in idxs.get('indexes', [])} if code == 200 else set()
    if key_name in existing:
        print(f'  = {col}/{key_name}: موجود مسبقاً', flush=True)
        created.append((col, key_name))
        return
    code, res = req(f'/databases/{DB}/collections/{col}/indexes', 'POST', {
        'key': key_name, 'type': 'key',
        'attributes': attributes, 'directions': ['ASC'] * len(attributes),
    })
    if code in (201, 202):
        print(f'  + {col}/{key_name}: أُنشئ ({code})', flush=True)
        created.append((col, key_name))
    else:
        print(f'  ✗ {col}/{key_name}: HTTP {code} — {json.dumps(res, ensure_ascii=False)[:200]}', flush=True)
        failed.append((col, key_name, code, res))


print('=== إنشاء فهارس updatedAt ===', flush=True)
for col in SYNC_COLLECTIONS:
    ensure_index(col, 'idx_updated_at', ['updatedAt'])
    time.sleep(1.0)

print('=== إنشاء فهارس deletedAt الناقصة ===', flush=True)
for col in NEED_DELETED_AT:
    ensure_index(col, 'idx_deleted_at', ['deletedAt'])
    time.sleep(1.0)

# انتظار التوفر (poll كل 10ث، حتى 6 دقائق)
print('=== انتظار التوفر ===', flush=True)
pending = set(created)
for round_i in range(36):
    if not pending:
        break
    still = set()
    for col, key_name in sorted(pending):
        code, idxs = req(f'/databases/{DB}/collections/{col}/indexes')
        idx = next((x for x in idxs.get('indexes', []) if x['key'] == key_name), None)
        st = idx.get('status') if idx else 'GONE'
        if st == 'available':
            pass
        elif st == 'processing':
            still.add((col, key_name))
        else:
            print(f'  ⚠️ {col}/{key_name}: status={st} error={idx.get("error") if idx else "?"}', flush=True)
            failed.append((col, key_name, 0, st))
    pending = still
    if pending:
        print(f'  ... processing: {len(pending)} (جولة {round_i + 1})', flush=True)
        time.sleep(10)

if pending:
    print('⏳ لم تكتمل بعد:', sorted(pending), flush=True)
print(f'\n✅ جاهزة: {len(created)} | فشل: {len(failed)}', flush=True)
for f_ in failed:
    print('  FAILED:', f_, flush=True)
sys.exit(1 if failed else 0)
