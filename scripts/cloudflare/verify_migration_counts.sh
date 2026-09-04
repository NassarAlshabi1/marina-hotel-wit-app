#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  verify_migration_counts.sh — بوابة التحقق (المرحلة 5.3)
#  مقارنة عدّادات /api/stats (D1) مقابل قاعدة SQLite محلية حقيقية
#  (نسخة .db خام — ميزة Task 21).
#
#  الاستخدام:
#    ./verify_migration_counts.sh <worker_url> <jwt_token> <local.db>
#
#  ملاحظة: العدّادات تشمل tombstones (deleted_at) على الطرفين —
#  المقارنة على المستوى الخام عادلة لأن الترحيل ينقل الصفوف كاملة.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

WORKER_URL="${1:?worker url مطلوب (مثل https://marina-worker.example.workers.dev)}"
JWT="${2:?jwt token مطلوب}"
DB_FILE="${3:?مسار ملف .db المحلي مطلوب}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "▶ جلب عدّادات D1 من $WORKER_URL/api/stats"
curl -sf -H "Authorization: Bearer $JWT" "$WORKER_URL/api/stats" > "$TMP/stats.json"
python3 - "$TMP/stats.json" "$DB_FILE" << 'PYEOF'
import json, sqlite3, sys

stats = json.load(open(sys.argv[1]))
tables = stats.get('tables', {})
db = sqlite3.connect(f'file:{sys.argv[2]}?mode=ro', uri=True)
# عدّاد لكل جدول مستخدم في D1 (نفس استعلام Task 21: sqlite_master)
local = {}
for (name,) in db.execute(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'drift_%' AND name NOT LIKE '_cf_%'"
):
    local[name] = db.execute(f'SELECT COUNT(*) FROM "{name}"').fetchone()[0]

mismatches, compared = [], 0
for entity, cloud_count in sorted(tables.items()):
    if entity in ('rate_limits', 'idempotency_log', 'sync_log', 'sync_conflicts', 'users', 'devices'):
        continue  # بنية تحتية D1 — بلا مرآة محلية مباشرة
    local_count = local.get(entity)
    if local_count is None:
        continue  # كيان D1 بلا جدول محلي بنفس الاسم (users/devices...)
    compared += 1
    mark = '✅' if local_count == cloud_count else '❌'
    if local_count != cloud_count:
        mismatches.append(entity)
    print(f"{mark} {entity:32} local={local_count:>7}  d1={cloud_count:>7}")

print(f"\nمُقارَن: {compared} كياناً | فروق: {len(mismatches)}")
if mismatches:
    print("❌ كيانات غير مطابقة:", ', '.join(mismatches))
    sys.exit(1)
print("✅ تطابق كامل — بوابة المرحلة 5.3 (العدّادات) ناجحة")
PYEOF

echo ""
echo "▶ التالي: عينات عشوائية صف-بصف (المرحلة 5.3) + قائمة E2E (القسم 9.2)"
