package io.magicmobile.xmage;

import java.io.BufferedReader;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.function.LongSupplier;

/**
 * Memory the phone running the engine still has for it, read when an AI search starts (AISearchMemory). iOS installs
 * os_proc_available_memory, the app's headroom before the system ends it (NativeEntryPoints); Android and Linux read
 * MemAvailable from /proc/meminfo, as ActivityManager.MemoryInfo does. JVM tools can stand in for a phone with
 * -Dmagicmobile.aiAvailableMemoryMB. The Java heap's own limit is not used: a phone's default limit is most of its
 * RAM, and the heap in use between collections is mostly garbage. Never an error: a failed reading is skipped.
 */
final class DeviceMemory {
    /** When nothing can be read. */
    static final long UNKNOWN_BYTES=512L<<20;
    private static volatile LongSupplier platform;
    private DeviceMemory() {}

    /** The platform's reading, in bytes; replaces /proc/meminfo. */
    static void install(LongSupplier reader) { platform=reader; }

    static long availableBytes() {
        LongSupplier reader=platform;
        long reading=reader!=null?read(reader):-1;
        if(reading<=0) reading=property();
        if(reading<=0) reading=memAvailable(Path.of("/proc/meminfo"));
        return reading>0?reading:UNKNOWN_BYTES;
    }
    private static long read(LongSupplier reader) {
        try { return reader.getAsLong(); } catch(RuntimeException | LinkageError e) { return -1; }
    }
    private static long property() {
        try { return Long.parseLong(System.getProperty("magicmobile.aiAvailableMemoryMB","-1"))<<20; }
        catch(RuntimeException e) { return -1; }
    }
    /** MemAvailable in bytes, or -1. */
    static long memAvailable(Path meminfo) {
        try(BufferedReader in=Files.newBufferedReader(meminfo,StandardCharsets.US_ASCII)) {
            for(String line=in.readLine();line!=null;line=in.readLine())
                if(line.startsWith("MemAvailable:")) {
                    String[] parts=line.substring(13).trim().split("\\s+");
                    long value=Long.parseLong(parts[0]);
                    return parts.length>1 && parts[1].equalsIgnoreCase("kB")?value*1024:value;
                }
        } catch(IOException | RuntimeException e) { return -1; }
        return -1;
    }
}
