package io.magicmobile.web;

import io.magicmobile.core.EngineService;
import io.magicmobile.xmage.XmageEngine;
import org.graalvm.webimage.api.JS;

/**
 * WEB BUILD ONLY: the GraalVM Web Image entry point, run in a dedicated Web Worker (apps/web-play/src/engine.worker.ts).
 * main never returns: the worker's thread is the engine's. The worker's script defines globalThis.mmHost before the
 * image starts: take(block) reads the page's next request from a SharedArrayBuffer (Atomics.wait while blocking, at
 * most 250 ms), reply(json) posts the answer back to the page.
 */
public final class WebMain {
    private WebMain() {}

    @JS.Coerce
    @JS(args={"block"},value="return mmHost.take(block);")
    private static native String take(boolean block);

    @JS.Coerce
    @JS(args={"json"},value="mmHost.reply(json);")
    private static native void reply(String json);

    public static void main(String[] args) {
        WebSetup.configure();
        EngineService service=EngineService.lazy(() -> new XmageEngine("web-image"));
        new WebHost(new WebHost.Channel() {
            @Override public String take(boolean block) { return WebMain.take(block); }
            @Override public void reply(String json) { WebMain.reply(json); }
        },service).run();
    }
}
