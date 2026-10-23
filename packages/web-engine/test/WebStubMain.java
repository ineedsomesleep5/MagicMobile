import io.magicmobile.core.*;
import io.magicmobile.web.WebHost;
import org.graalvm.webimage.api.JS;
import java.util.*;

/** WEB BUILD ONLY, browser plumbing check: the real WebHost and EngineService over a stub engine (no XMage). */
public final class WebStubMain {
    @JS.Coerce @JS(args={"block"},value="return mmHost.take(block);") private static native String take(boolean block);
    @JS.Coerce @JS(args={"json"},value="mmHost.reply(json);") private static native void reply(String json);
    public static void main(String[] args) {
        EnginePort stub=new EnginePort() {
            public Map<String,Object> create(Map<String,Object> c) { throw new BridgeException("stub","No engine in this check"); }
            public Map<String,Object> poll(String m,String v,long a) { throw new BridgeException("stub","No engine"); }
            public Map<String,Object> respond(String m,String s,Map<String,Object> c) { throw new BridgeException("stub","No engine"); }
            public void destroy(String m) {}
            public Map<String,Object> capabilities() {
                java.util.zip.Checksum crc=new WebCrc32(); crc.update("web".getBytes(),0,3);
                return Json.map("protocol",1,"engine","stub","execution","web-image-stub","crc",crc.getValue(),"uuid",UUID.randomUUID().toString());
            }
            public void close() {}
        };
        new WebHost(new WebHost.Channel() {
            public String take(boolean block) { return WebStubMain.take(block); }
            public void reply(String json) { WebStubMain.reply(json); }
        },new EngineService(stub)).run();
    }
}
