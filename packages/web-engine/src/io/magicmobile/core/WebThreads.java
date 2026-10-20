package io.magicmobile.core;

import java.util.*;
import java.util.concurrent.*;

/**
 * WEB BUILD ONLY (packages/web-engine; phone builds never compile this file). GraalVM Web Image runs one thread:
 * Thread.start runs nothing and timed waits return at once. web_sources.py rewrites the engine's thread
 * boundaries to these:
 * - the GAME "thread" is a task deferred until the current request has been answered, then run on the
 *   worker's own thread (WebHost runs it);
 * - the mailbox delivers an answer on the caller's thread, inside the respond request;
 * - a human question waits in the host's blocking read (Atomics.wait in the browser), serving the page's
 *   requests until an answer for it is queued.
 */
public final class WebThreads {
    private WebThreads() {}

    /** The page's channel. WebHost installs it before the first request. */
    public interface Host {
        /** Serves at most one of the page's requests; with block, waits for one (up to about 250 ms). */
        void serveOne(boolean block);
    }
    private static Host host;
    public static void install(Host channel) { host=Objects.requireNonNull(channel); }

    private static final ArrayDeque<Runnable> deferred=new ArrayDeque<>();
    private static int running;

    /** True while a deferred task (a game) is on the stack. */
    public static boolean busy() { return running>0; }

    /** Runs deferred tasks, oldest first, until none is left. Called by WebHost between requests. */
    public static void runDeferred() {
        for(Runnable task=deferred.poll();task!=null;task=deferred.poll()) {
            running++;
            try { task.run(); }
            finally { running--; }
        }
    }

    /**
     * Replaces MobileHumanPlayer's 250 ms poll: an answer already queued, else serve the page (blocking) and look
     * again. The answer arrives through a respond request, delivered inline by the mailbox.
     */
    public static <T> T awaitAnswer(BlockingQueue<T> answers) throws InterruptedException {
        T answer=answers.poll();
        if(answer!=null) return answer;
        if(host==null) throw new IllegalStateException("Web engine host is not installed");
        host.serveOne(true);
        return answers.poll();
    }

    /** At a published snapshot during a game: answer one waiting request (a poll, usually) without blocking. */
    public static void servePending() { if(host!=null) host.serveOne(false); }

    /** The mailbox's CALL executor: runs each task at once on the caller's thread. */
    public static ExecutorService inline() { return new Single(false); }
    /** A match's GAME executor: runs its task after the current request, on the worker's thread. */
    public static ExecutorService deferred() { return new Single(true); }

    private static final class Single extends AbstractExecutorService {
        private final boolean defer;
        private boolean shutdown;
        private int active;
        private final List<Runnable> queued=new ArrayList<>();
        Single(boolean defer) { this.defer=defer; }
        @Override public void execute(Runnable command) {
            Objects.requireNonNull(command);
            if(shutdown) throw new RejectedExecutionException("Executor is shut down");
            Runnable task=() -> {
                if(!queued.remove(command)) return; // dropped by shutdownNow
                active++;
                try { command.run(); } finally { active--; }
            };
            queued.add(command);
            if(defer) deferred.add(task); else task.run();
        }
        @Override public void shutdown() { shutdown=true; }
        @Override public List<Runnable> shutdownNow() {
            shutdown=true;
            List<Runnable> never=new ArrayList<>(queued);
            queued.clear();
            return never;
        }
        @Override public boolean isShutdown() { return shutdown; }
        @Override public boolean isTerminated() { return shutdown && active==0 && queued.isEmpty(); }
        /** Never waits: one thread cannot wait for itself. A running task ends only once control returns to it. */
        @Override public boolean awaitTermination(long timeout,TimeUnit unit) { return isTerminated(); }
    }
}
