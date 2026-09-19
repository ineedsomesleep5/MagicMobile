/*
 * GraalVM links the JDK's AWT JNI bootstrap into the image even though MagicMobile
 * substitutes java.awt.Color and never brings up a toolkit. Android has no AWT, so those
 * symbols are left undefined and dlopen of libmmengine.so fails at load with
 * "cannot locate symbol JNI_OnLoad_awt" — a green build that cannot start a game.
 *
 * Evidence from a real device run (Android 15, arm64): the engine loads, creates its
 * Graal isolate, builds an XMage Commander game and serves prompts, and none of these
 * entry points is ever reached. They are needed for symbol resolution only.
 *
 * Because that is observed rather than guaranteed, the implementations are chosen to be
 * safe if XMage ever does reach them. The load hooks report a supported JNI version so a
 * library load cannot fail mid-startup, and they log loudly so an unexpected call is
 * visible in logcat instead of silent. They still create no toolkit and no peers: there is
 * no AWT implementation behind them, so any genuine attempt to use one fails at the point
 * of use with a normal Java error rather than corrupting engine startup.
 */
#include <jni.h>
#include <android/log.h>

#define MM_AWT_TAG "MagicMobileAWT"

static void mm_awt_note(const char *entry) {
    __android_log_print(ANDROID_LOG_WARN, MM_AWT_TAG,
        "%s was called. MagicMobile ships no AWT on Android; no toolkit is created. "
        "If gameplay depends on this, the engine needs a real substitution, not this stub.",
        entry);
}

JNIEXPORT jint JNICALL JNI_OnLoad_awt(JavaVM *vm, void *reserved) {
    (void)vm; (void)reserved;
    mm_awt_note("JNI_OnLoad_awt");
    return JNI_VERSION_1_6;
}

JNIEXPORT jint JNICALL JNI_OnLoad_awt_headless(JavaVM *vm, void *reserved) {
    (void)vm; (void)reserved;
    mm_awt_note("JNI_OnLoad_awt_headless");
    return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL Java_java_awt_Toolkit_initIDs(JNIEnv *env, jclass type) {
    (void)env; (void)type;
    mm_awt_note("java.awt.Toolkit.initIDs");
}
