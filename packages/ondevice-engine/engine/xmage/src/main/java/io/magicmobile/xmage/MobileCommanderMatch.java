package io.magicmobile.xmage;

import mage.constants.MultiplayerAttackOption;
import mage.game.CommanderFreeForAllMatch;
import mage.game.GameException;
import mage.game.match.MatchOptions;

/** Uses XMage's match initialization, including card ownership and player metadata. */
final class MobileCommanderMatch extends CommanderFreeForAllMatch {
    MobileCommanderMatch() { super(options()); }
    private static MatchOptions options() {
        MatchOptions options=new MatchOptions("Mobile Commander","Commander Free For All",true);
        options.setDeckType("Commander");
        options.setWinsNeeded(1);
        options.setFreeMulligans(1);
        options.setAttackOption(MultiplayerAttackOption.MULTIPLE);
        return options;
    }
    @Override public void startGame() throws GameException {
        MobileCommanderGame game=new MobileCommanderGame();
        game.setNumPlayers(players.size());
        initGame(game);
        games.add(game);
    }
}
