#!/usr/bin/env python3
"""
Appwrite Cloud migration v2: mirror uuid link — plan / backup / apply / reconcile.

الترتيب الإلزامي (لا يُعكس):
    plan  →  backup  →  apply  →  reconcile

المبادئ المحافظة:
  • لا يُلمس expenseId / relatedId إطلاقاً — الحقول الصحيحة القديمة تبقى كما هي.
  • يُكتب فقط مفتاح uuid المعني (expenseUuid على السحبة / withdrawalUuid على المصروف).
  • حارس عدم الكتابة فوق: uuid موجود ومختلف ⇒ skip + تسجيل في التقرير (لا تخمين).
  • النسخ الاحتياطي الكامل قبل أي كتابة ⇒ قابل للاستعادة بالكامل، صفر فقدان بيانات.
  • reconcile يقارن كل حقول المستند مع النسخة الاحتياطية (عدا updatedAt ومفتاح uuid).
  • idempotent: تشغيل apply ثانية بعد النجاح = صفر كتابات.

المدخلات (أي أحدهما):
  --pairs-csv  CSV بالروابط المؤكدة (withdrawalLocalUuid,expenseLocalUuid,...)
               الافتراضي: scripts/appwrite/data/confirmed_historical_links.csv
  --pairs-json JSON بأزواج snapshot {'withdrawals':[{'$id','expense_uuid'}],
               'expenses':[{'$id','withdrawal_uuid'}]}

الاستخدام (يتطلب APPWRITE_API_KEY بصلاحيات databases/documents):
  export APPWRITE_API_KEY=standard_xxx
  python3 apply_uuid_mirror_fix.py plan
  python3 apply_uuid_mirror_fix.py backup
  python3 apply_uuid_mirror_fix.py apply
  python3 apply_uuid_mirror_fix.py reconcile

التقارير تُكتب في مجلد download/ (أو OUT_DIR).
"""
import argparse
import csv
import json
import os
import sys
import time
import urllib.error
import urllib.request

ENDPOINT = os.environ.get('APPWRITE_ENDPOINT', 'https://fra.cloud.appwrite.io/v1')
PROJECT = os.environ.get('APPWRITE_PROJECT_ID', '6a4408f300217885fd7b')
DATABASE = os.environ.get('APPWRITE_DATABASE_ID', '6a4409b50019dd39dde5')
API_KEY = os.environ.get('APPWRITE_API_KEY', '')
OUT_DIR = os.environ.get('APPWRITE_REPORT_DIR', '/home/z/my-project/download')

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CSV = os.path.join(SCRIPT_DIR, 'data', 'confirmed_historical_links.csv')

W_COLL, E_COLL = 'salary_withdrawals', 'expenses'
W_KEY, E_KEY = 'expenseUuid', 'withdrawalUuid'
UUID_KEYS = {W_COLL: W_KEY, E_COLL: E_KEY}


class Api:
    def __init__(self, key):
        self.key = key
        self.calls = 0

    def request(self, method, path, payload=None, ok_409=False, ok_404=False):
        url = f'{ENDPOINT}{path}'
        data = json.dumps(payload).encode() if payload is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers={
            'X-Appwrite-Project': PROJECT,
            'X-Appwrite-Key': self.key,
            'Content-Type': 'application/json',
        })
        self.calls += 1
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as e:
            body = e.read().decode('utf-8', 'replace')
            try:
                err = json.loads(body)
            except json.JSONDecodeError:
                err = {'message': body}
            if e.code == 409 and ok_409:
                return {'status': 'already-exists'}
            if e.code == 404 and ok_404:
                return {'status': 'not-found'}
            raise RuntimeError(f'{method} {path} -> {e.code}: {err}') from e


# ───────────────────────── pairs loading ─────────────────────────

def load_pairs(args):
    """→ list of {'withdrawal_id','expense_id','source'}"""
    pairs = []
    if getattr(args, 'pairs_json', None):
        data = json.load(open(args.pairs_json, encoding='utf-8'))
        for p in data.get('withdrawals', []):
            pairs.append({'withdrawal_id': p['$id'],
                          'expense_id': p['expense_uuid'], 'source': 'json'})
        for p in data.get('expenses', []):
            pairs.append({'withdrawal_id': p['withdrawal_uuid'],
                          'expense_id': p['$id'], 'source': 'json'})
        seen = {(p['withdrawal_id'], p['expense_id']) for p in pairs}
        return [p for p in pairs if (p['withdrawal_id'], p['expense_id']) in seen]
    path = args.pairs_csv
    with open(path, encoding='utf-8-sig') as f:
        for r in csv.DictReader(f):
            wid = (r.get('withdrawalLocalUuid') or '').strip()
            eid = (r.get('expenseLocalUuid') or '').strip()
            if wid and eid:
                pairs.append({'withdrawal_id': wid, 'expense_id': eid,
                              'source': 'csv'})
    # 1:1 sanity — refuse to run on a non-unique list
    wids = [p['withdrawal_id'] for p in pairs]
    eids = [p['expense_id'] for p in pairs]
    assert len(set(wids)) == len(wids), 'duplicate withdrawal in pairs file'
    assert len(set(eids)) == len(eids), 'duplicate expense in pairs file'
    return pairs


# ───────────────────────── helpers ─────────────────────────

def create_string_attribute(api, collection, key):
    return api.request(
        'POST',
        f'/databases/{DATABASE}/collections/{collection}/attributes/string',
        {'key': key, 'size': 36, 'required': False}, ok_409=True)


def wait_attribute(api, collection, key, timeout_s=180):
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        attr = api.request(
            'GET', f'/databases/{DATABASE}/collections/{collection}/attributes/{key}')
        status = attr.get('status')
        if status == 'available':
            return
        if status == 'stuck':
            raise RuntimeError(f'attribute {collection}.{key} is stuck')
        time.sleep(3)
    raise RuntimeError(f'timeout waiting for {collection}.{key}')


def attribute_status(api, collection, key):
    try:
        attr = api.request(
            'GET', f'/databases/{DATABASE}/collections/{collection}/attributes/{key}',
            ok_404=True)
        return attr.get('status', 'not-found') if isinstance(attr, dict) else 'not-found'
    except RuntimeError:
        return 'not-found'


def list_all_documents(api, collection):
    import urllib.parse
    # Appwrite server 2.3.0 (fra.cloud) rejects legacy `queries=["limit(100)"]`
    # strings AND method-strings; it requires JSON-object queries passed as
    # repeated `queries[]` params: {"method":"limit","values":[100]}.
    out, cursor = [], None
    while True:
        qparams = [('queries[]',
                    json.dumps({'method': 'limit', 'values': [100]}))]
        if cursor:
            qparams.append(('queries[]', json.dumps(
                {'method': 'cursorAfter', 'values': [cursor]})))
        qs = urllib.parse.urlencode(qparams)
        page = api.request(
            'GET',
            f'/databases/{DATABASE}/collections/{collection}/documents'
            f'?{qs}')
        docs = page.get('documents', [])
        out.extend(docs)
        if len(docs) < 100:
            return out
        cursor = docs[-1]['$id']


def full_export(api):
    return {W_COLL: list_all_documents(api, W_COLL),
            E_COLL: list_all_documents(api, E_COLL)}


def save_json(name, payload):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    print(f'  → {path}')
    return path


def classify(api, pairs):
    """Classify every pair against live cloud state. Zero writes."""
    live = {W_COLL: {d['$id']: d for d in list_all_documents(api, W_COLL)},
            E_COLL: {d['$id']: d for d in list_all_documents(api, E_COLL)}}
    plan, counts = [], {'ALREADY_LINKED': 0, 'TO_PATCH': 0, 'CONFLICT': 0,
                        'MISSING': 0}
    for p in pairs:
        wid, eid = p['withdrawal_id'], p['expense_id']
        w = live[W_COLL].get(wid)
        e = live[E_COLL].get(eid)
        if w is None or e is None:
            counts['MISSING'] += 1
            plan.append({**p, 'status': 'MISSING',
                         'detail': 'withdrawal' if w is None else 'expense'})
            continue
        cur_w, cur_e = w.get(W_KEY) or '', e.get(E_KEY) or ''
        if cur_w == eid and cur_e == wid:
            counts['ALREADY_LINKED'] += 1
            plan.append({**p, 'status': 'ALREADY_LINKED'})
        elif (cur_w and cur_w != eid) or (cur_e and cur_e != wid):
            counts['CONFLICT'] += 1
            plan.append({**p, 'status': 'CONFLICT',
                         'detail': f'cloud w={cur_w or "∅"} e={cur_e or "∅"}'})
        else:
            counts['TO_PATCH'] += 1
            plan.append({**p, 'status': 'TO_PATCH'})
    return plan, counts


# ───────────────────────── phases ─────────────────────────

def phase_plan(api, pairs, _args):
    print('\n== PLAN (dry-run — صفر كتابات) ==')
    st_w = attribute_status(api, W_COLL, W_KEY)
    st_e = attribute_status(api, E_COLL, E_KEY)
    print(f'  attribute {W_COLL}.{W_KEY}: {st_w}')
    print(f'  attribute {E_COLL}.{E_KEY}: {st_e}')
    plan, counts = classify(api, pairs)
    for k, v in counts.items():
        print(f'  {k}: {v}')
    save_json('appwrite_plan.json', {
        'attributes': {f'{W_COLL}.{W_KEY}': st_w, f'{E_COLL}.{E_KEY}': st_e},
        'counts': counts, 'pairs': plan, 'generated_at': time.time()})
    need_attr = st_e != 'available' or st_w != 'available'
    print(f'\n  verdict: patch={counts["TO_PATCH"]} '
          f'already={counts["ALREADY_LINKED"]} conflict={counts["CONFLICT"]} '
          f'missing={counts["MISSING"]}'
          + ('  [attribute creation needed]' if need_attr else ''))
    return plan, counts


def phase_backup(api, _pairs, _args):
    print('\n== BACKUP (نسخة احتياطية كاملة قبل أي كتابة) ==')
    snap = full_export(api)
    ts = time.strftime('%Y%m%d_%H%M%S')
    save_json(f'appwrite_backup_{ts}.json', {
        'taken_at': time.time(), 'timestamp': ts,
        'endpoint': ENDPOINT, 'project': PROJECT, 'database': DATABASE,
        'counts': {k: len(v) for k, v in snap.items()},
        'collections': snap})
    print(f"  withdrawal docs: {len(snap[W_COLL])}  expense docs: {len(snap[E_COLL])}")
    # expose latest backup path for apply/reconcile in the same run
    with open(os.path.join(OUT_DIR, '.latest_backup'), 'w') as f:
        f.write(f'appwrite_backup_{ts}.json')


def latest_backup_path():
    name = os.environ.get('APPWRITE_BACKUP_FILE')
    if name:
        return name if os.path.isabs(name) else os.path.join(OUT_DIR, name)
    with open(os.path.join(OUT_DIR, '.latest_backup')) as f:
        return os.path.join(OUT_DIR, f.read().strip())


def phase_apply(api, pairs, _args):
    print('\n== APPLY (يُكتب مفتاح uuid فقط — حارس عدم الكتابة فوق) ==')
    backup_path = latest_backup_path()
    if not os.path.exists(backup_path):
        print('  ❌ لا توجد نسخة احتياطية — شغّل backup أولاً (الترتيب إلزامي)')
        sys.exit(3)
    print(f'  backup: {backup_path}')

    st_e = attribute_status(api, E_COLL, E_KEY)
    if st_e != 'available':
        create_string_attribute(api, E_COLL, E_KEY)
        print(f'  ✓ attribute created: {E_COLL}.{E_KEY} (waiting …)')
        wait_attribute(api, E_COLL, E_KEY)
    st_w = attribute_status(api, W_COLL, W_KEY)
    if st_w != 'available':
        create_string_attribute(api, W_COLL, W_KEY)
        print(f'  ✓ attribute created: {W_COLL}.{W_KEY} (waiting …)')
        wait_attribute(api, W_COLL, W_KEY)

    plan, counts = classify(api, pairs)
    if counts['CONFLICT']:
        print(f'  ⚠ {counts["CONFLICT"]} CONFLICT — سيتم تجاوزها وتسجيلها (لا كتابة فوق)')
    patched, skipped_conflict, already, missing = [], [], 0, []
    for p in plan:
        if p['status'] == 'ALREADY_LINKED':
            already += 1
        elif p['status'] == 'CONFLICT':
            skipped_conflict.append(p)
        elif p['status'] == 'MISSING':
            missing.append(p)
        else:
            api.request('PATCH',
                        f'/databases/{DATABASE}/collections/{W_COLL}'
                        f'/documents/{p["withdrawal_id"]}',
                        {'data': {W_KEY: p['expense_id']}})
            api.request('PATCH',
                        f'/databases/{DATABASE}/collections/{E_COLL}'
                        f'/documents/{p["expense_id"]}',
                        {'data': {E_KEY: p['withdrawal_id']}})
            patched.append(p)
    result = {'patched_pairs': len(patched), 'already_linked': already,
              'conflict_skipped': len(skipped_conflict), 'missing': len(missing),
              'conflicts': skipped_conflict, 'missing_pairs': missing,
              'backup_file': os.path.basename(backup_path),
              'api_calls': api.calls}
    save_json('appwrite_apply_result.json', result)
    print(f"  patched={len(patched)} already={already} "
          f"conflict_skipped={len(skipped_conflict)} missing={len(missing)}")


def phase_reconcile(api, pairs, _args):
    print('\n== RECONCILE (uuid صحيح + لا حقل آخر تغيّر) ==')
    backup_path = latest_backup_path()
    backup = json.load(open(backup_path, encoding='utf-8'))
    bidx = {c: {d['$id']: d for d in backup['collections'][c]}
            for c in (W_COLL, E_COLL)}
    apply_res_path = os.path.join(OUT_DIR, 'appwrite_apply_result.json')
    applied = json.load(open(apply_res_path, encoding='utf-8'))
    conflict_ids = {(p['withdrawal_id'], p['expense_id'])
                    for p in applied.get('conflicts', [])}

    live = {W_COLL: {d['$id']: d for d in list_all_documents(api, W_COLL)},
            E_COLL: {d['$id']: d for d in list_all_documents(api, E_COLL)}}

    results, bad = [], []
    stats = {'verified': 0, 'conflict_preserved': 0, 'missing': 0,
             'mutated_fields': 0}
    EXEMPT = {'$updatedAt', W_KEY, E_KEY, 'updatedAt', 'updatedAtIso',
              'lastModified', 'lastModifiedEpoch', 'syncTimestamp'}
    for p in pairs:
        wid, eid = p['withdrawal_id'], p['expense_id']
        w, e = live[W_COLL].get(wid), live[E_COLL].get(eid)
        if w is None or e is None:
            stats['missing'] += 1
            results.append({**p, 'status': 'MISSING'})
            continue
        entry = {'withdrawal_id': wid, 'expense_id': eid}
        # uuid correctness
        uuid_ok = (w.get(W_KEY) == eid and e.get(E_KEY) == wid)
        # field mutation check vs backup (uuid keys + volatile stamps exempt)
        mutated = []
        for coll, doc, other in ((W_COLL, w, eid), (E_COLL, e, wid)):
            b = bidx[coll].get(doc['$id'])
            if b is None:
                mutated.append(f'{coll}:no-backup-doc')
                continue
            for k, v in doc.items():
                if k in EXEMPT:
                    continue
                if b.get(k) != v:
                    mutated.append(f'{coll}.{k}')
            entry[f'{coll}_uuid'] = doc.get(UUID_KEYS[coll])
        if not uuid_ok:
            if (wid, eid) in conflict_ids:
                stats['conflict_preserved'] += 1
                entry['status'] = 'conflict_preserved'
            else:
                stats['mutated_fields'] += 1
                bad.append({**entry, 'problem': 'uuid_mismatch'})
                entry['status'] = 'UUID_MISMATCH'
        elif mutated:
            stats['mutated_fields'] += 1
            bad.append({**entry, 'problem': 'mutated:' + ','.join(mutated)})
            entry['status'] = 'MUTATED'
        else:
            stats['verified'] += 1
            entry['status'] = 'VERIFIED'
        results.append(entry)

    ok = stats['mutated_fields'] == 0
    verdict = ('PASS' if ok else 'FAIL') + (
        ' — conflict_preserved docs keep their pre-existing link by design'
        if stats['conflict_preserved'] else '')
    save_json('appwrite_reconciliation.json', {
        'verdict': verdict, 'stats': stats, 'bad': bad[:100],
        'results': results, 'backup_file': os.path.basename(backup_path)})
    print(f"  verified={stats['verified']} conflict_preserved="
          f"{stats['conflict_preserved']} missing={stats['missing']} "
          f"mutated={stats['mutated_fields']}")
    print(f'\n  ✅ RECONCILE {verdict}' if ok else f'\n  ❌ RECONCILE {verdict}')
    return 0 if ok else 4


# ───────────────────────── main ─────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('phase', choices=['plan', 'backup', 'apply', 'reconcile',
                                      'dry-run'])
    ap.add_argument('--pairs-csv', default=DEFAULT_CSV)
    ap.add_argument('--pairs-json',
                    default=os.environ.get('UUID_PAIRS_FILE'))
    args = ap.parse_args()
    if args.phase == 'dry-run':        # backwards compatibility
        args.phase = 'plan'
    if not API_KEY:
        print('❌ APPWRITE_API_KEY مطلوب (databases + documents scopes)')
        print('   export APPWRITE_API_KEY=standard_xxx')
        sys.exit(2)

    api = Api(API_KEY)
    pairs = load_pairs(args)
    print(f'pairs: {len(pairs)}  (source: {pairs[0]["source"] if pairs else "-"})')

    if args.phase == 'plan':
        phase_plan(api, pairs, args)
    elif args.phase == 'backup':
        phase_backup(api, pairs, args)
    elif args.phase == 'apply':
        phase_apply(api, pairs, args)
    elif args.phase == 'reconcile':
        sys.exit(phase_reconcile(api, pairs, args))
    print(f'\n({api.calls} API calls)')


if __name__ == '__main__':
    main()
