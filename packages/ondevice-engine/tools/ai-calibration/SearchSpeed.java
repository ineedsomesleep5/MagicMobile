package io.magicmobile.xmage;

import mage.abilities.Ability;
import mage.game.Game;
import mage.game.GameImpl;
import mage.game.events.TableEvent;
import mage.player.ai.ComputerPlayer6;
import mage.player.ai.SimulationNode2;
import mage.players.Player;
import mage.util.RandomUtil;
import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.*;
import java.util.concurrent.TimeUnit;

/**
 * AI search speed of an engine build: CPU per search node at real AI decisions (docs/LIGHTER_ENGINE_PLAN.md,
 * step 4: GraalVM -O2 against -Os). A measurement tool, never an app path; it runs on the JVM and as a host
 * native image of the same engine (scripts/build_native_bench.sh), so both read process CPU the same way, from
 * /proc/self/stat (Linux). One seeded AI-vs-AI game per run. The game's own AI decisions are limited by nodes, not
 * time, so a slower build plays the same kind of game; at AI decisions (main phases and combat, empty stack, one a
 * turn, something to search) the deciding AI's production search (cards copied on first use, search memory) runs
 * in full (not continuing its last plan) on a copy of the live game with no time limit and a fixed node limit, twice
 * from the same seeded generator; the row keeps the faster run. Positions can differ between builds (the game is not recorded), so compare totals.
 *
 * Usage: SearchSpeed out.csv seed skill_a skill_b a_first(1|0) deck_a.json deck_b.json max_turns max_probes
 *        probe_nodes game_nodes
 */
public final class SearchSpeed {
    static final String HEADER="game_seed,turn,step,seat,skill,nodes,copies,cpu_ms,wall_ms,repeat_cpu_ms,decision";
    static final double TICK_MS=10.0; // USER_HZ 100 on Linux

    public static void main(String[] args) throws Exception {
        if(args.length<11) throw new IllegalArgumentException("See the class comment for arguments");
        Path out=Path.of(args[0]);
        long seed=Long.parseLong(args[1]);
        AICalibration.Seat seatA=new AICalibration.Seat(Integer.parseInt(args[2]),"","0",seed^0x5EA7A11CEL);
        AICalibration.Seat seatB=new AICalibration.Seat(Integer.parseInt(args[3]),"","0",seed^0x5EA7B0B0L);
        boolean aFirst=args[4].equals("1");
        int maxTurns=Integer.parseInt(args[7]),maxProbes=Integer.parseInt(args[8]);
        int probeNodes=Integer.parseInt(args[9]),gameNodes=Integer.parseInt(args[10]);
        // The app's save/resume self-test: in a native benchmark, checks the checkpoint metadata and feature.
        System.out.println("SAVE-RESUME "+Checkpoints.available());
        XmageEngine engine=new XmageEngine("jvm-ai-calibration");
        Map<String,Map<String,Object>> decks=new HashMap<>();
        Map<String,Object> deckA=AICalibration.deck(decks,args[5]),deckB=AICalibration.deck(decks,args[6]);
        boolean header=!Files.exists(out);
        long started=System.nanoTime(),startCpu=cpuTicks();
        try(PrintWriter csv=new PrintWriter(Files.newBufferedWriter(out,StandardOpenOption.CREATE,StandardOpenOption.APPEND))) {
            if(header) csv.println(HEADER);
            RandomUtil.setSeed(seed);
            MobileAICancellation players=new MobileAICancellation(),lifecycle=new MobileAICancellation();
            MobileCommanderMatch match=new MobileCommanderMatch();
            Player a=AICalibration.aiPlayer(players,"A",seatA),b=AICalibration.aiPlayer(players,"B",seatB);
            if(aFirst) { match.addPlayer(a,DeckLoader.load(deckA));match.addPlayer(b,DeckLoader.load(deckB)); }
            else { match.addPlayer(b,DeckLoader.load(deckB));match.addPlayer(a,DeckLoader.load(deckA)); }
            match.startMatch();match.startGame();
            MobileCommanderGame game=(MobileCommanderGame)match.getGame();
            game.setCancellation(lifecycle);
            for(Player player:List.of(game.getPlayer(a.getId()),game.getPlayer(b.getId()))) limit(player,gameNodes);
            Map<UUID,String> seats=Map.of(a.getId(),"A",b.getId(),"B");
            Map<UUID,Integer> skills=Map.of(a.getId(),seatA.skill(),b.getId(),seatB.skill());
            Set<Integer> probed=new HashSet<>();
            int[] probes={0},attempts={0},empty={0},activeEmpty={0};
            game.addTableEventListener(event->{
                if(event.getEventType()!=TableEvent.EventType.UPDATE || probes[0]>=maxProbes) return;
                UUID deciding=game.getPriorityPlayerId();
                if(deciding==null || !seats.containsKey(deciding) || !game.getStack().isEmpty()
                        || !MobileAICancellation.searchesAt(game.getTurnStepType()) || probed.contains(game.getTurnNum())) return;
                try {
                    long probeSeed=seed+31L*game.getTurnNum();
                    attempts[0]++;
                    Run first=search(game,deciding,probeSeed,probeNodes);
                    if(first.nodes()==0) { // only Pass: nothing to search (mostly the player whose turn it is not)
                        empty[0]++;
                        if(deciding.equals(game.getActivePlayerId())) activeEmpty[0]++;
                        return;
                    }
                    Run second=search(game,deciding,probeSeed,probeNodes);
                    Run best=second.cpuMs()<first.cpuMs()?second:first;
                    probed.add(game.getTurnNum());
                    probes[0]++;
                    csv.println(seed+","+game.getTurnNum()+","+game.getTurnStepType()+","+seats.get(deciding)+","
                        +skills.get(deciding)+","+best.nodes()+","+best.copies()+","+best.cpuMs()+","+best.wallMs()+","
                        +Math.max(first.cpuMs(),second.cpuMs())+","+SearchEquivalence.quote(best.decision()));
                    csv.flush();
                } catch(Exception e) {
                    System.err.println("probe failed at turn "+game.getTurnNum()+": "+e);
                    e.printStackTrace();
                }
            });
            Thread worker=new Thread(()->{
                try { game.start(aFirst?a.getId():b.getId()); }
                catch(Throwable failure) { if(!lifecycle.isClosing()) failure.printStackTrace(); }
            },"GAME search-speed-"+game.getId()); // upstream checks the GAME prefix
            worker.setDaemon(true);
            worker.start();
            long deadline=System.nanoTime()+TimeUnit.HOURS.toNanos(2);
            while(worker.isAlive() && game.getTurnNum()<=maxTurns && probes[0]<maxProbes && System.nanoTime()<deadline) worker.join(200);
            lifecycle.close();players.close();worker.interrupt();worker.join(10_000);
            StringBuilder board=new StringBuilder();
            for(Player player:List.of(game.getPlayer(a.getId()),game.getPlayer(b.getId())))
                board.append(' ').append(seats.get(player.getId())).append(": life ").append(player.getLife()).append(", ")
                    .append(game.getBattlefield().getAllActivePermanents(player.getId()).size()).append(" permanents");
            System.out.println("BOARD"+board);
            System.out.println("PROBES "+probes[0]+" ("+attempts[0]+" tried, "+empty[0]+" with nothing to search, "+activeEmpty[0]
                +" of them on the deciding player's turn) to turn "
                +game.getTurnNum()+" in "
                +(System.nanoTime()-started)/1_000_000_000+" s, "+Math.round((cpuTicks()-startCpu)*TICK_MS/1000)+" s CPU");
        } finally { engine.close(); }
        System.exit(0); // upstream AI pools are non-daemon threads
    }

    /** Searches end at their depth or this many nodes, never on time (no quick search, no mistakes). */
    static void limit(Player player,int maxNodes) throws ReflectiveOperationException {
        SearchEquivalence.set(player,ComputerPlayer6.class,"maxThinkTimeSecs",600);
        SearchEquivalence.set(player,ComputerPlayer6.class,"maxNodes",maxNodes);
        SearchEquivalence.set(player,player.getClass(),"expert",false);
        SearchEquivalence.set(player,player.getClass(),"mistakePercent",0);
    }

    record Run(String move,int score,int nodes,int copies,long cpuMs,long wallMs) {
        String decision() { return move+" score "+score+" nodes "+nodes; }
    }
    static Run search(Game live,UUID deciding,long seed,int maxNodes) throws Exception {
        Game position=live.copy();
        position.getPlayerList().setCurrent(deciding);
        Player searcher=position.getPlayer(deciding);
        limit(searcher,maxNodes);
        ((List<?>)SearchEquivalence.get(searcher,ComputerPlayer6.class,"actions")).clear();
        // A full search every time: with its last line kept, the AI continues that plan without searching
        // whenever the game's state hash still matches (ComputerPlayer6.getNextAction).
        SearchEquivalence.set(searcher,ComputerPlayer6.class,"root",null);
        RandomUtil.setSeed(seed);
        SimulationNode2.resetCount();
        int copies=GameImpl.COPIED_COUNT.get();
        long ticks=cpuTicks(),started=System.nanoTime();
        searcher.priority(position);
        long wallMs=(System.nanoTime()-started)/1_000_000,cpuMs=Math.round((cpuTicks()-ticks)*TICK_MS);
        SimulationNode2 kept=(SimulationNode2)SearchEquivalence.get(searcher,ComputerPlayer6.class,"root");
        StringBuilder move=new StringBuilder();
        if(kept==null || kept.getAbilities()==null) move.append("none");
        else for(Ability ability:kept.getAbilities()) move.append(ability.toString()).append(';');
        return new Run(move.toString(),kept==null?0:kept.getScore(),SimulationNode2.getCount(),
            GameImpl.COPIED_COUNT.get()-copies,cpuMs,wallMs);
    }

    /** utime + stime of this process in clock ticks (fields 14 and 15 of /proc/self/stat). */
    static long cpuTicks() {
        try {
            String stat=Files.readString(Path.of("/proc/self/stat"));
            String[] fields=stat.substring(stat.lastIndexOf(')')+2).split(" ");
            return Long.parseLong(fields[11])+Long.parseLong(fields[12]);
        } catch(java.io.IOException e) { throw new IllegalStateException("Needs Linux /proc/self/stat",e); }
    }
}
