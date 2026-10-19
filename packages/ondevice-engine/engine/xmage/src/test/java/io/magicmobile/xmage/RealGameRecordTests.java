package io.magicmobile.xmage;

import io.magicmobile.core.BridgeException;
import io.magicmobile.core.Json;
import mage.game.Game;
import java.io.ByteArrayOutputStream;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.zip.GZIPOutputStream;

/**
 * Game records (docs/cloud/game-record.md) on the real JVM engine: games played with real MAD AI seats
 * and a scripted human through the production API, recorded, then replayed from the record alone to the
 * same winner, turn and life totals. Per-entry state digests locate the first difference on a failure.
 *
 * Args: work dir, then resolved decks token-triumph, chaos-incarnate, first-flight, isamaru, yargle, adeline.
 * JVM only; not native or phone evidence.
 */
public final class RealGameRecordTests {
    private static Path work;
    private static final List<String> sizes=new ArrayList<>();

    public static void main(String[] args) throws Exception {
        work=Files.createDirectories(Path.of(args[0]).toAbsolutePath());
        Map<String,Object> tokens=deck(args[1]),chaos=deck(args[2]),flight=deck(args[3]),isamaru=deck(args[4]),yargle=deck(args[5]),adeline=deck(args[6]);
        GameRecorder.trace=true;
        long start=System.nanoTime();
        // -Dmagicmobile.recordOnly=<scenario> runs one scenario while debugging.
        String only=System.getProperty("magicmobile.recordOnly","");
        if(only.isEmpty()) seededSetup(isamaru,yargle);
        // Two AIs play to a natural end after the only human concedes at once (a watcher seat).
        if(only.isEmpty() || only.equals("ai-duel")) aiGame("ai-duel",List.of(isamaru,yargle,adeline),101L);
        if(only.isEmpty() || only.equals("ai-precons")) aiGame("ai-precons",List.of(flight,chaos,tokens),202L);
        // A scripted human plays lands, casts spells and attacks against one AI, then concedes.
        if(only.isEmpty() || only.equals("human-vs-ai")) humanGame("human-vs-ai",tokens,List.of(chaos),303L,160,true);
        // Four seats, recorded mid-game while the human's question waits: the replay stops at that question.
        if(only.isEmpty() || only.equals("human-vs-3ai")) humanGame("human-vs-3ai",flight,List.of(isamaru,yargle,adeline),404L,90,false);
        // Two human seats (an online table) and an AI: both humans answer through the API, then concede in turn.
        if(only.isEmpty() || only.equals("two-humans")) twoHumans(tokens,flight,chaos,505L);
        // Expert AIs (skill 5 and up): the combat planner's attacks and blocks and the quick search move replay too.
        if(only.isEmpty() || only.equals("ai-experts")) aiGame("ai-experts",List.of(flight,chaos,tokens),606L,6);
        if(only.isEmpty() || only.equals("human-vs-expert")) humanGame("human-vs-expert",tokens,List.of(flight),707L,160,true,5);
        if(only.isEmpty()) tamper(isamaru,yargle);
        // -Dmagicmobile.recordSoak=<games>: more seeds and deck pairings, alternating AI-only and human games.
        int soak=Integer.getInteger("magicmobile.recordSoak",0);
        List<Map<String,Object>> precons=List.of(tokens,chaos,flight,adeline,isamaru,yargle);
        for(int i=Integer.getInteger("magicmobile.recordSoakFrom",0);i<soak;i++) {
            Map<String,Object> a=precons.get(i%precons.size()),b=precons.get((i*5+1)%precons.size()),c=precons.get((i*7+2)%precons.size());
            long seed=1000+i;
            switch(i%4) {
                case 0: aiGame("soak-"+i,List.of(a,b,c),seed);break;
                case 1: humanGame("soak-"+i,a,List.of(b),seed,200,true);break;
                case 2: aiGame("soak-"+i,List.of(b,c,a),seed);break;
                default: humanGame("soak-"+i,c,List.of(a,b,precons.get((i+3)%precons.size())),seed,120,i%8==3);
            }
        }
        if(soak>0) System.out.println("PASS soak: "+soak+" more games replayed to their recorded end");
        System.out.println("SIZES "+String.join("; ",sizes));
        System.out.println("ELAPSED total "+TimeUnit.NANOSECONDS.toSeconds(System.nanoTime()-start)+"s");
    }

    /** The same seed and seats deal the same opening hands and libraries, before any decision. */
    private static void seededSetup(Map<String,Object> a,Map<String,Object> b) throws Exception {
        List<String> first=null;
        for(int run=0;run<2;run++) {
            XmageEngine engine=new XmageEngine("jvm-record-seed");
            try {
                String id=Json.requiredString(engine.create(config(List.of(seat("human","Human",a,null),seat("ai1","AI 1",b,1)),77L)),"matchId");
                Game game=game(engine,id);
                RealCheckpointTests.Driver driver=new RealCheckpointTests.Driver(engine,id,false);
                driver.untilPrompt(60);
                // Card instances by load order (the record's names), not card names: basics are interchangeable by name.
                GameRecorder recorder=recorder(engine,id);
                List<String> libraries=new ArrayList<>();
                for(mage.players.Player player:game.getPlayers().values()) {
                    List<String> names=new ArrayList<>();
                    for(UUID card:player.getLibrary().getCardList()) names.add(recorder.name(card,game));
                    for(UUID card:player.getHand()) names.add("hand:"+recorder.name(card,game));
                    libraries.add(String.join(",",names));
                }
                if(first==null) first=libraries;
                else check(first.equals(libraries),"same seed and seats give the same libraries and hands");
                engine.destroy(id);
            } finally { engine.close(); }
        }
        System.out.println("PASS seeded setup: two matches with seed 77 dealt the same card instances to identical hands and library orders");
    }

    private static void aiGame(String name,List<Map<String,Object>> decks,long seed) throws Exception { aiGame(name,decks,seed,1); }
    private static void aiGame(String name,List<Map<String,Object>> decks,long seed,int skill) throws Exception {
        List<Object> seats=new ArrayList<>();
        seats.add(seat("human","Watcher",decks.get(2),null));
        seats.add(seat("ai1","AI 1",decks.get(0),skill));
        seats.add(seat("ai2","AI 2",decks.get(1),skill));
        XmageEngine engine=new XmageEngine("jvm-record-"+name);
        Map<String,Object> record;List<String> digests;
        long started=System.nanoTime();
        try {
            String id=Json.requiredString(engine.create(config(seats,seed)),"matchId");
            Game game=game(engine,id);
            RealCheckpointTests.Driver driver=new RealCheckpointTests.Driver(engine,id,false);
            driver.untilPrompt(60);
            engine.concede(id,"human");
            Map<String,Object> last=driver.untilFinished(900);
            check("ended".equals(last.get("phase")),name+": the AIs finish the game: "+last.get("failure"));
            record=engine.record(id);
            digests=new ArrayList<>(recorder(engine,id).digests);
            System.out.println("PLAYED "+name+" turns="+game.getTurnNum()+" in "+TimeUnit.NANOSECONDS.toSeconds(System.nanoTime()-started)+"s");
            engine.destroy(id);
        } finally { engine.close(); }
        replayMatches(name,record,digests,true);
    }

    private static void humanGame(String name,Map<String,Object> human,List<Map<String,Object>> ais,long seed,int prompts,boolean finish) throws Exception {
        humanGame(name,human,ais,seed,prompts,finish,1);
    }
    private static void humanGame(String name,Map<String,Object> human,List<Map<String,Object>> ais,long seed,int prompts,boolean finish,int skill) throws Exception {
        List<Object> seats=new ArrayList<>();
        seats.add(seat("human","Human",human,null));
        for(int i=0;i<ais.size();i++) seats.add(seat("ai"+(i+1),"AI "+(i+1),ais.get(i),skill));
        XmageEngine engine=new XmageEngine("jvm-record-"+name);
        Map<String,Object> record;List<String> digests;
        try {
            String id=Json.requiredString(engine.create(config(seats,seed)),"matchId");
            Game game=game(engine,id);
            RealCheckpointTests.Driver driver=new RealCheckpointTests.Driver(engine,id,true);
            Map<String,Object> state=driver.play(prompts,600);
            if(finish) {
                if("running".equals(state.get("phase"))) { engine.concede(id,"human");state=driver.untilFinished(240); }
                check("ended".equals(state.get("phase")),name+": game ended: "+state.get("failure"));
            } else {
                state=driver.untilPrompt(240);
                check("running".equals(state.get("phase")),name+": still running for a mid-game record");
            }
            record=engine.record(id);
            digests=new ArrayList<>(recorder(engine,id).digests);
            System.out.println("PLAYED "+name+" turns="+game.getTurnNum()+" humanAnswers="+driver.answered+" actions="+driver.actions);
            engine.destroy(id);
        } finally { engine.close(); }
        replayMatches(name,record,digests,finish);
    }

    private static void twoHumans(Map<String,Object> first,Map<String,Object> second,Map<String,Object> ai,long seed) throws Exception {
        String name="two-humans";
        List<Object> seats=List.of(seat("human","Human",first,null),seat("human2","Human 2",second,null),seat("ai1","AI 1",ai,1));
        XmageEngine engine=new XmageEngine("jvm-record-"+name);
        Map<String,Object> record;List<String> digests;
        try {
            String id=Json.requiredString(engine.create(config(seats,seed)),"matchId");
            Game game=game(engine,id);
            List<RealCheckpointTests.Driver> drivers=List.of(new RealCheckpointTests.Driver(engine,id,true,0,"human"),
                new RealCheckpointTests.Driver(engine,id,true,0,"human2"));
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(600);
            int answered=0;
            String phase="running";
            // Whichever seat XMage is asking answers; neither ever waits on the other.
            Set<String> live=Set.of("starting","running");
            while(answered<240 && live.contains(phase)) {
                check(System.nanoTime()<deadline,name+": stalled after "+answered+" answers");
                boolean any=false;
                for(RealCheckpointTests.Driver driver:drivers) {
                    Map<String,Object> state=driver.poll();
                    phase=String.valueOf(state.get("phase"));
                    if(!live.contains(phase)) break;
                    Map<String,Object> prompt=state.get("prompt")==null?null:Json.object(state.get("prompt"));
                    if(prompt==null || Boolean.TRUE.equals(prompt.get("submitted")) || driver.seen.contains((String)prompt.get("promptId"))) continue;
                    driver.answer(state);answered++;any=true;
                }
                if(!any) Thread.sleep(2);
            }
            if(live.contains(phase)) {
                engine.concede(id,"human2");
                Thread.sleep(300);
                if(!"ended".equals(drivers.get(0).poll().get("phase"))) engine.concede(id,"human");
            }
            Map<String,Object> last=drivers.get(0).untilFinished(300);
            check("ended".equals(last.get("phase")),name+": game ended: "+last.get("failure"));
            record=engine.record(id);
            digests=new ArrayList<>(recorder(engine,id).digests);
            System.out.println("PLAYED "+name+" turns="+game.getTurnNum()+" humanAnswers="+answered);
            engine.destroy(id);
        } finally { engine.close(); }
        long concedes=strings(record.get("entries")).stream().filter(e->e.length()>1 && e.charAt(1)=='c').count();
        check(concedes>=1,name+": the record holds the human concedes");
        replayMatches(name,record,digests,true);
    }

    private static void replayMatches(String name,Map<String,Object> record,List<String> digests,boolean ended) throws Exception {
        Files.writeString(work.resolve(name+".record.json"),Json.write(record));
        check(!record.containsKey("broken"),name+": recording stopped: "+record.get("broken"));
        Map<String,Object> end=Json.parseObject((String)record.get("end"));
        check(ended==("ended".equals(end.get("state"))),name+": record end state "+end.get("state"));
        long started=System.nanoTime();
        // A fresh JVM, as a verifier runs it: the documented command line, with nothing left over from the
        // recorded game's process.
        Map<String,Object> result=replayInFreshJvm(work.resolve(name+".record.json"));
        long millis=TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-started);
        if(!Boolean.TRUE.equals(result.get("matches"))) {
            // Diagnostics only: the same replay in this process, with per-entry traces.
            Map<String,Object> local=GameReplay.replay(record,false,TimeUnit.MINUTES.toMillis(5));
            result.put("inProcess",Json.map("outcome",local.get("outcome"),"entriesUsed",local.get("entriesUsed"),"message",local.get("message")));
            List<String> replayed=GameReplay.lastDigests;
            int first=0;
            while(first<Math.min(digests.size(),replayed.size()) && digests.get(first).equals(replayed.get(first))) first++;
            List<?> entries=Json.array(record.get("entries"));
            // Full state per entry for both runs, for a diff (GameRecorder.trace).
            Files.write(work.resolve(name+".recorded-trace.txt"),digests);
            Files.write(work.resolve(name+".replayed-trace.txt"),replayed);
            throw new AssertionError(name+": replay differs: "+Json.write(result)+"\n first state difference at entry "+first
                +" of "+digests.size()+" (replayed "+replayed.size()+"), traces in "+work+"; entries around it: "
                +entries.subList(Math.max(0,first-8),Math.min(entries.size(),first+4)));
        }
        int bytes=Json.write(record).getBytes(StandardCharsets.UTF_8).length;
        String size=name+": "+entries(record)+" entries, "+bytes+" B JSON, "+gzip(Json.write(record))+" B gzip, decisions only "
            +gzip(String.join("\n",strings(record.get("entries"))))+" B gzip";
        sizes.add(size);
        System.out.println("PASS "+name+" replay "+result.get("outcome")+" to the recorded "+(ended?"winner, ":"question, ")
            +"turn "+end.get("turn")+" and life totals "+Json.write(end.get("seats"))+" in "+millis+"ms; "+size);
    }

    private static Map<String,Object> replayInFreshJvm(Path file) throws Exception {
        String java=ProcessHandle.current().info().command().orElse(Path.of(System.getProperty("java.home"),"bin","java").toString());
        Path log=file.resolveSibling(file.getFileName()+".replay.log");
        Process process=new ProcessBuilder(java,"-Xmx1g","-Djava.awt.headless=true","-cp",System.getProperty("java.class.path"),
            GameReplay.class.getName(),file.toString()).redirectError(log.toFile()).start();
        String output=new String(process.getInputStream().readAllBytes(),StandardCharsets.UTF_8);
        if(!process.waitFor(300,TimeUnit.SECONDS)) { process.destroyForcibly();throw new AssertionError("replay timed out: "+file); }
        String line=output.lines().filter(l->l.startsWith("{")).reduce((a,b)->b).orElse(null);
        if(line==null) throw new AssertionError("replay printed no result ("+process.exitValue()+"): "+Files.readString(log).lines().limit(20).toList());
        Map<String,Object> result=new LinkedHashMap<>(Json.parseObject(line));
        check((process.exitValue()==0)==Boolean.TRUE.equals(result.get("matches")),"the command line exits 0 exactly when the replay matches");
        return result;
    }

    /** A changed entry breaks the hash chain; a different engine build is refused unless allowed. */
    private static void tamper(Map<String,Object> a,Map<String,Object> b) throws Exception {
        Map<String,Object> record=Json.parseObject(Files.readString(work.resolve("human-vs-ai.record.json")));
        List<Object> entries=new ArrayList<>(Json.array(record.get("entries")));
        Map<String,Object> changed=new LinkedHashMap<>(record);
        String entry=(String)entries.get(entries.size()/2);
        entries.set(entries.size()/2,entry+"x");changed.put("entries",entries);
        expect("record_corrupt",()->GameReplay.replay(changed,false,1000));
        Map<String,Object> setup=Json.parseObject((String)record.get("setup"));
        Json.object(setup.get("engine")).put("engineBuild","sha256:other");
        Map<String,Object> other=new LinkedHashMap<>(record);
        String setupText=Json.write(setup);
        other.put("setup",setupText);
        List<String> list=strings(record.get("entries"));
        other.put("head",GameRecord.head(setupText,list,(String)record.get("end")));
        expect("record_engine_mismatch",()->GameReplay.replay(other,false,1000));
        Map<String,Object> anyBuild=GameReplay.replay(other,true,TimeUnit.MINUTES.toMillis(5));
        check(Boolean.TRUE.equals(anyBuild.get("matches")) && Boolean.FALSE.equals(anyBuild.get("sameBuild")),"an explicitly allowed build replays: "+anyBuild);
        Map<String,Object> broken=new LinkedHashMap<>(record);broken.put("broken","test");
        expect("record_incomplete",()->GameReplay.replay(broken,false,1000));
        XmageEngine engine=new XmageEngine("jvm-record-config");
        try {
            for(Object bad:List.of("7",1.5,true))
                expectBridge("invalid_configuration",()->engine.create(config(List.of(seat("human","Human",a,null),seat("ai1","AI",b,1)),bad)));
        } finally { engine.close(); }
        System.out.println("PASS tampered entry fails the hash chain; other engine builds refused unless allowed; incomplete records refused; seed validated");
    }

    // ---- Helpers -----------------------------------------------------------------------------

    private static Map<String,Object> config(List<Object> seats,Object seed) { return Json.map("seats",seats,"seed",seed); }
    private static Map<String,Object> seat(String id,String name,Map<String,Object> deck,Integer skill) {
        Map<String,Object> seat=Json.map("seatId",id,"name",name,"controller",skill==null?"human":"ai","deck",deck);
        if(skill!=null) seat.put("aiSkill",skill);
        return seat;
    }
    private static Map<String,Object> deck(String path) throws Exception { return Json.parseObject(Files.readString(Path.of(path))); }
    private static int entries(Map<String,Object> record) { return Json.array(record.get("entries")).size(); }
    private static List<String> strings(Object list) { List<String> out=new ArrayList<>();for(Object o:Json.array(list)) out.add((String)o);return out; }
    private static int gzip(String text) throws Exception {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();
        try(GZIPOutputStream out=new GZIPOutputStream(bytes)) { out.write(text.getBytes(StandardCharsets.UTF_8)); }
        return bytes.size();
    }
    static Game game(XmageEngine engine,String id) throws Exception { return RealCheckpointTests.game(engine,id); }
    static GameRecorder recorder(XmageEngine engine,String id) throws Exception {
        Field matches=XmageEngine.class.getDeclaredField("matches");matches.setAccessible(true);
        Object running=((Map<?,?>)matches.get(engine)).get(id);
        Field recorder=running.getClass().getDeclaredField("recorder");recorder.setAccessible(true);
        return (GameRecorder)recorder.get(running);
    }
    private interface Action { void run() throws Exception; }
    private static void expect(String code,Action action) throws Exception {
        try { action.run();throw new AssertionError("Expected "+code); }
        catch(BridgeException e) { check(code.equals(e.code()),"Expected "+code+", got "+e.code()+": "+e.getMessage()); }
    }
    private static void expectBridge(String code,Action action) throws Exception { expect(code,action); }
    private static void check(boolean value,String message) { if(!value) throw new AssertionError(message); }
}
