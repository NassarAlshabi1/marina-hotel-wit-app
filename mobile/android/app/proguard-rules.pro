# ──────────────────────────────────────────────
# ProGuard / R8 rules — Marina Hotel
# ──────────────────────────────────────────────

# Flutter engine + embedding
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# AndroidX Lifecycle (used by many plugins)
-keep class androidx.lifecycle.DefaultLifecycleObserver
-keep class androidx.lifecycle.FullLifecycleObserver

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Appwrite
-keep class io.appwrite.** { *; }
-dontwarn io.appwrite.**

# OkHttp / Dio (networking)
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep serialization metadata
-keepattributes Exceptions, InnerClasses, Signature, Deprecated, SourceFile, LineNumberTable, *Annotation*, EnclosingMethod, RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations

# Keep Kotlin metadata for reflection
-keep class kotlin.Metadata { *; }

# Drift / SQLite runtime (reflection-based)
-keep class **.g.** { *; }
-keep class **.freezed.** { *; }
# ✅ تم إزالة "-keep class _\$** { *; }" — غير صالحة لـ R8 (تسبب Build failure)
# ملفات Drift/Freezed مغطاة بالقواعد أعلاه
-dontwarn java.lang.ClassValue

# Suppress warnings for optional dependencies
-dontwarn org.jetbrains.annotations.**
-dontwarn javax.annotation.**
-dontwarn kotlin.**
-dontwarn com.google.errorprone.**
