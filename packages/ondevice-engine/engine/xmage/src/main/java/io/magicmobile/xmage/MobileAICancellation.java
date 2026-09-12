package io.magicmobile.xmage;

import mage.constants.RangeOfInfluence;
import mage.player.ai.ComputerPlayerControllableProxy;
import mage.player.ai.SimulationNode2;
import java.util.concurrent.CancellationException;
import java.util.concurrent.TimeUnit;

/** Shared by one match and its copies. Owns lifecycle only; all AI decisions remain upstream. */
final class MobileAICancellation {
    private volatile boolean closing;
    private int simulations;

    boolean isClosing() { return closing; }
    synchronized void close() { closing=true; }
    synchronized void runIfOpen(Runnable action) { if(!closing) action.run(); }
    private synchronized void enterSimulation() {
        // A queued upstream FutureTask can enter after its GAME thread was cancelled.
        // Reject before touching any game state, including shared upstream search counters.
        if(closing) throw new CancellationException("Mobile AI match stopped");
        simulations++;
    }
    private synchronized void leaveSimulation() { simulations--;notifyAll(); }
    synchronized boolean awaitQuiescence(long deadline) throws InterruptedException {
        while(simulations!=0) {
            long remaining=deadline-System.nanoTime();
            if(remaining<=0) return false;
            TimeUnit.NANOSECONDS.timedWait(this,remaining);
        }
        return true;
    }
    ComputerPlayerControllableProxy player(String name) { return new CancellablePlayer(name,this); }

    private static final class CancellablePlayer extends ComputerPlayerControllableProxy {
        private final transient MobileAICancellation cancellation;
        CancellablePlayer(String name,MobileAICancellation cancellation) {
            super(name,RangeOfInfluence.ALL,1);this.cancellation=cancellation;
        }
        private CancellablePlayer(CancellablePlayer source) {
            super(source);cancellation=source.cancellation;
            // Keep the configured upstream budgets when XMage copies this live adapter.
            maxNodes=source.maxNodes;maxThinkTimeSecs=source.maxThinkTimeSecs;
        }
        @Override public CancellablePlayer copy() { return new CancellablePlayer(this); }
        @Override protected int addActions(SimulationNode2 node,int depth,int alpha,int beta) {
            cancellation.enterSimulation();
            try { return super.addActions(node,depth,alpha,beta); }
            finally { cancellation.leaveSimulation(); }
        }
    }
}
