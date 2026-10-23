import io.magicmobile.core.WebCrc32;
import io.magicmobile.core.WebInflate;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;

/** WEB BUILD ONLY, JVM check: WebInflate and WebCrc32 against java.util.zip. Args: gzip files to compare. */
public final class WebZipTests {
    static int checks;
    public static void main(String[] args) throws Exception {
        for(String file:args) {
            byte[] gz=Files.readAllBytes(Path.of(file));
            long t0=System.nanoTime();
            byte[] mine=WebInflate.gunzip(gz);
            long t1=System.nanoTime();
            byte[] jdk;
            try(InputStream in=new GZIPInputStream(new ByteArrayInputStream(gz))) { jdk=in.readAllBytes(); }
            same(file,mine,jdk);
            System.out.printf("%s: %d -> %d bytes, %.0f ms%n",Path.of(file).getFileName(),gz.length,mine.length,(t1-t0)/1e6);
        }
        Random random=new Random(7);
        for(int level:new int[]{0,1,6,9}) for(int size:new int[]{0,1,2,100,65535,65536,70000,1<<20}) {
            byte[] data=new byte[size];
            for(int i=0;i<size;i++) data[i]=(byte)(i%7==0?random.nextInt(256):"abcabcabd".charAt(i%9)); // mixed matches and literals
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();
            try(GZIPOutputStream out=new GZIPOutputStream(bytes){{def.setLevel(level);}}) { out.write(data); }
            same("level "+level+" size "+size,WebInflate.gunzip(bytes.toByteArray()),data);
        }
        for(int size:new int[]{0,1,5,1000}) {
            byte[] data=new byte[size];random.nextBytes(data);
            CRC32 jdk=new CRC32();jdk.update(data);
            WebCrc32 mine=new WebCrc32();mine.update(data);
            if(jdk.getValue()!=mine.getValue()) throw new AssertionError("crc "+size);
            WebCrc32 single=new WebCrc32();for(byte b:data) single.update(b);
            if(jdk.getValue()!=single.getValue()) throw new AssertionError("crc single "+size);
            checks++;
        }
        try { WebInflate.gunzip(new byte[]{1,2,3}); throw new AssertionError("accepted garbage"); } catch(IOException expected) { checks++; }
        System.out.println("PASS WebZipTests: "+checks+" checks");
    }
    static void same(String what,byte[] a,byte[] b) {
        if(!Arrays.equals(a,b)) throw new AssertionError(what+": differs ("+a.length+" vs "+b.length+")");
        checks++;
    }
}
