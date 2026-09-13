package io.magicmobile.xmage;
import mage.game.CommanderFreeForAll;
import mage.game.GameOptions;
import mage.game.mulligan.LondonMulligan;
import mage.constants.*;
/** Casual Commander pod rules, including when tested with two seats. Not Duel Commander. */
final class MobileCommanderGame extends CommanderFreeForAll {
    private transient MobileAICancellation cancellation=new MobileAICancellation();
    MobileCommanderGame() {
        super(MultiplayerAttackOption.MULTIPLE,RangeOfInfluence.ALL,new LondonMulligan(1),40,7);
        this.gameOptions=new GameOptions();
        this.gameOptions.rollbackTurnsAllowed=false;
    }
    private MobileCommanderGame(MobileCommanderGame source) {
        super(source);cancellation=source.cancellation;
    }
    void setCancellation(MobileAICancellation cancellation) { this.cancellation=cancellation; }
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
