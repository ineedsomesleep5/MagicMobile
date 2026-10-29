package io.magicmobile.xmage;

import io.magicmobile.core.*;
import io.magicmobile.generated.GeneratedCardFactory;
import mage.cards.Card;
import mage.cards.CardSetInfo;
import mage.constants.Zone;
import mage.game.Game;
import mage.game.GameImpl;
import mage.game.PutToBattlefieldInfo;
import mage.game.permanent.Permanent;
import mage.game.permanent.PermanentImpl;
import mage.cards.MobileExpansionSet;
import mage.players.Player;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/**
 * Lesson recorder only (scripts/lessons/record.py): EngineCli plus a `lessonStage` op that sets a
 * board with XMage's own test cheat while the GAME thread waits on a human's answer. Never shipped:
 * it lives in engine/tools, outside the engine's source list.
 */
public final class LessonCli {
    public static void main(String[] args) throws Exception {
        try(XmageEngine engine=new XmageEngine("lesson-recorder")) {
            EngineService service=new EngineService(engine);
            BufferedReader input=new BufferedReader(new InputStreamReader(System.in,StandardCharsets.UTF_8));
            for(String line;(line=input.readLine())!=null;) {
                Map<String,Object> request=Json.object(Json.parse(line));
                if(!"lessonStage".equals(request.get("op"))) {System.out.println(service.request(line));continue;}
                Object result;
                try {result=Json.map("protocol",1,"ok",true,"result",stage(engine,request));}
                catch(Throwable e) {
                    e.printStackTrace(System.err);
                    result=Json.map("protocol",1,"ok",false,"error",Json.map("code","stage_failed","message",String.valueOf(e)));
                }
                System.out.println(Json.write(result));
            }
        }
    }

    /** {matchId, seats: {seatId: {life, hand, battlefield: [{card, tapped, sick}], library (top first), graveyard}}}. */
    @SuppressWarnings("unchecked")
    static Map<String,Object> stage(XmageEngine engine,Map<String,Object> request) throws Exception {
        Field matchesField=XmageEngine.class.getDeclaredField("matches");matchesField.setAccessible(true);
        Object running=((Map<String,Object>)matchesField.get(engine)).get(Json.requiredString(request,"matchId"));
        if(running==null) throw new IllegalArgumentException("Unknown match");
        Field gameField=running.getClass().getDeclaredField("game");gameField.setAccessible(true);
        Field seatsField=running.getClass().getDeclaredField("seats");seatsField.setAccessible(true);
        Game game=(Game)gameField.get(running);
        Map<String,MobileHumanPlayer> seats=(Map<String,MobileHumanPlayer>)seatsField.get(running);
        Map<String,Object> staged=new LinkedHashMap<>();
        for(Map.Entry<String,Object> entry:Json.object(request.get("seats")).entrySet()) {
            Map<String,Object> spec=Json.object(entry.getValue());
            Player player=game.getPlayer(seats.get(entry.getKey()).getId());
            // The dealt hand goes to the bottom of the library; the lesson's cards replace it.
            for(Card card:new ArrayList<>(player.getHand().getCards(game))) {
                player.getHand().remove(card);
                game.getState().setZone(card.getId(),Zone.LIBRARY);
                player.getLibrary().putOnBottom(card,game);
            }
            List<Card> hand=cards(spec.get("hand")),graveyard=cards(spec.get("graveyard")),library=cards(spec.get("library"));
            Collections.reverse(library);
            List<PutToBattlefieldInfo> battlefield=new ArrayList<>();
            List<Map<String,Object>> rows=new ArrayList<>();
            for(Object row:spec.containsKey("battlefield")?Json.array(spec.get("battlefield")):List.of()) {
                Map<String,Object> r=Json.object(row);
                Card card=cards(List.of(r.get("card"))).get(0);
                battlefield.add(new PutToBattlefieldInfo(card,Boolean.TRUE.equals(r.get("tapped"))));
                rows.add(r);
            }
            ((GameImpl)game).cheat(player.getId(),library,hand,battlefield,graveyard,List.of(),List.of());
            for(int i=0;i<battlefield.size();i++) {
                Permanent permanent=game.getPermanent(battlefield.get(i).getCard().getId());
                if(permanent instanceof PermanentImpl && !Boolean.TRUE.equals(rows.get(i).get("sick"))) ((PermanentImpl)permanent).removeSummoningSickness();
            }
            // A Commander deck is 100 cards: the commander, the library and what the lesson put in play, hand and graveyard.
            // The dealt hand went to the bottom of the library; the bottom comes off until the deck adds up again.
            int librarySize=99-hand.size()-battlefield.size()-graveyard.size();
            List<UUID> order=player.getLibrary().getCardList();
            for(int i=order.size()-1;i>=0 && player.getLibrary().size()>librarySize;i--) {
                Card card=player.getLibrary().remove(order.get(i),game);
                if(card!=null) game.getState().setZone(card.getId(),Zone.OUTSIDE);
            }
            if(spec.containsKey("life")) player.setLife((int)Json.integer(spec.get("life")),game,null);
            List<Object> ids=new ArrayList<>();
            for(Card card:hand) ids.add(Json.map("zone","hand","name",card.getName(),"id",card.getId().toString()));
            for(PutToBattlefieldInfo info:battlefield) ids.add(Json.map("zone","battlefield","name",info.getCard().getName(),"id",info.getCard().getId().toString()));
            staged.put(entry.getKey(),ids);
        }
        // Republish every seat's board, as a board change on the GAME thread would.
        Method snapshot=running.getClass().getDeclaredMethod("snapshot");snapshot.setAccessible(true);
        snapshot.invoke(running);
        return Json.map("staged",staged);
    }

    /** Deck rows ({name, setCode, collectorNumber}) as new cards, the way DeckLoader makes them. */
    static List<Card> cards(Object value) {
        List<Card> cards=new ArrayList<>();
        if(value==null) return cards;
        for(Object row:Json.array(value)) {
            Map<String,Object> r=Json.object(row);
            String code=Json.requiredString(r,"setCode"),number=Json.requiredString(r,"collectorNumber");
            List<MobileExpansionSet.Printing> printings=DeckLoader.printings(code,number);
            if(printings==null || printings.size()!=1) throw new IllegalArgumentException("Unknown printing "+code+" "+number);
            CardSetInfo info=printings.get(0).setInfo(code);
            cards.add(GeneratedCardFactory.create(printings.get(0).getClassName(),info));
        }
        return cards;
    }
}
