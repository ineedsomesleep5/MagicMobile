package io.magicmobile.xmage;

import java.util.Random;
import java.util.concurrent.ThreadLocalRandom;

/**
 * XMage's process-wide generator (RandomUtil) for one match, installed by the adapter. Only the rules
 * code on the match's GAME thread draws from the seeded stream: shuffles, coin flips, "at random"
 * effects and the opening player. AI reasoning (search threads, and AI choice code on the GAME thread)
 * draws from an unseeded source instead, so a replay that feeds the AI's recorded choices back draws
 * exactly the same seeded values (docs/cloud/game-record.md).
 *
 * The seeded stream is java.util.Random's own generator, so its state is saved with a checkpoint.
 */
final class GameRandom extends Random {
    private static final long serialVersionUID=1L;
    // Rebound after a restore; never part of the saved stream.
    private transient volatile Thread owner;
    private transient volatile GameRecorder recorder;

    GameRandom(long seed) { super(seed); }

    /** The thread whose rules code draws the seeded stream (the creating thread during setup, then GAME). */
    void bind(Thread thread,GameRecorder recorder) { this.recorder=recorder;owner=thread; }

    @Override protected int next(int bits) {
        GameRecorder r=recorder;
        if(Thread.currentThread()==owner && (r==null || !r.inAI())) return super.next(bits);
        return ThreadLocalRandom.current().nextInt()>>>(32-bits);
    }
}
