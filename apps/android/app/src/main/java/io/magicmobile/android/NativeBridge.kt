package io.magicmobile.android

/** JNI UTF-8 byte transport. The library is packaged in the APK, never downloaded at runtime. */
object NativeBridge {
    init { System.loadLibrary("magicmobile_jni") }
    external fun open(): Long
    external fun request(token: Long, json: ByteArray): ByteArray
    external fun close(token: Long): Int
}
