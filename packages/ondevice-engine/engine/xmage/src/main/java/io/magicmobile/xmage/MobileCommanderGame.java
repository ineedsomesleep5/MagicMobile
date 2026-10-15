package io.magicmobile.xmage;
import mage.game.CommanderFreeForAll;
import mage.game.GameOptions;
import mage.game.mulligan.LondonMulligan;
import mage.constants.*;
/** Casual Commander pod rules, including when tested with two seats. Not Duel Commander. */
final class MobileCommanderGame extends CommanderFreeForAll {
    private static final long serialVersionUID=1L;
    private transient MobileAICancellation cancellation=new MobileAICancellation();
    private void readObject(java.io.ObjectInputStream in) throws java.io.IOException, ClassNotFoundException {
        in.defaultReadObject();
        cancellation=new MobileAICancellation(); // Replaced by the restoring match's setCancellation.
    }
    MobileCommanderGame() {
        super(MultiplayerAttackOption.MULTIPLE,RangeOfInfluence.ALL,new LondonMulligan(1),40,7);
        this.gameOptions=new GameOptions();
        this.gameOptions.rollbackTurnsAllowed=false;
    }
    private MobileCommanderGame(MobileCommanderGame source) {
        super(source);cancellation=source.cancellation;
    }
    void setCancellation(MobileAICancellation cancellation) { this.cancellation=cancellation;cancellation.bind(this); }
    MobileAICancellation cancellation() { return cancellation; }
    boolean hasConcedeRequest() { return cancellation.hasConcedeFor(this); }
    void requestConcede(java.util.UUID playerId) { cancellation.requestConcede(playerId); }
    @Override public void checkConcede(boolean mustRunInGameThread) {
        // Upstream checks conceding players at every priority and after each resolution.
        // Mobile requests join here, on the GAME thread: concede marks the loss and XMage's
        // own leave() removes the player's objects; the remaining players play on.
        GameRecorder recorder=cancellation.recorder();
        if(recorder!=null && recorder.active(this)) {
            // The record says after how many of these calls each concede happened (docs/cloud/game-record.md).
            recorder.concedeCheck();
            if(recorder.replaying) for(java.util.UUID id=recorder.replayConcede();id!=null;id=recorder.replayConcede()) concede(id);
            else for(java.util.UUID id=cancellation.nextConcede(this);id!=null;id=cancellation.nextConcede(this)) { recorder.conceded(id);concede(id); }
        } else for(java.util.UUID id=cancellation.nextConcede(this);id!=null;id=cancellation.nextConcede(this)) concede(id);
        super.checkConcede(mustRunInGameThread);
    }
    // Rules code that AI reasoning calls while recording: decisions it asks for are recorded, and it draws
    // the game's seeded stream, exactly as when a replay makes the same call.
    @Override public void fireEvent(mage.game.events.GameEvent event) {
        GameRecorder recorder=aiCall();
        if(recorder==null) super.fireEvent(event); else recorder.engineRun(()->super.fireEvent(event));
    }
    @Override public boolean replaceEvent(mage.game.events.GameEvent event) {
        GameRecorder recorder=aiCall();
        return recorder==null?super.replaceEvent(event):recorder.engine(()->super.replaceEvent(event));
    }
    @Override public boolean replaceEvent(mage.game.events.GameEvent event,mage.abilities.Ability targetAbility) {
        GameRecorder recorder=aiCall();
        return recorder==null?super.replaceEvent(event,targetAbility):recorder.engine(()->super.replaceEvent(event,targetAbility));
    }
    private GameRecorder aiCall() {
        GameRecorder recorder=cancellation.recorder();
        return recorder!=null && recorder.recordsEffect(this)?recorder:null;
    }
    @Override public MobileCommanderGame copy() { return new MobileCommanderGame(this); }
    @Override public boolean hasEnded() {
        // Opening-player selection loops on hasEnded(), not checkIfGameIsOver().
        // Interrupting its worker makes every player unable to respond; the
        // durable stop signal must also terminate that upstream initialization loop.
        return cancellation.isClosing() || super.hasEnded();
    }
    @Override public boolean checkIfGameIsOver() {
        // MAD can consume InterruptedException. Copies must retain the durable stop signal.
        return cancellation.isClosing() || super.checkIfGameIsOver();
    }
}
