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

# If you add Firebase or other SDKs later, append their rules here
