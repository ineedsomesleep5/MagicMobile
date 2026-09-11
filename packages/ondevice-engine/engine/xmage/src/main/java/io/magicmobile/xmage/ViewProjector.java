package io.magicmobile.xmage;

import io.magicmobile.core.Json;
import mage.constants.Zone;
import mage.game.Game;
import mage.players.Player;
import mage.view.GameView;
import mage.view.SimpleCardsView;
import java.util.*;

/** Projection happens on the GAME thread, not while the engine is mutating elsewhere. */
public final class ViewProjector {
    private ViewProjector() {}
    public static Map<String,Map<String,Object>> project(Game game,Map<String,MobileHumanPlayer> players) {
        Map<String,Map<String,Object>> out=new LinkedHashMap<>();
        // Match upstream GameSessionPlayer's projection boundary. Playability checks
        // may simulate actions, so they must not mutate the authoritative game.
        Game source=game.copy();
        for(Map.Entry<String,MobileHumanPlayer> seat:players.entrySet()) {
            // A separate upstream view per seat. Never serialize Game/GameState to peers.
            UUID viewer=seat.getValue().getId();
            GameView view=new GameView(source.getState(),source,viewer,null);
            Player priority=source.getPlayer(source.getPriorityPlayerId());
            if(priority!=null && viewer.equals(priority.getTurnControlledBy()))
                view.setCanPlayObjects(priority.getPlayableObjects(source,Zone.ALL));
            // Match GameSessionPlayer.processControlledPlayers, using only seat-scoped client DTOs.
            // A replaced controller can remain in upstream's reverse set until reset, so also
            // require the acted player's current controller before disclosing their hand.
            Player owner=source.getPlayer(viewer);
            view.getOpponentHands().clear();
            Map<String,Object> controlledPlayerViews=new LinkedHashMap<>();
            for(UUID controlledId:owner.getPlayersUnderYourControl()) {
                Player controlled=source.getPlayer(controlledId);
                if(controlled!=null && !viewer.equals(controlledId) && viewer.equals(controlled.getTurnControlledBy())
                        && viewer.equals(owner.getTurnControlledBy()) && controlled.getPlayersUnderYourControl().isEmpty()) {
                    view.getOpponentHands().put(controlled.getName(),new SimpleCardsView(controlled.getHand().getCards(source),true));
                    // CR 723.4 permits the controlled player's in-game information, not their
                    // outside-game cards. Preserve upstream visibility without replacing our own view.
                    GameView controlledView=new GameView(source.getState(),source,controlledId,null);
                    controlledView.getPlayers().forEach(player->player.getSideboard().clear());
                    controlledPlayerViews.put(controlledId.toString(),Json.parseObject(controlledView.toJson()));
                }
            }
            Map<String,Object> data=Json.parseObject(view.toJson());
            out.put(seat.getKey(),Json.map("schema","xmage-gameview-v1","gameView",data,
                "controlledPlayerViews",controlledPlayerViews,
                "enginePlayerId",seat.getValue().getId().toString()));
        }
        return out;
    }
}
