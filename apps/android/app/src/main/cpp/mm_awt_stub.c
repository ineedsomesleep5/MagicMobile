/*
 * GraalVM links the JDK's AWT JNI bootstrap into the image even though MagicMobile
 * substitutes java.awt.Color and never brings up a toolkit. Android has no AWT, so
 * those three symbols are left undefined and dlopen of libmmengine.so fails at load
 * with "cannot locate symbol JNI_OnLoad_awt" — a green build that cannot start a game.
 *
 * These definitions exist only so the engine resolves and loads. They deliberately do
 * NOT pretend AWT works: if anything ever does try to initialise a toolkit it gets a
 * clean JNI error and a loud UnsatisfiedLinkError, rather than a silent half-state.
 */
#include <jni.h>

JNIEXPORT jint JNICALL JNI_OnLoad_awt(JavaVM *vm, void *reserved) {
    (void)vm; (void)reserved;
    return JNI_ERR;
}

JNIEXPORT jint JNICALL JNI_OnLoad_awt_headless(JavaVM *vm, void *reserved) {
    (void)vm; (void)reserved;
    return JNI_ERR;
}

JNIEXPORT void JNICALL Java_java_awt_Toolkit_initIDs(JNIEnv *env, jclass type) {
    (void)env; (void)type;
}
