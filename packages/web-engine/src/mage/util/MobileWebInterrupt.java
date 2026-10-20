package mage.util;

/**
 * WEB BUILD ONLY (packages/web-engine). XMage stops an AI search by interrupting its thread: the search's own
 * checks, a simulated player's canRespond and a simulated game's checkIfGameIsOver then let it unwind. On GraalVM
 * Web Image, Thread.interrupt() on the current thread does nothing, and the search runs on the game's own thread, so
 * web_sources.py points those checks here. Set only while an inline search runs (by its deadline or its copy cap),
 * cleared when it returns, so the live game never sees it.
 */
public final class MobileWebInterrupt {
    private static boolean set;
    private MobileWebInterrupt() {}
    public static void set() { set=true; }
    public static void clear() { set=false; }
    /** The flag, or a real interrupt (the JVM test harness still has them). */
    public static boolean isSet() { return set || Thread.currentThread().isInterrupted(); }
}
