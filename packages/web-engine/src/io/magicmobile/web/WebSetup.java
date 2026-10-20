package io.magicmobile.web;

import io.magicmobile.xmage.XmageEngine;

/** WEB BUILD ONLY: process setup shared by the Web Image entry point and its JVM harness. */
final class WebSetup {
    /** What an AI search may count on (AISearchMemory takes a quarter): a tab has no reading of its own headroom. */
    static final long AI_AVAILABLE_BYTES=1L<<30;
    private WebSetup() {}
    static void configure() {
        // reload4j's default root level is DEBUG with no appender: every debug message is built and dropped.
        // Logging only; no rule or AI choice reads it (the calibration tools set WARN the same way).
        org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        XmageEngine.useAvailableMemory(() -> AI_AVAILABLE_BYTES);
    }
}
