package io.magicmobile.core;

import java.io.*;

/**
 * WEB BUILD ONLY: gzip reading in plain Java (RFC 1952 around RFC 1951 inflate, after zlib's "puff"). Web Image has no
 * native zip library, so GZIPInputStream fails there; the engine's bundled catalogues (/mage/mobile/*.gz) stay
 * compressed in the image and are read through this instead. Whole-buffer: the output is sized from the gzip
 * trailer and checked against its CRC-32 and length.
 */
public final class WebInflate {
    private WebInflate() {}

    /** Replaces new GZIPInputStream(stream): reads and closes stream, returns the decompressed bytes. */
    public static InputStream gunzip(InputStream stream) throws IOException {
        byte[] data;
        try(InputStream in=stream) { data=in.readAllBytes(); }
        return new ByteArrayInputStream(gunzip(data));
    }

    public static byte[] gunzip(byte[] d) throws IOException {
        if(d.length<18 || (d[0]&255)!=0x1f || (d[1]&255)!=0x8b || d[2]!=8) throw new IOException("Not a gzip stream");
        int flags=d[3]&255,p=10;
        if((flags&4)!=0) p+=2+((d[p]&255)|(d[p+1]&255)<<8);
        if((flags&8)!=0) while(d[p++]!=0) {}
        if((flags&16)!=0) while(d[p++]!=0) {}
        if((flags&2)!=0) p+=2;
        int size=le32(d,d.length-4);
        Inflater inflater=new Inflater(d,p,d.length-8,size<0?1<<20:size);
        byte[] out=inflater.inflate();
        if(inflater.pos!=d.length-8) throw new IOException("Unexpected data after the gzip member");
        WebCrc32 crc=new WebCrc32();crc.update(out,0,out.length);
        if((int)crc.getValue()!=le32(d,d.length-8) || out.length!=size) throw new IOException("Corrupt gzip stream");
        return out;
    }
    private static int le32(byte[] d,int at) {
        return (d[at]&255)|(d[at+1]&255)<<8|(d[at+2]&255)<<16|(d[at+3]&255)<<24;
    }

    private static final int[] LBASE={3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258};
    private static final int[] LEXT={0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0};
    private static final int[] DBASE={1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,
        6145,8193,12289,16385,24577};
    private static final int[] DEXT={0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13};
    private static final int[] ORDER={16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15};
    private static final int FAST=9;

    /** A canonical Huffman code: counts per length and symbols by code, plus a table for codes up to FAST bits. */
    private static final class Huffman {
        final short[] count=new short[16];
        final short[] symbol;
        final int[] fast=new int[1<<FAST]; // (symbol << 4) | length; 0 when the code is longer than FAST bits
        Huffman(int[] lengths,int n) throws IOException {
            symbol=new short[n];
            for(int i=0;i<n;i++) count[lengths[i]]++;
            if(count[0]==n) return; // no codes: only an error if one is decoded
            int left=1;
            for(int len=1;len<16;len++) { left<<=1;left-=count[len];if(left<0) throw new IOException("Over-subscribed code"); }
            int[] offs=new int[16];
            for(int len=1;len<15;len++) offs[len+1]=offs[len]+count[len];
            for(int i=0;i<n;i++) if(lengths[i]!=0) symbol[offs[lengths[i]]++]=(short)i;
            // Canonical codes, MSB-first; the stream sends them LSB-first, so the table indexes reversed codes.
            int code=0;
            int[] next=new int[16];
            for(int len=1;len<16;len++) { code=(code+(len==1?0:count[len-1]))<<1;next[len]=code; } // RFC 1951 3.2.2
            for(int i=0;i<n;i++) {
                int len=lengths[i];
                if(len==0 || len>FAST) continue;
                int c=next[len]++,reversed=0;
                for(int b=0;b<len;b++) { reversed=(reversed<<1)|(c&1);c>>>=1; }
                for(int fill=reversed;fill<(1<<FAST);fill+=1<<len) fast[fill]=i<<4|len;
            }
        }
    }

    private static final class Inflater {
        final byte[] in;final int end;int pos;
        int bitbuf,bitcnt;
        byte[] out;int outcnt;
        Inflater(byte[] in,int start,int end,int size) { this.in=in;this.pos=start;this.end=end;out=new byte[Math.max(16,size)]; }

        private int bits(int need) throws IOException {
            int val=bitbuf;
            while(bitcnt<need) {
                if(pos>=end) throw new IOException("Truncated deflate stream");
                val|=(in[pos++]&255)<<bitcnt;bitcnt+=8;
            }
            bitbuf=val>>>need;bitcnt-=need;
            return val&((1<<need)-1);
        }
        private int decode(Huffman h) throws IOException {
            // Fill up to FAST bits without failing at the end of input: a short final code needs fewer.
            while(bitcnt<FAST && pos<end) { bitbuf|=(in[pos++]&255)<<bitcnt;bitcnt+=8; }
            int entry=h.fast[bitbuf&((1<<FAST)-1)];
            if(entry!=0 && (entry&15)<=bitcnt) { bitbuf>>>=entry&15;bitcnt-=entry&15;return entry>>>4; }
            int code=0,first=0,index=0;
            for(int len=1;len<16;len++) {
                code|=bits(1);
                int count=h.count[len];
                if(code-count<first) return h.symbol[index+(code-first)];
                index+=count;first+=count;first<<=1;code<<=1;
            }
            throw new IOException("Invalid Huffman code");
        }
        private void put(int b) {
            if(outcnt==out.length) out=java.util.Arrays.copyOf(out,out.length*2);
            out[outcnt++]=(byte)b;
        }
        byte[] inflate() throws IOException {
            boolean last;
            do {
                last=bits(1)==1;
                int type=bits(2);
                if(type==0) stored();
                else if(type==1) codes(FIXED_LEN,FIXED_DIST);
                else if(type==2) dynamic();
                else throw new IOException("Invalid deflate block type");
            } while(!last);
            // Return whole bytes still buffered to the input (the trailer follows).
            pos-=bitcnt>>>3;bitbuf=0;bitcnt=0;
            return outcnt==out.length?out:java.util.Arrays.copyOf(out,outcnt);
        }
        private void stored() throws IOException {
            pos-=bitcnt>>>3;bitbuf=0;bitcnt=0;
            if(pos+4>end) throw new IOException("Truncated stored block");
            int len=(in[pos]&255)|(in[pos+1]&255)<<8,nlen=(in[pos+2]&255)|(in[pos+3]&255)<<8;
            pos+=4;
            if(len!=(~nlen&0xffff) || pos+len>end) throw new IOException("Invalid stored block");
            for(int i=0;i<len;i++) put(in[pos++]);
        }
        private void codes(Huffman lencode,Huffman distcode) throws IOException {
            while(true) {
                int symbol=decode(lencode);
                if(symbol<256) { put(symbol);continue; }
                if(symbol==256) return;
                symbol-=257;
                if(symbol>=29) throw new IOException("Invalid length symbol");
                int len=LBASE[symbol]+bits(LEXT[symbol]);
                int ds=decode(distcode);
                if(ds>=30) throw new IOException("Invalid distance symbol");
                int dist=DBASE[ds]+bits(DEXT[ds]);
                if(dist>outcnt) throw new IOException("Distance too far back");
                if(outcnt+len>out.length) out=java.util.Arrays.copyOf(out,Math.max(out.length*2,outcnt+len));
                for(int i=0;i<len;i++) { out[outcnt]=out[outcnt-dist];outcnt++; }
            }
        }
        private void dynamic() throws IOException {
            int nlen=bits(5)+257,ndist=bits(5)+1,ncode=bits(4)+4;
            if(nlen>286 || ndist>30) throw new IOException("Bad code counts");
            int[] lengths=new int[320];
            for(int i=0;i<ncode;i++) lengths[ORDER[i]]=bits(3);
            Huffman lencode=new Huffman(lengths,19);
            int index=0;
            int[] all=new int[nlen+ndist];
            while(index<nlen+ndist) {
                int symbol=decode(lencode);
                if(symbol<16) { all[index++]=symbol;continue; }
                int len=0,repeat;
                if(symbol==16) { if(index==0) throw new IOException("Repeat with no first length");len=all[index-1];repeat=3+bits(2); }
                else if(symbol==17) repeat=3+bits(3);
                else repeat=11+bits(7);
                if(index+repeat>nlen+ndist) throw new IOException("Too many lengths");
                while(repeat-->0) all[index++]=len;
            }
            if(all[256]==0) throw new IOException("No end-of-block code");
            int[] litlen=java.util.Arrays.copyOf(all,nlen),dist=java.util.Arrays.copyOfRange(all,nlen,nlen+ndist);
            codes(new Huffman(litlen,nlen),new Huffman(dist,ndist));
        }
    }

    private static final Huffman FIXED_LEN,FIXED_DIST;
    static {
        try {
            int[] lengths=new int[288];
            for(int i=0;i<288;i++) lengths[i]=i<144?8:i<256?9:i<280?7:8;
            FIXED_LEN=new Huffman(lengths,288);
            int[] dist=new int[30];
            java.util.Arrays.fill(dist,5);
            FIXED_DIST=new Huffman(dist,30);
        } catch(IOException e) { throw new ExceptionInInitializerError(e); }
    }
}
