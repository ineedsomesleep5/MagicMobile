package io.magicmobile.web;

import io.magicmobile.core.EngineService;
import io.magicmobile.xmage.XmageEngine;

/**
 * SPIKE ONLY. Browser (CheerpJ) entry point for the real XMage adapter: the same
 * JSON protocol as EngineCli and NativeEntryPoints, called from a Web Worker.
 */
public final class WebEntryPoints {
    private static EngineService service;
    private WebEntryPoints() {}
    private static synchronized EngineService service() {
        if(service==null) service=EngineService.lazy(()->new XmageEngine("web-cheerpj"));
        return service;
    }
    /** EngineService.request never throws; it returns a protocol error envelope instead. */
    public static String request(String json) { return service().request(json); }
}
