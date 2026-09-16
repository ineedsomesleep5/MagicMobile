package io.magicmobile.core;

import java.util.*;

/** One bounded process-local failure. Never include this in viewer polls or peer replies. */
public final class EngineDiagnostics {
    public static final int MAX_CHARS=16384;
    private static String report;
    private EngineDiagnostics() {}
    public static synchronized void captureIncident(String boundary,BridgeException failure) {
        try {
            StringBuilder text=new StringBuilder("[local-engine-incident] ");
            append(text,boundary);append(text,"\nOccurred: "+java.time.Instant.now()+"\n");
            append(text,Json.write(failure.envelope()));
            report=text.toString();
        } catch(Throwable ignored) {
            report="[local-engine-incident] Report unavailable; original rejection retained.";
        }
    }
    public static synchronized void capture(String boundary,Throwable failure) {
        // Diagnostics must never replace or prevent the original failure signal.
        try {
            StringBuilder text=new StringBuilder("[DEBUG-native-failure] ");
            append(text,boundary);append(text,"\n");
            append(text,"Occurred: "+java.time.Instant.now()+"\n");
            Set<Throwable> seen=Collections.newSetFromMap(new IdentityHashMap<>());
            Throwable cause=failure;
            for(int depth=0;cause!=null && depth<8 && seen.add(cause);depth++,cause=cause.getCause()) {
                if(depth>0) append(text,"Caused by: ");
                append(text,cause.getClass().getName());append(text,": ");
                String message=cause.getMessage();
                if(message!=null) append(text,message.substring(0,Math.min(message.length(),1024)));
                append(text,"\n");
                StackTraceElement[] frames=cause.getStackTrace();
                for(int i=0;i<Math.min(frames.length,48);i++) {
                    append(text,"  at ");append(text,frames[i].toString());append(text,"\n");
                }
                if(frames.length>48) append(text,"  [remaining frames omitted]\n");
                if(cause.getSuppressed().length>0) append(text,"  [suppressed exceptions omitted]\n");
            }
            if(cause!=null) append(text,"[remaining or cyclic causes omitted]\n");
            // JSON must not receive an unpaired surrogate at a truncation boundary.
            if(text.length()>0 && Character.isHighSurrogate(text.charAt(text.length()-1))) text.setLength(text.length()-1);
            report=text.toString();
        } catch(Throwable ignored) {
            report="[DEBUG-native-failure] Error report unavailable; original engine failure retained.";
        }
    }
    private static void append(StringBuilder text,String value) {
        int length=Math.min(value.length(),MAX_CHARS-text.length());
        if(length>0 && Character.isHighSurrogate(value.charAt(length-1))) length--;
        if(length>0) text.append(value,0,length);
    }
    public static synchronized Map<String,Object> read() {return Json.map("report",report);}
    public static synchronized void clear() {report=null;}
}
