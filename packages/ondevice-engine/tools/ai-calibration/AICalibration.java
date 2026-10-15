package io.magicmobile.xmage;

import io.magicmobile.core.BridgeException;
import io.magicmobile.core.Json;
import mage.game.Game;
import mage.players.Player;
import mage.util.RandomUtil;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.TimeUnit;

/**
 * AI-vs-AI calibration games on the real XMage JVM engine. A measurement tool, never an app path.
 * scripts/ai_calibration.py starts one of these JVMs per CPU and gives each its own game numbers.
 *
 * Budgets (both use the production MobileAICancellation player):
 *  phone   - no person in the game, but the AIs keep the think budget they use against a person who
 *            is playing (skill x 3 s on an empty stack, 2 s while responding). This is what a ranked
 *            player faces. The AIs' cancellation is never bound to a live game, so humansPlaying()
 *            stays true (its documented "no live game" branch).
 *  watcher - the October 2026 method: a human watcher seat goes through the production adapter,
 *            picks the starting AI, then concedes at its first priority; the two AIs play on at
 *            watching pace (every search capped at STACK_THINK_SECS).
 *
 * Seeds: XMage's RandomUtil (shuffles, coin flips, random choices) is reseeded before each game.
 * AI searches are time-bounded and run on their own thread, so a seed fixes the decks' order and
 * the engine's random calls, not every AI decision; repeated runs agree statistically, not exactly.
 *
 * Protocol: one game per stdin line, games run one at a time (upstream AI search state is static,
 * so parallel games need separate JVMs):
 *   key,seed,budget,skill_a,skill_b,a_first(1|0),deck_a.json,deck_b.json,max_turns,max_seconds[,depth_a,mistake_a,depth_b,mistake_b]
 * and one stdout line per game, after it ends (XMage may log other lines to stdout):
 *   RESULT,key,first(A|B|?),winner(A|B|draw),turns,seconds,end(ended|turn-limit|time-limit|...)[,mistakes_a,mistakes_b]
 * The four optional fields (blank = the skill's default) and the two mistake counts need an engine with
 * AIDifficulty (cloud/c2-engine-a and later); it is found by reflection, so the tool also runs on
 * engines without it. There, each AI's mistake rolls are seeded from the game seed.
 */
public final class AICalibration {
    public static void main(String[] args) throws Exception {
        XmageEngine engine=new XmageEngine("jvm-ai-calibration"); // installs the generated card factories
        Map<String,Map<String,Object>> decks=new HashMap<>();
        java.io.BufferedReader in=new java.io.BufferedReader(new java.io.InputStreamReader(System.in));
        System.out.println("READY");System.out.flush();
        try {
            for(String line=in.readLine();line!=null;line=in.readLine()) {
                if(line.isBlank()) continue;
                String[] f=line.split(",",-1);
                if(f.length!=10 && f.length!=14) throw new IllegalArgumentException("Bad game line: "+line);
                boolean extended=f.length==14;
                String key=f[0],budget=f[2];long seed=Long.parseLong(f[1]);
                Seat skillA=new Seat(Integer.parseInt(f[3]),extended?f[10]:"",extended?f[11]:"",seed^0x5EA7A11CEL);
                Seat skillB=new Seat(Integer.parseInt(f[4]),extended?f[12]:"",extended?f[13]:"",seed^0x5EA7B0B0L);
                boolean aFirst=f[5].equals("1");
                Map<String,Object> deckA=deck(decks,f[6]),deckB=deck(decks,f[7]);
                int maxTurns=Integer.parseInt(f[8]),maxSeconds=Integer.parseInt(f[9]);
                RandomUtil.setSeed(seed);
                long started=System.nanoTime();
                Result r;
                try {
                    r=switch(budget) {
                        case "phone" -> phone(deckA,deckB,skillA,skillB,aFirst,maxTurns,maxSeconds);
                        case "watcher" -> watcher(engine,deckA,deckB,skillA,skillB,aFirst,maxTurns,maxSeconds);
                        default -> throw new IllegalArgumentException("budget is phone or watcher");
                    };
                } catch(BridgeException e) { r=new Result("?","draw",0,"error-"+e.code(),"",""); }
                double seconds=(System.nanoTime()-started)/1e9;
                System.out.printf(Locale.ROOT,"RESULT,%s,%s,%s,%d,%.1f,%s%s%n",key,r.first,r.winner,r.turns,seconds,r.end,
                    extended?","+r.mistakesA+","+r.mistakesB:"");
                System.out.flush();
            }
        } finally { engine.close(); }
        // Upstream AI pools are non-daemon threads.
        System.exit(0);
    }
    static Map<String,Object> deck(Map<String,Map<String,Object>> cache,String path) throws java.io.IOException {
        Map<String,Object> deck=cache.get(path);
        if(deck==null) { deck=Json.parseObject(Files.readString(Path.of(path)));cache.put(path,deck); }
        return deck;
    }

    /** A or B for the seat that won, draw when nobody did, first is the seat that took turn 1. */
    record Result(String first,String winner,int turns,String end,String mistakesA,String mistakesB) {}

    /** One AI seat: skill, optional depth and mistake overrides (blank = the skill's default), mistake seed. */
    record Seat(int skill,String depth,String mistakes,long seed) {
        boolean overridden() { return !depth.isEmpty() || !mistakes.isEmpty(); }
    }
    /** AIDifficulty exists from engine release A (C2) on; null on older engines. */
    static final Class<?> DIFFICULTY=difficultyClass();
    static Class<?> difficultyClass() {
        try { return Class.forName("io.magicmobile.xmage.AIDifficulty"); }
        catch(ClassNotFoundException absent) { return null; }
    }
    static Player aiPlayer(MobileAICancellation players,String name,Seat seat) throws Exception {
        if(DIFFICULTY==null) {
            if(seat.overridden()) throw new IllegalStateException("This engine has no AI depth or mistake settings");
            return players.player(name,seat.skill());
        }
        java.lang.reflect.Method depth=DIFFICULTY.getDeclaredMethod("searchDepth",int.class);
        java.lang.reflect.Method mistakes=DIFFICULTY.getDeclaredMethod("mistakePercent",int.class);
        depth.setAccessible(true);mistakes.setAccessible(true);
        int d=seat.depth().isEmpty()?(int)depth.invoke(null,seat.skill()):Integer.parseInt(seat.depth());
        int m=seat.mistakes().isEmpty()?(int)mistakes.invoke(null,seat.skill()):Integer.parseInt(seat.mistakes());
        java.lang.reflect.Constructor<?> make=DIFFICULTY.getDeclaredConstructor(int.class,int.class,long.class);
        make.setAccessible(true);
        java.lang.reflect.Method player=MobileAICancellation.class.getDeclaredMethod("player",String.class,int.class,DIFFICULTY);
        player.setAccessible(true);
        return (Player)player.invoke(players,name,seat.skill(),make.newInstance(d,m,seat.seed()));
    }
    static String mistakes(Game game,Player player) {
        try {
            java.lang.reflect.Method count=MobileAICancellation.class.getDeclaredMethod("mistakes",Player.class);
            count.setAccessible(true);
            return String.valueOf(count.invoke(null,game.getPlayer(player.getId())));
        } catch(ReflectiveOperationException absent) { return ""; }
    }

    static Result phone(Map<String,Object> deckA,Map<String,Object> deckB,Seat skillA,Seat skillB,boolean aFirst,
                        int maxTurns,int maxSeconds) throws Exception {
        MobileAICancellation players=new MobileAICancellation(); // never bound: AIs think as against a person
        MobileAICancellation lifecycle=new MobileAICancellation();
        MobileCommanderMatch match=new MobileCommanderMatch();
        Player a=aiPlayer(players,"A",skillA),b=aiPlayer(players,"B",skillB);
        // Seat order is turn order; the first seat also chooses who starts.
        if(aFirst) { match.addPlayer(a,DeckLoader.load(deckA));match.addPlayer(b,DeckLoader.load(deckB)); }
        else { match.addPlayer(b,DeckLoader.load(deckB));match.addPlayer(a,DeckLoader.load(deckA)); }
        match.startMatch();match.startGame();
        MobileCommanderGame game=(MobileCommanderGame)match.getGame();
        game.setCancellation(lifecycle);
        UUID chooser=aFirst?a.getId():b.getId();
        Thread worker=new Thread(()->{
            try { game.start(chooser); }
            catch(Throwable failure) { if(!lifecycle.isClosing()) failure.printStackTrace(); }
        },"GAME ai-calibration-"+game.getId()); // upstream checks the GAME prefix
        worker.setDaemon(true);worker.start();
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(maxSeconds);
        String end="ended";
        while(worker.isAlive()) {
            worker.join(200);
            if(game.getTurnNum()>maxTurns) { end="turn-limit";break; }
            if(System.nanoTime()>deadline) { end="time-limit";break; }
        }
        if(!end.equals("ended")) {
            lifecycle.close();players.close();worker.interrupt();worker.join(10_000);
        } else if(!game.hasEnded()) end="engine-stopped";
        return new Result(seatOf(game.getStartingPlayerId(),a,b),end.equals("ended")?winner(game,a,b):"draw",
            game.getTurnNum(),end,mistakes(game,a),mistakes(game,b));
    }

    static Result watcher(XmageEngine engine,Map<String,Object> deckA,Map<String,Object> deckB,Seat skillA,Seat skillB,
                          boolean aFirst,int maxTurns,int maxSeconds) throws Exception {
        Map<String,Object> config=Json.map("seats",List.of(
            Json.map("seatId","watcher","name","Watcher","controller","human","deck",deckA),
            aiSeat("a","A",skillA,deckA),aiSeat("b","B",skillB,deckB)));
        String id=Json.requiredString(engine.create(config),"matchId");
        String first="?",end="ended",winner="draw";int turns=0;boolean conceded=false;
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(maxSeconds);
        try {
            while(true) {
                Map<String,Object> state=engine.poll(id,"watcher",0);
                Object phase=state.get("phase");
                if("failed".equals(phase)) { end="engine-failed";break; }
                Map<String,Object> view=state.get("snapshot")==null?null:Json.object(Json.object(state.get("snapshot")).get("gameView"));
                if(view!=null && view.get("turn")!=null) turns=(int)Json.integer(view.get("turn"));
                if("ended".equals(phase)) {
                    for(Object p:Json.array(view.get("players"))) {
                        Map<String,Object> player=Json.object(p);
                        if(Json.integer(player.get("wins"))>=1) winner=String.valueOf(player.get("name"));
                    }
                    if(winner.equals("Watcher")) winner="draw";
                    break;
                }
                if(turns>maxTurns) { end="turn-limit";break; }
                if(System.nanoTime()>deadline) { end="time-limit";break; }
                Object raw=state.get("prompt");
                Map<String,Object> prompt=raw==null?null:Json.object(raw);
                if(!conceded && prompt!=null && !Boolean.TRUE.equals(prompt.get("submitted"))) {
                    Map<String,Object> payload=Json.object(prompt.get("payload"));
                    String message=String.valueOf(payload.get("message")).toLowerCase(Locale.ROOT);
                    if(message.contains("starting player")) {
                        String wanted=aFirst?"A":"B";first=wanted;
                        Object choice=null;
                        for(Object p:Json.array(view.get("players")))
                            if(wanted.equals(Json.object(p).get("name"))) choice=Json.object(p).get("playerId");
                        engine.respond(id,"watcher",Json.map("requestId",UUID.randomUUID().toString(),"promptId",prompt.get("promptId"),
                            "promptRevision",prompt.get("revision"),"answer",Json.map("kind","uuid","value",choice)));
                    } else {
                        // Mulligan or first priority: leave the game; the AIs play on.
                        engine.concede(id,"watcher");conceded=true;
                    }
                }
                Thread.sleep(50);
            }
        } finally { destroy(engine,id); }
        return new Result(first,winner,turns,end,"","");
    }

    static Map<String,Object> aiSeat(String id,String name,Seat seat,Map<String,Object> deck) {
        Map<String,Object> s=Json.map("seatId",id,"name",name,"controller","ai","aiSkill",seat.skill(),"deck",deck);
        if(DIFFICULTY!=null) s.put("aiSeed",seat.seed());
        if(!seat.depth().isEmpty()) s.put("aiSearchDepth",Integer.parseInt(seat.depth()));
        if(!seat.mistakes().isEmpty()) s.put("aiMistakePercent",Integer.parseInt(seat.mistakes()));
        return s;
    }
    static String seatOf(UUID id,Player a,Player b) {
        return id==null?"?":id.equals(a.getId())?"A":id.equals(b.getId())?"B":"?";
    }
    static String winner(Game game,Player a,Player b) {
        boolean aWon=game.getPlayer(a.getId()).hasWon(),bWon=game.getPlayer(b.getId()).hasWon();
        if(aWon==bWon) {
            // A pod game ends when one player is left; that player may not be flagged as the winner.
            boolean aIn=game.getPlayer(a.getId()).isInGame(),bIn=game.getPlayer(b.getId()).isInGame();
            if(aIn!=bIn) return aIn?"A":"B";
            return "draw";
        }
        return aWon?"A":"B";
    }
    static void destroy(XmageEngine engine,String id) throws InterruptedException {
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(30);
        while(true) {
            try { engine.destroy(id);return; }
            catch(BridgeException e) {
                if(!"engine_busy_shutdown".equals(e.code()) || System.nanoTime()>deadline) throw e;
                Thread.sleep(100);
            }
        }
    }
}
