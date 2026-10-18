package io.magicmobile.xmage;

import mage.abilities.Ability;
import mage.constants.PhaseStep;
import mage.game.Game;
import mage.game.GameImpl;
import mage.game.events.TableEvent;
import mage.player.ai.ComputerPlayer6;
import mage.player.ai.SimulationNode2;
import mage.players.Player;
import mage.util.RandomUtil;
import java.io.PrintWriter;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.TimeUnit;

/**
 * Engine release C's AI search memory against upstream's way, in real long games (docs/LIGHTER_ENGINE_PLAN.md, step
 * 3). A measurement tool, never an app path. One seeded AI-vs-AI game on AICalibration's phone budget; at AI decisions
 * (main phases and combat, empty stack, one a turn, decisions with something to search) the deciding AI's search runs on deep
 * copies of the live game three times from the same seeded generator, with no time limit (it ends at its depth or a
 * node limit, so it can repeat): twice the upstream way (GameImpl.mobileLazyCards and ComputerPlayer6.mobileSearchMemory
 * off: every copy deep, a library search's copies made up front), then with both on. Where the two upstream runs
 * agree, the position repeats, and the new way must make the same move with the same score and node count. Each run
 * also reports the copies it made and the most it held alive at once (AISearchMemory).
 *
 * Usage: SearchEquivalence out.csv seed skill_a skill_b a_first(1|0) deck_a.json deck_b.json max_turns max_probes max_nodes
 */
public final class SearchEquivalence {
    static final String HEADER="game_seed,turn,step,seat,skill,repeatable,equal,nodes,copies_upstream,copies_new,"
        +"alive_upstream,alive_new,ms_upstream,ms_new,decision_upstream,decision_new";

    public static void main(String[] args) throws Exception {
        if(args.length<10) throw new IllegalArgumentException("See the class comment for arguments");
        Path out=Path.of(args[0]);
        long seed=Long.parseLong(args[1]);
        AICalibration.Seat seatA=new AICalibration.Seat(Integer.parseInt(args[2]),"","",seed^0x5EA7A11CEL);
        AICalibration.Seat seatB=new AICalibration.Seat(Integer.parseInt(args[3]),"","",seed^0x5EA7B0B0L);
        boolean aFirst=args[4].equals("1");
        int maxTurns=Integer.parseInt(args[7]),maxProbes=Integer.parseInt(args[8]),maxNodes=Integer.parseInt(args[9]);
        XmageEngine engine=new XmageEngine("jvm-ai-calibration");
        Map<String,Map<String,Object>> decks=new HashMap<>();
        Map<String,Object> deckA=AICalibration.deck(decks,args[5]),deckB=AICalibration.deck(decks,args[6]);
        boolean header=!Files.exists(out);
        try(PrintWriter csv=new PrintWriter(Files.newBufferedWriter(out,java.nio.file.StandardOpenOption.CREATE,
                java.nio.file.StandardOpenOption.APPEND))) {
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
            Map<UUID,String> seats=Map.of(a.getId(),"A",b.getId(),"B");
            Map<UUID,Integer> skills=Map.of(a.getId(),seatA.skill(),b.getId(),seatB.skill());
            Set<String> probed=new HashSet<>();
            int[] probes={0};
            game.addTableEventListener(event->{
                if(event.getEventType()!=TableEvent.EventType.UPDATE || probes[0]>=maxProbes) return;
                UUID deciding=game.getPriorityPlayerId();
                if(deciding==null || !seats.containsKey(deciding) || !game.getStack().isEmpty()
                        || !MobileAICancellation.searchesAt(game.getTurnStepType())) return;
                if(probed.contains(String.valueOf(game.getTurnNum()))) return; // at most one decision a turn
                try {
                    String[] row=probe(game,deciding,seed+31L*game.getTurnNum(),maxNodes);
                    if(row[2].equals("0")) return; // nothing to search (only Pass), so nothing to compare
                    probed.add(String.valueOf(game.getTurnNum()));
                    probes[0]++;
                    csv.println(seed+","+game.getTurnNum()+","+game.getTurnStepType()+","+seats.get(deciding)+","+skills.get(deciding)
                        +","+String.join(",",row));
                    csv.flush();
                } catch(Exception e) {
                    System.err.println("probe failed at turn "+game.getTurnNum()+": "+e);
                    e.printStackTrace();
                }
            });
            Thread worker=new Thread(()->{
                try { game.start(aFirst?a.getId():b.getId()); }
                catch(Throwable failure) { if(!lifecycle.isClosing()) failure.printStackTrace(); }
            },"GAME search-equivalence-"+game.getId());
            worker.setDaemon(true);
            worker.start();
            long deadline=System.nanoTime()+TimeUnit.HOURS.toNanos(2);
            while(worker.isAlive() && game.getTurnNum()<=maxTurns && probes[0]<maxProbes && System.nanoTime()<deadline) worker.join(200);
            lifecycle.close();players.close();worker.interrupt();worker.join(10_000);
            System.out.println("PROBES "+probes[0]+" to turn "+game.getTurnNum());
        } finally { engine.close(); }
        System.exit(0); // upstream AI pools are non-daemon threads
    }

    /** repeatable, equal, nodes, copies and copies alive (upstream, new), ms (upstream, new), decisions. */
    static String[] probe(Game live,UUID deciding,long seed,int maxNodes) throws Exception {
        Run upstream=search(live,deciding,seed,maxNodes,false),again=search(live,deciding,seed,maxNodes,false);
        Run changed=search(live,deciding,seed,maxNodes,true);
        boolean repeatable=upstream.decision().equals(again.decision());
        boolean equal=upstream.decision().equals(changed.decision());
        return new String[]{repeatable?"1":"0",equal?"1":"0",String.valueOf(upstream.nodes),String.valueOf(upstream.copies),
            String.valueOf(changed.copies),String.valueOf(upstream.alive),String.valueOf(changed.alive),
            String.valueOf(upstream.ms),String.valueOf(changed.ms),quote(upstream.decision()),quote(changed.decision())};
    }
    record Run(String move,int score,int nodes,int copies,int alive,long ms) {
        String decision() { return move+" score "+score+" nodes "+nodes; }
    }
    static Run search(Game live,UUID deciding,long seed,int maxNodes,boolean newWay) throws Exception {
        GameImpl.mobileLazyCards=newWay;ComputerPlayer6.mobileSearchMemory=newWay;
        try {
            Game position=live.copy();
            position.getPlayerList().setCurrent(deciding);
            Player searcher=position.getPlayer(deciding);
            set(searcher,ComputerPlayer6.class,"maxThinkTimeSecs",600);
            set(searcher,ComputerPlayer6.class,"maxNodes",maxNodes);
            ((List<?>)get(searcher,ComputerPlayer6.class,"actions")).clear();
            Class<?> adapter=searcher.getClass();
            set(searcher,adapter,"expert",false); // no quick search: it is bounded by time
            set(searcher,adapter,"mistakePercent",0);
            RandomUtil.setSeed(seed);
            SimulationNode2.resetCount();
            int copies=GameImpl.COPIED_COUNT.get();
            long started=System.nanoTime();
            searcher.priority(position);
            long ms=(System.nanoTime()-started)/1_000_000;
            SimulationNode2 kept=(SimulationNode2)get(searcher,ComputerPlayer6.class,"root");
            AISearchMemory memory=AISearchMemory.last;
            StringBuilder move=new StringBuilder();
            if(kept==null || kept.getAbilities()==null) move.append("none");
            else for(Ability ability:kept.getAbilities()) {
                move.append(ability.toString());
                ability.getAllSelectedTargets().forEach(t->t.getTargets().forEach(id->move.append(" ->").append(id)));
                move.append(';');
            }
            return new Run(move.toString(),kept==null?0:kept.getScore(),SimulationNode2.getCount(),
                GameImpl.COPIED_COUNT.get()-copies,memory==null?-1:memory.peak,ms);
        } finally { GameImpl.mobileLazyCards=true;ComputerPlayer6.mobileSearchMemory=true; }
    }
    static String quote(String s) { return '"'+s.replace("\"","'")+'"'; }
    static Object get(Object target,Class<?> owner,String name) throws ReflectiveOperationException {
        Field f=owner.getDeclaredField(name);f.setAccessible(true);return f.get(target);
    }
    static void set(Object target,Class<?> owner,String name,Object value) throws ReflectiveOperationException {
        Field f=owner.getDeclaredField(name);f.setAccessible(true);f.set(target,value);
    }
}
