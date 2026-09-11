package io.magicmobile.xmage;
import io.magicmobile.core.EngineService;
import java.io.*;
import java.nio.charset.StandardCharsets;
/** JVM integration harness only. This process is never required on a player's phone. */
public final class EngineCli {
    public static void main(String[] args) throws Exception {
        try(XmageEngine engine=new XmageEngine("jvm-integration")) {
            EngineService service=new EngineService(engine);
            BufferedReader input=new BufferedReader(new InputStreamReader(System.in,StandardCharsets.UTF_8));
            for(String line;(line=input.readLine())!=null;) System.out.println(service.request(line));
        }
    }
}
