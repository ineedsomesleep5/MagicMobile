package io.magicmobile.xmage;

import io.magicmobile.core.BridgeException;
import io.magicmobile.core.EngineService;
import io.magicmobile.core.Json;
import io.magicmobile.generated.EngineBuildIdentity;
import io.magicmobile.generated.GeneratedCardFactory;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.TimeUnit;

/**
 * Replays a game record on the JVM engine (docs/cloud/game-record.md): the same seeded generator, the
 * same seats and decks, and every recorded decision fed back in order, including save and resume points.
 * No AI search runs. The result says how the replay ended and whether it reached the recorded end.
 *
 * XMage's generator is process-wide, so a replay must not run beside a live match in the same process.
 *
 * Command line: {@code java -cp <runtime classpath> io.magicmobile.xmage.GameReplay record.json [--any-build]};
 * prints the result as JSON and exits 0 only when the replay matches the record.
 */
public final class GameReplay {
    private GameReplay() {}

    /**
     * The view code the live engine runs at each human question (XmageEngine.Running.query): the per-seat
     * snapshot and the prompt encoding. Its output is dropped, but some upstream view code touches game
     * state, so a replay that skipped it could drift from the recorded game.
     */
    private static final class Views implements mage.game.events.Listener<mage.game.events.PlayerQueryEvent> {
        private final transient mage.game.Game game;
        private final transient LinkedHashMap<String,MobileHumanPlayer> seats;
        private final transient GameRecorder recorder;
        Views(mage.game.Game game,LinkedHashMap<String,MobileHumanPlayer> seats,GameRecorder recorder) {
            this.game=game;this.seats=seats;this.recorder=recorder;
            for(MobileHumanPlayer human:seats.values()) human.onBoardChanged(this::project);
        }
        void project() { recorder.presenting(()->ViewProjector.project(game,seats)); }
        @Override public void event(mage.game.events.PlayerQueryEvent e) {
            if(e.getQueryType()==mage.game.events.PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) return;
            mage.players.Player acting=game.getPlayer(e.getPlayerId());
            mage.players.Player controller=acting==null?null:game.getPlayer(acting.getTurnControlledBy());
            project();
            if(controller instanceof MobileHumanPlayer) recorder.presenting(()->QueryEncoder.encode(e,game));
        }
    }

    /** Stops the replay's GAME thread at a recorded save, carrying the checkpoint payload it saved. */
    private static final class Resume extends Error {
        private static final long serialVersionUID=1L;
        final transient byte[] payload;
        Resume(byte[] payload) { super("resume",null,false,false);this.payload=payload; }
    }

    public static void main(String[] args) throws Exception {
        if(args.length<1) { System.err.println("usage: GameReplay record.json [--any-build]");System.exit(2); }
        Map<String,Object> record=Json.parseObject(Files.readString(Path.of(args[0])));
        // Debugging: -Dmagicmobile.recordTrace=<file> writes the state before every entry, for a diff.
        String trace=System.getProperty("magicmobile.recordTrace");
        GameRecorder.trace=trace!=null;
        Map<String,Object> result=replay(record,Arrays.asList(args).contains("--any-build"),TimeUnit.MINUTES.toMillis(10));
        if(trace!=null) Files.write(Path.of(trace),lastDigests);
        System.out.println(Json.write(result));
        System.exit(Boolean.TRUE.equals(result.get("matches"))?0:1);
    }

    /**
     * Replays the record. Throws record_* errors for a record that is malformed, incomplete, fails its hash
     * chain or (unless anyBuild) was made by a different engine build; otherwise returns
     * {@code outcome} (ended, exhausted, diverged, error or timeout), {@code matches}, the entries used,
     * the replay's {@code end} and the record's {@code recordedEnd}.
     */
    public static synchronized Map<String,Object> replay(Map<String,Object> record,boolean anyBuild,long timeoutMillis) throws InterruptedException {
        GameRecord.Parsed parsed=GameRecord.parse(record);
        Map<String,Object> engine=Json.object(parsed.setup.get("engine"));
        boolean sameBuild=EngineBuildIdentity.VALUE.equals(engine.get("engineBuild")) && XmageEngine.UPSTREAM.equals(engine.get("upstream"))
            && GeneratedCardFactory.CATALOGUE_HASH.equals(engine.get("catalogueHash")) && Json.integer(engine.get("protocol"))==EngineService.PROTOCOL;
        if(!sameBuild && !anyBuild) throw new BridgeException("record_engine_mismatch","The record was made by a different engine build");
        XmageEngine.installCards();
        long seed;List<Object> seatConfigs;List<UUID> playerIds=new ArrayList<>();
        try {
            seed=Long.parseLong(Json.requiredString(parsed.setup,"seed"));
            seatConfigs=Json.array(parsed.setup.get("seats"));
            for(Object id:Json.array(parsed.setup.get("players"))) playerIds.add(UUID.fromString(Json.string(id)));
            if(playerIds.size()!=seatConfigs.size()) throw new IllegalArgumentException("players and seats differ");
        } catch(RuntimeException e) { throw new BridgeException("record_corrupt","The record's setup is malformed: "+e.getMessage()); }
        MobileAICancellation cancellation=new MobileAICancellation();
        XmageEngine.Built built=XmageEngine.build(seatConfigs,cancellation,seed,playerIds);
        GameRecorder recorder=GameRecorder.replaying(built.record,parsed);
        List<String> seatIds=new ArrayList<>(built.players.keySet());
        LinkedHashMap<String,UUID> seats=new LinkedHashMap<>();
        built.players.forEach((seat,player)->seats.put(seat,player.getId()));
        ArrayList<String> humanSeats=new ArrayList<>(built.seats.keySet());
        UUID chooser=built.seats.values().iterator().next().getId();

        MobileCommanderMatch match=built.match;
        MobileCommanderGame game=(MobileCommanderGame)match.getGame();
        GameRandom random=built.random;
        cancellation.setRecorder(recorder);game.setCancellation(cancellation);
        game.addPlayerQueryEventListener(new Views(game,built.seats,recorder));
        long deadline=System.nanoTime()+TimeUnit.MILLISECONDS.toNanos(timeoutMillis);
        boolean resumed=false;
        String outcome,message=null;
        while(true) {
            MobileCommanderGame current=game;GameRandom stream=random;boolean resume=resumed;
            Throwable[] failure=new Throwable[1];
            recorder.resumeHook=()->{
                byte[] payload;
                try { payload=Checkpoints.serialize(new Checkpoints.Payload(current,seats,humanSeats,mage.util.RandomUtil.getRandom(),built.record)); }
                catch(java.io.IOException e) { throw new IllegalStateException("The replay could not save its game",e); }
                throw new Resume(payload);
            };
            Thread thread=new Thread(()->{
                try {
                    stream.bind(Thread.currentThread(),recorder);
                    recorder.bind(current,Thread.currentThread());
                    if(resume) current.resume(); else current.start(chooser);
                } catch(Throwable e) { failure[0]=e; }
            },"GAME replay");
            thread.setDaemon(true);thread.start();
            thread.join(Math.max(1,TimeUnit.NANOSECONDS.toMillis(deadline-System.nanoTime())));
            if(thread.isAlive()) {
                cancellation.close();thread.interrupt();
                outcome="timeout";message="The replay did not finish in "+timeoutMillis+" ms";break;
            }
            if(failure[0] instanceof Resume) {
                // As a fresh process restoring the checkpoint (XmageEngine.restore), then resuming it.
                cancellation.close();
                Checkpoints.Payload payload;
                try { payload=(Checkpoints.Payload)Checkpoints.deserialize(((Resume)failure[0]).payload); }
                catch(Exception e) { outcome="error";message="The replay could not restore its own save: "+e;break; }
                cancellation=new MobileAICancellation();
                game=payload.game;
                cancellation.adopt(game);
                Checkpoints.rehydrateSingletons(game);
                match=MobileCommanderMatch.restored(game);
                random=(GameRandom)payload.random;
                mage.util.RandomUtil.restoreRandom(random);
                cancellation.setRecorder(recorder);game.setCancellation(cancellation);
                LinkedHashMap<String,MobileHumanPlayer> restoredSeats=new LinkedHashMap<>();
                for(String seat:humanSeats) restoredSeats.put(seat,(MobileHumanPlayer)game.getPlayer(seats.get(seat)));
                game.addPlayerQueryEventListener(new Views(game,restoredSeats,recorder));
                resumed=true;
                continue;
            }
            if(failure[0] instanceof GameRecorder.Stop) {
                GameRecorder.Stop stop=(GameRecorder.Stop)failure[0];
                outcome=stop.kind;message=stop.getMessage();
            } else if(failure[0]!=null) {
                outcome="error";message=String.valueOf(failure[0]);
            } else if(game.hasEnded()) {
                match.endGame();outcome="ended";
            } else { outcome="error";message="XMage returned before ending the match"; }
            break;
        }
        cancellation.close();
        Map<String,Object> end=Json.parseObject(recorder.endJson(game,seatIds,"ended".equals(outcome)));
        // Same entry count and state as recorded; a finished record must also finish here.
        boolean used=recorder.cursor()==recorder.size();
        Map<String,Object> recorded=parsed.end;
        boolean matches=used && Objects.equals(recorded.get("state"),end.get("state"))
            && ("ended".equals(outcome) || "exhausted".equals(outcome))
            && Objects.equals(recorded.get("turn"),end.get("turn")) && Objects.equals(recorded.get("winners"),end.get("winners"))
            && Objects.equals(recorded.get("seats"),end.get("seats")) && Objects.equals(recorded.get("digest"),end.get("digest"))
            && Objects.equals(recorded.get("engineErrors"),end.get("engineErrors"));
        Map<String,Object> result=Json.map("outcome",outcome,"matches",matches,"entriesUsed",(long)recorder.cursor(),
            "entries",(long)recorder.size(),"resumes",(long)resumes(parsed),"sameBuild",sameBuild,"end",end,"recordedEnd",recorded);
        if(message!=null) result.put("message",message);
        lastDigests=new ArrayList<>(recorder.digests);
        return result;
    }
    private static int resumes(GameRecord.Parsed parsed) {
        int count=0;
        for(String entry:parsed.entries) if(entry.equals("-R")) count++;
        return count;
    }
    /**
     * Gives a new seat the recorded player's ID (JVM replay only: reflection on upstream's final field), with
     * the library and mana pool that carry it. Rules code iterates some hash sets of player IDs, such as the
     * defenders asked to block in a multiplayer game, so the replay must order them as the recorded game did.
     */
    static void usePlayerId(mage.players.Player player,UUID id) {
        try {
            for(String name:List.of("playerId","library","manaPool")) {
                java.lang.reflect.Field field=mage.players.PlayerImpl.class.getDeclaredField(name);
                field.setAccessible(true);
                field.set(player,name.equals("playerId")?id:name.equals("library")?new mage.players.Library(id):new mage.players.ManaPool(id));
            }
        } catch(ReflectiveOperationException | RuntimeException e) {
            throw new BridgeException("replay_unavailable","This runtime cannot replay records: "+e);
        }
    }
    /** Per-entry state digests of the last replay (when {@link GameRecorder#trace} is on). Tests only. */
    static volatile List<String> lastDigests=List.of();
}
