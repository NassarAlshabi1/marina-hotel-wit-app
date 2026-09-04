#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  staging_setup.sh — بيئة D1 تجريبية (خطة الانتقال — المرحلة 5.1)
#  المصدر: خطة_الانتقال_إلى_Cloudflare_Worker.md — ملحق ج
#  المتطلبات: wrangler مسجّل الدخول (npx wrangler login)
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

DB_NAME="${1:-marina-hotel-db-staging}"
WORKER_DIR="$(cd "$(dirname "$0")/../.." && pwd)/worker"

echo "▶ إنشاء قاعدة D1 التجريبية: $DB_NAME"
npx --prefix "$WORKER_DIR" wrangler d1 create "$DB_NAME"

echo ""
echo "⚠️  انسخ database_id من المخرجات أعلاه إلى worker/wrangler.toml"
echo "   (أو صدّره لبيئة staging منفصلة عبر --config)"
echo ""
echo "▶ تطبيق المخطط الكامل (schema.sql)"
npx --prefix "$WORKER_DIR" wrangler d1 execute "$DB_NAME" --remote --file="$WORKER_DIR/schema.sql"

echo "▶ تطبيق الهجرات (0002_inventory_blacklist.sql)"
npx --prefix "$WORKER_DIR" wrangler d1 execute "$DB_NAME" --remote --file="$WORKER_DIR/migrations/0002_inventory_blacklist.sql"

echo ""
echo "▶ (يدوي موصى به) ضبط سر JWT للبيئة التجريبية:"
echo "   npx wrangler secret put JWT_SECRET   # ≥64 بايت عشوائية"
echo ""
echo "▶ النشر التجريبي:"
echo "   npx wrangler versions upload   # معاينة بلا ترويج (القسم 10.3)"
echo ""
echo "✅ اكتمل إعداد staging: $DB_NAME"
