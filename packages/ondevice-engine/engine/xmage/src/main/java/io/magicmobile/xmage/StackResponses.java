package io.magicmobile.xmage;

import mage.abilities.Ability;
import mage.abilities.ActivatedAbility;
import mage.abilities.Mode;
import mage.abilities.PlayLandAbility;
import mage.abilities.SpellAbility;
import mage.abilities.StaticAbility;
import mage.abilities.TriggeredAbility;
import mage.abilities.costs.Cost;
import mage.abilities.costs.common.*;
import mage.abilities.effects.Effect;
import mage.cards.Card;
import mage.constants.Outcome;
import mage.constants.PhaseStep;
import mage.game.Game;
import mage.game.permanent.Permanent;
import mage.game.stack.Spell;
import mage.game.stack.StackObject;
import mage.target.Target;
import java.util.*;

/**
 * Whether each offered play could actually answer what is pending now: the stack, or attacks that
 * have not dealt their damage yet. A hint for smart pass stops (Arena's "you have a response"),
 * never a legality decision. Built from current ability, target and effect objects, not rules text.
 * Conservative: a play this cannot judge counts as a response.
 */
final class StackResponses {
    private StackResponses() {}
    /** Effects that only help their controller's own resources; an untargeted play of these answers nothing. */
    private static final Set<Outcome> SELF_ONLY=EnumSet.of(Outcome.DrawCard,Outcome.PutManaInPool,Outcome.PutLandInPlay);
    /** Outcomes that protect a player from a spell or ability that targets them. */
    private static final Set<Outcome> PROTECTS_PLAYER=EnumSet.of(Outcome.GainLife,Outcome.PreventDamage,
        Outcome.Protect,Outcome.RedirectDamage);
    /** Bad outcomes that touch only players or hands, never a permanent (drains, discard, cast limits). */
    private static final Set<Outcome> PLAYER_ONLY_HARM=EnumSet.of(Outcome.LoseLife,Outcome.Discard,Outcome.PreventCast);

    /** What is pending in a game: what a play would have to touch to answer it. */
    static final class Pending {
        final Set<UUID> objects=new HashSet<>(); // stack objects, their sources, their non-player targets, creatures in combat
        final Set<UUID> threatened=new HashSet<>(); // non-player objects that a stack object targets
        final Set<UUID> players=new HashSet<>(); // players that a stack object targets
        boolean untargetedHarm; // an untargeted stack object with an effect that hurts others (a sweeper, an edict)
        boolean combat; // attackers that have not dealt all their combat damage yet
        boolean stack;
        boolean any() { return stack || combat; }
    }

    static Pending pending(Game game) {
        Pending pending=new Pending();
        for(StackObject object:game.getStack()) {
            pending.stack=true;
            pending.objects.add(object.getId());pending.objects.add(object.getSourceId());
            List<Ability> abilities=new ArrayList<>();
            if(object instanceof Spell) abilities.addAll(((Spell)object).getSpellAbilities());
            else abilities.add(object.getStackAbility());
            boolean targeted=false,harmful=false;
            for(Ability ability:abilities) {
                if(ability==null) { harmful=true;continue; }
                for(Target target:ability.getAllSelectedTargets())
                    for(UUID id:target.getTargets()) {
                        targeted=true;
                        if(game.getPlayer(id)!=null) pending.players.add(id);
                        else { pending.objects.add(id);pending.threatened.add(id); }
                    }
                for(Effect effect:ability.getAllEffects())
                    if(!effect.getOutcome().isGood() && !PLAYER_ONLY_HARM.contains(effect.getOutcome())) harmful=true;
            }
            // A permanent spell is answered on the stack (counter, copy) or after it resolves; its
            // eventual abilities trigger and use the stack themselves.
            boolean permanentSpell=object instanceof Spell && ((Spell)object).isPermanent(game);
            if(!targeted && harmful && !permanentSpell) pending.untargetedHarm=true;
        }
        PhaseStep step=game.getTurnStepType();
        if((step==PhaseStep.DECLARE_ATTACKERS || step==PhaseStep.DECLARE_BLOCKERS || step==PhaseStep.FIRST_COMBAT_DAMAGE)
                && !game.getCombat().getAttackers().isEmpty()) {
            pending.combat=true;
            pending.objects.addAll(game.getCombat().getAttackers());
            pending.objects.addAll(game.getCombat().getBlockers());
        }
        return pending;
    }

    /** True when the play could answer something pending; false when nothing is pending. */
    static boolean responds(ActivatedAbility ability,Game game,Pending pending) {
        if(!pending.any() || ability instanceof PlayLandAbility) return false;
        try {
            // Abilities of a threatened object (sacrifice, blink, regenerate it) answer the threat.
            if(pending.threatened.contains(ability.getSourceId())) return true;
            if(sacrifices(ability) && (pending.untargetedHarm || controlsThreatened(ability.getControllerId(),game,pending)))
                return true;
            if(ability.isManaAbility()) return false;
            boolean permanentSpell=false;
            if(ability instanceof SpellAbility) {
                Card card=game.getCard(ability.getSourceId());
                if(card==null) return true;
                permanentSpell=card.isPermanent(game);
                // Flash blockers and creatures during an attack; elsewhere only a permanent with
                // abilities of its own (an enters trigger, a lord) can change what is pending.
                if(permanentSpell && (pending.combat || ownAbilities(card,game))) return true;
            }
            for(Mode mode:ability.getModes().values()) {
                // A permanent spell's own effect is the permanent; only an Aura's target can answer something.
                if(permanentSpell && mode.getTargets().isEmpty()) continue;
                if(modeResponds(mode,ability,game,pending)) return true;
            }
            return false;
        } catch(RuntimeException unknown) {
            return true; // Unsure: never hide a possible response.
        }
    }

    private static boolean modeResponds(Mode mode,Ability ability,Game game,Pending pending) {
        if(mode.getTargets().isEmpty()) {
            if(mode.getEffects().isEmpty()) return true;
            for(Effect effect:mode.getEffects()) if(!SELF_ONLY.contains(effect.getOutcome())) return true;
            return false;
        }
        boolean protectsPlayer=mode.getEffects().stream().anyMatch(effect->PROTECTS_PLAYER.contains(effect.getOutcome()));
        for(Target target:mode.getTargets()) {
            for(UUID id:target.possibleTargets(ability.getControllerId(),ability,game)) {
                if(pending.objects.contains(id)) return true;
                if(protectsPlayer && pending.players.contains(id)) return true;
                // An untargeted sweeper or edict: protecting, sacrificing or blinking any permanent can answer it.
                if(pending.untargetedHarm && game.getPermanent(id)!=null) return true;
            }
        }
        return false;
    }

    private static boolean sacrifices(Ability ability) {
        for(Cost cost:ability.getCosts())
            if(cost instanceof SacrificeTargetCost || cost instanceof SacrificeSourceCost || cost instanceof SacrificeAllCost
                    || cost instanceof SacrificeXTargetCost || cost instanceof SacrificeAttachedCost
                    || cost instanceof SacrificeAttachmentCost) return true;
        return false;
    }

    private static boolean controlsThreatened(UUID controllerId,Game game,Pending pending) {
        for(UUID id:pending.threatened) {
            Permanent permanent=game.getPermanent(id);
            if(permanent!=null && permanent.isControlledBy(controllerId)) return true;
        }
        return false;
    }

    /** Triggered or non-keyword static abilities: what a flashed-in permanent could do beyond its body. */
    private static boolean ownAbilities(Card card,Game game) {
        for(Ability ability:card.getAbilities(game)) {
            if(ability instanceof TriggeredAbility) return true;
            if(ability instanceof StaticAbility && !(ability instanceof SpellAbility)
                    && !ability.getClass().getPackageName().equals("mage.abilities.keyword")) return true;
        }
        return false;
    }
}
