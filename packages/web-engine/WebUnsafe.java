// SPIKE ONLY. Java side of the CheerpJ Unsafe natives in apps/web-play/src/engine.worker.ts.
//
// CheerpJ 4.3's Java 17 runtime has no jdk.internal.misc.Unsafe
// get/put{Boolean,Byte,Short,Char,Float,Double}Volatile natives. JDK 17 core reflection uses them
// for every final field, so any Field.get on a final primitive field (XMage's Watcher.copy, Gson
// serializing mage.view.GameView) throws UnsatisfiedLinkError. The worker implements those natives
// in JavaScript and, through the CheerpJ library object, calls these static helpers, which use the
// plain accessors CheerpJ does provide. Offsets are the same (sun.misc.Unsafe delegates to
// jdk.internal.misc.Unsafe). Volatile ordering is not needed: CheerpJ runs every Java thread on the
// worker's one JavaScript thread.
package io.magicmobile.web;

import java.lang.reflect.Field;

public final class WebUnsafe {
    private static final sun.misc.Unsafe U = load();

    private WebUnsafe() {}

    private static sun.misc.Unsafe load() {
        try {
            Field field = sun.misc.Unsafe.class.getDeclaredField("theUnsafe");
            field.setAccessible(true);
            return (sun.misc.Unsafe) field.get(null);
        } catch (ReflectiveOperationException e) {
            throw new ExceptionInInitializerError(e);
        }
    }

    public static boolean getBoolean(Object o, long offset) { return U.getBoolean(o, offset); }
    public static byte getByte(Object o, long offset) { return U.getByte(o, offset); }
    public static short getShort(Object o, long offset) { return U.getShort(o, offset); }
    public static char getChar(Object o, long offset) { return U.getChar(o, offset); }
    public static float getFloat(Object o, long offset) { return U.getFloat(o, offset); }
    public static double getDouble(Object o, long offset) { return U.getDouble(o, offset); }

    public static void putBoolean(Object o, long offset, boolean value) { U.putBoolean(o, offset, value); }
    public static void putByte(Object o, long offset, byte value) { U.putByte(o, offset, value); }
    public static void putShort(Object o, long offset, short value) { U.putShort(o, offset, value); }
    public static void putChar(Object o, long offset, char value) { U.putChar(o, offset, value); }
    public static void putFloat(Object o, long offset, float value) { U.putFloat(o, offset, value); }
    public static void putDouble(Object o, long offset, double value) { U.putDouble(o, offset, value); }
}
