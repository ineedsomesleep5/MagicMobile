package io.magicmobile.xmage;
import mage.game.CommanderFreeForAll;
import mage.game.GameOptions;
import mage.game.mulligan.LondonMulligan;
import mage.constants.*;
/** Casual Commander pod rules, including when tested with two seats. Not Duel Commander. */
final class MobileCommanderGame extends CommanderFreeForAll {
    MobileCommanderGame() {
        super(MultiplayerAttackOption.MULTIPLE,RangeOfInfluence.ALL,new LondonMulligan(1),40,7);
        this.gameOptions=new GameOptions();
        this.gameOptions.rollbackTurnsAllowed=false;
    }
}
