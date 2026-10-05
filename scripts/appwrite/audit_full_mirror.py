#!/usr/bin/env python3
"""Full mirror-consistency audit v2 (read-only) — deleted-aware.

Distinguishes:
  • links to soft-deleted targets (doc exists, deletedAt set)  → informational
  • links to truly-absent targets (no doc at all)              → real breakage
  • non-mutual links, duplicate targets                        → real breakage
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apply_uuid_mirror_fix import (Api, W_COLL, E_COLL, W_KEY, E_KEY,
                                   list_all_documents, OUT_DIR)  # noqa: E402

api = Api(os.environ['APPWRITE_API_KEY'])
w_all = list_all_documents(api, W_COLL)
e_all = list_all_documents(api, E_COLL)

w_by_id = {d['$id']: d for d in w_all}
e_by_id = {d['$id']: d for d in e_all}
w_deleted = {d['$id'] for d in w_all if d.get('deletedAt')}
e_deleted = {d['$id'] for d in e_all if d.get('deletedAt')}

w_set = {d['$id']: (d.get(W_KEY) or '').strip()
         for d in w_all if (d.get(W_KEY) or '').strip()}
e_set = {d['$id']: (d.get(E_KEY) or '').strip()
         for d in e_all if (d.get(E_KEY) or '').strip()}


def classify_side(side_links, target_by_id, target_deleted, other_set):
    """→ (mutual_alive, mutual_to_deleted, one_way_to_deleted, broken_absent,
          non_mutual_alive, duplicates)"""
    mutual_alive = mutual_del = one_way_del = 0
    broken, non_mutual, dups = [], [], {}
    for src, tgt in side_links.items():
        if tgt not in target_by_id:
            broken.append((src, tgt))
            continue
        back = (other_set.get(tgt) or '')
        if back == src:
            if tgt in target_deleted or src in target_deleted:
                mutual_del += 1
            else:
                mutual_alive += 1
        elif back == '':
            if tgt in target_deleted:
                one_way_del += 1
            else:
                non_mutual.append((src, tgt, 'target-alive-but-unlinked-back'))
        else:
            non_mutual.append((src, tgt, f'points-elsewhere:{back[:12]}'))
    for tgt in side_links.values():
        dups[tgt] = dups.get(tgt, 0) + 1
    dup = {t: c for t, c in dups.items() if c > 1}
    return mutual_alive, mutual_del, one_way_del, broken, non_mutual, dup


ma_w, md_w, ow_w, br_w, nm_w, dp_w = classify_side(
    w_set, e_by_id, e_deleted, e_set)
ma_e, md_e, ow_e, br_e, nm_e, dp_e = classify_side(
    e_set, w_by_id, w_deleted, w_set)

print(f'total docs: withdrawals={len(w_all)} (deleted {len(w_deleted)}), '
      f'expenses={len(e_all)} (deleted {len(e_deleted)})')
print(f'links set: w.expenseUuid={len(w_set)}  e.withdrawalUuid={len(e_set)}')
print(f'w side → mutual-alive={ma_w} mutual-involving-deleted={md_w} '
      f'one-way-to-deleted={ow_w}')
print(f'e side → mutual-alive={ma_e} mutual-involving-deleted={md_e} '
      f'one-way-to-deleted={ow_e}')
print(f'BROKEN (target absent entirely): w→e={len(br_w)} e→w={len(br_e)}')
for s, t in br_w[:10]:
    print(f'   w {s} → missing expense {t}')
for s, t in br_e[:10]:
    print(f'   e {s} → missing withdrawal {t}')
print(f'non-mutual (alive): w={len(nm_w)} e={len(nm_e)}')
for item in (nm_w + nm_e)[:10]:
    print(f'   non-mutual: {item}')
print(f'duplicate targets: w={dp_w or "none"} e={dp_e or "none"}')

hard_fail = br_w or br_e or nm_w or nm_e or dp_w or dp_e
verdict = 'FAIL' if hard_fail else 'PASS'
print(f'\nFULL MIRROR AUDIT (deleted-aware): {verdict}')

result = {
    'verdict': verdict,
    'total': {'salary_withdrawals': len(w_all), 'deleted_w': len(w_deleted),
              'expenses': len(e_all), 'deleted_e': len(e_deleted)},
    'links_set': {'w.expenseUuid': len(w_set), 'e.withdrawalUuid': len(e_set)},
    'w_side': {'mutual_alive': ma_w, 'mutual_involving_deleted': md_w,
               'one_way_to_deleted': ow_w, 'broken_absent': br_w,
               'non_mutual': nm_w, 'duplicates': dp_w},
    'e_side': {'mutual_alive': ma_e, 'mutual_involving_deleted': md_e,
               'one_way_to_deleted': ow_e, 'broken_absent': br_e,
               'non_mutual': nm_e, 'duplicates': dp_e},
    'api_calls': api.calls,
}
os.makedirs(OUT_DIR, exist_ok=True)
path = os.path.join(OUT_DIR, 'appwrite_full_mirror_audit.json')
with open(path, 'w', encoding='utf-8') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
print(f'→ {path}')
sys.exit(0 if verdict == 'PASS' else 4)
