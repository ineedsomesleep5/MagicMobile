package io.magicmobile.xmage;

import mage.abilities.keyword.DeathtouchAbility;
import mage.abilities.keyword.DefenderAbility;
import mage.abilities.keyword.DoubleStrikeAbility;
import mage.abilities.keyword.FirstStrikeAbility;
import mage.abilities.keyword.IndestructibleAbility;
import mage.abilities.keyword.InfectAbility;
import mage.abilities.keyword.LifelinkAbility;
import mage.abilities.keyword.MenaceAbility;
import mage.abilities.keyword.TrampleAbility;
import mage.abilities.keyword.VigilanceAbility;
import mage.abilities.Abilities;
import mage.abilities.Ability;
import mage.filter.StaticFilters;
import mage.game.Game;
import mage.game.combat.CombatGroup;
import mage.game.permanent.Permanent;
import mage.player.ai.score.ArtificialScoringSystem;
import mage.player.ai.score.GameStateEvaluator2;
import mage.players.Player;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * Attack and block choices for the strongest AI tiers (AIDifficulty.expert). Upstream XMage
 * declares attackers by a fixed rule (attack only with creatures no single blocker can kill) and
 * never asks whether its blocks leave it dead. This planner predicts the defender's blocks and the
 * crack-back on the next turn with plain combat arithmetic on the real permanents, then picks the
 * attack that scores best with upstream's own life and permanent values. It reads the game and
 * declares through the same player calls as upstream; it never changes rules or sees hidden cards.
 */
final class CombatPlanner {
    /** Weight of the opponent's lost life against upstream's life score, in percent (above 100 races harder). */
    static final int AGGRESSION_PERCENT=100;
    /** Weight of the predicted crack-back damage, in percent (below 100 trusts the opponent not to swing back). */
    static final int CRACK_BACK_PERCENT=100;
    /** Every subset is scored up to this many attackers; larger boards hill-climb from three starts. */
    static final int EXHAUSTIVE_ATTACKERS=10;
    private static final int LETHAL_FOR_US=-10_000_000;

    private CombatPlanner() {}

    /** A creature as combat sees it: its stats, keywords and upstream's value for it. */
    static final class Unit {
        final UUID id;final Permanent permanent;
        final int power,toughness,value;
        final boolean firstStrike,doubleStrike,deathtouch,indestructible,lifelink,trample,vigilance,menace;
        Unit(Permanent p,Game game) {
            id=p.getId();permanent=p;
            Abilities<Ability> a=p.getAbilities(game);
            power=Math.max(0,p.getPower().getValue());
            toughness=p.getToughness().getValue()-p.getDamage();
            value=GameStateEvaluator2.evaluatePermanent(p,game,false);
            firstStrike=a.containsKey(FirstStrikeAbility.getInstance().getId());
            doubleStrike=a.containsKey(DoubleStrikeAbility.getInstance().getId());
            deathtouch=a.containsKey(DeathtouchAbility.getInstance().getId());
            indestructible=a.containsKey(IndestructibleAbility.getInstance().getId());
            lifelink=a.containsKey(LifelinkAbility.getInstance().getId());
            trample=a.containsKey(TrampleAbility.getInstance().getId());
            vigilance=a.containsKey(VigilanceAbility.getInstance().getId());
            menace=a.containsClass(MenaceAbility.class);
        }
        Unit(String name,int power,int toughness,int value,String keywords) {
            id=UUID.nameUUIDFromBytes(name.getBytes());permanent=null;
            this.power=power;this.toughness=toughness;this.value=value;
            firstStrike=keywords.contains("first");doubleStrike=keywords.contains("double");
            deathtouch=keywords.contains("deathtouch");indestructible=keywords.contains("indestructible");
            lifelink=keywords.contains("lifelink");trample=keywords.contains("trample");
            vigilance=keywords.contains("vigilance");menace=keywords.contains("menace");
        }
        int hits() { return doubleStrike?2:1; }
        @Override public String toString() { return power+"/"+toughness; }
    }

    /** One blocked fight: who dies, damage that tramples over, and life each side gains. */
    record Fight(boolean attackerDies,boolean blockerDies,int trampleOver,int attackerGain,int blockerGain) {}

    /** One attacker against one blocker, first strike and double strike in two damage steps. */
    static Fight fight(Unit a,Unit b) {
        boolean aEarly=a.firstStrike || a.doubleStrike,bEarly=b.firstStrike || b.doubleStrike;
        int toA=0,toB=0,over=0;boolean aHitByTouch=false,bHitByTouch=false,aDead=false,bDead=false;
        for(int step=0;step<2;step++) {
            boolean first=step==0;
            boolean aHits=!aDead && (first?aEarly:(!aEarly || a.doubleStrike));
            boolean bHits=!bDead && (first?bEarly:(!bEarly || b.doubleStrike));
            if(aHits && a.power>0) {
                if(bDead) { if(a.trample) over+=a.power; }
                else {
                    int lethal=a.deathtouch?1:Math.max(0,b.toughness-toB);
                    int assigned=a.trample?Math.min(a.power,lethal):a.power;
                    toB+=assigned;over+=a.power-assigned;bHitByTouch|=a.deathtouch;
                }
            }
            if(bHits && b.power>0) { toA+=b.power;aHitByTouch|=b.deathtouch; }
            aDead=dies(a,toA,aHitByTouch);bDead=dies(b,toB,bHitByTouch);
        }
        int aDealt=toB+over,bDealt=toA;
        return new Fight(aDead,bDead,over,a.lifelink?aDealt:0,b.lifelink?bDealt:0);
    }
    private static boolean dies(Unit u,int damage,boolean deathtouched) {
        return !u.indestructible && damage>0 && (damage>=u.toughness || deathtouched);
    }

    /** What one declared attack does, under the blocks the defender is predicted to make. */
    static final class Outcome {
        int damage,attackerGain,defenderGain;
        final Set<UUID> attackersDead=new HashSet<>(),blockersDead=new HashSet<>(),blockersUsed=new HashSet<>();
    }

    /**
     * The defender's blocks, modelled on upstream's blockWithGoodTrade2 plus a lethal check: each
     * attacker (strongest first) is blocked by the cheapest blocker that kills it and lives, else one that
     * lives, else an even or better trade; then, if the rest would still be lethal, chump blocks.
     */
    static Outcome predict(List<Unit> attackers,List<Unit> blockers,boolean[][] canBlock,int defenderLife) {
        Outcome out=new Outcome();
        Integer[] order=byThreat(attackers);
        boolean[] blocked=new boolean[attackers.size()];
        for(int i:order) {
            Unit a=attackers.get(i);
            if(a.menace) continue; // needs two blockers; the chump pass below may still find them
            int best=-1,bestRank=Integer.MAX_VALUE;
            for(int j=0;j<blockers.size();j++) {
                Unit b=blockers.get(j);
                if(!canBlock[i][j] || out.blockersUsed.contains(b.id)) continue;
                Fight f=fight(a,b);
                int rank;
                if(!f.blockerDies() && f.attackerDies()) rank=0;
                else if(!f.blockerDies()) rank=1;
                else if(f.attackerDies() && b.value<=a.value) rank=2;
                else continue;
                rank=rank*1_000_000+b.value;
                if(rank<bestRank) { bestRank=rank;best=j; }
            }
            if(best>=0) { block(out,a,blockers.get(best));blocked[i]=true; }
        }
        // Unblocked damage; chump the biggest attackers while it would be lethal.
        for(int i:order) {
            if(blocked[i]) continue;
            Unit a=attackers.get(i);
            if(unblockedDamage(attackers,blocked)+out.damage<defenderLife+out.defenderGain) break;
            int need=a.menace?2:1;List<Unit> chumps=new ArrayList<>();
            for(int j=0;j<blockers.size() && chumps.size()<need;j++)
                if(canBlock[i][j] && !out.blockersUsed.contains(blockers.get(j).id)) chumps.add(blockers.get(j));
            if(chumps.size()<need) continue;
            chumps.sort(Comparator.comparingInt(u->u.value));
            if(need==1) block(out,a,chumps.get(0));
            else {
                // Two blockers share the attacker's damage; count the cheaper one as dying.
                out.blockersUsed.add(chumps.get(0).id);out.blockersUsed.add(chumps.get(1).id);
                if(a.power>0) out.blockersDead.add(chumps.get(0).id);
                if(chumps.get(0).power+chumps.get(1).power>=a.toughness && !a.indestructible) out.attackersDead.add(a.id);
            }
            blocked[i]=true;
        }
        for(int i=0;i<attackers.size();i++) if(!blocked[i]) {
            Unit a=attackers.get(i);
            int dealt=a.power*a.hits();
            out.damage+=dealt;if(a.lifelink) out.attackerGain+=dealt;
        }
        return out;
    }
    private static void block(Outcome out,Unit a,Unit b) {
        Fight f=fight(a,b);
        out.blockersUsed.add(b.id);
        if(f.attackerDies()) out.attackersDead.add(a.id);
        if(f.blockerDies()) out.blockersDead.add(b.id);
        out.damage+=f.trampleOver();out.attackerGain+=f.attackerGain();out.defenderGain+=f.blockerGain();
    }
    private static int unblockedDamage(List<Unit> attackers,boolean[] blocked) {
        int sum=0;
        for(int i=0;i<attackers.size();i++) if(!blocked[i]) sum+=attackers.get(i).power*attackers.get(i).hits();
        return sum;
    }
    private static Integer[] byThreat(List<Unit> units) {
        Integer[] order=new Integer[units.size()];
        for(int i=0;i<order.length;i++) order[i]=i;
        java.util.Arrays.sort(order,Comparator.<Integer>comparingInt(i->-units.get(i).power*units.get(i).hits())
            .thenComparingInt(i->-units.get(i).value));
        return order;
    }

    /**
     * Damage the opponent's whole team deals back on its next turn, when every creature that can block
     * (ours that stayed home, or attacked with vigilance and lived) blocks the biggest attacker it can.
     */
    static int crackBack(List<Unit> theirs,List<Unit> ourBlockers,boolean[][] canBlock) {
        Integer[] order=byThreat(theirs);
        boolean[] used=new boolean[ourBlockers.size()];
        int damage=0;
        for(int i:order) {
            Unit a=theirs.get(i);
            int need=a.menace?2:1,found=0;
            for(int j=0;j<ourBlockers.size() && found<need;j++) if(!used[j] && canBlock[i][j]) found++;
            if(found<need) { damage+=a.power*a.hits();continue; }
            for(int j=0,taken=0;j<ourBlockers.size() && taken<need;j++)
                if(!used[j] && canBlock[i][j]) { used[j]=true;taken++; }
            if(a.trample && need==1) damage+=Math.max(0,a.power-1); // blocker toughness unknown here; assume small
        }
        return damage;
    }

    /** One opponent's board, our attackers and life totals: everything a candidate attack is scored on. */
    static final class Board {
        final List<Unit> attackers,blockers,theirTeam,ourHome;
        final boolean[][] canBlock,canBlockBack;
        final int ourLife,theirLife;
        /** canBlockBack[i][j]: our creature j can block their creature i; ourHome are ours that cannot attack. */
        Board(List<Unit> attackers,List<Unit> blockers,boolean[][] canBlock,List<Unit> theirTeam,List<Unit> ourHome,
              boolean[][] canBlockBack,int ourLife,int theirLife) {
            this.attackers=attackers;this.blockers=blockers;this.canBlock=canBlock;this.theirTeam=theirTeam;
            this.ourHome=ourHome;this.canBlockBack=canBlockBack;this.ourLife=ourLife;this.theirLife=theirLife;
        }
    }

    /** The score of attacking with the chosen attackers (bit i = attackers[i]). Higher is better for us. */
    static long score(Board board,long chosen) {
        List<Unit> attacking=new ArrayList<>();List<Integer> rows=new ArrayList<>();
        for(int i=0;i<board.attackers.size();i++) if((chosen>>>i&1)!=0) { attacking.add(board.attackers.get(i));rows.add(i); }
        boolean[][] canBlock=new boolean[attacking.size()][];
        for(int k=0;k<attacking.size();k++) canBlock[k]=board.canBlock[rows.get(k)];
        Outcome out=predict(attacking,board.blockers,canBlock,board.theirLife);
        int ourLife=board.ourLife+out.attackerGain,theirLife=board.theirLife-out.damage+out.defenderGain;
        if(theirLife<=0) return GameStateEvaluator2.WIN_GAME_SCORE-attacking.size();
        long score=life(ourLife)-life(board.ourLife);
        score+=(long)(life(board.theirLife)-life(theirLife))*AGGRESSION_PERCENT/100;
        for(Unit b:board.blockers) if(out.blockersDead.contains(b.id)) score+=b.value;
        for(Unit a:attacking) if(out.attackersDead.contains(a.id)) score-=a.value;
        // Crack-back: their survivors swing at whatever of ours can still block.
        List<Unit> theirs=new ArrayList<>();List<Integer> theirRows=new ArrayList<>();
        for(int i=0;i<board.theirTeam.size();i++) {
            Unit u=board.theirTeam.get(i);
            if(!out.blockersDead.contains(u.id)) { theirs.add(u);theirRows.add(i); }
        }
        List<Unit> home=new ArrayList<>();List<Integer> homeCols=new ArrayList<>();
        List<Unit> all=new ArrayList<>(board.attackers);all.addAll(board.ourHome);
        for(int j=0;j<all.size();j++) {
            Unit u=all.get(j);
            boolean attacked=j<board.attackers.size() && (chosen>>>j&1)!=0;
            if(out.attackersDead.contains(u.id) || (attacked && !u.vigilance)) continue;
            home.add(u);homeCols.add(j);
        }
        boolean[][] back=new boolean[theirs.size()][home.size()];
        for(int i=0;i<theirs.size();i++) for(int j=0;j<home.size();j++) back[i][j]=board.canBlockBack[theirRows.get(i)][homeCols.get(j)];
        int crack=crackBack(theirs,home,back);
        if(crack>=ourLife) score+=LETHAL_FOR_US;
        else score-=(long)(life(ourLife)-life(ourLife-crack))*CRACK_BACK_PERCENT/100;
        return score;
    }
    private static int life(int life) { return ArtificialScoringSystem.getLifeScore(life); }

    /** The best attack: every subset for small boards, else hill-climbing from none, all and each alone. */
    static long choose(Board board) {
        int n=board.attackers.size();
        if(n==0) return 0;
        if(n<=EXHAUSTIVE_ATTACKERS) {
            long best=0,bestScore=score(board,0);
            for(long set=1;set<(1L<<n);set++) {
                long s=score(board,set);
                if(s>bestScore || (s==bestScore && Long.bitCount(set)<Long.bitCount(best))) { best=set;bestScore=s; }
            }
            return best;
        }
        n=Math.min(n,62);
        long best=0,bestScore=Long.MIN_VALUE;
        for(long start:new long[]{0,(1L<<n)-1}) {
            long set=start,s=score(board,set);
            for(boolean improved=true;improved;) {
                improved=false;
                for(int i=0;i<n;i++) {
                    long next=set^(1L<<i),ns=score(board,next);
                    if(ns>s) { set=next;s=ns;improved=true; }
                }
            }
            if(s>bestScore) { best=set;bestScore=s; }
        }
        return best;
    }

    /** The attack the planner chose against the only opponent. */
    record Plan(UUID defenderId,List<UUID> attackers) {}

    /**
     * The planned attack, or null where upstream's rule should decide: several opponents, planeswalkers
     * or battles to attack, a defender who can't lose life, or infect.
     */
    static Plan planAttack(Player me,Game game) {
        List<UUID> opponents=new ArrayList<>();
        for(UUID id:game.getOpponents(me.getId(),true)) { Player p=game.getPlayer(id);if(p!=null && p.isInGame()) opponents.add(id); }
        if(opponents.size()!=1) return null;
        UUID defenderId=opponents.get(0);
        Player defender=game.getPlayer(defenderId);
        if(!game.getBattlefield().getActivePermanents(StaticFilters.FILTER_PERMANENT_PLANESWALKER,me.getId(),game).isEmpty()
                || !game.getBattlefield().getActivePermanents(StaticFilters.FILTER_PERMANENT_BATTLE,me.getId(),game).isEmpty()
                || !defender.isLifeTotalCanChange() || !defender.canLose(game)) return null;
        List<Permanent> available=me.getAvailableAttackers(defenderId,game);
        List<Unit> attackers=new ArrayList<>();
        for(Permanent p:available) {
            if(p.getAbilities(game).containsKey(InfectAbility.getInstance().getId())) return null;
            attackers.add(new Unit(p,game));
        }
        if(attackers.isEmpty()) return new Plan(defenderId,List.of());
        List<Unit> blockers=units(defender.getAvailableBlockers(game),game);
        Set<UUID> availableIds=new HashSet<>();for(Permanent p:available) availableIds.add(p.getId());
        List<Unit> theirTeam=new ArrayList<>(),ourHome=new ArrayList<>();
        for(Permanent p:game.getBattlefield().getAllActivePermanents(StaticFilters.FILTER_PERMANENT_CREATURE,defenderId,game))
            if(!p.getAbilities(game).containsKey(DefenderAbility.getInstance().getId()) && p.getPower().getValue()>0) theirTeam.add(new Unit(p,game));
        for(Permanent p:game.getBattlefield().getAllActivePermanents(StaticFilters.FILTER_PERMANENT_CREATURE,me.getId(),game))
            if(!availableIds.contains(p.getId()) && !p.isTapped()) ourHome.add(new Unit(p,game));
        boolean[][] canBlock=new boolean[attackers.size()][blockers.size()];
        for(int i=0;i<attackers.size();i++) for(int j=0;j<blockers.size();j++)
            canBlock[i][j]=blockers.get(j).permanent.canBlock(attackers.get(i).id,game);
        List<Unit> ours=new ArrayList<>(attackers);ours.addAll(ourHome);
        boolean[][] back=new boolean[theirTeam.size()][ours.size()];
        for(int i=0;i<theirTeam.size();i++) for(int j=0;j<ours.size();j++)
            back[i][j]=ours.get(j).permanent.canBlock(theirTeam.get(i).id,game);
        long chosen=choose(new Board(attackers,blockers,canBlock,theirTeam,ourHome,back,me.getLife(),defender.getLife()));
        List<UUID> ids=new ArrayList<>();
        for(int i=0;i<attackers.size();i++) if((chosen>>>i&1)!=0) ids.add(attackers.get(i).id);
        return new Plan(defenderId,ids);
    }
    private static List<Unit> units(List<Permanent> permanents,Game game) {
        List<Unit> out=new ArrayList<>();
        for(Permanent p:permanents) if(p.isCreature(game)) out.add(new Unit(p,game));
        return out;
    }

    /**
     * After upstream chose its blocks: if the attackers left unblocked would still kill us, add chump
     * blocks on the biggest of them with creatures that are not blocking yet. Returns the blockers added.
     */
    static int chumpIfLethal(Player me,Game game) {
        int life=me.getLife();
        if(!me.isLifeTotalCanChange() || !me.canLose(game)) return 0;
        List<Unit> unblocked=new ArrayList<>();int incoming=0;
        Set<UUID> blocking=new HashSet<>();
        for(CombatGroup group:game.getCombat().getGroups()) {
            blocking.addAll(group.getBlockers());
            if(!me.getId().equals(group.getDefenderId())) continue;
            for(UUID attackerId:group.getAttackers()) {
                Permanent attacker=game.getPermanent(attackerId);
                if(attacker==null) continue;
                Unit u=new Unit(attacker,game);
                if(group.getBlockers().isEmpty()) { unblocked.add(u);incoming+=u.power*u.hits(); }
                else if(u.trample) incoming+=Math.max(0,u.power-1);
            }
        }
        if(incoming<life) return 0;
        unblocked.sort(Comparator.comparingInt((Unit u)->-u.power*u.hits()));
        List<Unit> spare=new ArrayList<>();
        for(Permanent p:me.getAvailableBlockers(game)) if(!blocking.contains(p.getId()) && p.isCreature(game)) spare.add(new Unit(p,game));
        spare.sort(Comparator.comparingInt(u->u.value));
        int added=0;
        for(Unit a:unblocked) {
            if(incoming<life) break;
            if(a.menace) continue;
            for(Unit b:spare) {
                if(blocking.contains(b.id) || !b.permanent.canBlock(a.id,game)) continue;
                me.declareBlocker(me.getId(),b.id,a.id,game);
                blocking.add(b.id);added++;
                incoming-=a.trample?Math.min(a.power,Math.max(0,b.toughness))*a.hits():a.power*a.hits();
                break;
            }
        }
        if(added>0) game.getPlayers().resetPassed();
        return added;
    }

    /**
     * What a double block on one attacker gains, in upstream's permanent values: the attacker's value if
     * the pair kills it, less what the attacker kills (it assigns its damage to the most valuable blockers it
     * can kill, first strike before they hit). Zero or less when the attacker survives or the trade is bad.
     */
    static int doubleBlockGain(Unit a,Unit b1,Unit b2) {
        if(a.indestructible) return 0;
        int damage=a.power*a.hits(),best=0;boolean[] bestKill={false,false};
        Unit[] pair={b1,b2};
        for(int mask=1;mask<4;mask++) {
            int need=0,value=0;
            for(int i=0;i<2;i++) if((mask>>i&1)!=0) {
                if(pair[i].indestructible) { need=Integer.MAX_VALUE/2;break; }
                need+=a.deathtouch?1:Math.max(1,pair[i].toughness);value+=pair[i].value;
            }
            if(need<=damage && value>best) { best=value;bestKill=new boolean[]{(mask&1)!=0,(mask&2)!=0}; }
        }
        boolean early=a.firstStrike || a.doubleStrike;
        int back=0;boolean touched=false;
        for(int i=0;i<2;i++) {
            Unit b=pair[i];
            boolean strikes=!(bestKill[i] && early && !b.firstStrike && !b.doubleStrike);
            if(strikes && b.power>0) { back+=b.power*b.hits();touched|=b.deathtouch; }
        }
        boolean dies=back>=a.toughness || (touched && back>0);
        return dies?a.value-best:0;
    }

    /**
     * After upstream chose its blocks (and any lethal chumps): double-block an unblocked attacker with two
     * creatures that are not blocking yet when together they kill it and lose less value than it is worth
     * (upstream never blocks with more than one creature). Strongest gains first. Returns the pairs added.
     */
    static int doubleBlock(Player me,Game game) {
        List<Unit> unblocked=new ArrayList<>();Set<UUID> blocking=new HashSet<>();
        for(CombatGroup group:game.getCombat().getGroups()) {
            blocking.addAll(group.getBlockers());
            if(!me.getId().equals(group.getDefenderId()) || !group.getBlockers().isEmpty()) continue;
            for(UUID attackerId:group.getAttackers()) { Permanent p=game.getPermanent(attackerId);if(p!=null) unblocked.add(new Unit(p,game)); }
        }
        if(unblocked.isEmpty()) return 0;
        List<Unit> spare=new ArrayList<>();
        for(Permanent p:me.getAvailableBlockers(game)) if(!blocking.contains(p.getId()) && p.isCreature(game)) spare.add(new Unit(p,game));
        unblocked.sort(Comparator.comparingInt((Unit u)->-u.value));
        int pairs=0;
        for(Unit a:unblocked) {
            int bestGain=0;Unit first=null,second=null;
            for(int i=0;i<spare.size();i++) for(int j=i+1;j<spare.size();j++) {
                Unit b1=spare.get(i),b2=spare.get(j);
                if(blocking.contains(b1.id) || blocking.contains(b2.id)) continue;
                int gain=doubleBlockGain(a,b1,b2);
                if(gain>bestGain && b1.permanent.canBlock(a.id,game) && b2.permanent.canBlock(a.id,game)) { bestGain=gain;first=b1;second=b2; }
            }
            if(first==null) continue;
            me.declareBlocker(me.getId(),first.id,a.id,game);me.declareBlocker(me.getId(),second.id,a.id,game);
            blocking.add(first.id);blocking.add(second.id);pairs++;
        }
        if(pairs>0) game.getPlayers().resetPassed();
        return pairs;
    }
}
