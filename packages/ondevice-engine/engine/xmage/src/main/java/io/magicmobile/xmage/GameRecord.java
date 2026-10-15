package io.magicmobile.xmage;

import io.magicmobile.core.BridgeException;
import io.magicmobile.core.Json;
import java.io.Serializable;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

/**
 * The data of one game record (docs/cloud/game-record.md): the setup (engine identity, seed, seats and
 * decks), every decision in order as short text entries, turn marks with state digests, and the end.
 * Saved inside a checkpoint, so a resumed game keeps one record. {@link GameRecorder} writes and reads it.
 */
final class GameRecord implements Serializable {
    private static final long serialVersionUID=1L;
    static final String FORMAT="magicmobile-game-record";
    static final int VERSION=1;
    /** The setup as an exact JSON string: the first link of the hash chain. */
    final String setup;
    /** Player IDs in seat order and card IDs in deck load order; never exported (they differ in every run). */
    final ArrayList<UUID> players,cards;
    final ArrayList<String> entries=new ArrayList<>();
    /** "turn index digest": the state digest when the first entry of each turn was written. */
    final ArrayList<String> marks=new ArrayList<>();
    /** Why recording stopped (the game itself went on), or null. A broken record cannot be replayed. */
    String broken;
    /** The end as an exact JSON string once the game is over; the last link of the hash chain. */
    String end;

    GameRecord(String setup,List<UUID> players,List<UUID> cards) {
        this.setup=setup;this.players=new ArrayList<>(players);this.cards=new ArrayList<>(cards);
    }

    /** The exported record. {@code end} describes the game now when it is still running. */
    Map<String,Object> export(String currentEnd) {
        String last=end!=null?end:currentEnd;
        Map<String,Object> out=Json.map("format",FORMAT,"version",VERSION,"setup",setup,
            "entries",new ArrayList<Object>(entries),"marks",new ArrayList<Object>(marks),"end",last);
        if(broken!=null) out.put("broken",broken);
        out.put("head",head(setup,entries,last));
        return out;
    }

    /** SHA-256 chain: h0 = H(setup), hi = H(hi-1 || "\n" || entry i), head = H(hn || "\n" || end). Lowercase hex. */
    static String head(String setup,List<String> entries,String end) {
        byte[] h=sha256(setup.getBytes(StandardCharsets.UTF_8));
        for(String entry:entries) h=link(h,entry);
        return hex(link(h,end));
    }
    private static byte[] link(byte[] previous,String next) {
        byte[] text=("\n"+next).getBytes(StandardCharsets.UTF_8);
        byte[] all=Arrays.copyOf(previous,previous.length+text.length);
        System.arraycopy(text,0,all,previous.length,text.length);
        return sha256(all);
    }
    private static byte[] sha256(byte[] data) {
        try { return MessageDigest.getInstance("SHA-256").digest(data); }
        catch(java.security.NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
    }
    static String hex(byte[] bytes) {
        StringBuilder text=new StringBuilder(bytes.length*2);
        for(byte b:bytes) text.append(Character.forDigit((b>>4)&15,16)).append(Character.forDigit(b&15,16));
        return text.toString();
    }

    /** A parsed, integrity-checked record for replay. */
    static final class Parsed {
        final Map<String,Object> setup,end;
        final List<String> entries;
        final Map<Integer,String[]> marks=new HashMap<>();
        Parsed(Map<String,Object> setup,Map<String,Object> end,List<String> entries) { this.setup=setup;this.end=end;this.entries=entries; }
    }
    static Parsed parse(Map<String,Object> record) {
        try {
            if(!FORMAT.equals(record.get("format")) || Json.integer(record.get("version"))!=VERSION)
                throw new BridgeException("record_unsupported","Not a version "+VERSION+" game record");
            if(record.containsKey("broken")) throw new BridgeException("record_incomplete","Recording stopped during this game: "+record.get("broken"));
            String setup=Json.requiredString(record,"setup"),end=Json.requiredString(record,"end");
            List<String> entries=new ArrayList<>();
            for(Object entry:Json.array(record.get("entries"))) entries.add(Json.string(entry));
            if(!head(setup,entries,end).equals(record.get("head"))) throw new BridgeException("record_corrupt","The record does not match its hash chain");
            Parsed parsed=new Parsed(Json.parseObject(setup),Json.parseObject(end),entries);
            for(Object mark:Json.array(record.get("marks"))) {
                String[] parts=Json.string(mark).split(" ");
                if(parts.length!=3) throw new BridgeException("record_corrupt","Malformed turn mark");
                parsed.marks.put(Integer.parseInt(parts[1]),parts);
            }
            return parsed;
        } catch(BridgeException e) {
            if(e.code().startsWith("record_")) throw e;
            throw new BridgeException("record_corrupt","The record is malformed: "+e.getMessage());
        } catch(RuntimeException e) {
            throw new BridgeException("record_corrupt","The record is malformed: "+e);
        }
    }
}
