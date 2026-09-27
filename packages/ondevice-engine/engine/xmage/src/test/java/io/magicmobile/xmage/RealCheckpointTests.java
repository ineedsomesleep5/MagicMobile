package io.magicmobile.xmage;

import io.magicmobile.core.BridgeException;
import io.magicmobile.core.EngineDiagnostics;
import io.magicmobile.core.EngineService;
import io.magicmobile.core.Json;
import mage.abilities.Ability;
import mage.abilities.common.delayed.ReflexiveTriggeredAbility;
import mage.abilities.effects.Effect;
import mage.abilities.effects.common.CreateTokenCopyTargetEffect;
import mage.abilities.effects.common.CreateTokenEffect;
import mage.abilities.effects.common.GainLifeEffect;
import mage.abilities.effects.common.TargetPlayerGainControlTargetPermanentEffect;
import mage.cards.Card;
import mage.constants.Zone;
import mage.game.Game;
import mage.game.command.CommandObject;
import mage.game.events.TableEvent;
import mage.game.permanent.Permanent;
import mage.game.permanent.token.SoldierToken;
import mage.game.stack.StackObject;
import mage.players.Player;
import mage.target.targetpointer.FixedTarget;
import mage.util.RandomUtil;
import java.io.*;
import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;
import java.util.zip.GZIPOutputStream;

/**
 * Save/resume through the production engine API on the real JVM engine (not native, not a phone).
 * Every restore runs in a fresh child JVM, as after process death. Human answers come from a
 * simple fixture policy; AI seats are upstream MAD.
 *
 * RealCheckpointTests WORK_DIR TOKEN_TRIUMPH CHAOS_INCARNATE FIRST_FLIGHT ISAMARU YARGLE ADELINE FEATURES
 * (resolved deck JSON files; see scripts/test_real_engine.sh)
 */
public final class RealCheckpointTests {
    private static final String HUMAN="human";
    private static Path work;
    private static final List<Long> writeMillis=new ArrayList<>(), writeBytes=new ArrayList<>();

    public static void main(String[] args) throws Exception {
        if(args.length>0 && args[0].equals("child")) { child(args); return; }
        work=Path.of(args[0]).toAbsolutePath();Files.createDirectories(work);
        Map<String,Object> tokens=deck(args[1]),chaos=deck(args[2]),flight=deck(args[3]);
        Map<String,Object> isamaru=deck(args[4]),yargle=deck(args[5]),adeline=deck(args[6]),features=deck(args[7]);
        long start=System.nanoTime();
        rejections(isamaru,yargle);
        randomContinuity(isamaru,yargle);
        // One AI: bundled precons (Token Triumph human vs Chaos Incarnate MAD) at several turns.
        scenario("solo-1ai-precons",tokens,List.of(chaos),new int[]{3,5,7},Set.of(),0,true,18);
        // Three AIs: four seats, every library order and hidden hand in one checkpoint.
        scenario("solo-3ai",flight,List.of(isamaru,yargle,adeline),new int[]{2,5},Set.of(),0,true,30);
        // Three precon AIs (tokens, Path/Swords/Banishing Light exile, Hate Mirage copies, stolen
        // creatures) against cheap token/exile/copy/control fixture spells: checkpoints are also
        // taken the first time each of these is on the board. Whatever play has not produced by
        // turn 10 is put on the board through upstream rules code (see place), so every run
        // restores all of them.
        scenario("solo-3ai-precons-features",features,List.of(chaos,flight,tokens),new int[]{3},
            Set.of("tokens","exile","copies","controlChanged","stack"),10,true,30);
        System.out.println("ELAPSED total "+TimeUnit.NANOSECONDS.toSeconds(System.nanoTime()-start)+"s");
        System.out.println("CHECKPOINT-WRITES count="+writeMillis.size()+" "+stats("writeMs",writeMillis)+" "+stats("bytes",writeBytes));
        System.out.println("PASS real-JVM save/resume: fresh-process restores, rejections and RNG continuity (not native, not iOS)");
    }

    // ---- Rejections ------------------------------------------------------------------------

    private static void rejections(Map<String,Object> humanDeck,Map<String,Object> aiDeck) throws Exception {
        XmageEngine engine=new XmageEngine("jvm-checkpoint-test");
        try {
            check(Boolean.TRUE.equals(engine.capabilities().get("saveResume")),"JVM build reports saveResume");
            check(Boolean.FALSE.equals(engine.capabilities().get("hostMigration")),"host migration unchanged");
            Path dir=Files.createDirectories(work.resolve("rejections"));
            Path file=dir.resolve("game.ckpt");
            Map<String,Object> two=Json.map("seats",List.of(seat("h1","human",humanDeck,null),seat("h2","human",aiDeck,null),
                seat("ai","ai",aiDeck,1)),"checkpoint",Json.map("path",file.toString()));
            expect("invalid_configuration",()->engine.create(two));
            expect("invalid_configuration",()->engine.create(solo(humanDeck,aiDeck,"relative/game.ckpt")));
            expect("invalid_configuration",()->engine.create(solo(humanDeck,aiDeck,dir.resolve("missing/game.ckpt").toString())));
            Map<String,Object> extra=solo(humanDeck,aiDeck,file.toString());
            Json.object(extra.get("checkpoint")).put("keep",true);
            expect("invalid_configuration",()->engine.create(extra));
            expect("invalid_request",()->engine.restore(Json.map("path","relative.ckpt")));
            expect("checkpoint_corrupt",()->engine.restore(Json.map("path",dir.resolve("absent.ckpt").toString())));
            check(threads("GAME mobile-")==0,"rejected configurations start no game");

            // A real checkpoint, then every damaged variant of it.
            String id=Json.requiredString(engine.create(solo(humanDeck,aiDeck,file.toString())),"matchId");
            Driver driver=new Driver(engine,id,false);
            Map<String,Object> saved=driver.untilCheckpoint(1,60);
            check(!Json.write(saved).contains(file.toString()),"polls never carry the checkpoint path or payload");
            check(Json.object(saved.get("checkpoint")).keySet().equals(Set.of("sequence","savedAtMillis","turn","bytes","writeMillis")),
                "poll checkpoint info is metadata only");
            byte[] valid=Files.readAllBytes(file);
            expect("match_limit",()->engine.restore(Json.map("path",file.toString())));
            // A failed write never ends or blocks the game.
            Path moved=dir.resolveSibling("rejections-away");
            Files.move(dir,moved);
            Map<String,Object> failed=driver.untilNewPrompt(e->e.containsKey("checkpointFailure"),60);
            check("checkpoint_write_failed".equals(Json.object(failed.get("checkpointFailure")).get("code")),"write failure reported in polls");
            check(String.valueOf(EngineDiagnostics.read().get("report")).contains("checkpoint-write"),"write failure kept in diagnostics");
            check("running".equals(failed.get("phase")) && failed.get("prompt")!=null,"game continues after a failed write");
            Files.move(moved,dir);
            long before=Json.integer(Json.object(failed.get("checkpoint")).get("sequence"));
            Map<String,Object> recovered=driver.untilNewPrompt(e->!e.containsKey("checkpointFailure"),60);
            check(Json.integer(Json.object(recovered.get("checkpoint")).get("sequence"))==before+1,"next safe point writes again");
            engine.destroy(id);
            EngineDiagnostics.clear();

            Path good=dir.resolve("good.ckpt");Files.write(good,valid);
            Map<String,Object> header=header(valid);
            for(Map.Entry<String,Object> change:List.<Map.Entry<String,Object>>of(Map.entry("upstream","0000000000000000000000000000000000000000"),
                    Map.entry("catalogueHash","0".repeat(64)),Map.entry("engineBuild","sha256:"+"0".repeat(64)),
                    Map.entry("protocol",(Object)2L),Map.entry("format",(Object)2L))) {
                Map<String,Object> changed=new LinkedHashMap<>(header);changed.put(change.getKey(),change.getValue());
                Path bad=dir.resolve("header-"+change.getKey()+".ckpt");Files.write(bad,withHeader(valid,changed,payload(valid)));
                expect("checkpoint_incompatible",()->engine.restore(Json.map("path",bad.toString())));
            }
            byte[] format=valid.clone();format[8]=0;format[9]=2;
            expect("checkpoint_incompatible",()->restore(engine,dir,"format.ckpt",format));
            byte[] flipped=valid.clone();flipped[flipped.length-40]^=0x5a;
            expect("checkpoint_corrupt",()->restore(engine,dir,"sha.ckpt",flipped));
            expect("checkpoint_corrupt",()->restore(engine,dir,"truncated.ckpt",Arrays.copyOf(valid,valid.length*3/5)));
            expect("checkpoint_corrupt",()->restore(engine,dir,"header-cut.ckpt",Arrays.copyOf(valid,20)));
            expect("checkpoint_corrupt",()->restore(engine,dir,"empty.ckpt",new byte[0]));
            byte[] longer=Arrays.copyOf(valid,valid.length+1);
            expect("checkpoint_corrupt",()->restore(engine,dir,"trailing.ckpt",longer));
            // Filter: a class outside the allowlist is refused before it is constructed.
            byte[] file0=gzipSerialized(new java.io.File("/etc/hosts"));
            expect("checkpoint_corrupt",()->restore(engine,dir,"filter.ckpt",withHeader(valid,header,file0)));
            check(String.valueOf(EngineDiagnostics.read().get("report")).contains("filter"),"filter rejection is the recorded cause");
            byte[] map0=gzipSerialized(new HashMap<>(Map.of("a",1)));
            expect("checkpoint_corrupt",()->restore(engine,dir,"wrong-root.ckpt",withHeader(valid,header,map0)));
            try { Checkpoints.serialize(new java.io.File("x"));throw new AssertionError("writer must refuse a disallowed class"); }
            catch(InvalidClassException expected) {}
            // Reconfigure keeps a Condition method reference in a Serializable field.
            Card reconfigure=new mage.cards.c.ChainflailCentipede(UUID.randomUUID(),
                new mage.cards.CardSetInfo("Chainflail Centipede","NEO","135",mage.constants.Rarity.COMMON));
            Card read=(Card)Checkpoints.deserialize(Checkpoints.serialize(reconfigure));
            check(read.getAbilities().size()==reconfigure.getAbilities().size() && read.getAbilities().stream()
                .anyMatch(a->a.getClass().getName().equals("mage.abilities.keyword.ReconfigureUnattachAbility")),
                "serializable lambdas in upstream abilities round-trip");
            check(threads("GAME mobile-")==0 && threads("CALL mobile-")==0,"failed restores leave no running threads");
            // No partial match remains: a valid restore is still accepted.
            Map<String,Object> restored=engine.restore(Json.map("path",good.toString()));
            check(restored.keySet().containsAll(Set.of("matchId","seats","engine","restored")),"restore returns the create shape plus restored");
            check(restored.get("matchId").equals(id),"restored match keeps its identity");
            engine.destroy(Json.requiredString(restored,"matchId"));
            EngineDiagnostics.clear();
            System.out.println("PASS checkpoint rejections: one-human rule, paths, header identity, format, SHA-256, truncation,"
                +" filter, wrong root, failed write keeps playing, no partial match or threads");
        } finally { engine.close(); }
        // Core boundary: the operation is reachable through the JSON API.
        try(EngineService service=new EngineService(new XmageEngine("jvm-checkpoint-service"))) {
            String reply=service.request("{\"protocol\":1,\"op\":\"restore\",\"checkpoint\":{\"path\":\""+work.resolve("none.ckpt")+"\"}}");
            check(reply.contains("checkpoint_corrupt"),"restore op through EngineService: "+reply);
        }
    }
    private static Object restore(XmageEngine engine,Path dir,String name,byte[] bytes) {
        try { Path path=dir.resolve(name);Files.write(path,bytes);return engine.restore(Json.map("path",path.toString())); }
        catch(IOException e) { throw new UncheckedIOException(e); }
    }

    // ---- RNG continuity --------------------------------------------------------------------

    private static void randomContinuity(Map<String,Object> humanDeck,Map<String,Object> aiDeck) throws Exception {
        Path dir=Files.createDirectories(work.resolve("rng"));
        Path file=dir.resolve("game.ckpt"),copy=dir.resolve("saved.ckpt");
        XmageEngine engine=new XmageEngine("jvm-checkpoint-rng");
        List<Long> drawn=new ArrayList<>();
        try {
            String id=Json.requiredString(engine.create(solo(humanDeck,aiDeck,file.toString())),"matchId");
            // The human goes first, so no AI search has started: only the waiting GAME thread owns the RNG.
            new Driver(engine,id,false).untilCheckpoint(1,60);
            Files.copy(file,copy);
            for(int i=0;i<64;i++) drawn.add(RandomUtil.nextInt()&0xffffffffL);
            engine.destroy(id);
        } finally { engine.close(); }
        Path expected=dir.resolve("expected-draws.txt");
        Files.writeString(expected,drawn.stream().map(String::valueOf).collect(Collectors.joining(",")));
        Map<String,Object> result=runChild("rng",copy,expected,"rng",0);
        check(Boolean.TRUE.equals(result.get("drawsMatch")),"restored RNG continues exactly: "+result);
        System.out.println("PASS RNG continuity: 64 draws after restore in a fresh JVM equal the saved process's next draws");
    }

    // ---- Games -----------------------------------------------------------------------------

    /**
     * Checkpoints at the first fresh priority decision at or after each turn, then (for each wanted
     * board feature) at the first one where it is present; each is restored in a fresh JVM. From
     * turn placeFromTurn on (0: never), features play has not produced are placed on the live
     * game at a checkpointed decision, and the re-asked decision (the next checkpoint) is saved.
     */
    private static void scenario(String name,Map<String,Object> humanDeck,List<Map<String,Object>> aiDecks,int[] turns,
                                 Set<String> wanted,int placeFromTurn,boolean active,int promptsAfterRestore) throws Exception {
        long started=System.nanoTime();
        Path dir=Files.createDirectories(work.resolve(name));
        Path file=dir.resolve("game.ckpt");
        List<Object> seats=new ArrayList<>();seats.add(seat(HUMAN,"Human",humanDeck,null));
        for(int i=0;i<aiDecks.size();i++) seats.add(seat("ai"+(i+1),"AI "+(i+1),aiDecks.get(i),1));
        List<Path> saved=new ArrayList<>();List<Map<String,Object>> savedInfo=new ArrayList<>();
        List<Integer> targets=new ArrayList<>();for(int turn:turns) targets.add(turn);
        Set<String> missing=new TreeSet<>(wanted),natural=new TreeSet<>(),placed=new TreeSet<>();
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(600);
        // A game that ends before the turn targets (or before placement) is replaced by a new one
        // (at most three). Every checkpoint taken is restored and checked either way.
        for(int attempt=1;attempt<=3 && (!targets.isEmpty() || !missing.isEmpty());attempt++) {
        XmageEngine engine=new XmageEngine("jvm-checkpoint-"+name);
        try {
            String id=Json.requiredString(engine.create(Json.map("seats",seats,"checkpoint",Json.map("path",file.toString()))),"matchId");
            Game game=game(engine,id);
            AtomicInteger errors=new AtomicInteger();
            game.addTableEventListener(e->{if(e.getEventType()==TableEvent.EventType.ERROR)errors.incrementAndGet();});
            Driver driver=new Driver(engine,id,active);
            Set<String> placing=Set.of(); // placed at the previous decision, so on this checkpoint
            long placedAt=-1;int placements=0;
            while(!targets.isEmpty() || !missing.isEmpty()) {
                check(System.nanoTime()<deadline,name+": features never on the board at a checkpoint: "+missing+driver.diagnostics());
                Map<String,Object> state=driver.untilCheckpoint(targets.isEmpty()?0:targets.get(0),240);
                if(!"running".equals(state.get("phase"))) {
                    check(targets.isEmpty(),name+": game ended before turns "+targets+driver.diagnostics());
                    System.out.println("GAME-ENDED "+name+" attempt "+attempt+" at turn "+game.getTurnNum()+"; still missing "+missing);
                    break;
                }
                Map<String,Object> info=Json.object(state.get("checkpoint"));
                long turn=Json.integer(info.get("turn"));
                // A placement is saved by the re-asked decision itself, never by a later one.
                check(placing.isEmpty() || Json.integer(info.get("sequence"))==placedAt+1,
                    name+": placed "+placing+" but the next checkpoint was not the re-asked decision: "+info+driver.diagnostics());
                Map<String,Object> board=features(game);
                Set<String> present=new TreeSet<>();
                for(String feature:missing) if(Json.integer(board.get(feature))>0) present.add(feature);
                Set<String> placedHere=new TreeSet<>(present),naturalHere=new TreeSet<>(present);
                placedHere.retainAll(placing);naturalHere.removeAll(placing);
                placing=Set.of();
                boolean target=!targets.isEmpty();
                if(target) targets.remove(0);
                if(target || !present.isEmpty()) {
                    missing.removeAll(present);natural.addAll(naturalHere);placed.addAll(placedHere);
                    int index=saved.size();
                    Path copy=dir.resolve("saved-"+index+".ckpt");Files.copy(file,copy,StandardCopyOption.REPLACE_EXISTING);
                    Map<String,Object> prompt=Json.object(state.get("prompt"));
                    Map<String,Object> expected=Json.map("fingerprint",fingerprint(game),"kind",prompt.get("kind"),
                        "message",Json.object(prompt.get("payload")).get("message"),"selectMode",Json.object(prompt.get("payload")).get("selectMode"),
                        "features",board,"sequence",info.get("sequence"),"turn",info.get("turn"));
                    Files.writeString(dir.resolve("expected-"+index+".json"),Json.write(expected));
                    saved.add(copy);savedInfo.add(expected);
                    System.out.println("CHECKPOINT "+name+" #"+index+" turn="+info.get("turn")+" seq="+info.get("sequence")
                        +" bytes="+info.get("bytes")+" writeMs="+info.get("writeMillis")+" features="+board
                        +(wanted.isEmpty()?"":" natural="+naturalHere+" placed="+placedHere));
                }
                if(!missing.isEmpty() && placeFromTurn>0 && turn>=placeFromTurn) {
                    check(++placements<=3,name+": placed features "+missing+" left the board before the next checkpoint"+driver.diagnostics());
                    placing=place(game,missing,name,turn,Json.integer(info.get("sequence")));
                    placedAt=Json.integer(info.get("sequence"));
                    driver.reask(state);
                } else if(!targets.isEmpty() || !missing.isEmpty()) driver.answer(state); // else destroyed while parked
            }
            check(errors.get()==0 && game.getTotalErrorsCount()==0,"original game had no errors");
            engine.destroy(id);
            writeMillis.addAll(driver.writeMillis);writeBytes.addAll(driver.writeBytes);
            System.out.println("WRITES "+name+" count="+driver.writeMillis.size()+" "+stats("writeMs",driver.writeMillis)+" "+stats("bytes",driver.writeBytes)+" humanActions="+driver.actions);
        } finally { engine.close(); }
        }
        check(targets.isEmpty() && missing.isEmpty(),name+": three games ended before board features "+missing+" were checkpointed");
        if(!wanted.isEmpty()) System.out.println("FEATURES "+name+" natural="+natural+" placed="+placed);
        Map<String,Integer> covered=new TreeMap<>();
        for(int i=0;i<saved.size();i++) {
            Map<String,Object> result=runChild(name,saved.get(i),work.resolve(name).resolve("expected-"+i+".json"),active?"active":"passive",promptsAfterRestore);
            check(Boolean.TRUE.equals(result.get("fingerprintMatches")),"restored fingerprint equals checkpoint: "+result);
            check(Boolean.TRUE.equals(result.get("samePrompt")),"restored game re-asks the same priority decision: "+result);
            check(Boolean.TRUE.equals(result.get("legalEnd")) && Json.integer(result.get("errors"))==0,"restored game plays to a legal end: "+result);
            check(Boolean.TRUE.equals(result.get("keepsCheckpointing")),"restored game keeps checkpointing: "+result);
            Json.object(savedInfo.get(i).get("features")).forEach((k,v)->covered.merge(k,(int)Json.integer(v)>0?1:0,Integer::sum));
            System.out.println("RESTORED "+name+" #"+i+" "+Json.write(result));
        }
        for(String feature:wanted) check(covered.getOrDefault(feature,0)>0,name+": no restored checkpoint had "+feature);
        System.out.println("PASS "+name+": "+saved.size()+" fresh-process restores matched turn, step, life, hands, full libraries,"
            +" battlefield, graveyards, exile and stack; restored checkpoints with features "+covered
            +(wanted.isEmpty()?"":" (natural "+natural+", placed "+placed+")")
            +" ("+TimeUnit.NANOSECONDS.toSeconds(System.nanoTime()-started)+"s)");
    }

    /** Fresh JVM: restore, compare, keep playing to a legal end. Prints one RESULT line. */
    private static void child(String[] args) throws Exception {
        Path checkpoint=Path.of(args[1]),expectedFile=Path.of(args[2]);String mode=args[3];int prompts=Integer.parseInt(args[4]);
        XmageEngine engine=new XmageEngine("jvm-checkpoint-child");
        Map<String,Object> result=new LinkedHashMap<>();
        try {
            long start=System.nanoTime();
            Map<String,Object> restored=engine.restore(Json.map("path",checkpoint.toString()));
            result.put("restoreMillis",TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-start));
            long[] peak=Checkpoints.lastRead;
            result.put("readDepth",peak[0]);result.put("readReferences",peak[1]);result.put("readStreamBytes",peak[2]);
            String id=Json.requiredString(restored,"matchId");
            Game game=game(engine,id);
            AtomicInteger errors=new AtomicInteger();
            game.addTableEventListener(e->{if(e.getEventType()==TableEvent.EventType.ERROR)errors.incrementAndGet();});
            Map<String,Object> restoredInfo=Json.object(restored.get("restored"));
            Driver driver=new Driver(engine,id,mode.equals("active"));
            Map<String,Object> first=driver.untilPrompt(90);
            if(mode.equals("rng")) {
                List<Long> draws=new ArrayList<>();
                for(int i=0;i<64;i++) draws.add(RandomUtil.nextInt()&0xffffffffL);
                String expected=Files.readString(expectedFile);
                result.put("drawsMatch",expected.equals(draws.stream().map(String::valueOf).collect(Collectors.joining(","))));
                engine.destroy(id);
            } else {
                Map<String,Object> expected=Json.parseObject(Files.readString(expectedFile));
                Map<String,Object> prompt=Json.object(first.get("prompt"));
                String actual=fingerprint(game);
                result.put("fingerprintMatches",expected.get("fingerprint").equals(actual));
                if(!expected.get("fingerprint").equals(actual)) result.put("diff",diff((String)expected.get("fingerprint"),actual));
                result.put("samePrompt",expected.get("kind").equals(prompt.get("kind"))
                    && Objects.equals(expected.get("message"),Json.object(prompt.get("payload")).get("message"))
                    && Objects.equals(expected.get("selectMode"),Json.object(prompt.get("payload")).get("selectMode"))
                    && Json.integer(restoredInfo.get("turn"))==Json.integer(expected.get("turn")));
                // The first re-asked decision is itself a safe point: the same path gets the next sequence.
                result.put("keepsCheckpointing",first.get("checkpoint")!=null
                    && Json.integer(Json.object(first.get("checkpoint")).get("sequence"))==Json.integer(expected.get("sequence"))+1
                    && Checkpoints.read(checkpoint).sequence()==Json.integer(expected.get("sequence"))+1);
                result.put("turnRestored",game.getTurnNum());
                driver.answer(first);
                Map<String,Object> last=driver.play(prompts,120);
                result.put("promptsAnswered",driver.answered);
                String phase=(String)last.get("phase");
                if(!"ended".equals(phase)) {
                    // Concede is XMage's own legal loss for the seat. With AI seats left, they play on
                    // to a win or a two-turn cap (upstream stopOnTurn), since only AI time remains.
                    game.getOptions().stopOnTurn=game.getTurnNum()+2;
                    engine.concede(id,HUMAN);
                    last=driver.untilFinished(240);
                    phase=(String)last.get("phase");
                }
                Map<?,?> failure=(Map<?,?>)last.get("failure");
                boolean capped=failure!=null && "engine_stopped".equals(failure.get("code")) && game.getTurnNum()>=game.getOptions().stopOnTurn;
                result.put("end","ended".equals(phase)?"win":capped?"turn-cap":String.valueOf(failure));
                result.put("legalEnd","ended".equals(phase) || capped);
                result.put("finalTurn",game.getTurnNum());
                result.put("errors",(long)errors.get()+game.getTotalErrorsCount());
                result.put("checkpointFailures",driver.failures);
                Object report=EngineDiagnostics.read().get("report");
                if(report!=null) result.put("diagnostics",String.valueOf(report).lines().limit(3).collect(Collectors.joining(" | ")));
                engine.destroy(id);
            }
        } finally { engine.close(); }
        System.out.println("RESULT "+Json.write(result));
        System.exit(0);
    }
    private static Map<String,Object> runChild(String name,Path checkpoint,Path expected,String mode,int prompts) throws Exception {
        String java=ProcessHandle.current().info().command().orElse(Path.of(System.getProperty("java.home"),"bin","java").toString());
        Path log=checkpoint.resolveSibling(checkpoint.getFileName()+".child.log");
        Path restoreCopy=checkpoint.resolveSibling(checkpoint.getFileName()+".restore");
        Files.copy(checkpoint,restoreCopy,StandardCopyOption.REPLACE_EXISTING); // the restored game keeps writing to its path
        Process process=new ProcessBuilder(java,"-Xmx1g","-Djava.awt.headless=true","-cp",System.getProperty("java.class.path"),
            RealCheckpointTests.class.getName(),"child",restoreCopy.toString(),expected.toString(),mode,Integer.toString(prompts))
            .redirectErrorStream(true).redirectOutput(log.toFile()).start();
        if(!process.waitFor(420,TimeUnit.SECONDS)) { process.destroyForcibly();throw new AssertionError("restore child timed out: "+log); }
        String output=Files.readString(log);
        String line=output.lines().filter(l->l.startsWith("RESULT ")).findFirst().orElse(null);
        if(process.exitValue()!=0 || line==null) throw new AssertionError("restore child failed ("+process.exitValue()+"): "
            +output.lines().filter(l->!l.contains("FATAL") && !l.startsWith("\t")).limit(60).collect(Collectors.joining("\n")));
        return Json.parseObject(line.substring(7));
    }

    // ---- Fixture human policy --------------------------------------------------------------

    /** Human answers through the production API only. Active: lands, spells, attacks; passive: pass. */
    static final class Driver {
        final XmageEngine engine; final String match; final boolean active;
        final Set<String> seen=new HashSet<>(), tried=new HashSet<>(), picked=new HashSet<>();
        final List<Long> writeMillis=new ArrayList<>(), writeBytes=new ArrayList<>();
        final Map<Long,Integer> perTurn=new HashMap<>();
        final Map<String,Integer> actions=new TreeMap<>();
        final ArrayDeque<String> recent=new ArrayDeque<>();
        String lastDialog="";
        long lastSequence=-1,failures;int answered;
        /** Recent questions and the GAME thread's stack, for a stalled-game failure. */
        String diagnostics() {
            String stack=Thread.getAllStackTraces().entrySet().stream().filter(e->e.getKey().getName().startsWith("GAME mobile-"))
                .map(e->Arrays.stream(e.getValue()).limit(25).map(String::valueOf).collect(Collectors.joining("\n    ")))
                .collect(Collectors.joining("\n  ---\n    "));
            return "\n recent prompts:\n  "+String.join("\n  ",recent)+"\n GAME thread:\n    "+stack;
        }
        Driver(XmageEngine engine,String match,boolean active) { this.engine=engine;this.match=match;this.active=active; }
        Map<String,Object> poll() {
            Map<String,Object> state=engine.poll(match,HUMAN,0);
            if(state.containsKey("checkpointFailure")) failures++;
            if(state.get("checkpoint")!=null) {
                Map<String,Object> info=Json.object(state.get("checkpoint"));
                long sequence=Json.integer(info.get("sequence"));
                if(sequence!=lastSequence && lastSequence>=0) { writeMillis.add(Json.integer(info.get("writeMillis")));writeBytes.add(Json.integer(info.get("bytes"))); }
                if(lastSequence<0) { writeMillis.add(Json.integer(info.get("writeMillis")));writeBytes.add(Json.integer(info.get("bytes"))); }
                lastSequence=sequence;
            }
            if("failed".equals(state.get("phase")) && !Json.write(state.get("failure")).contains("engine_stopped"))
                throw new AssertionError("engine failed: "+state.get("failure"));
            return state;
        }
        /** Next unanswered prompt, without answering it. */
        Map<String,Object> untilPrompt(int seconds) throws InterruptedException {
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(seconds);
            while(System.nanoTime()<deadline) {
                Map<String,Object> state=poll();
                Map<String,Object> prompt=state.get("prompt")==null?null:Json.object(state.get("prompt"));
                if(prompt!=null && !Boolean.TRUE.equals(prompt.get("submitted")) && !seen.contains((String)prompt.get("promptId"))) return state;
                if(!"running".equals(state.get("phase")) && !"starting".equals(state.get("phase"))) return state;
                Thread.sleep(5);
            }
            throw new AssertionError("no prompt within "+seconds+"s"+diagnostics());
        }
        /** Answers prompts until one is a new checkpointed priority decision at or after the turn. */
        Map<String,Object> untilCheckpoint(int turn,int seconds) throws InterruptedException {
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(seconds);
            long sequence=lastSequence;
            while(System.nanoTime()<deadline) {
                Map<String,Object> state=untilPrompt(seconds);
                if(!"running".equals(state.get("phase"))) return state; // callers decide whether an end is expected
                Map<String,Object> info=state.get("checkpoint")==null?null:Json.object(state.get("checkpoint"));
                boolean fresh=info!=null && Json.integer(info.get("sequence"))!=sequence;
                if(info!=null) sequence=Json.integer(info.get("sequence"));
                if(fresh && Json.integer(info.get("turn"))>=turn) {
                    Map<String,Object> prompt=Json.object(state.get("prompt"));
                    check("SELECT".equals(prompt.get("kind")) && "priority".equals(Json.object(prompt.get("payload")).get("selectMode")),
                        "a checkpoint is written only for a priority decision: "+prompt.get("kind"));
                    return state;
                }
                answer(state);
            }
            throw new AssertionError("no checkpoint at turn "+turn+" within "+seconds+"s"+diagnostics());
        }
        Map<String,Object> untilNewPrompt(java.util.function.Predicate<Map<String,Object>> condition,int seconds) throws InterruptedException {
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(seconds);
            Map<String,Object> state=untilPrompt(seconds);
            answer(state);
            while(System.nanoTime()<deadline) {
                state=untilPrompt(seconds);
                if(condition.test(state)) return state;
                answer(state);
            }
            throw new AssertionError("condition not reached");
        }
        Map<String,Object> play(int prompts,int seconds) throws InterruptedException {
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(seconds);
            Map<String,Object> state=poll();
            for(int i=0;i<prompts && System.nanoTime()<deadline;i++) {
                state=untilPrompt(seconds);
                if(!"running".equals(state.get("phase"))) return state;
                answer(state);
            }
            return poll();
        }
        Map<String,Object> untilFinished(int seconds) throws InterruptedException {
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(seconds);
            while(System.nanoTime()<deadline) {
                Map<String,Object> state=poll();
                if(!"running".equals(state.get("phase"))) return state;
                Thread.sleep(20);
            }
            throw new AssertionError("game did not finish within "+seconds+"s"+diagnostics());
        }
        void answer(Map<String,Object> state) {
            Map<String,Object> prompt=Json.object(state.get("prompt"));
            String id=(String)prompt.get("promptId");
            if(!seen.add(id)) return;
            Map<String,Object> value=choose(state,prompt);
            try { respond(prompt,value); }
            catch(BridgeException invalid) {
                if(!"invalid_response".equals(invalid.code())) throw invalid;
                respond(prompt,Json.map("kind","boolean","value",false));
            }
            answered++;
        }
        /**
         * A click on no object: upstream HumanPlayer.priority returns without passing, so
         * GameImpl.playPriority applies state-based actions, triggers and effects and asks the same
         * player again. That new priority() call is the next safe point, in the same step.
         */
        void reask(Map<String,Object> state) {
            Map<String,Object> prompt=Json.object(state.get("prompt"));
            check(seen.add((String)prompt.get("promptId")),"re-ask of an answered prompt");
            respond(prompt,uuid(UUID.randomUUID()));
            actions.merge("reasks",1,Integer::sum);
        }
        private void respond(Map<String,Object> prompt,Map<String,Object> answer) {
            engine.respond(match,HUMAN,Json.map("requestId",UUID.randomUUID().toString(),"promptId",prompt.get("promptId"),
                "promptRevision",prompt.get("revision"),"answer",answer));
        }
        private Map<String,Object> choose(Map<String,Object> state,Map<String,Object> prompt) {
            String kind=(String)prompt.get("kind");
            Map<String,Object> payload=Json.object(prompt.get("payload"));
            String message=String.valueOf(payload.get("message")).toLowerCase(Locale.ROOT);
            Map<String,Object> snapshot=state.get("snapshot")==null?Map.of():Json.object(state.get("snapshot"));
            Map<String,Object> view=snapshot.isEmpty()?Map.of():Json.object(snapshot.get("gameView"));
            long turn=view.containsKey("turn")?Json.integer(view.get("turn")):0;
            List<?> types=Json.array(prompt.get("responseTypes"));
            // XMage re-asks until an answer is usable; a fixture that repeats itself would loop.
            // Past a per-turn budget, decline whatever can be declined.
            int count=perTurn.merge(turn,1,Integer::sum);
            recent.addLast(turn+" "+kind+" "+payload.get("selectMode")+" "+message);
            while(recent.size()>16) recent.removeFirst();
            // Leftover mana after a cancelled cast: pass anyway, or the pass would be asked forever.
            if(kind.equals("ASK") && message.contains("mana pool")) return Json.map("kind","boolean","value",true);
            // Clone-style "enter as a copy" choices are optional; take them so copies reach the board.
            if(active && kind.equals("ASK") && message.contains("copy")) return Json.map("kind","boolean","value",true);
            if(count>60 && types.contains("boolean") && !message.contains("starting player")) { actions.merge("budgetDeclines",1,Integer::sum);return Json.map("kind","boolean","value",false); }
            actions.merge(kind.equals("SELECT")?"select-"+payload.get("selectMode"):kind,1,Integer::sum);
            String dialog=kind+":"+message;
            if(!dialog.equals(lastDialog)) { lastDialog=dialog;picked.clear(); }
            switch(kind) {
                case "PICK_TARGET": {
                    List<Object> candidates=new ArrayList<>(Json.array(payload.get("candidates")));
                    if(message.contains("starting player")) return uuid(snapshot.get("enginePlayerId"));
                    // Removal, theft and copies aim at the opponents' permanents first.
                    Set<Object> own=new HashSet<>();
                    for(Object player:Json.array(view.getOrDefault("players",List.of())))
                        if(Objects.equals(Json.object(player).get("playerId"),snapshot.get("enginePlayerId")))
                            own.addAll(Json.object(Json.object(player).get("battlefield")).keySet());
                    candidates.sort(Comparator.comparing(own::contains));
                    Object chosen=payload.get("options") instanceof Map?((Map<?,?>)payload.get("options")).get("chosenTargets"):null;
                    for(Object candidate:candidates)
                        if(!(chosen instanceof List && ((List<?>)chosen).contains(candidate)) && picked.add(String.valueOf(candidate)))
                            return uuid(candidate);
                    if(!types.contains("boolean") && !candidates.isEmpty()) return uuid(candidates.get(0));
                    break;
                }
                case "CHOOSE_CHOICE": {
                    List<Object> order=Json.array(payload.get("choiceOrder"));
                    if(!order.isEmpty()) return Json.map("kind","string","value",order.get(0));
                    break;
                }
                case "CHOOSE_MODE": return uuid(Json.array(payload.get("choiceOrder")).get(0));
                case "CHOOSE_ABILITY": case "PICK_ABILITY": return uuid(Json.object(Json.array(payload.get("abilities")).get(0)).get("id"));
                case "AMOUNT": return Json.map("kind","integer","value",prompt.get("min"));
                case "MULTI_AMOUNT": {
                    List<Object> values=new ArrayList<>();long total=0;
                    for(Object row:Json.array(payload.get("allocations"))) {long n=Json.integer(Json.object(row).get("min"));values.add(n);total+=n;}
                    long min=Json.integer(prompt.get("min"));
                    if(total<min && !values.isEmpty()) values.set(0,Json.integer(values.get(0))+min-total);
                    return Json.map("kind","integers","value",values);
                }
                case "CHOOSE_PILE": return Json.map("kind","boolean","value",true);
                case "PLAY_MANA": case "PLAY_X_MANA": {
                    // Tap a basic land of a colour the unpaid cost still needs, else any untapped land.
                    List<String> wantedLands=new ArrayList<>();
                    for(String[] colour:new String[][]{{"{w}","Plains"},{"{u}","Island"},{"{b}","Swamp"},{"{r}","Mountain"},{"{g}","Forest"}})
                        if(message.contains(colour[0])) wantedLands.add(colour[1]);
                    if(kind.equals("PLAY_MANA")) for(Object player:Json.array(view.getOrDefault("players",List.of()))) {
                        Map<String,Object> p=Json.object(player);
                        if(!Objects.equals(p.get("playerId"),snapshot.get("enginePlayerId"))) continue;
                        List<Map<String,Object>> lands=new ArrayList<>();
                        for(Object card:Json.object(p.get("battlefield")).values()) {
                            Map<String,Object> c=Json.object(card);
                            if(!Boolean.TRUE.equals(c.get("tapped")) && Json.array(c.getOrDefault("cardTypes",List.of())).contains("LAND")) lands.add(c);
                        }
                        lands.sort(Comparator.comparing(c->!wantedLands.contains(String.valueOf(c.get("name")))));
                        for(Map<String,Object> c:lands)
                            if(tried.add(turn+":mana:"+prompt.get("promptId")+":"+c.get("id"))) { actions.merge("manaTaps",1,Integer::sum);return uuid(c.get("id")); }
                    }
                    break;
                }
                case "SELECT": {
                    String mode=String.valueOf(payload.get("selectMode"));
                    if(!active) break;
                    if(mode.equals("attackers")) {
                        Map<?,?> options=payload.get("options") instanceof Map?(Map<?,?>)payload.get("options"):Map.of();
                        if(options.containsKey("specialButton") && tried.add(turn+":attack")) { actions.merge("attacks",1,Integer::sum);return Json.map("kind","string","value","special"); }
                        break;
                    }
                    if(mode.equals("priority")) {
                        Map<String,Object> playable=view.get("canPlayObjects") instanceof Map?Json.object(view.get("canPlayObjects")):Map.of();
                        Map<String,Object> objects=playable.get("objects") instanceof Map?Json.object(playable.get("objects")):Map.of();
                        for(String category:List.of("basicPlayAbilities","basicCastAbilities"))
                            for(Map.Entry<String,Object> entry:objects.entrySet())
                                if(Json.object(entry.getValue()).get(category)!=null && tried.add(turn+":"+category+":"+entry.getKey()))
                                    { actions.merge(category,1,Integer::sum);return uuid(entry.getKey()); }
                    }
                    break;
                }
                default: break;
            }
            if(types.contains("boolean")) return Json.map("kind","boolean","value",false);
            throw new AssertionError("fixture policy has no answer for "+kind+" "+payload);
        }
        private static Map<String,Object> uuid(Object id) { return Json.map("kind","uuid","value",String.valueOf(id)); }
    }

    // ---- Feature placement -----------------------------------------------------------------

    /**
     * Puts each missing board feature on the live game through upstream rules code, at a
     * checkpointed human priority decision, and returns the features placed. The caller then
     * re-asks that decision (Driver.reask), so the next checkpoint holds them.
     *
     * Runs on the test thread, only while the GAME thread is parked in the human's answer wait
     * (see parked). Nothing here asks a player a question, and upstream's
     * ThreadUtils.isRunGameThread accepts this "main" thread as a test runner. State-based
     * actions, triggers (onto the stack) and layered effects are left to the GAME thread, which
     * applies them in GameImpl.playPriority before it asks again.
     */
    private static Set<String> place(Game game,Set<String> missing,String name,long turn,long sequence) throws InterruptedException {
        parked(game);
        Player human=game.getState().getPlayers().values().stream().filter(p->p instanceof MobileHumanPlayer).findFirst().orElseThrow();
        Player opponent=game.getOpponents(human.getId()).stream().map(game::getPlayer).filter(p->p!=null && p.isInGame())
            .min(Comparator.comparing(Player::getName)).orElseThrow();
        // The source of every placement is the human's commander's own activated ability, Zedruu's
        // "{U}{R}{W}: Target opponent gains control of target permanent you control".
        Card commander=game.getCard(human.getCommandersIds().iterator().next());
        Ability zedruu=commander.getAbilities().stream()
            .filter(a->a.getEffects().stream().anyMatch(e->e instanceof TargetPlayerGainControlTargetPermanentEffect)).findFirst()
            .orElseThrow(()->new AssertionError("placement needs Zedruu's gain-control ability, not "+commander.getName()));
        Ability source=zedruu.copy();source.setControllerId(human.getId());
        // Basic lands have no enter-the-battlefield choices, so copying or giving one asks nobody.
        List<Permanent> lands=game.getBattlefield().getAllActivePermanents(human.getId()).stream()
            .filter(p->!p.isToken() && p.isLand(game) && p.isBasic(game)).sorted(Comparator.comparing(Permanent::getName)).collect(Collectors.toList());
        Set<String> placed=new TreeSet<>();List<String> how=new ArrayList<>();
        if(missing.contains("exile")) {
            Card top=human.getLibrary().getFromTop(game);
            if(top!=null && human.moveCards(top,Zone.EXILED,source,game)) { placed.add("exile");how.add("exile: top library card moved to exile (Player.moveCards)"); }
        }
        if(missing.contains("tokens") && new CreateTokenEffect(new SoldierToken()).apply(game,source)) {
            placed.add("tokens");how.add("tokens: a Soldier token (CreateTokenEffect, as Raise the Alarm)");
        }
        if(missing.contains("copies") && !lands.isEmpty()) {
            Effect copy=new CreateTokenCopyTargetEffect().setTargetPointer(new FixedTarget(lands.get(0),game));
            if(copy.apply(game,source)) { placed.add("copies");how.add("copies: a token copy of "+lands.get(0).getName()+" (CreateTokenCopyTargetEffect, as Quasiduplicate)"); }
        }
        if(missing.contains("controlChanged") && !lands.isEmpty()) {
            // The ability's own effect with its own targets, as it resolves: a GainControlTargetEffect
            // (Duration.Custom) that the GAME thread's layer pass applies.
            Ability give=source.copy();
            give.getTargets().get(0).add(opponent.getId(),game);
            Permanent land=lands.get(lands.size()-1);
            give.getTargets().get(1).add(land.getId(),game);
            if(give.getEffects().stream().allMatch(e->e.apply(game,give))) {
                placed.add("controlChanged");how.add("controlChanged: "+opponent.getName()+" gains control of "+land.getName()+" (Zedruu's effect)");
            }
        }
        if(missing.contains("stack")) {
            // Goes on the stack when the GAME thread next checks triggers, before it asks again.
            game.fireReflexiveTriggeredAbility(new ReflexiveTriggeredAbility(new GainLifeEffect(1),false),source);
            placed.add("stack");how.add("stack: a reflexive \"you gain 1 life\" trigger (Game.fireReflexiveTriggeredAbility)");
        }
        parked(game);
        System.out.println("PLACED "+name+" turn="+turn+" seq="+sequence+" "+placed+" of missing "+missing+": "+String.join("; ",how));
        return placed;
    }

    /**
     * Returns once the match's GAME thread is parked in MobileHumanPlayer.waitForResponse. That
     * loop only polls the answer queue and the concede queue until an answer arrives, and no AI
     * search runs during a human decision, so the test thread is then the only one touching the
     * game. Its writes happen before the GAME thread wakes: the answer passes through the
     * synchronized mailbox and the player's answer queue.
     */
    private static void parked(Game game) throws InterruptedException {
        String gameThread="GAME mobile-"+game.getId();
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);
        while(true) {
            for(Map.Entry<Thread,StackTraceElement[]> entry:Thread.getAllStackTraces().entrySet()) {
                if(!entry.getKey().getName().equals(gameThread)) continue;
                boolean waiting=Arrays.stream(entry.getValue()).anyMatch(frame->frame.getClassName().equals(MobileHumanPlayer.class.getName())
                    && frame.getMethodName().equals("waitForResponse"));
                boolean conceding=Arrays.stream(entry.getValue()).anyMatch(frame->frame.getMethodName().equals("checkConcede"));
                // Timed wait inside waitForResponse: the answer queue poll.
                if(waiting && !conceding && entry.getKey().getState()==Thread.State.TIMED_WAITING) return;
            }
            check(System.nanoTime()<deadline,"GAME thread is not parked in the human's answer wait");
            Thread.sleep(5);
        }
    }

    // ---- Fingerprints ----------------------------------------------------------------------

    /** Everything the rules or a player could observe, without process-specific object IDs. */
    static String fingerprint(Game game) {
        StringBuilder text=new StringBuilder();
        text.append("turn=").append(game.getTurnNum()).append(" step=").append(game.getTurnStepType())
            .append(" active=").append(name(game,game.getActivePlayerId()))
            .append(" priority=").append(name(game,game.getState().getPriorityPlayerId()));
        List<Player> players=new ArrayList<>(game.getState().getPlayers().values());
        players.sort(Comparator.comparing(Player::getName));
        for(Player p:players) {
            text.append("\n ").append(p.getName()).append(" life=").append(p.getLife()).append(" lost=").append(p.hasLost())
                .append(" won=").append(p.hasWon()).append(" left=").append(p.hasLeft()).append(" counters=").append(p.getCountersAsCopy())
                .append(" pool=").append(p.getManaPool().getMana()).append(" landsPlayed=").append(p.getLandsPlayed())
                .append("\n  hand=").append(names(p.getHand().getCards(game),true))
                .append("\n  library=").append(names(p.getLibrary().getCards(game),false))
                .append("\n  graveyard=").append(names(p.getGraveyard().getCards(game),false));
        }
        List<String> battlefield=new ArrayList<>();
        for(Permanent perm:game.getBattlefield().getAllPermanents())
            battlefield.add(perm.getName()+"@"+name(game,perm.getControllerId())+"/"+name(game,perm.getOwnerId())
                +(perm.isTapped()?":T":"")+(perm.isToken()?":token":"")+(perm.isCopy()?":copy":"")+(perm.isFaceDown(game)?":down":"")
                +" "+perm.getPower().getValue()+"/"+perm.getToughness().getValue()+" dmg="+perm.getDamage()+" "+perm.getCounters(game)
                +" attached="+(perm.getAttachedTo()==null?"-":nameOf(game,perm.getAttachedTo())));
        Collections.sort(battlefield);
        text.append("\n battlefield=").append(String.join(" | ",battlefield));
        List<String> stack=new ArrayList<>();
        for(StackObject object:game.getStack()) stack.add(object.getName()+"@"+name(game,object.getControllerId()));
        text.append("\n stack=").append(String.join(" | ",stack));
        text.append("\n exile=").append(game.getExile().getAllCards(game).stream().map(Card::getName).sorted().collect(Collectors.joining("|")));
        List<String> command=new ArrayList<>();
        for(CommandObject object:game.getState().getCommand()) command.add(object.getName()+"@"+name(game,object.getControllerId()));
        Collections.sort(command);
        text.append("\n command=").append(String.join("|",command));
        return text.toString();
    }
    static Map<String,Object> features(Game game) {
        long tokens=0,copies=0,control=0;
        for(Permanent perm:game.getBattlefield().getAllPermanents()) {
            if(perm.isToken())tokens++;
            if(perm.isCopy())copies++;
            if(!perm.getControllerId().equals(perm.getOwnerId()))control++;
        }
        return Json.map("exile",(long)game.getExile().getAllCards(game).size(),"tokens",tokens,"copies",copies,
            "controlChanged",control,"stack",(long)game.getStack().size());
    }
    private static String names(Collection<? extends Card> cards,boolean sort) {
        List<String> names=cards.stream().map(Card::getName).collect(Collectors.toList());
        if(sort) Collections.sort(names);
        return String.join("|",names);
    }
    private static String name(Game game,UUID id) {
        if(id==null) return "-";
        Player player=game.getPlayer(id);
        return player==null?"?":player.getName();
    }
    private static String nameOf(Game game,UUID id) {
        mage.MageObject object=game.getObject(id);
        return object!=null?object.getName():name(game,id);
    }
    private static String diff(String expected,String actual) {
        String[] a=expected.split("\n"),b=actual.split("\n");
        for(int i=0;i<Math.min(a.length,b.length);i++) if(!a[i].equals(b[i])) return "line "+i+": expected ["+a[i]+"] actual ["+b[i]+"]";
        return "line count "+a.length+" vs "+b.length;
    }

    // ---- File helpers ----------------------------------------------------------------------

    private static Map<String,Object> header(byte[] file) {
        int length=ByteBuffer.wrap(file,10,4).getInt();
        return Json.parseObject(new String(file,14,length,StandardCharsets.UTF_8));
    }
    private static byte[] payload(byte[] file) {
        int length=ByteBuffer.wrap(file,10,4).getInt();
        return Arrays.copyOfRange(file,14+length,file.length);
    }
    private static byte[] withHeader(byte[] file,Map<String,Object> header,byte[] payload) {
        Map<String,Object> copy=new LinkedHashMap<>(header);
        copy.put("payloadBytes",(long)payload.length);copy.put("payloadSha256",Checkpoints.sha256(payload));
        byte[] json=Json.write(copy).getBytes(StandardCharsets.UTF_8);
        return ByteBuffer.allocate(14+json.length+payload.length).put(file,0,10).putInt(json.length).put(json).put(payload).array();
    }
    private static byte[] gzipSerialized(Object value) throws IOException {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();
        try(ObjectOutputStream out=new ObjectOutputStream(new GZIPOutputStream(bytes))) { out.writeObject(value); }
        return bytes.toByteArray();
    }

    // ---- Misc ------------------------------------------------------------------------------

    private static Map<String,Object> deck(String path) throws IOException { return Json.parseObject(Files.readString(Path.of(path))); }
    private static Map<String,Object> seat(String id,String name,Map<String,Object> deck,Integer skill) {
        Map<String,Object> seat=Json.map("seatId",id,"name",name,"controller",skill==null?"human":"ai","deck",deck);
        if(skill!=null) seat.put("aiSkill",skill);
        return seat;
    }
    private static Map<String,Object> solo(Map<String,Object> humanDeck,Map<String,Object> aiDeck,String path) {
        return Json.map("seats",List.of(seat(HUMAN,"Human",humanDeck,null),seat("ai","AI",aiDeck,1)),
            "checkpoint",Json.map("path",path));
    }
    static Game game(XmageEngine engine,String id) throws Exception {
        Field matches=XmageEngine.class.getDeclaredField("matches");matches.setAccessible(true);
        Object running=((Map<?,?>)matches.get(engine)).get(id);
        Field game=running.getClass().getDeclaredField("game");game.setAccessible(true);
        return (Game)game.get(running);
    }
    private static long threads(String prefix) {
        return Thread.getAllStackTraces().keySet().stream().filter(t->t.isAlive() && t.getName().startsWith(prefix)).count();
    }
    private static String stats(String label,List<Long> values) {
        if(values.isEmpty()) return label+"=none";
        List<Long> sorted=new ArrayList<>(values);Collections.sort(sorted);
        return label+"[min="+sorted.get(0)+" median="+sorted.get(sorted.size()/2)+" p90="+sorted.get(Math.min(sorted.size()-1,sorted.size()*9/10))
            +" max="+sorted.get(sorted.size()-1)+"]";
    }
    private static void expect(String code,Runnable action) {
        try { action.run();throw new AssertionError("Expected "+code); }
        catch(BridgeException e) { check(code.equals(e.code()),"Expected "+code+", got "+e.code()+": "+e.getMessage()); }
    }
    private static void check(boolean value,String message) { if(!value) throw new AssertionError(message); }
}
