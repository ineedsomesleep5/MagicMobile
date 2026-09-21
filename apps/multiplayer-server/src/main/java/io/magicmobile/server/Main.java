package io.magicmobile.server;

import io.magicmobile.core.*;
import java.net.*;
import java.util.*;
import java.util.function.Supplier;

public final class Main {
    public static void main(String[] args)throws Exception{
        String url=required("SUPABASE_URL"),key=required("SUPABASE_PUBLISHABLE_KEY");
        Map<String,Object> identity=Json.parseObject(required("MAGICMOBILE_BUILD_IDENTITY"));
        if(!identity.keySet().equals(Set.of("protocolVersion","upstreamCommit","catalogueHash","adapterVersion")))throw new IllegalArgumentException("Invalid build identity fields");
        Supplier<EnginePort> engines=()->{try{return (EnginePort)Class.forName("io.magicmobile.xmage.XmageEngine").getConstructor(String.class).newInstance("dedicated-server");}catch(Exception e){throw new IllegalStateException("Real XMage engine unavailable",e);}};
        try(EnginePort probe=engines.get()){
            Map<String,Object> capabilities=probe.capabilities();
            if(Json.integer(identity.get("protocolVersion"))!=EngineService.PROTOCOL || !Objects.equals(identity.get("upstreamCommit"),capabilities.get("upstream")) || !Objects.equals(identity.get("catalogueHash"),capabilities.get("catalogueHash")))throw new IllegalStateException("Configured identity differs from compiled XMage engine");
        }
        MultiplayerServer server=new MultiplayerServer(bindAddress(System.getenv()),new SupabaseBackend(url,key),engines,identity,url,key,Integer.parseInt(System.getenv().getOrDefault("MAX_MATCHES","1")));
        Runtime.getRuntime().addShutdownHook(new Thread(server::close));server.start();System.out.println("MagicMobile multiplayer listening on configured address, port "+server.port());
    }
    static InetSocketAddress bindAddress(Map<String,String> environment){
        String address=environment.getOrDefault("BIND_ADDRESS","127.0.0.1");
        if(!Set.of("127.0.0.1","0.0.0.0","::1").contains(address))throw new IllegalArgumentException("BIND_ADDRESS must be loopback or explicit 0.0.0.0");
        int port=Integer.parseInt(environment.getOrDefault("PORT","8088"));
        if(port<1||port>65535)throw new IllegalArgumentException("PORT must be 1–65535");
        return new InetSocketAddress(address,port);
    }
    private static String required(String name){String value=System.getenv(name);if(value==null||value.isBlank())throw new IllegalArgumentException("Missing "+name);return value;}
}
