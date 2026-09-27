package io.magicmobile.xmage;

import mage.constants.MultiplayerAttackOption;
import mage.game.CommanderFreeForAllMatch;
import mage.game.GameException;
import mage.game.match.MatchOptions;
import mage.game.match.MatchPlayer;
import mage.players.Player;

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
    /**
     * Binds a game read from a checkpoint. The match wrapper is not serializable; each player
     * carries its own MatchPlayer (with its deck), so the rebuilt match records the same result.
     */
    static MobileCommanderMatch restored(MobileCommanderGame game) {
        MobileCommanderMatch match=new MobileCommanderMatch();
        match.startMatch();
        for(Player player:game.getState().getPlayers().values()) {
            MatchPlayer matchPlayer=player.getMatchPlayer();
            if(matchPlayer==null || matchPlayer.getPlayer()!=player)
                throw new IllegalStateException("Checkpoint player has no match binding");
            match.players.add(matchPlayer);
        }
        match.addGame();
        match.games.add(game);
        return match;
    }
}
