#!/usr/bin/env python3
# =====================================================================
# تدقيق فهارس وسمات Appwrite لمسارات المزامنة (Delta/Full/tombstone)
# ---------------------------------------------------------------------
# الاستخدام:
#   APPWRITE_API_KEY=standard_xxx python3 scripts/appwrite/appwrite_full_audit.py
#
# ماذا يفحص لكل كولكشن مزامنة؟
#   1) فهرس $updatedAt متاح (نوافذ الدلتا greaterThan في sync_pull_service.dart)
#   2) سمة deletedAt متاحة (فلتر استبعاد tombstones في buildFullSyncQueries)
#   3) فهرس deletedAt (اختياري — يعجّل فلتر OR)
#   4) عدد المستندات (لقياس الأثر)
# المخرجات: جدول للطرفية + JSON كامل في appwrite_index_audit_result.json
# ---------------------------------------------------------------------
# 🔴 بلا أسرار: المفتاح يُقرأ من متغير البيئة APPWRITE_API_KEY فقط.
# =====================================================================
import json, time, urllib.request, urllib.error, urllib.parse, os, sys

ENDPOINT = os.environ.get('APPWRITE_ENDPOINT', 'https://fra.cloud.appwrite.io/v1')
PROJECT = os.environ.get('APPWRITE_PROJECT_ID', '6a4408f300217885fd7b')
DB = os.environ.get('APPWRITE_DATABASE_ID', '6a4409b50019dd39dde5')
KEY = os.environ.get('APPWRITE_API_KEY', '')
if not KEY:
    sys.exit('❌ مرّر APPWRITE_API_KEY=... (Server key بصلاحية databases.read)')

SYNC_COLLECTIONS = {
    'rooms', 'bookings', 'payments', 'expenses', 'employees', 'debts',
    'booking_notes', 'shift_notes', 'cash_transactions', 'booking_nights',
    'salary_cycles', 'salary_payments', 'salary_withdrawals',
    'salary_carry_over_logs', 'blacklist', 'price_adjustments',
    'booking_price_adjustments', 'audit_logs', 'payment_voids', 'guest_infos',
    'inventory_items', 'inventory_transactions', 'app_settings',
}
EXTRA_QUERIED = {'devices': ['deviceId', 'status']}  # استعلامات خارج مسار المزامنة


def req(path, method='GET', body=None):
    data = json.dumps(body).encode() if body else None
    r = urllib.request.Request(ENDPOINT + path, data=data, method=method, headers={
        'X-Appwrite-Project': PROJECT, 'X-Appwrite-Key': KEY,
        'Content-Type': 'application/json',
    })
    for attempt in range(5):
        try:
            with urllib.request.urlopen(r, timeout=25) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                wait = 5 * (attempt + 1)
                print(f'  ⏳ 429 rate-limit — انتظار {wait}ث', flush=True)
                time.sleep(wait)
                continue
            if e.code >= 500:
                time.sleep(3)
                continue
            raise
    raise RuntimeError(f'failed after retries: {path}')


def paginate(path, kind):
    out, limit = [], 100
    res = req(f'{path}?queries[]={urllib.parse.quote(json.dumps({"method": "limit", "values": [limit]}))}')
    out.extend(res.get(kind, []))
    total = res.get('total', len(out))
    while len(out) < total:
        res = req(f'{path}?queries[]={urllib.parse.quote(json.dumps({"method": "limit", "values": [limit]}))}'
                  f'&queries[]={urllib.parse.quote(json.dumps({"method": "offset", "values": [len(out)]}))}')
        out.extend(res.get(kind, []))
    return out


cols = paginate(f'/databases/{DB}/collections', 'collections')
print(f'collections: {len(cols)}\n', flush=True)

hdr = f"{'collection':<26}{'docs':>8}  {'updatedAt idx':<15}{'deletedAt attr':<24}{'delIdx':<7}indexes"
print(hdr)
print('-' * len(hdr), flush=True)

results = []
for c in sorted(cols, key=lambda x: x['$id']):
    cid = c['$id']
    attrs = paginate(f'/databases/{DB}/collections/{cid}/attributes', 'attributes')
    idxs = paginate(f'/databases/{DB}/collections/{cid}/indexes', 'indexes')

    up_idx = [i for i in idxs if 'updatedAt' in (i.get('attributes') or [])]
    up_ok = bool(up_idx) and all(i.get('status') == 'available' for i in up_idx)
    up_dir = ','.join((up_idx[0].get('attributesDirections') or up_idx[0].get('directions') or ['?'])) if up_idx else '-'

    del_attr = next((a for a in attrs if a.get('key') == 'deletedAt'), None)
    del_info = '-' if not del_attr else f"{del_attr.get('type')}/{del_attr.get('status')}"
    del_idx = [i for i in idxs if 'deletedAt' in (i.get('attributes') or [])]

    # عدد المستندات — رخيص: select $id + limit 1
    try:
        q = urllib.parse.quote(json.dumps({"method": "limit", "values": [1]}))
        q2 = urllib.parse.quote(json.dumps({"method": "select", "values": ["$id"]}))
        docs = req(f'/databases/{DB}/collections/{cid}/documents?queries[]={q}&queries[]={q2}').get('total', '?')
    except Exception:
        docs = 'ERR'
    time.sleep(0.5)

    in_sync = cid in SYNC_COLLECTIONS or cid in EXTRA_QUERIED
    mark = '' if in_sync else '  (خارج المزامنة)'
    up_disp = ('PASS(' + up_dir + ')') if up_ok else ('PROCESSING' if up_idx else 'MISSING')
    del_disp = del_info if (in_sync or del_attr) else '-'
    idx_names = '; '.join(f"{i['key']}[{','.join(i.get('attributes') or [])}]" for i in idxs[:8]) or 'لا فهارس'
    print(f"{cid:<26}{str(docs):>8}  {up_disp:<15}{del_disp:<24}{'نعم' if del_idx else 'لا':<7}{idx_names}{mark}", flush=True)

    results.append({
        'collection': cid, 'sync_scope': cid in SYNC_COLLECTIONS,
        'docs': docs, 'updatedAt_index': {
            'present': bool(up_idx), 'available': up_ok,
            'directions': up_idx[0].get('attributesDirections') if up_idx else None,
            'status': up_idx[0].get('status') if up_idx else None,
        },
        'deletedAt_attribute': None if not del_attr else {
            'type': del_attr.get('type'), 'status': del_attr.get('status'),
            'required': del_attr.get('required'), 'default': del_attr.get('default'),
        },
        'deletedAt_index': bool(del_idx),
        'indexes': [{'key': i['key'], 'type': i.get('type'), 'status': i.get('status'),
                     'attributes': i.get('attributes'),
                     'directions': i.get('attributesDirections') or i.get('directions')}
                    for i in idxs],
    })

out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)) or '.',
                        'appwrite_index_audit_result.json')
# اكتب النتيجة في مجلد العمل الحالي بدل مجلد السكربت
with open('appwrite_index_audit_result.json', 'w') as f:
    json.dump(results, f, ensure_ascii=False, indent=2)
print(f'\n📁 JSON: {os.path.abspath("appwrite_index_audit_result.json")}', flush=True)

print('\n=== الخلاصة ===', flush=True)
sync = [r for r in results if r['sync_scope']]
no_up = [r['collection'] for r in sync if not r['updatedAt_index']['available']]
no_del = [r['collection'] for r in sync
          if not r['deletedAt_attribute'] or r['deletedAt_attribute']['status'] != 'available']
print(f"كولكشنات المزامنة المدققة: {len(sync)}")
print(f"بلا فهرس $updatedAt متاح: {no_up or 'لا شيء ✓'}")
print(f"بلا سمة deletedAt متاحة: {no_del or 'لا شيء ✓'}")
sys.exit(1 if (no_up or no_del) else 0)
