#!/usr/bin/env python3
"""
Appwrite Cloud migration: mirror uuid link attributes + backfill.

Same fix family as PR #601 (employee_uuid) and PR #609 (cycle_uuid), applied
to Appwrite Cloud (user request: "واصلا ذلك في appwrite cloud"):

  1. expenses.withdrawalUuid        (string 36, optional)
  2. salary_withdrawals.expenseUuid (string 36, optional)
  3. Backfill existing documents from the deterministic 1:1 pairs computed
     from appwrite_snapshot_2026-10-02 (same-employee + same-amount +
     same-day, exactly one candidate per side — SalaryMirrorMatcher L3
     semantics). Cross-employee and ambiguous slots stay UNLINKED by design.

Usage (requires an Appwrite API key with databases/documents scopes —
Appwrite Console → Overview → Integrations → API Keys):

  APPWRITE_API_KEY=standard_xxx python3 appwrite_apply_uuid_fix.py            # apply
  APPWRITE_API_KEY=standard_xxx python3 appwrite_apply_uuid_fix.py --dry-run  # plan only
  APPWRITE_API_KEY=standard_xxx python3 appwrite_apply_uuid_fix.py --live-pair # + live Tier-1 pass for new rows

Endpoint/project/database defaults match mobile/lib/services/appwrite_config.dart.
Idempotent: attribute creation ignores code 409 (exists), document PATCH only
touches docs whose uuid field is empty.
"""
import argparse
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

PAIRS_FILE = os.environ.get(
    'UUID_PAIRS_FILE',
    '/home/z/my-project/download/appwrite_uuid_backfill.json',
)


class Api:
    def __init__(self, key):
        self.key = key
        self.calls = 0

    def request(self, method, path, payload=None):
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
            # 409 = already exists → treat as success (idempotency)
            if e.code == 409:
                return {'status': 'already-exists'}
            raise RuntimeError(f'{method} {path} -> {e.code}: {err}') from e


def create_string_attribute(api, collection, key):
    """Create an optional string(36) attribute; 409 → exists."""
    return api.request(
        'POST',
        f'/databases/{DATABASE}/collections/{collection}/attributes/string',
        {'key': key, 'size': 36, 'required': False},
    )


def wait_attribute(api, collection, key, timeout_s=180):
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        attr = api.request(
            'GET',
            f'/databases/{DATABASE}/collections/{collection}/attributes/{key}',
        )
        status = attr.get('status')
        if status == 'available':
            return
        if status == 'stuck':
            raise RuntimeError(
                f'attribute {collection}.{key} is stuck — check Appwrite console')
        time.sleep(3)
    raise RuntimeError(f'timeout waiting for {collection}.{key}')


def list_all_documents(api, collection):
    out = []
    cursor = None
    while True:
        q = ['limit(100)']
        if cursor:
            q.append(f'cursorAfter("{cursor}")')
        page = api.request(
            'GET',
            f'/databases/{DATABASE}/collections/{collection}/documents'
            f'?queries={json.dumps(q)}',
        )
        docs = page.get('documents', [])
        out.extend(docs)
        if len(docs) < 100:
            return out
        cursor = docs[-1]['$id']


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--live-pair', action='store_true',
                    help='after backfill, run a live Tier-1 pairing pass '
                         'over documents still missing uuids (created after '
                         'the snapshot)')
    args = ap.parse_args()

    if not API_KEY:
        print('❌ APPWRITE_API_KEY is required (databases + documents scopes)')
        print('   APPWRITE_API_KEY=standard_xxx python3 appwrite_apply_uuid_fix.py')
        sys.exit(2)

    api = Api(API_KEY)
    pairs = json.load(open(PAIRS_FILE))
    meta = pairs['meta']
    print(f"pairs snapshot: {meta.get('snapshot')} "
          f"(exact_pairs={meta.get('exact_pairs')}, "
          f"rule={meta.get('rule')})")

    plan = [
        ('attribute', 'expenses', 'withdrawalUuid'),
        ('attribute', 'salary_withdrawals', 'expenseUuid'),
        ('backfill', 'expenses', 'withdrawalUuid', len(pairs['expenses'])),
        ('backfill', 'salary_withdrawals', 'expenseUuid', len(pairs['withdrawals'])),
    ]
    print('\n== plan ==')
    for step in plan:
        print('  ', step)
    if args.dry_run:
        print('\n(dry-run — nothing executed)')
        return

    # ── 1. attributes ──
    for coll, key in [('expenses', 'withdrawalUuid'),
                      ('salary_withdrawals', 'expenseUuid')]:
        create_string_attribute(api, coll, key)
        print(f'✓ attribute ensured: {coll}.{key}')
    for coll, key in [('expenses', 'withdrawalUuid'),
                      ('salary_withdrawals', 'expenseUuid')]:
        wait_attribute(api, coll, key)
        print(f'✓ attribute available: {coll}.{key}')

    # ── 2. backfill via deterministic pairs ──
    def apply_pairs(coll, uuid_key, pair_key, rows):
        done = skipped = missing = 0
        for p in rows:
            target_uuid = p[pair_key]
            doc_id = p['$id']
            try:
                doc = api.request(
                    'GET',
                    f'/databases/{DATABASE}/collections/{coll}'
                    f'/documents/{doc_id}',
                )
            except RuntimeError as e:
                if '404' in str(e):
                    missing += 1
                    continue
                raise
            current = doc.get(uuid_key)
            if current == target_uuid:
                skipped += 1
                continue
            if current:  # already linked to something else — never overwrite
                skipped += 1
                continue
            api.request(
                'PATCH',
                f'/databases/{DATABASE}/collections/{coll}'
                f'/documents/{doc_id}',
                {'data': {uuid_key: target_uuid}},
            )
            done += 1
        print(f'  {coll}.{uuid_key}: patched={done} skipped={skipped} '
              f'missing={missing}')
        return done

    print('\n== backfill (snapshot pairs) ==')
    apply_pairs('salary_withdrawals', 'expenseUuid', 'expense_uuid',
                pairs['withdrawals'])
    apply_pairs('expenses', 'withdrawalUuid', 'withdrawal_uuid',
                pairs['expenses'])

    # ── 3. optional live Tier-1 pass for post-snapshot rows ──
    if args.live_pair:
        print('\n== live Tier-1 pairing (1:1 same-employee/amount/day) ==')
        sw_docs = [d for d in list_all_documents(api, 'salary_withdrawals')
                   if not d.get('deletedAt')]
        exp_docs = [d for d in list_all_documents(api, 'expenses')
                    if not d.get('deletedAt')]
        CASH = {'سحب راتب', 'سحب من الراتب', 'رواتب'}
        DEDU = {'خصم من الراتب', 'خصم راتب'}

        def day(doc, *keys):
            import re
            for k in keys:
                v = str(doc.get(k) or '').strip()
                m = re.match(r'^(\d{4}-\d{2}-\d{2})', v)
                if m:
                    return m.group(1)
            return None

        def amt(v):
            try:
                return round(float(v), 2)
            except (TypeError, ValueError):
                return None

        slot_w, slot_e = {}, {}
        for w in sw_docs:
            k = (w.get('employeeUuid'), day(w, 'withdrawDate', 'date'),
                 amt(w.get('amount')))
            if k[0] and k[1] and k[2]:
                slot_w.setdefault(k, []).append(w)
        for e in exp_docs:
            t = (e.get('expenseType') or '').strip()
            if t not in CASH and t not in DEDU:
                continue
            k = (e.get('employeeUuid'), day(e, 'date'), amt(e.get('amount')))
            if k[0] and k[1] and k[2]:
                slot_e.setdefault(k, []).append(e)
        live = 0
        for k, ws in slot_w.items():
            es = slot_e.get(k, [])
            if len(ws) == 1 and len(es) == 1 and not es[0].get('withdrawalUuid'):
                w, e = ws[0], es[0]
                api.request('PATCH',
                            f'/databases/{DATABASE}/collections/'
                            f'salary_withdrawals/documents/{w["$id"]}',
                            {'data': {'expenseUuid': e['$id']}})
                api.request('PATCH',
                            f'/databases/{DATABASE}/collections/'
                            f'expenses/documents/{e["$id"]}',
                            {'data': {'withdrawalUuid': w['$id']}})
                live += 1
        print(f'  live pairs linked: {live}')

    print(f'\n✅ done — {api.calls} API calls total')


if __name__ == '__main__':
    main()
