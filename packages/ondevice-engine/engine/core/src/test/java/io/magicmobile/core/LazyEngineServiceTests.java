package io.magicmobile.core;

import java.util.concurrent.atomic.AtomicInteger;

/** Tests lazy diagnostic routing, not native execution or gameplay. */
public final class LazyEngineServiceTests {
    private static void check(boolean value,String message) { if(!value) throw new AssertionError(message); }
    public static void main(String[] args) {
        AtomicInteger constructions=new AtomicInteger();
        EngineService service=EngineService.lazy(()->{
            constructions.incrementAndGet();
            throw new UnsatisfiedLinkError("PRIVATE-INITIALIZER");
        });
        EngineDiagnostics.clear();
        service.request("{\"protocol\":1,\"op\":\"diagnostics\"}");
        service.request("{\"protocol\":1,\"op\":\"clearDiagnostics\"}");
        check(constructions.get()==0,"Diagnostics initialized XMage");
        String failure=service.request("{\"protocol\":1,\"op\":\"capabilities\"}");
        check(Boolean.FALSE.equals(Json.parseObject(failure).get("ok")),"Initializer fault was not signalled");
        check(!failure.contains("PRIVATE-INITIALIZER"),"Initializer leaked to normal request");
        String report=service.request("{\"protocol\":1,\"op\":\"diagnostics\"}");
        check(report.contains("PRIVATE-INITIALIZER") && report.contains("UnsatisfiedLinkError"),"Original initializer report is inaccessible");
        check(constructions.get()==1,"Report request retried the broken initializer");
        service.request("{\"protocol\":1,\"op\":\"clearDiagnostics\"}");
        check(constructions.get()==1 && EngineDiagnostics.read().get("report")==null,"Clear cannot work after initialization failure");
        System.out.println("PASS: 6 lazy engine diagnostic checks; scope=standalone-core");
    }
}
