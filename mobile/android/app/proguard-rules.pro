# ProGuard rules for Marina Hotel Kotlin app

# Hilt
-keep class dagger.hilt.internal.** { *; }
-keep class dagger.hilt.android.** { *; }
-keep class androidx.hilt.** { *; }
-keep class com.marina.marina.di.** { *; }
-keep class * extends dagger.hilt.android.internal.managers.ViewComponentManager$FragmentContextWrapper

# Keep Room database, entities and generated implementations
-keep class * extends androidx.room.RoomDatabase { *; }
-keep @androidx.room.Entity class * { *; }
-keep @androidx.room.DatabaseView class * { *; }
-keepclassmembers class * extends androidx.room.RoomDatabase { *; }
-keepclassmembers class *_Impl { *; }
-keep class androidx.room.paging.** { *; }

# Keep Kotlin coroutines
-dontwarn kotlinx.coroutines.**
-keepclassmembers class kotlinx.coroutines.internal.MainDispatcherFactory { *; }
-keepclassmembers class kotlinx.coroutines.android.AndroidDispatcherFactory { *; }
-dontwarn kotlinx.coroutines.internal.MainDispatcherConfigurer

# Keep model / DTO classes for Gson (reflection-based) serialization
-keep class com.marina.marina.data.** { *; }
-keep class com.marina.marina.domain.** { *; }
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep class * implements com.google.gson.JsonDeserializer
-keep class * implements com.google.gson.JsonSerializer

# Keep Retrofit API interfaces
-keep,allowobfuscation,allowshrinking interface retrofit2.Call
-keep,allowshrinking,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}
-dontwarn retrofit2.**
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep Compose runtime (needed for reflection-based tooling / previews)
-keep class androidx.compose.runtime.** { *; }
-keep class androidx.compose.ui.** { *; }

# Suppress noisy warnings from optional/annotation-only dependencies
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
