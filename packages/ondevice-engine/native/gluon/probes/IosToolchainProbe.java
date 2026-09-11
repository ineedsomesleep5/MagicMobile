package io.magicmobile.nativebridge;

import org.graalvm.nativeimage.IsolateThread;
import org.graalvm.nativeimage.c.function.CEntryPoint;

/**
 * Compile/archive-only SDK diagnostic. Contains no XMage and is never an engine backend.
 * Its deliberately different export must never satisfy mm_engine_* symbol checks.
 */
public final class IosToolchainProbe {
    @CEntryPoint(name = "mm_toolchain_probe")
    public static int probe(IsolateThread thread) {
        return 42;
    }
}
