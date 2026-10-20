package io.magicmobile.web.svm;

import com.oracle.svm.core.annotate.Substitute;
import com.oracle.svm.core.annotate.TargetClass;

/**
 * WEB BUILD ONLY, compiled for the Web Image build alone. Web Image runs one thread, and its Thread.start() returns
 * without running anything, so a task handed to a new thread would silently never happen. The web threading mode
 * starts none (docs/WEB_ENGINE_M1.md); any start that remains fails here, loudly, instead.
 */
@TargetClass(java.lang.Thread.class)
final class Target_java_lang_Thread_Web {
    @Substitute
    public void start() {
        throw new IllegalStateException("MagicMobile web engine: Thread.start is not supported (single-threaded Web Image): "
            +((Thread)(Object)this).getName());
    }
}
