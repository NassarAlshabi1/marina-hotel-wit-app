# Flutter and common Android libraries keep rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep lifecycle to avoid obfuscation issues with some plugins
-keep class androidx.lifecycle.DefaultLifecycleObserver
-keep class androidx.lifecycle.FullLifecycleObserver

# Keep annotations and signatures for reflection-based libraries
-keepattributes Exceptions, InnerClasses, Signature, Deprecated, SourceFile, LineNumberTable, *Annotation*, EnclosingMethod

# Reduce noise from common annotations and kotlin
-dontwarn org.jetbrains.annotations.**
-dontwarn javax.annotation.**
-dontwarn kotlin.**

# Dio/OkHttp are Dart-side; no Android rules required
# Drift/SQLite use generated Dart code; no Java rules required

# Ditto Live - P2P Sync
-keep class live.ditto.** { *; }
-keep interface live.ditto.** { *; }
-dontwarn live.ditto.**

# Google APIs (googleapis)
-keep class com.google.api.** { *; }
-keep class com.google.api.client.** { *; }
-dontwarn com.google.api.**
-dontwarn com.google.api.client.**

# Google Auth
-keep class com.google.auth.** { *; }
-dontwarn com.google.auth.**

# Google Sign In
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

# PDF libraries
-keep class com.itextpdf.** { *; }
-dontwarn com.itextpdf.**

# WorkManager (للـ background tasks)
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.CoroutineWorker

# Drift (SQLite ORM)
-keep class drift.** { *; }
-keep class ** extends drift.DatabaseConnectionUser { *; }

# Sqflite
-keep class com.tekartik.sqflite.** { *; }

# Preserve line numbers for debugging crashes
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# If you add Firebase or other SDKs later, append their rules here
