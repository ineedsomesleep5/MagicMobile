package io.magicmobile.xmage;

import io.magicmobile.core.*;
import io.magicmobile.generated.GeneratedCardFactory;
import mage.cards.*;
import mage.cards.decks.Deck;
import mage.deck.Commander;
import java.util.*;

/** Resolve printings only from compiled XMage set metadata, never caller-supplied Java classes. */
public final class DeckLoader {
    private DeckLoader() {}
    public static Deck load(Map<String,Object> config) {
        Json.onlyKeys(config,Set.of("name","main","commanders","companions"));
        Deck d=new Deck();d.setName(Json.optionalString(config,"name","Mobile Commander"));
        loadCards(Json.array(config.get("main")),d.getCards());
        loadCards(Json.array(config.get("commanders")),d.getSideboard());
        if(config.containsKey("companions")) loadCards(Json.array(config.get("companions")),d.getSideboard());
        if(d.getCards().size()+d.getSideboard().size()>2000)
            throw new BridgeException("invalid_deck","Deck exceeds mobile resource limit");
        // Upstream handles 100-card/companion/Rulebreaker sizes. Do not duplicate those rules.
        Commander validator=new Commander();
        if(!validator.validate(d)) {
            List<Object> issues=new ArrayList<>();
            for(mage.cards.decks.DeckValidatorError issue:validator.getErrorsList()) {
                issues.add(Json.map("type",issue.getErrorType().name(),"group",issue.getGroup(),
                    "message",issue.getMessage(),"cardName",issue.getCardName()));
            }
            throw new BridgeException("invalid_deck","Deck failed the pinned XMage Commander validator",
                Json.map("validator","Commander","issues",issues));
        }
        return d;
    }
    private static void loadCards(List<Object> rows,Set<Card> cards) {
        int total=0;
        for(Object value:rows) {
            Map<String,Object> r=Json.object(value);
            Json.onlyKeys(r,Set.of("count","setCode","collectorNumber","name"));
            long countLong=Json.integer(r.get("count"));
            if(countLong<1 || countLong>2000 || (total+=(int)countLong)>2000)
                throw new BridgeException("invalid_deck","Invalid card count");
            String code=Json.requiredString(r,"setCode"),number=Json.requiredString(r,"collectorNumber");
            ExpansionSet set=Sets.getInstance().get(code);
            if(set==null) throw new BridgeException("unknown_printing","Set is not in the compiled catalogue");
            ExpansionSet.SetCardInfo selected=null;
            for(ExpansionSet.SetCardInfo info:set.getSetCardInfo()) {
                if(!info.getCardNumber().equals(number))continue;
                if(selected!=null) throw new BridgeException("ambiguous_printing","Collector number is not unique in this set");
                selected=info;
            }
            if(selected==null) throw new BridgeException("unknown_printing","Collector number is not in the compiled catalogue");
            if(r.containsKey("name") && !Json.string(r.get("name")).equals(selected.getName()))
                throw new BridgeException("printing_name_mismatch","Requested name does not match the compiled printing");
            CardSetInfo info=new CardSetInfo(selected.getName(),code,number,selected.getRarity(),selected.getGraphicInfo());
            for(int i=0;i<(int)countLong;i++) {
                Card c=GeneratedCardFactory.create(selected.getCardClass().getName(),info);
                if(c==null) throw new BridgeException("unsupported_card","Compiled printing has no working factory");
                cards.add(c);
            }
        }
    }
}
