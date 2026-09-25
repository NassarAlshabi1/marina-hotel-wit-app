# ──────────────────────────────────────────────
# ProGuard / R8 rules — Marina Hotel
# ──────────────────────────────────────────────

# Flutter engine + embedding
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# ✅ Play Core (referenced by FlutterPlayStoreSplitApplication)
# R8 يفشل بدون هذه القواعد لأن Play Core classes غير موجودة في classpath
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# AndroidX Lifecycle (used by many plugins)
-keep class androidx.lifecycle.DefaultLifecycleObserver
-keep class androidx.lifecycle.FullLifecycleObserver

# Firebase / GMS — قواعد -keep الفضفاضة أُزيلت (تُعطّل تقليص R8 لحزم
# كاملة = تضخّم شائع وموثّق)؛ مكتبات Firebase/GMS تُرفق consumer rules
# خاصة بها داخل AARs فلا حاجة لـ keep هنا.
# ⚠️ لم يُختبر بناء فعلي بعد (لا Flutter SDK محلياً) — قبل التوزيع
#    اختبر على جهاز حقيقي: Google Sign-In، إشعار FCM، حدث Crashlytics.
#    التراجع فوري إن ظهر عطل — أعد السطرين المحذوفين:
#    -keep class com.google.firebase.** { *; }
#    -keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Appwrite
-keep class io.appwrite.** { *; }
-dontwarn io.appwrite.**

# OkHttp / Okio — قواعد -keep الفضفاضة أُزيلت (نفس سبب Firebase)؛
# okhttp/okio يرفقان consumer rules خاصة بهما داخل AARs منذ الإصدارات
# الحديثة، والواجهات المستخدمة تعتمد توليد كود لا reflection.
# ⚠️ نفس شرط الاختبار على جهاز حقيقي والتراجع أعلاه:
#    -keep class okhttp3.** { *; }
#    -keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep serialization metadata
-keepattributes Exceptions, InnerClasses, Signature, Deprecated, SourceFile, LineNumberTable, *Annotation*, EnclosingMethod, RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations

# Keep Kotlin metadata for reflection
-keep class kotlin.Metadata { *; }

# Drift / SQLite runtime (reflection-based)
-keep class **.g.** { *; }
-keep class **.freezed.** { *; }
-dontwarn java.lang.ClassValue

# Suppress warnings for optional dependencies
-dontwarn org.jetbrains.annotations.**
-dontwarn javax.annotation.**
-dontwarn kotlin.**
-dontwarn com.google.errorprone.**
