package io.magicmobile.xmage;

import io.magicmobile.core.*;
import mage.abilities.Ability;
import mage.cards.Card;
import mage.cards.ModalDoubleFacedCard;
import mage.choices.Choice;
import mage.constants.Constants;
import mage.constants.Zone;
import mage.game.Game;
import mage.game.events.PlayerQueryEvent;
import mage.game.permanent.Permanent;
import mage.util.MultiAmountMessage;
import mage.view.CardView;
import mage.view.AbilityPickerView;
import com.google.gson.Gson;
import java.util.*;

/** Exhaustive transport mapping; legality remains in HumanPlayer / XMage. */
public final class QueryEncoder {
    private static final Gson GSON=new Gson();
    private QueryEncoder() {}
    public static DecisionSpec encode(PlayerQueryEvent e,Game game) {
        String kind=e.getQueryType().name();
        Map<String,?> options=e.getOptions()==null?Collections.emptyMap():e.getOptions();
        Map<String,Object> p=Json.map("message",e.getMessage()==null?"":e.getMessage(),
            "required",e.isRequired(),"options",safe(options,0));
        Set<String> types=new LinkedHashSet<>(), ids=null, strings=null;
        long min=e.getMin(),max=e.getMax();
        List<long[]> allocations=new ArrayList<>();
        switch(e.getQueryType()) {
            case ASK: types.add("boolean");break;
            case CHOOSE_CHOICE: {
                Choice c=e.getChoice();
                if(c==null) throw unsupported(kind);
                Map<String,String> choices=new LinkedHashMap<>();
                if(c.isKeyChoice()) choices.putAll(c.getKeyChoices());
                else for(String s:c.getChoices()) choices.put(s,s);
                p.put("message",c.getMessage());p.put("required",c.isRequired());
                p.put("choices",safe(choices,0));
                p.put("choiceOrder",new ArrayList<>(choices.keySet()));
                p.put("keyChoice",c.isKeyChoice());p.put("subMessage",c.getSubMessage());
                p.put("searchEnabled",c.isSearchEnabled());
                p.put("searchText",c.getSearchText());
                p.put("sortEnabled",c.isSortEnabled());p.put("sortData",safe(c.getSortData(),0));
                p.put("hintType",safe(c.getHintType(),0));p.put("hintData",safe(c.getHintData(),0));
                p.put("specialEnabled",c.isSpecialEnabled());p.put("specialText",c.getSpecialText());
                p.put("specialHint",c.getSpecialHint());p.put("specialCanBeEmpty",c.isSpecialCanBeEmpty());
                strings=new LinkedHashSet<>(choices.keySet());
                // GamePanel prefixes special answers; HumanPlayer.chooseReplacementEffect strips it.
                Map<String,String> specialChoices=new LinkedHashMap<>();
                if(c.isSpecialEnabled()) choices.forEach((key,label)->specialChoices.put("#"+key,label));
                strings.addAll(specialChoices.keySet());p.put("specialChoices",specialChoices);
                // Do not invent a "#" answer for special-empty: upstream sends null in that case.
                if(!c.isRequired()) strings.add("");
                types.add("string");break;
            }
            case CHOOSE_MODE: {
                Map<String,Object> choices=new LinkedHashMap<>();
                if(e.getModes()!=null) e.getModes().forEach((id,label)->choices.put(id.toString(),label));
                ids=new LinkedHashSet<>(choices.keySet());p.put("choices",choices);
                p.put("choiceOrder",new ArrayList<>(choices.keySet()));types.add("uuid");break;
            }
            case CHOOSE_ABILITY:
            case PICK_ABILITY: {
                ids=new LinkedHashSet<>();List<Object> choices=new ArrayList<>();
                String objectName=e.getChoices()==null || e.getChoices().isEmpty()?null:e.getChoices().iterator().next();
                Map<UUID,String> labels=new AbilityPickerView(null,objectName,
                    e.getAbilities()==null?Collections.emptyList():e.getAbilities(),e.getMessage()).getChoices();
                if(e.getAbilities()!=null) for(Ability ability:e.getAbilities()) {
                    String id=ability.getId().toString();ids.add(id);
                    Map<String,Object> row=Json.map("id",id,"label",labels.get(ability.getId()),
                        "sourceId",safe(ability.getSourceId(),0),"originalId",safe(ability.getOriginalId(),0));
                    Object source=abilitySource(ability,e.getPlayerId(),game);
                    if(source!=null) row.put("sourceCard",source);
                    choices.add(row);
                }
                p.put("objectName",objectName);
                p.put("abilities",choices);types.add("uuid");
                if(!e.isRequired()) types.add("boolean");break;
            }
            case PICK_TARGET: {
                ids=new LinkedHashSet<>();List<Object> cards=new ArrayList<>();
                if(e.getTargets()!=null) for(UUID id:e.getTargets()) ids.add(id.toString());
                if(e.getCards()!=null) for(UUID id:e.getCards()) {
                    ids.add(id.toString());Card c=game.getCard(id);
                    if(c!=null) cards.add(card(c,game));
                }
                if(e.getPerms()!=null) for(Permanent c:e.getPerms()) {ids.add(c.getId().toString());cards.add(card(c,game));}
                // HumanPlayer removes an existing target before checking possibleTargets.
                Object chosen=options.get("chosenTargets");
                if(chosen instanceof Collection<?>) for(Object id:(Collection<?>)chosen) {
                    if(!(id instanceof UUID)) throw unsupported("chosenTargets");
                    ids.add(id.toString());
                }
                p.put("candidates",new ArrayList<>(ids));p.put("cards",cards);types.add("uuid");
                // CardView exposes the MDFC back-face ID. HumanPlayer normalizes it only off stack/battlefield.
                Map<String,String> aliases=new LinkedHashMap<>();
                if(game!=null) for(String id:new ArrayList<>(ids)) {
                    Card c=game.getCard(UUID.fromString(id));
                    if(c instanceof ModalDoubleFacedCard) {
                        ModalDoubleFacedCard m=(ModalDoubleFacedCard)c;
                        for(Card half:List.of(m.getLeftHalfCard(),m.getRightHalfCard())) {
                            Zone zone=game.getState().getZone(half.getId());
                            if(zone!=Zone.BATTLEFIELD && zone!=Zone.STACK) {
                                ids.add(half.getId().toString());aliases.put(half.getId().toString(),id);
                            }
                        }
                    }
                }
                p.put("responseAliases",aliases);
                if(!e.isRequired()) types.add("boolean");break;
            }
            case SELECT: {
                // Combat lists are highlights, not a substitute for engine validation of toggles.
                boolean attackers=options.containsKey(Constants.Option.POSSIBLE_ATTACKERS);
                boolean blockers=options.containsKey(Constants.Option.POSSIBLE_BLOCKERS);
                p.put("selectMode",attackers?"attackers":blockers?"blockers":"priority");
                types.addAll(Set.of("uuid","boolean","integer"));min=Integer.MIN_VALUE;max=Integer.MAX_VALUE;
                if((!attackers && !blockers) || options.containsKey(Constants.Option.SPECIAL_BUTTON)) {
                    types.add("string");strings=Set.of("special");
                }
                if(!attackers && !blockers) {types.add("mana");p.put("manaPlayerId",e.getPlayerId().toString());}
                break;
            }
            case PLAY_MANA:
                types.addAll(Set.of("uuid","boolean","mana","string"));strings=Set.of("special");
                p.put("manaPlayerId",e.getPlayerId().toString());break;
            case PLAY_X_MANA:
                types.addAll(Set.of("uuid","boolean","mana","integer"));min=0;max=Integer.MAX_VALUE;
                p.put("manaPlayerId",e.getPlayerId().toString());break;
            case AMOUNT: types.add("integer");break;
            case MULTI_AMOUNT: {
                types.add("integers");List<Object> rows=new ArrayList<>();
                if(Boolean.TRUE.equals(options.get("canCancel"))) types.add("boolean");
                if(e.getMessages()==null) throw unsupported(kind);
                for(MultiAmountMessage m:e.getMessages()) {
                    allocations.add(new long[]{m.min,m.max});
                    rows.add(Json.map("message",m.message,"min",m.min,"max",m.max,"defaultValue",m.defaultValue));
                }
                p.put("allocations",rows);break;
            }
            case CHOOSE_PILE: {
                types.add("boolean");
                List<Object> one=new ArrayList<>(),two=new ArrayList<>();
                if(e.getPile1()!=null) for(Card c:e.getPile1()) one.add(card(c,game));
                if(e.getPile2()!=null) for(Card c:e.getPile2()) two.add(card(c,game));
                p.put("pile1",one);p.put("pile2",two);break;
            }
            case PERSONAL_MESSAGE: throw new BridgeException("not_a_decision","Personal messages are not prompts");
            case DRAFT_PICK_CARD:
            case TOURNAMENT_CONSTRUCT: throw new BridgeException("format_not_supported","This client targets constructed Commander, not draft/tournaments");
            default: throw unsupported(kind);
        }
        return new DecisionSpec(kind,p,types,ids,strings,min,max,allocations);
    }
    private static Object card(Card c,Game game) {
        // Only called for cards explicitly supplied to this seat's query by XMage.
        return Json.parse(GSON.toJson(new CardView(c,game)));
    }
    private static Object abilitySource(Ability ability,UUID viewer,Game game) {
        if(game==null || ability.getSourceId()==null) return null;
        UUID id=ability.getSourceId();
        Card source=game.getPermanent(id);
        if(source==null) source=game.getCard(id);
        if(source==null || source.isFaceDown(game)) return null;
        Zone zone=game.getState().getZone(id);
        boolean visible=zone==Zone.BATTLEFIELD || zone==Zone.STACK || zone==Zone.GRAVEYARD
            || zone==Zone.EXILED || zone==Zone.COMMAND
            || (zone==Zone.HAND && viewer.equals(source.getOwnerId()));
        // An offered ability is not permission to reveal a private source or library card.
        return visible?card(source,game):null;
    }
    private static BridgeException unsupported(String kind) {
        return new BridgeException("unsupported_prompt","Unmapped XMage prompt: "+kind);
    }
    private static Object safe(Object o,int depth) {
        if(depth>32) throw new BridgeException("metadata_too_deep","Query metadata nesting exceeds limit");
        if(o==null || o instanceof String || o instanceof Boolean || o instanceof Integer || o instanceof Long) return o;
        if(o instanceof UUID || o instanceof Enum<?>) return o.toString();
        // Explicit client DTO only; never serialize an arbitrary engine Card/Ability/Game here.
        if(o instanceof CardView) return Json.parse(GSON.toJson(o));
        if(o instanceof Map<?,?>) {
            Map<String,Object> m=new LinkedHashMap<>();
            for(Map.Entry<?,?> e:((Map<?,?>)o).entrySet()) {
                Object key=e.getKey();
                if(!(key instanceof String) && !(key instanceof UUID) && !(key instanceof Enum<?>)) throw unsupported("metadata-key");
                m.put(key.toString(),safe(e.getValue(),depth+1));
            }
            return m;
        }
        if(o instanceof Collection<?>) {
            List<Object> a=new ArrayList<>();for(Object v:(Collection<?>)o)a.add(safe(v,depth+1));return a;
        }
        // No arbitrary Serializable objects or reflective object dumps at the wire boundary.
        throw new BridgeException("unsupported_metadata","XMage query contains an unmapped metadata type");
    }
}
