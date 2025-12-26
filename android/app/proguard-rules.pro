# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep SharedPreferences
-keep class androidx.datastore.** { *; }

# Prevent obfuscation of types which use @GeneratedValue for SharedPreferences
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep Kotlin classes
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# General Android optimizations
-optimizations !code/simplification/arithmetic,!code/simplification/cast,!field/*,!class/merging/*
-optimizationpasses 5
-allowaccessmodification

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep org.json classes (needed for JSON parsing in Kotlin/Java code)
-keep class org.json.** { *; }
-keepclassmembers class org.json.** { *; }

# Keep AndroidX Wear Tiles classes
-keep class androidx.wear.tiles.** { *; }
-keep class androidx.wear.protolayout.** { *; }
-dontwarn androidx.wear.tiles.**
-dontwarn androidx.wear.protolayout.**

# Keep AndroidX Wear Complications classes
-keep class androidx.wear.watchface.complications.** { *; }
-dontwarn androidx.wear.watchface.complications.**

# Keep SharedPreferences related internals
-keep class android.content.SharedPreferences { *; }
-keep class android.content.SharedPreferences$* { *; }
-keep class android.app.SharedPreferencesImpl { *; }

# Keep Guava classes (used by Tiles)
-keep class com.google.common.util.concurrent.** { *; }
-dontwarn com.google.common.util.concurrent.**

# Keep Coroutines
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Prevent stripping of method parameters for error stack traces
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Keep application's own classes (Tile, Complication, MainActivity)
-keep class com.chiscung.quanlychitieu.** { *; }
-keepclassmembers class com.chiscung.quanlychitieu.** { *; }

