package io.magicmobile.xmage;

import io.magicmobile.core.EngineDiagnostics;
import mage.constants.PhaseStep;
import mage.game.Game;
import mage.player.ai.ComputerPlayerControllableProxy;
import mage.player.ai.SimulationNode2;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.Arrays;
import java.util.UUID;
import java.util.concurrent.CancellationException;

/** Focused JVM adapter test; no game, card repository, native build or AI worker pool required. */
public final class RealAIDiagnosticsTests {
    public static void main(String[] args) throws Exception {
        int initialNodes=SimulationNode2.getCount();
        try {
            unexpectedFailure(false);
            unexpectedFailure(true);
            excludedFailures();
            searchBudgets();
            System.out.println("PASS real AI adapter diagnostics, exact rethrow, bounds and lifecycle cleanup");
        } finally {
            EngineDiagnostics.clear();
            // Construction increments the upstream counter even for our controlled node.
            var count=SimulationNode2.class.getDeclaredField("nodeCount");
            count.setAccessible(true);count.setInt(null,initialNodes);
        }
    }
    private static void unexpectedFailure(boolean copied) throws Exception {
        EngineDiagnostics.clear();
        MobileAICancellation cancellation=new MobileAICancellation();
        ComputerPlayerControllableProxy player=cancellation.player("diagnostic-test");
        if(copied)player=player.copy();
        UnsatisfiedLinkError failure=new UnsatisfiedLinkError("controlled-native-symbol "+"x".repeat(2048));
        StackTraceElement[] frames=new StackTraceElement[64];
        Arrays.fill(frames,new StackTraceElement("ControlledNativeFixture","lookup","x".repeat(1024),1));
        failure.setStackTrace(frames);
        invokeFailure(player,node(cancellation,failure,false),failure);
        String report=report();
        check(report!=null && report.contains("ai-simulation")
            && report.contains("java.lang.UnsatisfiedLinkError: controlled-native-symbol"),"adapter captures native failure");
        check(report.length()<=EngineDiagnostics.MAX_CHARS,"private report remains bounded");
        check(report.contains("ControlledNativeFixture.lookup"),"failure frames retained");
        check(cancellation.awaitQuiescence(System.nanoTime()),"failed simulation released");
        var simulations=MobileAICancellation.class.getDeclaredField("simulations");
        simulations.setAccessible(true);
        check(simulations.getInt(cancellation)==0,"simulation count restored exactly");
    }
    private static void excludedFailures() throws Exception {
        // Seed through the production adapter, never by calling capture directly.
        unexpectedFailure(false);
        String original=report();
        MobileAICancellation cancellation=new MobileAICancellation();
        ComputerPlayerControllableProxy player=cancellation.player("diagnostic-test");
        CancellationException cancelled=new CancellationException("controlled cancellation");
        invokeFailure(player,node(cancellation,cancelled,false),cancelled);
        check(original.equals(report()),"open-match cancellation preserves prior report");
        check(cancellation.awaitQuiescence(System.nanoTime()),"cancelled simulation released");
        IllegalStateException closing=new IllegalStateException("controlled closing failure");
        invokeFailure(player,node(cancellation,closing,true),closing);
        check(original.equals(report()),"closing failure preserves prior report");
        check(cancellation.awaitQuiescence(System.nanoTime()),"closing simulation released");
        // No node may be touched when a queued simulation enters after close.
        try {
            invoke(player,null);
            throw new AssertionError("closed simulation must be rejected");
        } catch(InvocationTargetException failure) {
            check(failure.getCause() instanceof CancellationException,"queued simulation rejected before upstream work");
        }
        check(cancellation.awaitQuiescence(System.nanoTime()),"rejected simulation did not change lifecycle count");
        check(original.equals(report()),"queued cancellation preserves prior report");
    }
    private static void searchBudgets() {
        check(MobileAICancellation.thinkBudget(6,true)==6,"empty stack keeps the configured think time");
        check(MobileAICancellation.thinkBudget(6,false)==MobileAICancellation.STACK_THINK_SECS,"stack responses are capped");
        check(MobileAICancellation.thinkBudget(1,false)==1,"cap never raises a lower configured budget");
        for(PhaseStep step:PhaseStep.values()) {
            boolean upstreamSearches=step==PhaseStep.PRECOMBAT_MAIN || step==PhaseStep.DECLARE_ATTACKERS
                || step==PhaseStep.DECLARE_BLOCKERS || step==PhaseStep.POSTCOMBAT_MAIN;
            check(MobileAICancellation.searchesAt(step)==upstreamSearches,"fast pass only replaces search steps: "+step);
        }
    }
    private static SimulationNode2 node(MobileAICancellation cancellation,Throwable failure,boolean close) {
        Game game=(Game)Proxy.newProxyInstance(Game.class.getClassLoader(),new Class<?>[]{Game.class},
            (proxy,method,args)->{
                if(method.getName().equals("setCustomData"))return null;
                throw new AssertionError("Unexpected fixture game access: "+method.getName());
            });
        return new SimulationNode2(null,game,1,UUID.randomUUID()) {
            @Override public Game getGame() {
                try {
                    check(!cancellation.awaitQuiescence(System.nanoTime()),"simulation counted before upstream access");
                } catch(InterruptedException interrupted) {throw new AssertionError(interrupted);}
                if(close)cancellation.close();
                if(failure instanceof Error)throw (Error)failure;
                throw (RuntimeException)failure;
            }
        };
    }
    private static void invokeFailure(ComputerPlayerControllableProxy player,SimulationNode2 node,Throwable expected)throws Exception {
        try {
            invoke(player,node);
            throw new AssertionError("Expected injected failure");
        } catch(InvocationTargetException failure) {
            check(failure.getCause()==expected,"adapter rethrows exact original throwable");
        }
    }
    private static void invoke(ComputerPlayerControllableProxy player,SimulationNode2 node)throws Exception {
        Method method=player.getClass().getDeclaredMethod("addActions",SimulationNode2.class,int.class,int.class,int.class);
        method.setAccessible(true);method.invoke(player,node,1,Integer.MIN_VALUE,Integer.MAX_VALUE);
    }
    private static String report() {return (String)EngineDiagnostics.read().get("report");}
    private static void check(boolean value,String message) {if(!value)throw new AssertionError(message);}
}
