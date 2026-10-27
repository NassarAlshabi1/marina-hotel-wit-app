#!/usr/bin/env python3
"""
Backfill salary_withdrawals.expenseUuid on Appwrite Cloud (+ dup report).

التشخيص (من سجلات SYNC_RELINK + تصدير CSV حي):
  • سحبات قديمة بلا expenseUuid (رُفعت قبل migration 68) — الأجهزة تتجاهل
    expenseId الرقمي عمداً (id محلي بجهاز المصدر) → تحذير كل دورة + روابط
    مكسورة + بوابة D1 تمنع الرفع.
  • مستندات مكررة (نفس localUuid بعدة $ids من حقبة ما قبل idempotency).
  • حاسمة: مصروفات السحابة تحمل serverId فارغاً دائماً → المطابقة عبر
    serverId مستحيلة. الحل = نفس حراس migration 68 المحلية:
    (نفس الموظف + نفس المبلغ ±0.005 + نفس اليوم) + فرادة الفتحة.

القواعد المحافظة:
  • لا يُلمس expenseId / relatedId / employeeId إطلاقاً.
  • uuid موجود مختلف → skip (لا تخمين). تعدد مرشحين → يدوي. لا مرشح → يتيم.
  • فحص اتساق reason=exp_NNN مع expenseId الرقمي (تقليد داخلي موثق في
    migration 33 والتقارير) — التعارض → يدوي.
  • idempotent: إعادة التشغيل بعد النجاح = صفر كتابات.

الاستخدام (يتطلب APPWRITE_API_KEY):
  export APPWRITE_API_KEY=standard_xxx
  python3 backfill_withdrawal_expense_uuid.py report   # قراءة فقط (افتراضي)
  python3 backfill_withdrawal_expense_uuid.py apply    # تطبيق فعلي
"""
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

ENDPOINT = os.environ.get('APPWRITE_ENDPOINT', 'https://fra.cloud.appwrite.io/v1')
PROJECT = os.environ.get('APPWRITE_PROJECT_ID', '6a4408f300217885fd7b')
DATABASE = os.environ.get('APPWRITE_DATABASE_ID', '6a4409b50019dd39dde5')
API_KEY = os.environ.get('APPWRITE_API_KEY', '')

W_COLL, E_COLL, EMP_COLL = 'salary_withdrawals', 'expenses', 'employees'
REASON_RE = re.compile(r'^exp_(\d+)$')


class Api:
    def __init__(self, key):
        self.key = key
        self.calls = 0

    def request(self, method, path, payload=None, retries=3):
        url = f'{ENDPOINT}{path}'
        data = json.dumps(payload).encode() if payload is not None else None
        last = None
        for attempt in range(retries):
            req = urllib.request.Request(url, data=data, method=method, headers={
                'X-Appwrite-Project': PROJECT,
                'X-Appwrite-Key': self.key,
                'Content-Type': 'application/json',
            })
            self.calls += 1
            try:
                with urllib.request.urlopen(req, timeout=45) as resp:
                    return json.load(resp)
            except urllib.error.HTTPError as e:
                body = e.read().decode('utf-8', 'replace')
                try:
                    err = json.loads(body)
                except json.JSONDecodeError:
                    err = {'message': body}
                raise RuntimeError(f'{method} {path} -> {e.code}: {err}') from e
            except Exception as e:
                last = e
                continue
        raise RuntimeError(f'{method} {path} -> retries exhausted: {last}')


def list_all(api, collection):
    out, cursor, total = [], None, 0
    while True:
        q = [('queries[]', json.dumps({'method': 'limit', 'values': [100]}))]
        if cursor:
            q.append(('queries[]', json.dumps(
                {'method': 'cursorAfter', 'values': [cursor]})))
        qs = '&'.join(f'{k}={urllib.parse.quote(v)}' for k, v in q)
        res = api.request(
            'GET', f'/databases/{DATABASE}/collections/{collection}/documents?{qs}')
        docs = res.get('documents', [])
        out.extend(docs)
        total = res.get('total', len(out))
        print(f'\r  📥 {collection}: {len(out)}/{total}', end='', flush=True)
        if not docs or len(out) >= total:
            break
        cursor = docs[-1]['$id']
    print()
    return out


def norm_uuid(v):
    if not isinstance(v, str):
        return None
    t = v.strip().lower()
    return t if t else None


def num_val(v):
    if v is None or isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    try:
        f = float(str(v))
        return f if f == f else None
    except (ValueError, TypeError):
        return None


def first_num(doc, *keys):
    for k in keys:
        n = num_val(doc.get(k))
        if n is not None:
            return n
    return None


def first_str(doc, *keys):
    for k in keys:
        v = doc.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return None


def is_deleted(doc):
    d = doc.get('deletedAt', doc.get('deleted_at'))
    if d is None:
        return False
    if isinstance(d, bool):
        return d
    if isinstance(d, (int, float)):
        return d > 0
    return isinstance(d, str) and d.strip() != ''


def same_day(w_day, e_day, e_hdk, w_hdk):
    """مطابقة اليوم حرفياً (دلالة migration 68 المستوى 3) — بلا تسامح زمني."""
    if e_hdk and w_hdk and e_hdk == w_hdk:
        return True
    return bool(e_day and w_day and e_day == w_day)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'report'
    apply = (mode == 'apply')
    if not API_KEY:
        print('❌ عيّن APPWRITE_API_KEY أولاً', file=sys.stderr)
        sys.exit(2)
    api = Api(API_KEY)
    print('════════════════════════════════════════════')
    print(f'🛠  Backfill expenseUuid | mode: {"APPLY ⚡" if apply else "REPORT (قراءة فقط)"}')
    print('════════════════════════════════════════════')

    print('📥 الموظفون...')
    employees = list_all(api, EMP_COLL)
    emp_by_server, emp_uuid_by_server = {}, {}
    for e in employees:
        if is_deleted(e):
            continue
        sid = first_num(e, 'serverId', 'server_id')
        lu = norm_uuid(e.get('localUuid')) or e['$id']
        if sid is not None:
            emp_by_server.setdefault(int(sid), []).append(e)
            emp_uuid_by_server[int(sid)] = lu
    print(f'👥 {len(employees)} موظف')

    print('📥 المصروفات...')
    expenses = list_all(api, E_COLL)
    live_exp = [e for e in expenses if not is_deleted(e)]
    print(f'🧾 {len(expenses)} مصروف ({len(live_exp)} نشط)')

    print('📥 السحوبات...')
    withdrawals = list_all(api, W_COLL)

    groups = {}
    for w in withdrawals:
        lu = norm_uuid(w.get('localUuid')) or w['$id']
        groups.setdefault(lu, []).append(w)
    dups = {k: v for k, v in groups.items() if len(v) > 1}
    print(f'💸 {len(withdrawals)} سحبة | مكررة (نفس localUuid): {len(dups)}')
    for lu, g in list(dups.items())[:50]:
        ids = ', '.join(d['$id'] for d in g)
        canon = '✔' if any(d['$id'] == lu for d in g) else '✘ بلا مرجع!'
        print(f'   🔁 {lu} ×{len(g)} [{canon}]: {ids}')
    if len(dups) > 50:
        print(f'   ... و{len(dups) - 50} مجموعة أخرى')

    fixed = clean = 0
    manual, orphan = [], []
    for w in withdrawals:
        if is_deleted(w):
            continue
        if norm_uuid(w.get('expenseUuid') or w.get('expense_uuid')):
            clean += 1
            continue
        # الموظف: employeeUuid أولاً، ثم حل serverId==employeeId (نهج السكربت الشقيق)
        w_emp = norm_uuid(w.get('employeeUuid') or w.get('employee_uuid')
                          or w.get('employeeLocalUuid') or w.get('employee_local_uuid'))
        if not w_emp:
            w_eid = first_num(w, 'employeeId', 'employee_id')
            if w_eid is not None and int(w_eid) in emp_uuid_by_server:
                w_emp = emp_uuid_by_server[int(w_eid)]
        if not w_emp:
            manual.append((w['$id'], 'بلا employeeUuid ولا حل serverId للموظف'))
            continue
        w_amt = num_val(w.get('amount'))
        if w_amt is None:
            manual.append((w['$id'], 'بلا amount رقمي'))
            continue
        w_day = first_str(w, 'withdrawDate', 'withdraw_date')
        w_hdk = first_str(w, 'hotelDayKey', 'hotel_day_key')
        # فحص اتساق reason=exp_NNN مع expenseId
        reason_m = REASON_RE.match((w.get('reason') or '').strip())
        raw_eid = first_num(w, 'expenseId', 'expense_id')
        if reason_m and raw_eid is not None and int(reason_m.group(1)) != int(raw_eid):
            manual.append((w['$id'],
                           f'تعارض reason={w.get("reason")} مع expenseId={int(raw_eid)}'))
            continue
        cands = []
        for e in live_exp:
            if norm_uuid(e.get('employeeUuid') or e.get('employee_uuid')) != w_emp:
                continue
            e_amt = num_val(e.get('amount'))
            if e_amt is None or abs(e_amt - w_amt) >= 0.005:
                continue
            e_day = first_str(e, 'date')
            e_hdk = first_str(e, 'hotelDayKey', 'hotel_day_key')
            if not same_day(w_day, e_day, e_hdk, w_hdk):
                continue
            cands.append(e)
        if len(cands) == 1:
            exp = cands[0]
            exp_uuid = norm_uuid(exp.get('localUuid')) or exp['$id']
            if apply:
                try:
                    api.request('PATCH',
                        f'/databases/{DATABASE}/collections/{W_COLL}/documents/{w["$id"]}',
                        {'expenseUuid': exp_uuid})
                    rev = norm_uuid(exp.get('withdrawalUuid') or exp.get('withdrawal_uuid'))
                    w_lu = norm_uuid(w.get('localUuid')) or w['$id']
                    if not rev:
                        api.request('PATCH',
                            f'/databases/{DATABASE}/collections/{E_COLL}/documents/{exp["$id"]}',
                            {'withdrawalUuid': w_lu})
                    elif rev != w_lu:
                        print(f'   ⚠️  المصروف {exp["$id"]} يحمل withdrawalUuid مختلف ({rev}) — تُرك')
                    fixed += 1
                except Exception as ex:
                    manual.append((w['$id'], f'فشل التحديث: {ex}'))
            else:
                fixed += 1
            print(f'  ✅ {w["$id"]} → مصروف {exp["$id"]} ({exp_uuid}) مبلغ={w_amt:g} يوم={w_day or w_hdk}')
        elif len(cands) > 1:
            manual.append((w['$id'], f'تعدد مرشحين ({len(cands)}) — خطر ربط خاطئ'))
        else:
            if raw_eid is None:
                manual.append((w['$id'], 'بلا expenseId رقمي ولا مرشح مطابق'))
            else:
                orphan.append((w['$id'], int(raw_eid)))
    print('════════════════════════════════════════════')
    print(f'🏁 سليم={clean} | شُفي={fixed}{"" if apply else " (تقرير فقط)"} | يدوي={len(manual)} | يتيم={len(orphan)}')
    for i, m in manual[:50]:
        print(f'   ⚠️  يدوي: {i} — {m}')
    for i, e in orphan[:50]:
        print(f'   🗑  يتيم: {i} (expenseId={e})')
    print(f'🔌 API calls: {api.calls}')
    if not apply and fixed > 0:
        print('💡 راجع القوائم ثم أعد التشغيل مع apply للتطبيق.')


if __name__ == '__main__':
    main()
