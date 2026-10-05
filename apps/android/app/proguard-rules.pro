# Release builds run R8 to remove the unused parts of the libraries (Compose, AndroidX, Kotlin,
# OkHttp, ML Kit), which were most of the app's 49 MB of code. It is set up to be as safe as it can be:
#
# - Nothing is renamed, so crash reports and logs read as before.
# - The app's own code (the :app and :core modules) is kept whole. Only library code the app never
#   reaches is removed.
-dontobfuscate
-keep class io.magicmobile.** { *; }
-keepattributes *Annotation*, InnerClasses, EnclosingMethod, Signature, SourceFile, LineNumberTable, RuntimeVisible*Annotations

# The packaged-engine device tests (src/androidTest) run against this same release build and share its
# classes, so the library entry points they call directly must stay even where the app itself does not
# call them: Kotlin's standard library and coroutines, Play Services Tasks and ML Kit text recognition,
# and the small AndroidX libraries the test runner itself shares with the app (tracing, annotations,
# futures).
-keep class kotlin.** { *; }
-keep class androidx.tracing.** { *; }
-keep class androidx.annotation.** { *; }
-keep class androidx.concurrent.futures.** { *; }
-keep class com.google.common.util.concurrent.ListenableFuture { *; }
-keep class kotlinx.coroutines.** { *; }
-keep class com.google.android.gms.tasks.** { public *; }
-keep class com.google.mlkit.vision.common.InputImage { public *; }
-keep class com.google.mlkit.vision.text.** { public *; }
