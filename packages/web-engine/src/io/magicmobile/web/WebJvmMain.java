package io.magicmobile.web;

import io.magicmobile.core.EngineService;
import io.magicmobile.xmage.XmageEngine;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;

/**
 * WEB BUILD ONLY, JVM test harness: the web threading mode on HotSpot, with the same Java sources as the Web Image
 * build. One request per stdin line, one reply per stdout line (as EngineCli, so apps/web-play's jvm-baseline.mjs
 * drives it with --web). A reader thread stands in for the page; the engine itself must start no thread, and the
 * harness exits with status 3 naming any it finds.
 */
public final class WebJvmMain {
    private WebJvmMain() {}
    public static void main(String[] args) throws Exception {
        BlockingQueue<String> lines=new LinkedBlockingQueue<>();
        Thread page=new Thread(() -> {
            try(BufferedReader input=new BufferedReader(new InputStreamReader(System.in,StandardCharsets.UTF_8))) {
                for(String line;(line=input.readLine())!=null;) lines.add(line);
            } catch(IOException ignored) {}
            lines.add("\u0000eof");
        },"web-jvm-page");
        page.setDaemon(true);page.start();
        PrintStream out=new PrintStream(new FileOutputStream(FileDescriptor.out),true,"UTF-8");
        System.setOut(new PrintStream(OutputStream.nullOutputStream())); // replies only on stdout
        java.util.Set<Thread> before=Thread.getAllStackTraces().keySet();
        WebSetup.configure();
        if(Boolean.getBoolean("magicmobile.webTrace")) // XMage's warnings and errors (rollbacks included) to stderr
            org.apache.log4j.Logger.getRootLogger().addAppender(new org.apache.log4j.ConsoleAppender(
                new org.apache.log4j.PatternLayout("LOG %p %c{1}: %m%n"),org.apache.log4j.ConsoleAppender.SYSTEM_ERR));
        EngineService service=EngineService.lazy(() -> new XmageEngine("web-image-jvm"));
        new WebHost(new WebHost.Channel() {
            @Override public String take(boolean block) {
                String line;
                try { line=block?lines.poll(250,TimeUnit.MILLISECONDS):lines.poll(); }
                catch(InterruptedException e) { throw new IllegalStateException("Web JVM harness interrupted",e); }
                if("\u0000eof".equals(line)) System.exit(0);
                return line;
            }
            @Override public void reply(String json) {
                out.println(json);
                for(Thread thread:Thread.getAllStackTraces().keySet())
                    if(!before.contains(thread) && !jvmThread(thread.getName())) {
                        System.err.println("FATAL: the web engine started a thread: "+thread.getName());
                        System.exit(3);
                    }
            }
        },service).run();
    }
    /** The JVM's own helpers, which a Web Image build does not have. Any other new thread is the engine's. */
    static boolean jvmThread(String name) {
        return name.equals("Common-Cleaner") || name.equals("Attach Listener") || name.equals("process reaper")
            || name.startsWith("C1 CompilerThread") || name.startsWith("C2 CompilerThread");
    }
}
