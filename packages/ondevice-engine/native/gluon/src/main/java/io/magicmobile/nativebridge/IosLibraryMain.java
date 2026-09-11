package io.magicmobile.nativebridge;

/** Gluon compile requires main(String[]); the app uses NativeEntryPoints' real C ABI. */
public final class IosLibraryMain {
    public static void main(String[] args) {
        throw new UnsupportedOperationException("Invoke the real mm_engine_* C entry points.");
    }
}
