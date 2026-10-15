package io.magicmobile.xmage;

/**
 * How hard one AI seat plays: upstream search depth and a chance of a deliberate mistake.
 * The defaults by skill live here, in one place, so calibration can change them; a seat may
 * override each value (PROTOCOL.md, AI seats). Rules and information access never change.
 */
final class AIDifficulty {
    /** Upstream depth for skills 3 and up: unchanged from XMage, max(4, skill). */
    static final int UPSTREAM_MIN_DEPTH=4;
    final int searchDepth;
    final int mistakePercent;
    final long seed;
    /**
     * Diamond and up: attacks and blocks from CombatPlanner instead of upstream's fixed rules, and a quick
     * search before each full one so a search that runs out of time still leaves a move.
     */
    final boolean expert;

    AIDifficulty(int searchDepth,int mistakePercent,long seed) { this(searchDepth,mistakePercent,seed,false); }
    AIDifficulty(int searchDepth,int mistakePercent,long seed,boolean expert) {
        if(searchDepth<1 || searchDepth>10) throw new IllegalArgumentException("AI search depth must be 1–10");
        if(mistakePercent<0 || mistakePercent>100) throw new IllegalArgumentException("AI mistake chance must be 0–100%");
        this.searchDepth=searchDepth;this.mistakePercent=mistakePercent;this.seed=seed;this.expert=expert;
    }
    static AIDifficulty forSkill(int skill,long seed) {
        return new AIDifficulty(searchDepth(skill),mistakePercent(skill),seed,expert(skill));
    }

    /**
     * Upstream depth counts one unit per action, and the last unit scores the game before that
     * action resolves: at depth 1 a spell is judged while still on the stack, so the AI never casts
     * one. N plies (actions the AI sees resolve) are therefore depth N+1. Skill 1 looks one action
     * ahead (greedy), skill 2 two; skill 3 and up keep XMage's max(4, skill).
     */
    static int searchDepth(int skill) {
        checkSkill(skill);
        return skill<=2?skill+1:Math.max(UPSTREAM_MIN_DEPTH,skill);
    }
    /** Chance of a deliberate suboptimal choice at each decision it applies to (Bronze to Gold). Tuned by C3
     *  (docs/cloud/reports/c3.md): Bronze and Silver 15% (their step is depth 2 against 3), Gold 10%. */
    static int mistakePercent(int skill) {
        checkSkill(skill);
        return switch(skill) { case 1,2->15; case 3->10; default->0; };
    }
    /** Skill 5 (Diamond) and up play as an expert (see the expert field). */
    static boolean expert(int skill) {
        checkSkill(skill);
        return skill>=5;
    }
    private static void checkSkill(int skill) { if(skill<1 || skill>10) throw new IllegalArgumentException("AI skill must be 1–10"); }

    /** SplitMix64: a small, serializable generator whose whole state is one long. */
    static long next(long state) { return state+0x9E3779B97F4A7C15L; }
    static long mix(long state) {
        long z=state;
        z=(z^(z>>>30))*0xBF58476D1CE4E5B9L;
        z=(z^(z>>>27))*0x94D049BB133111EBL;
        return z^(z>>>31);
    }
    /** True with the given chance for this generator state (0–99 uniform roll below the percent). */
    static boolean rolls(long state,int percent) {
        return percent>0 && Long.remainderUnsigned(mix(state),100)<percent;
    }
}
