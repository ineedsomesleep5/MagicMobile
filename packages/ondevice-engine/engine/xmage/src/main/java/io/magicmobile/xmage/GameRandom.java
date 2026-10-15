package io.magicmobile.xmage;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.List;
import java.util.Random;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

/**
 * XMage's process-wide generator (RandomUtil) for one match, installed by the adapter. Only the rules
 * code on the match's GAME thread draws from the seeded stream: shuffles, coin flips, "at random"
 * effects and the opening player. AI reasoning (search threads, and AI choice code on the GAME thread)
 * and views for the app draw from an unseeded source instead, so a replay that feeds the AI's recorded choices back draws
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
        if(Thread.currentThread()==owner && (r==null || r.drawsSeeded())) return super.next(bits);
        return ThreadLocalRandom.current().nextInt()>>>(32-bits);
    }

    /**
     * A random order from XMage's generator. Upstream's "in a random order" library placement uses
     * Collections.shuffle's own generator, which no seed reaches; both seat classes use this instead.
     */
    static List<UUID> randomOrder(Collection<UUID> ids) {
        List<UUID> order=new ArrayList<>(ids);
        Collections.shuffle(order,mage.util.RandomUtil.getRandom());
        return order;
    }
}
