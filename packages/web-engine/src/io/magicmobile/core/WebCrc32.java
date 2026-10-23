package io.magicmobile.core;

import java.util.zip.Checksum;

/**
 * WEB BUILD ONLY: java.util.zip.CRC32's values in plain Java. Web Image has no native zip library, so the JDK's
 * CRC32 fails to load there. Same polynomial and output, so game records and their digests match phones'.
 */
public final class WebCrc32 implements Checksum {
    private static final int[] TABLE=new int[256];
    static {
        for(int n=0;n<256;n++) {
            int c=n;
            for(int k=0;k<8;k++) c=(c&1)!=0?0xEDB88320^(c>>>1):c>>>1;
            TABLE[n]=c;
        }
    }
    private int crc;
    @Override public void update(int b) { int c=~crc;crc=~(TABLE[(c^b)&0xff]^(c>>>8)); }
    @Override public void update(byte[] b,int off,int len) {
        int c=~crc;
        for(int i=off,end=off+len;i<end;i++) c=TABLE[(c^b[i])&0xff]^(c>>>8);
        crc=~c;
    }
    @Override public long getValue() { return crc&0xffffffffL; }
    @Override public void reset() { crc=0; }
}
