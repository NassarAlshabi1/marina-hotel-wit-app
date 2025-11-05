#!/bin/bash

# ============================================================================
# دليل تشغيل سريع - اختبارات Supabase
# Quick Run Guide - Supabase Tests
# ============================================================================

cat << "EOF"

╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║      🎉 اختبارات Supabase جاهزة للتشغيل! 🎉                   ║
║         Supabase Tests Ready to Run!                            ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

═════════════════════════════════════════════════════════════════

✅ تم تكوين الإعدادات | Credentials Configured:

   URL: https://mjsexsrrjphcgpvqcisb.supabase.co
   User: adenmarina2@gmail.com
   Status: ✅ جاهز

═════════════════════════════════════════════════════════════════

🚀 خيارات التشغيل | Run Options:

   1️⃣  تشغيل سريع (30 ثانية):
       $ ./quick_test.sh

   2️⃣  تشغيل كامل مع فحص:
       $ ./run_supabase_tests.sh

   3️⃣  تشغيل يدوي:
       $ cd mobile && flutter pub get && cd ..
       $ flutter test test/supabase_sync_test.dart

   4️⃣  عبر GitHub Actions:
       $ git push origin Ali
       ثم: Actions tab في GitHub

═════════════════════════════════════════════════════════════════

⚠️  قبل التشغيل | Before Running:

   تأكد من إعداد (20 دقيقة):
   
   ☐ قاعدة البيانات (جداول + RLS)
   ☐ Edge Functions منشورة
   ☐ مستخدم اختبار موجود
   
   راجع: SUPABASE_SETUP_GUIDE.md

═════════════════════════════════════════════════════════════════

📚 الوثائق | Documentation:

   🔥 README_QUICK.txt            ← هذا الملف
   ⚠️  SECURITY_WARNING.md         ← اقرأه أولاً!
   📖 SUPABASE_SETUP_GUIDE.md     ← دليل الإعداد
   📋 FINAL_SUMMARY.md            ← ملخص شامل

═════════════════════════════════════════════════════════════════

🎯 اختبار سريع | Quick Test:

   هل أنت جاهز؟
   
   $ ./quick_test.sh
   
   النتيجة المتوقعة:
   ✅ All 14 tests passed! 🎉

═════════════════════════════════════════════════════════════════

💡 نصيحة | Tip:

   إذا فشل الاختبار الأول، غالباً بسبب:
   - قاعدة البيانات غير مُعدة
   - Edge Functions غير منشورة
   - مستخدم الاختبار غير موجود
   
   راجع: SUPABASE_SETUP_GUIDE.md

═════════════════════════════════════════════════════════════════

EOF

read -p "اضغط Enter لعرض دليل الإعداد... | Press Enter for setup guide..." 

cat << "EOF"

═════════════════════════════════════════════════════════════════

📖 دليل الإعداد السريع | Quick Setup Guide:

1️⃣  قاعدة البيانات (10 دقائق):
    
    في Supabase Dashboard > SQL Editor:
    
    -- أنشئ الجداول الأساسية
    CREATE TABLE rooms (...);
    CREATE TABLE bookings (...);
    -- راجع SUPABASE_SETUP_GUIDE.md للكود الكامل

2️⃣  Edge Functions (5 دقائق):
    
    $ npm install -g supabase
    $ supabase login
    $ supabase link --project-ref mjsexsrrjphcgpvqcisb
    $ supabase functions deploy sync-push
    $ supabase functions deploy sync-pull

3️⃣  مستخدم الاختبار (2 دقيقة):
    
    Dashboard > Authentication > Users > Add User
    Email: adenmarina2@gmail.com
    Password: Tottinnbb007
    Auto-confirm: ✅

4️⃣  التشغيل:
    
    $ ./quick_test.sh

═════════════════════════════════════════════════════════════════

✅ Done! الآن جاهز 100%

EOF
