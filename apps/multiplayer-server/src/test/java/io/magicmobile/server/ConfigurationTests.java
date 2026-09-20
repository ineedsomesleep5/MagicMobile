package io.magicmobile.server;

import java.util.Map;

public final class ConfigurationTests {
    public static void main(String[] args){
        var local=Main.bindAddress(Map.of());
        check(local.getAddress().isLoopbackAddress()&&local.getPort()==8088,"Default must stay loopback");
        var render=Main.bindAddress(Map.of("BIND_ADDRESS","0.0.0.0","PORT","10000"));
        check(render.getAddress().isAnyLocalAddress()&&render.getPort()==10000,"Explicit Render address/port");
        for(Map<String,String> invalid:java.util.List.of(Map.of("BIND_ADDRESS","example.com"),Map.of("PORT","0"),Map.of("PORT","65536"))){
            try{Main.bindAddress(invalid);throw new AssertionError("Invalid binding accepted");}catch(IllegalArgumentException expected){}
        }
        System.out.println("PASS: 5 server binding configuration checks");
    }
    static void check(boolean valid,String message){if(!valid)throw new AssertionError(message);}
}
