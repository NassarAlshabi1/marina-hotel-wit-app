# ProGuard / R8 rules for Marina Hotel Kotlin app.
#
# Release builds run with minifyEnabled + shrinkResources
# (proguard-android-optimize.txt). WITHOUT the -keepattributes below, R8
# strips the annotations and generic signatures that Hilt / Retrofit / Gson /
# Room rely on at runtime — the app then crashes instantly on open in release
# while debug (no minify) works fine. Do NOT remove the keepattributes block.

# ── Attributes: must be kept for DI + reflection + Crashlytics ──────────────
-keepattributes *Annotation*
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations, AnnotationDefault
-keepattributes Exceptions
-keepattributes SourceFile, LineNumberTable

# ── Hilt / Dagger ────────────────────────────────────────────────────────────
-keep class dagger.hilt.** { *; }
-keep class dagger.hilt.internal.** { *; }
-keep class dagger.hilt.android.** { *; }
-keep class androidx.hilt.** { *; }
-keep class javax.inject.** { *; }
-keep class com.marina.marina.di.** { *; }
-keep @dagger.hilt.android.HiltAndroidApp class * { *; }
-keep @dagger.hilt.android.AndroidEntryPoint class * { *; }
-keep @dagger.hilt.android.lifecycle.HiltViewModel class * { *; }
-keep class * extends dagger.hilt.internal.ComponentManager { *; }
-keep class dagger.hilt.android.internal.managers.** { *; }
-keep class * extends dagger.hilt.android.internal.managers.ViewComponentManager$FragmentContextWrapper

# ── App entry points (never obfuscate away) ──────────────────────────────────
-keep public class com.marina.marina.MarinaApp { *; }
-keep public class com.marina.marina.MainActivity { *; }
-keep class * extends androidx.lifecycle.ViewModel { *; }
-keep class * extends android.app.Application { *; }
-keep class * extends androidx.activity.ComponentActivity { *; }

# ── Kotlin ───────────────────────────────────────────────────────────────────
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# ── Room database, entities and generated implementations ────────────────────
-keep class * extends androidx.room.RoomDatabase { *; }
-keep @androidx.room.Entity class * { *; }
-keep @androidx.room.DatabaseView class * { *; }
-keep @androidx.room.Dao class * { *; }
-keepclassmembers class * extends androidx.room.RoomDatabase { *; }
-keepclassmembers class *_Impl { *; }
-keep class androidx.room.paging.** { *; }

# ── Kotlin coroutines ────────────────────────────────────────────────────────
-dontwarn kotlinx.coroutines.**
-keepclassmembers class kotlinx.coroutines.internal.MainDispatcherFactory { *; }
-keepclassmembers class kotlinx.coroutines.android.AndroidDispatcherFactory { *; }
-dontwarn kotlinx.coroutines.internal.MainDispatcherConfigurer

# ── Gson (reflection-based serialization) ────────────────────────────────────
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep class * implements com.google.gson.JsonDeserializer
-keep class * implements com.google.gson.JsonSerializer
-keepclassmembers,allowshrinking,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ── App model / DTO classes ──────────────────────────────────────────────────
-keep class com.marina.marina.data.** { *; }
-keep class com.marina.marina.domain.** { *; }

# ── Retrofit / OkHttp / Okio ─────────────────────────────────────────────────
-keep,allowobfuscation,allowshrinking interface retrofit2.Call
-keep,allowshrinking,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}
-keep class retrofit2.** { *; }
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn retrofit2.**
-dontwarn okhttp3.**
-dontwarn okio.**

# ── DataStore / WorkManager (ship consumer rules; explicit keeps as guard) ──
-keep class androidx.datastore.** { *; }
-dontwarn androidx.datastore.**
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.ListenableWorker { *; }

# ── Firebase / Play services ─────────────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ── Coil image loading ───────────────────────────────────────────────────────
-keep class coil.** { *; }
-dontwarn coil.**

# ── Navigation Compose ───────────────────────────────────────────────────────
-keep class androidx.navigation.** { *; }

# ── Enums / Parcelable / Serializable ────────────────────────────────────────
-keepclassmembers enum * { *; }
-keepclassmembers class * implements android.os.Parcelable { *; }
-keepclassmembers class * implements java.io.Serializable { *; }

# Compose ships its own consumer rules — no broad keeps needed.

# Suppress noisy warnings from optional/annotation-only dependencies
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
-dontwarn androidx.security.**
