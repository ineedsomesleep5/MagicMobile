package io.magicmobile.xmage;

import com.sun.management.GarbageCollectionNotificationInfo;
import com.sun.management.HotSpotDiagnosticMXBean;
import mage.game.Game;
import mage.game.GameImpl;
import mage.game.events.TableEvent;
import mage.players.Player;
import mage.util.RandomUtil;
import javax.management.NotificationEmitter;
import javax.management.ObjectName;
import javax.management.openmbean.CompositeData;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryUsage;
import java.lang.management.ThreadInfo;
import java.lang.ref.Reference;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.LockSupport;

/**
 * One long seeded AI-vs-AI game on the real XMage JVM engine, observed for the lighter engine plan's step 1
 * (docs/LIGHTER_ENGINE_PLAN.md). A measurement tool, never an app path; scripts/profile_long_games.py runs it,
 * one JVM per game, and attaches async-profiler between the GAME and ENDED lines.
 *
 * The game is AICalibration's phone budget (the think time a ranked player faces) with the same seats and seeds.
 * Nothing in the engine changes; the tool only watches from outside:
 *  - searches: the GAME thread's stack is sampled every 10 ms; a search is the time it spends inside the AI's
 *    calculateActions. Per search: wall time, CPU and allocation of the GAME and AI-SIM-MAD threads, game copies
 *    (GameImpl.COPIED_COUNT, every copy anywhere) and upstream's node count.
 *  - turns: at the first priority of each turn (a table UPDATE event, on the GAME thread, outside any search) the
 *    live game is copied three times and timed, with the board's size. In memory mode it also measures what one
 *    copy keeps alive (heap after a full GC with eight copies held, minus without; rough, since a late search
 *    thread can free or allocate between the two GCs: heap dumps give the exact figure).
 *  - heap: a timeline every 250 ms and every GC (before and after).
 *  - memory mode only: a full GC every few seconds gives the live heap; each new live peak gets a class histogram,
 *    and the largest peak (once it is dump_over_baseline_mb above the heap before the game) a heap dump of live objects.
 *
 * Usage: LongGameProfile out key seed skill_a skill_b a_first(1|0) deck_a.json deck_b.json max_turns max_seconds
 *        mode(profile|memory) [gc_every_ms] [dump_over_baseline_mb]
 * Protocol: prints "READY", waits for a line on stdin, prints "GAME <pid>", plays, prints "ENDED", waits for a
 * line on stdin (the profiler is stopped in between), writes result.json and exits.
 */
public final class LongGameProfile {
    static final com.sun.management.ThreadMXBean THREADS=(com.sun.management.ThreadMXBean)ManagementFactory.getThreadMXBean();
    static final com.sun.management.OperatingSystemMXBean OS=(com.sun.management.OperatingSystemMXBean)ManagementFactory.getOperatingSystemMXBean();
    static final String AI_CLASS=MobileAICancellation.class.getName()+"$CancellablePlayer";
    static final long T0=System.nanoTime();
    static final Set<String> HEAP_POOLS=new HashSet<>();
    static {
        for(java.lang.management.MemoryPoolMXBean pool:ManagementFactory.getMemoryPoolMXBeans())
            if(pool.getType()==java.lang.management.MemoryType.HEAP) HEAP_POOLS.add(pool.getName());
    }

    public static void main(String[] args) throws Exception {
        if(args.length<11) throw new IllegalArgumentException("See the class comment for arguments");
        Path out=Path.of(args[0]);Files.createDirectories(out);
        long seed=Long.parseLong(args[2]);
        AICalibration.Seat seatA=new AICalibration.Seat(Integer.parseInt(args[3]),"","",seed^0x5EA7A11CEL);
        AICalibration.Seat seatB=new AICalibration.Seat(Integer.parseInt(args[4]),"","",seed^0x5EA7B0B0L);
        boolean aFirst=args[5].equals("1");
        int maxTurns=Integer.parseInt(args[8]),maxSeconds=Integer.parseInt(args[9]);
        boolean memory=args[10].equals("memory");
        long gcEveryMs=args.length>11?Long.parseLong(args[11]):2500;
        long dumpOver=(args.length>12?Long.parseLong(args[12]):40)<<20;

        XmageEngine engine=new XmageEngine("jvm-ai-calibration"); // installs the generated card factories
        Map<String,Map<String,Object>> decks=new HashMap<>();
        Map<String,Object> deckA=AICalibration.deck(decks,args[6]),deckB=AICalibration.deck(decks,args[7]);
        BufferedReader in=new BufferedReader(new InputStreamReader(System.in));
        Map<String,Object> result=new LinkedHashMap<>();
        result.put("key",args[1]);result.put("seed",seed);result.put("skill_a",seatA.skill());result.put("skill_b",seatB.skill());
        result.put("deck_a",Path.of(args[6]).getFileName().toString().replace(".json",""));
        result.put("deck_b",Path.of(args[7]).getFileName().toString().replace(".json",""));
        result.put("mode",memory?"memory":"profile");
        try {
            // Load and validate both decks once first, so the card catalogue (loaded on first use) is in the baseline
            // and outside the profile.
            DeckLoader.load(deckA);DeckLoader.load(deckB);
            System.gc();System.gc();
            long baseline=usedHeap();
            result.put("baseline_live_mb",mb(baseline));
            if(memory) Files.writeString(out.resolve("hist-baseline.txt"),histogram());
            System.out.println("READY");System.out.flush();
            in.readLine();
            RandomUtil.setSeed(seed);
            Observer observer=new Observer(out,memory,gcEveryMs,dumpOver,baseline);
            System.out.println("GAME "+ProcessHandle.current().pid());System.out.flush();
            long started=System.nanoTime();
            play(result,observer,deckA,deckB,seatA,seatB,aFirst,maxTurns,maxSeconds);
            result.put("seconds",Math.round((System.nanoTime()-started)/1e8)/10.0);
            observer.finish(result);
            System.out.println("ENDED");System.out.flush();
            in.readLine();
        } finally {
            Files.writeString(out.resolve("result.json"),json(result)+"\n");
            engine.close();
        }
        System.exit(0); // upstream AI pools are non-daemon threads
    }

    /** AICalibration.phone with the observer attached to the game and its GAME thread. */
    static void play(Map<String,Object> result,Observer observer,Map<String,Object> deckA,Map<String,Object> deckB,
                     AICalibration.Seat skillA,AICalibration.Seat skillB,boolean aFirst,int maxTurns,int maxSeconds) throws Exception {
        MobileAICancellation players=new MobileAICancellation(); // never bound: AIs think as against a person
        MobileAICancellation lifecycle=new MobileAICancellation();
        MobileCommanderMatch match=new MobileCommanderMatch();
        Player a=AICalibration.aiPlayer(players,"A",skillA),b=AICalibration.aiPlayer(players,"B",skillB);
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
        worker.setDaemon(true);
        observer.attach(game,worker,Map.of(a.getId(),"A",b.getId(),"B"),Map.of("A",skillA.skill(),"B",skillB.skill()));
        worker.start();
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(maxSeconds);
        String end="ended";
        while(worker.isAlive()) {
            worker.join(200);
            if(game.getTurnNum()>maxTurns) { end="turn-limit";break; }
            if(System.nanoTime()>deadline) { end="time-limit";break; }
        }
        observer.stop();
        if(!end.equals("ended")) {
            lifecycle.close();players.close();worker.interrupt();worker.join(10_000);
        } else if(!game.hasEnded()) end="engine-stopped";
        result.put("first",AICalibration.seatOf(game.getStartingPlayerId(),a,b));
        result.put("winner",end.equals("ended")?AICalibration.winner(game,a,b):"draw");
        result.put("turns",game.getTurnNum());
        result.put("end",end);
    }

    /** Flat JSON object of strings and numbers (the adapter's Json has no doubles). */
    static String json(Map<String,Object> values) {
        StringJoiner out=new StringJoiner(",","{","}");
        values.forEach((k,v)->out.add('"'+k+"\":"+(v instanceof Number?v:'"'+String.valueOf(v).replace("\"","'")+'"')));
        return out.toString();
    }
    static long usedHeap() { return ManagementFactory.getMemoryMXBean().getHeapMemoryUsage().getUsed(); }
    static double mb(long bytes) { return Math.round(bytes/1048576.0*10)/10.0; }
    static double ms(long nanos) { return Math.round(nanos/1e5)/10.0; }
    static long now() { return System.nanoTime()-T0; }
    static String histogram() throws Exception {
        // As jcmd GC.class_histogram: live objects only (runs a full GC first).
        return (String)ManagementFactory.getPlatformMBeanServer().invoke(new ObjectName("com.sun.management:type=DiagnosticCommand"),
            "gcClassHistogram",new Object[]{new String[0]},new String[]{String[].class.getName()});
    }

    /** Watches one game from the GAME thread's table events, a sampler thread and GC notifications. */
    static final class Observer {
        final Path out;final boolean memory;final long gcEveryNs,dumpOver,baseline;
        final PrintWriter searches,turns,timeline,gcs;
        MobileCommanderGame game;Thread gameThread;Map<UUID,String> seats;Map<String,Integer> skills;
        volatile boolean stopped;Thread sampler;
        java.lang.reflect.Field nodeCount;
        // Totals and peaks.
        long maxBeforeGc,maxAfterGc,maxAfterFull,maxLive,lastHistogram,lastDump;int dumpTurn=-1;
        int probeCopies,lastProbedTurn;long gcCount,gcNanos,fullGcCount,forcedGcNanos;
        long startCopies,startCpu;
        final List<Long> searchWallMs=new ArrayList<>();

        Observer(Path out,boolean memory,long gcEveryMs,long dumpOver,long baseline) throws IOException {
            this.out=out;this.memory=memory;this.gcEveryNs=gcEveryMs*1_000_000L;this.dumpOver=dumpOver;this.baseline=baseline;
            searches=writer("searches.csv","t_start_s,turn,step,seat,skill,stack,wall_ms,quick_ms,nodes_quick,nodes,copies,"
                +"game_cpu_ms,sim_cpu_ms,process_cpu_ms,game_alloc_mb,sim_alloc_mb,heap_max_mb,searched_full");
            turns=writer("turns.csv","turn,t_s,permanents,game_cards,hand,library,graveyard,exile,triggers,"
                +"copy_wall_ms,copy_cpu_ms,copy_alloc_kb,copy_retained_kb,heap_mb");
            timeline=writer("timeline.csv","t_s,turn,heap_used_mb,heap_committed_mb,copies,nodes,process_cpu_s,gc_count,gc_ms,in_search");
            gcs=writer("gc.csv","t_s,turn,gc,action,cause,ms,before_mb,after_mb");
            try { nodeCount=Class.forName("mage.player.ai.SimulationNode2").getDeclaredField("nodeCount");nodeCount.setAccessible(true); }
            catch(ReflectiveOperationException e) { throw new IllegalStateException(e); }
            for(GarbageCollectorMXBean bean:ManagementFactory.getGarbageCollectorMXBeans())
                ((NotificationEmitter)bean).addNotificationListener((n,h)->{
                    if(n.getType().equals(GarbageCollectionNotificationInfo.GARBAGE_COLLECTION_NOTIFICATION))
                        onGc(GarbageCollectionNotificationInfo.from((CompositeData)n.getUserData()));
                },null,null);
        }
        PrintWriter writer(String name,String header) throws IOException {
            PrintWriter w=new PrintWriter(Files.newBufferedWriter(out.resolve(name)));w.println(header);return w;
        }
        void attach(MobileCommanderGame game,Thread gameThread,Map<UUID,String> seats,Map<String,Integer> skills) {
            this.game=game;this.gameThread=gameThread;this.seats=seats;this.skills=skills;
            startCopies=GameImpl.COPIED_COUNT.get();startCpu=OS.getProcessCpuTime();
            game.addTableEventListener(event->{ if(event.getEventType()==TableEvent.EventType.UPDATE) probe(); });
            sampler=new Thread(this::sample,"mm-profile-sampler");sampler.setDaemon(true);sampler.start();
        }
        int turn() { return game==null?0:game.getTurnNum(); }

        synchronized void onGc(GarbageCollectionNotificationInfo info) {
            // GcInfo covers every memory pool; only the Java heap counts here (Metaspace holds the card classes).
            long before=0,after=0;
            for(Map.Entry<String,MemoryUsage> e:info.getGcInfo().getMemoryUsageBeforeGc().entrySet()) if(HEAP_POOLS.contains(e.getKey())) before+=e.getValue().getUsed();
            for(Map.Entry<String,MemoryUsage> e:info.getGcInfo().getMemoryUsageAfterGc().entrySet()) if(HEAP_POOLS.contains(e.getKey())) after+=e.getValue().getUsed();
            boolean full=info.getGcAction().contains("major");
            gcCount++;gcNanos+=info.getGcInfo().getDuration()*1_000_000L;
            if(full) fullGcCount++;
            maxBeforeGc=Math.max(maxBeforeGc,before);maxAfterGc=Math.max(maxAfterGc,after);
            if(full) maxAfterFull=Math.max(maxAfterFull,after);
            gcs.printf(Locale.ROOT,"%.2f,%d,%s,%s,%s,%d,%.1f,%.1f%n",now()/1e9,turn(),info.getGcName(),info.getGcAction(),
                info.getGcCause(),info.getGcInfo().getDuration(),mb(before),mb(after));
        }

        /** GAME thread, first priority of each turn: the live game's copy cost and board size. */
        void probe() {
            int turn=game.getTurnNum();
            if(turn<=lastProbedTurn || stopped) return;
            lastProbedTurn=turn;
            try {
                int hand=0,library=0,graveyard=0;
                for(Player p:game.getState().getPlayers().values()) {
                    hand+=p.getHand().size();library+=p.getLibrary().size();graveyard+=p.getGraveyard().size();
                }
                int permanents=game.getBattlefield().getAllPermanents().size();
                int cards=game.getCards().size();
                int exile=game.getExile().getAllCards(game).size();
                int triggers=game.getState().getTriggers().size();
                long[] wall=new long[3],cpu=new long[3],alloc=new long[3];
                Game copy=null;
                for(int i=0;i<3;i++) {
                    long a0=THREADS.getCurrentThreadAllocatedBytes(),c0=THREADS.getCurrentThreadCpuTime(),w0=System.nanoTime();
                    copy=game.copy();
                    wall[i]=System.nanoTime()-w0;cpu[i]=THREADS.getCurrentThreadCpuTime()-c0;alloc[i]=THREADS.getCurrentThreadAllocatedBytes()-a0;
                }
                Reference.reachabilityFence(copy);
                probeCopies+=3;
                Arrays.sort(wall);Arrays.sort(cpu);Arrays.sort(alloc);
                String retained="";
                if(memory) {
                    Game[] held=new Game[8];
                    System.gc();System.gc();long u0=usedHeap();
                    for(int i=0;i<held.length;i++) held[i]=game.copy();
                    System.gc();System.gc();long u1=usedHeap();
                    Reference.reachabilityFence(held);
                    probeCopies+=held.length;
                    retained=String.valueOf((u1-u0)/held.length/1024);
                }
                synchronized(this) {
                    turns.printf(Locale.ROOT,"%d,%.2f,%d,%d,%d,%d,%d,%d,%d,%.2f,%.2f,%d,%s,%.1f%n",turn,now()/1e9,permanents,cards,hand,
                        library,graveyard,exile,triggers,wall[1]/1e6,cpu[1]/1e6,alloc[1]/1024,retained,mb(usedHeap()));
                    turns.flush();
                }
            } catch(RuntimeException e) {
                System.err.println("probe failed at turn "+turn+": "+e);
            }
        }

        // ---- Sampler thread ----------------------------------------------------------------
        long[] simIds=new long[0];
        void refreshSimThreads() {
            List<Long> ids=new ArrayList<>();
            for(ThreadInfo info:THREADS.getThreadInfo(THREADS.getAllThreadIds()))
                if(info!=null && info.getThreadName().startsWith("AI-SIM-MAD")) ids.add(info.getThreadId());
            simIds=ids.stream().mapToLong(Long::longValue).toArray();
        }
        Map<Long,long[]> simCounters() {
            Map<Long,long[]> values=new HashMap<>();
            long[] alloc=THREADS.getThreadAllocatedBytes(simIds),cpu=THREADS.getThreadCpuTime(simIds);
            for(int i=0;i<simIds.length;i++) values.put(simIds[i],new long[]{Math.max(0,cpu[i]),Math.max(0,alloc[i])});
            return values;
        }
        static long[] delta(Map<Long,long[]> start,Map<Long,long[]> end) {
            long cpu=0,alloc=0;
            for(Map.Entry<Long,long[]> e:end.entrySet()) {
                long[] s=start.getOrDefault(e.getKey(),new long[2]);
                cpu+=e.getValue()[0]-s[0];alloc+=e.getValue()[1]-s[1];
            }
            return new long[]{cpu,alloc};
        }
        int nodes() { try { return nodeCount.getInt(null); } catch(IllegalAccessException e) { return -1; } }

        // One search in progress (sampler thread only).
        boolean inSearch;long sStart,sFullAt,sCopies,sGameCpu,sGameAlloc,sProcessCpu,sHeapMax;int sTurn,sStack,sQuickNodes,sNodes;
        String sStep,sSeat;Map<Long,long[]> sSim;boolean sFull;

        void sample() {
            long nextTimeline=0,nextThreads=0,nextGc=gcEveryNs;
            long gameId=gameThread.getId();
            while(!stopped) {
                long t=now();
                if(t>=nextThreads) { refreshSimThreads();nextThreads=t+1_000_000_000L; }
                StackTraceElement[] stack=gameThread.getStackTrace();
                boolean searching=false,full=false;
                for(StackTraceElement f:stack)
                    if(f.getClassName().equals(AI_CLASS)) {
                        if(f.getMethodName().equals("calculateActions")) searching=true;
                        // expertSearch calls the quick search first, the full one below it (MobileAICancellation).
                        if(f.getMethodName().equals("expertSearch") && f.getLineNumber()>=245) full=true;
                    }
                long heap=usedHeap();
                if(searching && !inSearch) {
                    refreshSimThreads();
                    inSearch=true;sStart=t;sFullAt=-1;sCopies=GameImpl.COPIED_COUNT.get();
                    sGameCpu=THREADS.getThreadCpuTime(gameId);sGameAlloc=THREADS.getThreadAllocatedBytes(gameId);
                    sProcessCpu=OS.getProcessCpuTime();sSim=simCounters();sHeapMax=heap;
                    sTurn=game.getTurnNum();sStep=String.valueOf(game.getTurnStepType());
                    sSeat=seats.getOrDefault(game.getPriorityPlayerId(),"?");
                    sStack=game.getStack().size();sQuickNodes=0;sNodes=0;sFull=false;
                }
                if(inSearch && searching) {
                    int n=nodes();
                    if(full && !sFull) { sFull=true;sFullAt=t; }
                    if(!sFull) sQuickNodes=Math.max(sQuickNodes,n); else sNodes=n;
                    sHeapMax=Math.max(sHeapMax,heap);
                }
                if(inSearch && !searching) {
                    inSearch=false;
                    refreshSimThreads(); // the pool starts a new thread per task until it is full
                    long[] sim=delta(sSim,simCounters());
                    long wall=t-sStart;
                    boolean expert=sFull || sFullAt>=0;
                    int nodes=expert?sNodes:sQuickNodes; // without an expert phase, the only search counts as the full one
                    synchronized(this) {
                        searchWallMs.add(wall/1_000_000);
                        searches.printf(Locale.ROOT,"%.2f,%d,%s,%s,%d,%d,%.0f,%s,%s,%d,%d,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%s%n",
                            sStart/1e9,sTurn,sStep,sSeat,skills.getOrDefault(sSeat,0),sStack,wall/1e6,
                            sFullAt>=0?String.format(Locale.ROOT,"%.0f",(sFullAt-sStart)/1e6):"",expert?String.valueOf(sQuickNodes):"",
                            nodes,GameImpl.COPIED_COUNT.get()-sCopies,
                            (THREADS.getThreadCpuTime(gameId)-sGameCpu)/1e6,sim[0]/1e6,(OS.getProcessCpuTime()-sProcessCpu)/1e6,
                            mb(THREADS.getThreadAllocatedBytes(gameId)-sGameAlloc),mb(sim[1]),mb(sHeapMax),expert?"1":"0");
                        searches.flush();
                    }
                }
                if(t>=nextTimeline) {
                    MemoryUsage heapUsage=ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
                    synchronized(this) {
                        timeline.printf(Locale.ROOT,"%.2f,%d,%.1f,%.1f,%d,%d,%.2f,%d,%d,%d%n",t/1e9,turn(),mb(heapUsage.getUsed()),
                            mb(heapUsage.getCommitted()),GameImpl.COPIED_COUNT.get()-startCopies,nodes(),
                            (OS.getProcessCpuTime()-startCpu)/1e9,gcCount,gcNanos/1_000_000,inSearch?1:0);
                    }
                    nextTimeline=t+250_000_000L;
                }
                if(memory && t>=nextGc) { forcedGc();nextGc=now()+gcEveryNs; }
                LockSupport.parkNanos(10_000_000L);
            }
        }

        /** Memory mode: the live heap now; histogram and heap dump at new peaks. */
        void forcedGc() {
            long g0=System.nanoTime();
            System.gc();
            long live=usedHeap();
            forcedGcNanos+=System.nanoTime()-g0;
            synchronized(this) {
                timeline.printf(Locale.ROOT,"%.2f,%d,%.1f,,,,,,,live%n",now()/1e9,turn(),mb(live));
                maxLive=Math.max(maxLive,live);
            }
            try {
                // A typical game's search state is tens of MB over the pre-game baseline, so peaks are small steps.
                if(live>lastHistogram+Math.max(8L<<20,lastHistogram/25) && live>baseline+(16L<<20)) {
                    lastHistogram=live;
                    Files.writeString(out.resolve(String.format(Locale.ROOT,"hist-t%03d-%04dmb.txt",turn(),live>>20)),histogram());
                }
                if(live>=baseline+dumpOver && live>lastDump*11/10) {
                    lastDump=live;dumpTurn=turn();
                    Path tmp=out.resolve("heap-new.hprof"),target=out.resolve("heap-peak.hprof");
                    Files.deleteIfExists(tmp);
                    ManagementFactory.getPlatformMXBean(HotSpotDiagnosticMXBean.class).dumpHeap(tmp.toString(),true);
                    Files.move(tmp,target,StandardCopyOption.REPLACE_EXISTING);
                }
            } catch(Exception e) { System.err.println("heap report failed: "+e); }
        }

        void stop() throws InterruptedException { stopped=true;if(sampler!=null) sampler.join(5000); }

        synchronized void finish(Map<String,Object> result) {
            result.put("copies",GameImpl.COPIED_COUNT.get()-startCopies-probeCopies);
            result.put("probe_copies",probeCopies);
            result.put("process_cpu_s",Math.round((OS.getProcessCpuTime()-startCpu)/1e7)/100.0);
            result.put("gc_count",gcCount);result.put("full_gc_count",fullGcCount);result.put("gc_ms",gcNanos/1_000_000);
            result.put("forced_gc_ms",forcedGcNanos/1_000_000);
            result.put("max_heap_before_gc_mb",mb(maxBeforeGc));result.put("max_heap_after_gc_mb",mb(maxAfterGc));
            result.put("max_heap_after_full_gc_mb",mb(maxAfterFull));
            if(memory) { result.put("max_live_mb",mb(maxLive));result.put("dump_live_mb",mb(lastDump));result.put("dump_turn",dumpTurn); }
            result.put("searches",searchWallMs.size());
            for(PrintWriter w:List.of(searches,turns,timeline,gcs)) w.close();
        }
    }
}
