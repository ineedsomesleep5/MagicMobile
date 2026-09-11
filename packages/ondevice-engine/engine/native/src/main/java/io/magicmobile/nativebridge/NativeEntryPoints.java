package io.magicmobile.nativebridge;

import io.magicmobile.core.*;
import io.magicmobile.xmage.XmageEngine;
import org.graalvm.nativeimage.*;
import org.graalvm.nativeimage.c.function.CEntryPoint;
import org.graalvm.nativeimage.c.type.CCharPointer;
import org.graalvm.word.WordFactory;
import java.nio.ByteBuffer;
import java.nio.charset.*;

/** Compiled ahead of time; no JIT or downloaded bytecode on an iPhone. */
public final class NativeEntryPoints {
    private static XmageEngine engine;
    private static EngineService service;
    private static synchronized EngineService service() {
        if(service==null) {engine=new XmageEngine("native-aot");service=new EngineService(engine);}
        return service;
    }
    @CEntryPoint(name="mm_engine_request")
    public static CCharPointer request(IsolateThread thread,CCharPointer input,int length) {
        try {
            if(input.isNull() || length<1 || length>Json.MAX_TEXT) return allocation("{\"protocol\":1,\"ok\":false,\"error\":{\"code\":\"invalid_request\",\"message\":\"Invalid native input size\"}}");
            byte[] bytes=new byte[length];for(int i=0;i<length;i++)bytes[i]=input.read(i);
            String request=StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
            return allocation(service().request(request));
        } catch(Throwable e) {
            try {return allocation("{\"protocol\":1,\"ok\":false,\"error\":{\"code\":\"native_failure\",\"message\":\"Native engine failed\"}}");}
            catch(Throwable ignored) {return WordFactory.nullPointer();}
        }
    }
    private static CCharPointer allocation(String value) {
        byte[] utf8=value.getBytes(StandardCharsets.UTF_8);
        if(utf8.length>Json.MAX_TEXT) throw new IllegalArgumentException("Native output too large");
        CCharPointer pointer=UnmanagedMemory.malloc(WordFactory.unsigned(utf8.length+1));
        if(pointer.isNull())return pointer;
        for(int i=0;i<utf8.length;i++)pointer.write(i,utf8[i]);pointer.write(utf8.length,(byte)0);return pointer;
    }
    @CEntryPoint(name="mm_engine_free")
    public static void free(IsolateThread thread,CCharPointer result) {if(result.isNonNull())UnmanagedMemory.free(result);}
    // Version the export so an old void-returning AOT library cannot satisfy this ABI.
    @CEntryPoint(name="mm_engine_shutdown_v2")
    public static synchronized int shutdown(IsolateThread thread) {
        try {if(engine!=null)engine.close();return 0;} // MM_OK: all workers terminated
        catch(BridgeException e) {return "engine_busy_shutdown".equals(e.code())?5:4;} // MM_BUSY / MM_ENGINE_FAILED
        catch(Throwable e) {return 4;} // Never permit teardown after an unconfirmed shutdown.
    }
}
