# ==============================================================================
# Lauriva Production ProGuard / R8 Rules
# Protects against reverse engineering, shrinks bytecode, and preserves reflection
# ==============================================================================

# --- Flutter Engine & Embedding ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.**  { *; }

# Preserve Dart VM entry points and native methods
-keepclasseswithmembers class * {
    native <methods>;
}

-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes Signature
-keepattributes InnerClasses,EnclosingMethod

# Preserve all entry points marked with @pragma('vm:entry-point')
-keep @interface dart.vm.EntryPoint
-keep @interface androidx.annotation.Keep
-keep @androidx.annotation.Keep class * { *; }
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <fields>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <methods>;
}

# --- Speech Recognition & Text-To-Speech Plugins ---
# speech_to_text plugin reflection & intents
-keep class com.csdcorp.speech_to_text.** { *; }
-keep class android.speech.** { *; }

# flutter_tts reflection & speech engine
-keep class com.tundralabs.fluttertts.** { *; }
-keep class android.speech.tts.** { *; }

# --- Flutter Secure Storage (KeyStore / Cryptography) ---
-keep class androidx.security.crypto.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# --- Shared Preferences ---
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# --- Prevent warnings for optional transitive dependencies ---
-dontwarn io.flutter.**
-dontwarn androidx.**
-dontwarn android.speech.**
-dontwarn javax.annotation.**
