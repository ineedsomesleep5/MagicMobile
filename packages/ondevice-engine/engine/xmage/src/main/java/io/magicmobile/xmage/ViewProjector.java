package io.magicmobile.xmage;

import com.google.gson.Gson;
import io.magicmobile.core.Json;
import io.magicmobile.generated.GeneratedCardFactory;
import mage.cards.Card;
import mage.cards.CardSetInfo;
import mage.cards.ExpansionSet;
import mage.cards.Sets;
import mage.constants.CommanderCardType;
import mage.constants.Zone;
import mage.game.Game;
import mage.game.permanent.PermanentToken;
import mage.game.permanent.token.Token;
import mage.players.Player;
import mage.players.PlayerImpl;
import mage.abilities.mana.ActivatedManaAbilityImpl;
import mage.abilities.keyword.MenaceAbility;
import mage.view.GameView;
import mage.view.CardView;
import mage.view.SimpleCardView;
import mage.view.SimpleCardsView;
import mage.watchers.common.CommanderInfoWatcher;
import mage.watchers.common.CommanderPlaysCountWatcher;
import java.util.*;

/** Projection happens on the GAME thread, not while the engine is mutating elsewhere. */
public final class ViewProjector {
    private ViewProjector() {}
    public static Map<String,Map<String,Object>> project(Game game,Map<String,MobileHumanPlayer> players) {
        Map<String,Map<String,Object>> out=new LinkedHashMap<>();
        // Match upstream GameSessionPlayer's projection boundary. Playability checks
        // may simulate actions, so they must not mutate the authoritative game.
        Game source=game.copy();
        Map<String,Object> commanders=commanderMetadata(source);
        List<String> winners=source.getPlayers().values().stream().filter(Player::hasWon)
            .map(player->player.getId().toString()).toList();
        Map<String,Object> outcome=Json.map("ended",source.hasEnded(),"winnerPlayerIds",winners);
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
            // PlayableObjectStats places non-basic mana abilities in `other` alongside
            // non-mana abilities. Preserve its authoritative choices and add only type
            // information, from the current ability objects (never rule-text parsing).
            if(priority!=null && viewer.equals(priority.getTurnControlledBy())) {
                Set<String> manaIds=new HashSet<>();
                ((PlayerImpl)priority).getPlayable(source,true,Zone.ALL,false).stream()
                    .filter(ActivatedManaAbilityImpl.class::isInstance)
                    .forEach(ability->manaIds.add(ability.getId().toString()));
                Map<String,Object> playable=Json.object(data.get("canPlayObjects"));
                for(Object stats:Json.object(playable.get("objects")).values())
                    for(Object rows:Json.object(stats).values())
                        for(Object row:Json.array(rows)) {
                            Map<String,Object> fields=Json.object(row);
                            fields.put("manaAbility",manaIds.contains(fields.get("id")));
                        }
            }
            // Pinned XMage has no menace CardIconType. Emit a text-badge extension
            // only for a currently visible permanent's current keyword ability.
            for(Object playerView:Json.array(data.get("players")))
                for(Object cardView:Json.object(Json.object(playerView).get("battlefield")).values()) {
                    Map<String,Object> fields=Json.object(cardView);
                    var permanent=source.getPermanent(UUID.fromString(Json.requiredString(fields,"id")));
                    if(permanent==null || permanent.isFaceDown(source) || Boolean.TRUE.equals(fields.get("hideInfo"))) continue;
                    // This is an artwork hint, not an original-card DTO. A copy
                    // token carries its source card even after the source leaves
                    // the battlefield. Disclose only the name already present on
                    // this seat's face-up CardView; never an ID or hidden origin.
                    String sourceArt=copySourceArtworkName(fields,permanent,source);
                    if(sourceArt!=null) fields.put("copySourceArtworkName",sourceArt);
                    if(permanent instanceof PermanentToken && Boolean.TRUE.equals(fields.get("isToken"))) {
                        Map<String,Object> artwork=tokenArtwork((PermanentToken)permanent,source);
                        // A template name must already be disclosed by this seat's
                        // current view. Never recover a concealed original name.
                        if(artwork.get("name") instanceof String artworkName && !artworkName.isBlank()
                                && artworkName.equals(fields.get("name")) && artworkName.equals(fields.get("displayName")))
                            fields.put("tokenArtwork",artwork);
                    }
                    if(permanent.getAbilities(source).stream().anyMatch(MenaceAbility.class::isInstance)) {
                        List<Object> icons=new ArrayList<>(Json.array(fields.get("cardIcons")));
                        icons.add(Json.map("cardIconType","ABILITY_MENACE","category","ABILITY","text","Menace",
                            "hint","This creature can't be blocked except by two or more creatures."));
                        fields.put("cardIcons",icons);
                    }
                }
            List<Object> namedExiles=new ArrayList<>();
            for(int i=0;i<view.getExile().size();i++) {
                var exile=view.getExile().get(i);
                namedExiles.add(Json.map("id",exile.getId().toString(),"name",exile.getName(),
                    "cards",Json.array(data.get("exiles")).get(i)));
            }
            Map<String,Object> authorizedLookedAt=new LinkedHashMap<>(),authorizedOpponentHands=new LinkedHashMap<>();
            view.getLookedAt().forEach(group->authorizedLookedAt.put(group.getName(),printedCards(group.getCards())));
            view.getOpponentHands().forEach((name,cards)->authorizedOpponentHands.put(name,printedCards(cards)));
            // CardsView preserves upstream top-first order; JSON object keys do not.
            List<String> stackOrder=view.getStack().keySet().stream().map(UUID::toString).toList();
            out.put(seat.getKey(),Json.map("schema","xmage-gameview-v1","gameView",data,
                "stackOrder",stackOrder,
                "commanders",commanders,
                "outcome",outcome,
                "namedExiles",namedExiles,
                "authorizedLookedAt",authorizedLookedAt,
                "authorizedOpponentHands",authorizedOpponentHands,
                "controlledPlayerViews",controlledPlayerViews,
                "enginePlayerId",seat.getValue().getId().toString()));
        }
        return out;
    }

    static String copySourceArtworkName(Map<String,Object> fields,mage.game.permanent.Permanent permanent,Game game) {
        if(!(permanent instanceof PermanentToken) || !permanent.isCopy()
                || permanent.isFaceDown(game) || Boolean.TRUE.equals(fields.get("hideInfo"))
                || !Boolean.TRUE.equals(fields.get("isToken"))) return null;
        Card copySource=((PermanentToken)permanent).getToken().getCopySourceCard();
        Object visibleName=fields.get("displayName");
        return copySource!=null && visibleName instanceof String
                && visibleName.equals(fields.get("name")) && visibleName.equals(copySource.getName())
                && !((String)visibleName).isBlank() ? (String)visibleName : null;
    }
    private static Map<String,Object> tokenArtwork(PermanentToken permanent,Game game) {
        Token template=permanent.isTransformed() && permanent.getToken().getBackFace()!=null
            ? permanent.getToken().getBackFace() : permanent.getToken();
        // Template characteristics, not continuous effects, counters or a hidden
        // original. The public CardView above is the disclosure gate.
        List<String> subs=new ArrayList<>();
        for(var subtype:template.getSubtype(null)) subs.add(subtype.name());
        var color=template.getColor(null);
        return Json.map("name",template.getName(),"cardTypes",template.getCardType(null).stream().map(Enum::name).toList(),
            "superTypes",template.getSuperType(null).stream().map(Enum::name).toList(),"subTypes",subs,
            "rules",template.getAbilities().getRules(game,template),
            "power",template.getPower().toString(),"toughness",template.getToughness().toString(),
            "color",Json.map("white",color.isWhite(),"blue",color.isBlue(),"black",color.isBlack(),
                "red",color.isRed(),"green",color.isGreen()));
    }

    private static Map<String,Object> printedCards(SimpleCardsView disclosed) {
        Map<UUID,SimpleCardView> printed=new LinkedHashMap<>(disclosed);
        for(var entry:disclosed.entrySet()) {
            SimpleCardView simple=entry.getValue();
            String code=simple.getExpansionSetCode(),number=simple.getCardNumber();
            if(code==null || code.isBlank() || number==null || number.isBlank()) continue;
            ExpansionSet set=Sets.getInstance().get(code);
            if(set==null) continue;
            ExpansionSet.SetCardInfo selected=null;
            for(var info:set.getSetCardInfo()) {
                if(!number.equals(info.getCardNumber())) continue;
                if(selected!=null) { selected=null; break; } // Ambiguous printing stays unknown.
                selected=info;
            }
            if(selected==null) continue;
            Card card=GeneratedCardFactory.create(selected.getCardClass().getName(),
                new CardSetInfo(selected.getName(),code,number,selected.getRarity(),selected.getGraphicInfo()));
            // Only fresh printed characteristics; never resolve a game object or pass Game to CardView.
            if(card!=null) printed.put(entry.getKey(),new CardView(card,simple));
        }
        return Json.parseObject(new Gson().toJson(printed));
    }

    private static Map<String,Object> commanderMetadata(Game source) {
        Map<String,Object> commanders=new LinkedHashMap<>();
        for(Player player:source.getPlayers().values()) {
            // Public commander definitions, independent of current zone or controller.
            for(UUID id:source.getCommandersIds(player,CommanderCardType.COMMANDER_OR_OATHBREAKER,false)) {
                Map<String,Object> info=Json.map("ownerPlayerId",player.getId().toString());
                Card commander=source.getCard(id); // This ID is a public commander definition, not a zone search.
                if(commander!=null) info.put("name",commander.getMainCard().getName());
                CommanderPlaysCountWatcher plays=source.getState().getWatcher(CommanderPlaysCountWatcher.class);
                if(plays!=null) {
                    int count=plays.getPlaysCount(id);
                    info.put("castsFromCommandZone",count);
                    // Tax component for the next command-zone cast, before other cost modifiers.
                    info.put("commanderTax",count*2);
                }
                CommanderInfoWatcher damage=source.getState().getWatcher(CommanderInfoWatcher.class,id);
                if(damage!=null) {
                    Map<String,Object> damageToPlayers=new LinkedHashMap<>();
                    damage.getDamageToPlayer().forEach((playerId,amount)->damageToPlayers.put(playerId.toString(),amount));
                    info.put("damageToPlayers",damageToPlayers);
                }
                commanders.put(id.toString(),info);
            }
        }
        return commanders;
    }
}
