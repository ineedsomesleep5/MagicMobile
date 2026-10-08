# The instrumentation test APK for the minified release build is left whole: nothing in it is removed,
# optimised or renamed. Only build-time annotations its libraries mention are absent.
-dontshrink
-dontoptimize
-dontobfuscate
-dontwarn com.google.errorprone.annotations.**
