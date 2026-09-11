package io.magicmobile.xmage;

import io.magicmobile.core.*;
import mage.abilities.*;
import mage.abilities.common.EntersBattlefieldTriggeredAbility;
import mage.abilities.costs.mana.GenericManaCost;
import mage.abilities.effects.common.GainLifeEffect;
import mage.cards.*;
import mage.cards.b.BalaGedRecovery;
import mage.cards.basiclands.Forest;
import mage.cards.f.FireIce;
import mage.cards.g.GrizzlyBears;
import mage.cards.v.ValkiGodOfLies;
import mage.choices.*;
import mage.constants.*;
import mage.filter.FilterCard;
import mage.game.events.PlayerQueryEvent;
import mage.game.permanent.PermanentCard;
import mage.target.common.TargetCardInHand;
import mage.util.MultiAmountMessage;
import mage.view.CardView;

import java.io.Serializable;
import java.util.*;
import java.util.function.Function;

/**
 * Standalone tests against the pinned, compiled XMage classes, including HumanPlayer's real
 * choice loops via MobileHumanPlayer. No mock mage classes, game startup, Maven, or network.
 * From the package root after build_jvm.sh:
 * CP=$(cat build/runtime-classpath.txt)
 * javac --release 17 -cp "$CP" -d build/test-real \
 *   engine/xmage/src/main/java/io/magicmobile/xmage/QueryEncoder.java \
 *   engine/xmage/src/test/java/io/magicmobile/xmage/RealQueryTests.java
 * java -Xmx512m -cp "build/test-real:$CP" io.magicmobile.xmage.RealQueryTests
 */
public final class RealQueryTests {
    private static final UUID PLAYER=UUID.fromString("00000000-0000-0000-0000-000000000001");
    private static int passed,failed;

    public static void main(String[] args) {
        run("SELECT priority, attackers and blockers",RealQueryTests::selectVariants);
        run("target selection and deselection candidates",RealQueryTests::targetCandidates);
        run("real HumanPlayer multi-target toggle loop",RealQueryTests::targetLoop);
        run("mode UUID commands and transport order",RealQueryTests::modes);
        run("real HumanPlayer mode selection",RealQueryTests::modeLoop);
        run("integer and allocation bounds/cancellation",RealQueryTests::amounts);
        run("real HumanPlayer integer/allocation answers",RealQueryTests::amountLoops);
        run("mana source versus floating mana",RealQueryTests::mana);
        run("choice hints, sorting and special tokens",RealQueryTests::choices);
        run("real HumanPlayer remembered replacement choice",RealQueryTests::replacementLoop);
        run("split/MDFC ability labels and exact IDs",RealQueryTests::abilityFaces);
        run("MDFC target face mapping and zone boundaries",RealQueryTests::targetFaces);
        run("trigger ordering and metadata boundaries",RealQueryTests::orderingMetadata);
        run("real HumanPlayer library ordering",RealQueryTests::libraryOrder);
        System.out.println("RealQueryTests: "+passed+" passed, "+failed+" failed");
        if(failed!=0) throw new AssertionError("Real-upstream query tests failed");
    }

    private static void selectVariants() {
        DecisionSpec priority=encode(PlayerQueryEvent.selectEvent(PLAYER,"Play spells and abilities"));
        eq(priority.payload.get("selectMode"),"priority");
        accepts(priority,"uuid",UUID.randomUUID().toString());
        accepts(priority,"boolean",true);accepts(priority,"integer",0);accepts(priority,"string","special");
        accepts(priority,"mana",Json.map("playerId",PLAYER.toString(),"manaType","GREEN"));
        rejects(priority,"string","cast");
        UUID attacker=UUID.randomUUID();
        DecisionSpec attack=encode(PlayerQueryEvent.selectEvent(PLAYER,"Select attackers",
            options(Constants.Option.POSSIBLE_ATTACKERS,new ArrayList<>(List.of(attacker)),Constants.Option.SPECIAL_BUTTON,"All attack")));
        eq(attack.payload.get("selectMode"),"attackers");
        eq(option(attack,Constants.Option.POSSIBLE_ATTACKERS),List.of(attacker.toString()));
        eq(option(attack,Constants.Option.SPECIAL_BUTTON),"All attack");
        accepts(attack,"uuid",attacker.toString());accepts(attack,"string","special");accepts(attack,"integer",0);
        rejects(attack,"mana",Json.map("playerId",PLAYER.toString(),"manaType","GREEN"));
        DecisionSpec block=encode(PlayerQueryEvent.selectEvent(PLAYER,"Select blockers",
            options(Constants.Option.POSSIBLE_BLOCKERS,new ArrayList<>(List.of(attacker)))));
        eq(block.payload.get("selectMode"),"blockers");
        accepts(block,"uuid",attacker.toString());accepts(block,"boolean",false);accepts(block,"integer",0);
        rejects(block,"string","special");
    }

    private static void targetCandidates() {
        UUID available=UUID.randomUUID(),selected=UUID.randomUUID();
        DecisionSpec spec=encode(PlayerQueryEvent.targetEvent(PLAYER,"Choose targets",new LinkedHashSet<>(List.of(available)),false,
            options("chosenTargets",new LinkedHashSet<>(List.of(selected)),"possibleTargets",new LinkedHashSet<>(List.of(available)),
                "targetZone",Zone.HAND,"UI.right.btn.text","Done")));
        accepts(spec,"uuid",available.toString());accepts(spec,"uuid",selected.toString());accepts(spec,"boolean",false);
        eq(option(spec,"chosenTargets"),List.of(selected.toString()));
        eq(option(spec,"possibleTargets"),List.of(available.toString()));
        rejects(spec,"uuid",UUID.randomUUID().toString());
        DecisionSpec required=encode(PlayerQueryEvent.targetEvent(PLAYER,"Required",new HashSet<>(List.of(available)),true));
        rejects(required,"boolean",false);
    }

    private static void targetLoop() {
        try(Fixture f=new Fixture()) {
            Card a=f.bear(),b=f.bear();f.bear();
            TargetCardInHand target=new TargetCardInHand(1,3,new FilterCard());
            f.answer(s->answer("uuid",a.getId()));
            f.answer(s->{eq(option(s,"chosenTargets"),List.of(a.getId().toString()));return answer("uuid",a.getId());});
            f.answer(s->{eq(option(s,"chosenTargets"),List.of());return answer("uuid",b.getId());});
            f.answer(s->{eq(s.payload.get("required"),false);return answer("boolean",false);});
            check(f.player.choose(Outcome.Neutral,target,null,f.game),"HumanPlayer completed target choice");
            eq(target.getTargets(),List.of(b.getId()));f.drained();
        }
    }

    private static void modes() {
        UUID second=UUID.fromString("ffffffff-0000-0000-0000-000000000000");
        UUID first=UUID.fromString("11111111-0000-0000-0000-000000000000");
        Map<UUID,String> choices=new LinkedHashMap<>();
        choices.put(second,"1. Gain life");choices.put(first,"2. Draw");
        choices.put(Modes.CHOOSE_OPTION_DONE_ID,"Done");choices.put(Modes.CHOOSE_OPTION_CANCEL_ID,"Cancel");
        DecisionSpec spec=encode(PlayerQueryEvent.chooseModeEvent(PLAYER,"Choose mode",choices));
        for(UUID id:choices.keySet()) accepts(spec,"uuid",id.toString());
        rejects(spec,"boolean",false);rejects(spec,"uuid",UUID.randomUUID().toString());
        Map<String,Object> wire=Json.object(Json.parseObject(Json.write(spec.describe())).get("payload"));
        eq(wire.get("choiceOrder"),choices.keySet().stream().map(UUID::toString).toList());
    }

    private static void modeLoop() {
        try(Fixture f=new Fixture()) {
            Ability source=f.bear().getSpellAbility();
            Modes modes=new Modes();modes.clear();modes.clearSelectedModes();
            Mode one=new Mode(new GainLifeEffect(1)),two=new Mode(new GainLifeEffect(2));
            modes.put(one.getId(),one);modes.put(two.getId(),two);
            f.answer(s->{eq(s.kind,"CHOOSE_MODE");return answer("uuid",two.getId());});
            eq(f.player.chooseMode(modes,source,f.game).getId(),two.getId());
            modes.setMinModes(0);
            f.answer(s->answer("uuid",Modes.CHOOSE_OPTION_DONE_ID));
            eq(f.player.chooseMode(modes,source,f.game),null);
            f.answer(s->answer("uuid",Modes.CHOOSE_OPTION_CANCEL_ID));
            eq(f.player.chooseMode(modes,source,f.game),null);f.drained();
        }
    }

    private static List<MultiAmountMessage> rows() {
        return List.of(new MultiAmountMessage("First target",0,3,1),new MultiAmountMessage("Second target",1,4,2));
    }

    private static void amounts() {
        DecisionSpec amount=encode(PlayerQueryEvent.amountEvent(PLAYER,"How many?",-2,4));
        accepts(amount,"integer",-2);accepts(amount,"integer",4);rejects(amount,"integer",5);rejects(amount,"integer",-3);
        DecisionSpec multi=encode(PlayerQueryEvent.multiAmountEvent(PLAYER,rows(),3,3,options("title","Assign damage","header","Distribute")));
        accepts(multi,"integers",List.of(1,2));accepts(multi,"integers",List.of(0,3));
        rejects(multi,"integers",List.of(1,1));rejects(multi,"integers",List.of(3,0));rejects(multi,"integers",List.of(3));
        rejects(multi,"boolean",false);
        eq(Json.object(Json.array(multi.payload.get("allocations")).get(1)).get("defaultValue"),2);
        DecisionSpec cancel=encode(PlayerQueryEvent.multiAmountEvent(PLAYER,rows(),3,3,options("canCancel",true)));
        accepts(cancel,"boolean",false);
    }

    private static void amountLoops() {
        try(Fixture f=new Fixture()) {
            f.answer(s->answer("integer",2));
            eq(f.player.getAmount(0,4,"Choose amount",null,f.game),2);
            f.answer(s->answer("integers",List.of(1,2)));
            eq(f.player.getMultiAmountWithIndividualConstraints(Outcome.Neutral,rows(),3,3,MultiAmountType.DAMAGE,f.game),List.of(1,2));
            f.answer(s->{eq(option(s,"canCancel"),true);return answer("boolean",false);});
            eq(f.player.getMultiAmountWithIndividualConstraints(Outcome.Neutral,rows(),3,3,MultiAmountType.CHEAT_LANDS,f.game),null);
            f.drained();
        }
    }

    private static void mana() {
        try(Fixture f=new Fixture()) {
            Card spell=f.bear();
            Card land=new Forest(f.player.getId(),info("Forest","LEA","298"));
            f.game.loadCards(new HashSet<>(List.of(land)),f.player.getId());
            PermanentCard permanent=new PermanentCard(land,f.player.getId(),f.game);
            f.game.getBattlefield().addPermanent(permanent);f.game.setZone(land.getId(),Zone.BATTLEFIELD);
            UUID source=land.getId();
            DecisionSpec spec=QueryEncoder.encode(PlayerQueryEvent.playManaEvent(f.player.getId(),"Pay {1}",options()),f.game);
            accepts(spec,"uuid",source.toString());
            accepts(spec,"mana",Json.map("playerId",f.player.getId().toString(),"manaType","GREEN"));
            accepts(spec,"boolean",false);accepts(spec,"string","special");rejects(spec,"integer",1);
            eq(spec.payload.get("manaPlayerId"),f.player.getId().toString());
            f.answer(s->answer("uuid",source));
            check(f.player.playMana(spell.getSpellAbility(),new GenericManaCost(1),"{1}",f.game),"mana source response handled");
            check(permanent.isTapped(),"real Forest mana ability tapped its source");
            eq(f.player.getManaPool().get(ManaType.GREEN),1);
            f.answer(s->answer("mana",Json.map("playerId",f.player.getId().toString(),"manaType","GREEN")));
            check(f.player.playMana(null,new GenericManaCost(1),"{1}",f.game),"floating mana response handled");
            eq(f.player.getManaPool().getUnlockedManaType(),ManaType.GREEN);
            f.answer(s->answer("boolean",false));
            check(!f.player.playMana(null,new GenericManaCost(1),"{1}",f.game),"mana cancellation handled");f.drained();
            // PLAY_X_MANA's factory exists, but the pinned HumanPlayer never emits it.
            DecisionSpec x=encode(PlayerQueryEvent.playXManaEvent(PLAYER,"Pay X"));
            accepts(x,"integer",5);rejects(x,"integer",-1);accepts(x,"uuid",source.toString());
        }
    }

    private static void choices() {
        ChoiceImpl choice=new ChoiceImpl(true,ChoiceHintType.GAME_OBJECT);
        choice.setMessage("Choose effect");choice.setSubMessage("Resolve first");choice.setSearchText("effect");
        choice.withItem("z","Last label",2,ChoiceHintType.GAME_OBJECT,PLAYER.toString());
        choice.withItem("a","First label",1,ChoiceHintType.TEXT,"Rules hint");
        choice.setSpecial(true,false,"Remember answer","Use next time");
        DecisionSpec spec=encode(PlayerQueryEvent.chooseChoiceEvent(PLAYER,choice));
        accepts(spec,"string","z");accepts(spec,"string","#z");rejects(spec,"string","#missing");rejects(spec,"string","");
        eq(spec.payload.get("choiceOrder"),List.of("z","a"));eq(spec.payload.get("subMessage"),"Resolve first");
        eq(spec.payload.get("searchText"),"effect");eq(spec.payload.get("sortEnabled"),true);
        eq(Json.object(spec.payload.get("sortData")).get("z"),2);
        eq(Json.object(spec.payload.get("hintData")).get("a"),List.of("TEXT","Rules hint"));
        eq(spec.payload.get("specialHint"),"Use next time");
        eq(Json.object(spec.payload.get("specialChoices")).get("#z"),"Last label");
        choice.setSpecial(false,false,"","");rejects(encode(PlayerQueryEvent.chooseChoiceEvent(PLAYER,choice)),"string","#z");
        ChoiceImpl optional=new ChoiceImpl(false);optional.setChoices(new LinkedHashSet<>(List.of("Red","Blue")));
        accepts(encode(PlayerQueryEvent.chooseChoiceEvent(PLAYER,optional)),"string","");
        choice.setSpecial(true,true,"Choose nothing","Empty is distinct from cancel");
        spec=encode(PlayerQueryEvent.chooseChoiceEvent(PLAYER,choice));
        eq(spec.payload.get("specialCanBeEmpty"),true);rejects(spec,"string","#");
        // This metadata must survive even though core currently cannot represent the upstream null answer.
    }

    private static void replacementLoop() {
        try(Fixture f=new Fixture()) {
            Map<String,String> effects=new LinkedHashMap<>();effects.put("first","Gain life");effects.put("second","Draw a card");
            f.answer(s->{eq(s.payload.get("specialEnabled"),true);return answer("string","#second");});
            eq(f.player.chooseReplacementEffect(effects,Map.of(),f.game),1);
            // The second call must use HumanPlayer's remembered effect without another prompt.
            eq(f.player.chooseReplacementEffect(effects,Map.of(),f.game),1);f.drained();
        }
    }

    private static void abilityFaces() {
        FireIce split=new FireIce(PLAYER,info("Fire // Ice","APC","128"));
        checkAbilityFaces(split.getLeftHalfCard(),split.getRightHalfCard(),split.getName(),"Fire","Ice");
        ValkiGodOfLies modal=new ValkiGodOfLies(PLAYER,info("Valki, God of Lies","KHM","114"));
        checkAbilityFaces(modal.getLeftHalfCard(),modal.getRightHalfCard(),modal.getName(),"Valki","Tibalt");
    }

    private static void checkAbilityFaces(Card left,Card right,String name,String leftName,String rightName) {
        List<ActivatedAbility> abilities=List.of(left.getSpellAbility(),right.getSpellAbility());
        DecisionSpec spec=encode(PlayerQueryEvent.chooseAbilityEvent(PLAYER,"Choose spell",name,abilities));
        List<Object> rows=Json.array(spec.payload.get("abilities"));eq(rows.size(),2);
        check(Json.requiredString(Json.object(rows.get(0)),"label").contains("Cast "+leftName),"left cast label");
        check(Json.requiredString(Json.object(rows.get(1)),"label").contains("Cast "+rightName),"right cast label");
        for(int i=0;i<2;i++) {
            eq(Json.object(rows.get(i)).get("id"),abilities.get(i).getId().toString());
            eq(Json.object(rows.get(i)).get("sourceId"),abilities.get(i).getSourceId().toString());
            accepts(spec,"uuid",abilities.get(i).getId().toString());
        }
        rejects(spec,"uuid",left.getId().toString());
    }

    private static void targetFaces() {
        try(Fixture f=new Fixture()) {
            BalaGedRecovery card=new BalaGedRecovery(f.player.getId(),info("Bala Ged Recovery","ZNR","180"));
            f.hand(card);f.bear();
            DecisionSpec spec=QueryEncoder.encode(PlayerQueryEvent.targetEvent(f.player.getId(),"Choose",new CardsImpl(card),true,options()),f.game);
            UUID back=card.getRightHalfCard().getId();
            accepts(spec,"uuid",back.toString());
            eq(Json.object(spec.payload.get("responseAliases")).get(back.toString()),card.getId().toString());
            Map<String,Object> view=Json.object(Json.array(spec.payload.get("cards")).get(0));
            eq(Json.object(view.get("secondCardFace")).get("id"),back.toString());
            TargetCardInHand target=new TargetCardInHand();
            f.answer(s->answer("uuid",back));
            check(f.player.choose(Outcome.Neutral,target,null,f.game),"MDFC face selected in HumanPlayer");
            eq(target.getFirstTarget(),card.getId());f.drained();
            for(Zone zone:List.of(Zone.BATTLEFIELD,Zone.STACK)) {
                f.game.setZone(back,zone);
                spec=QueryEncoder.encode(PlayerQueryEvent.targetEvent(f.player.getId(),"Choose",new HashSet<>(List.of(card.getId())),true),f.game);
                rejects(spec,"uuid",back.toString());
            }
            FireIce split=new FireIce(f.player.getId(),info("Fire // Ice","APC","128"));f.hand(split);
            spec=QueryEncoder.encode(PlayerQueryEvent.targetEvent(f.player.getId(),"Choose",new CardsImpl(split),true,options()),f.game);
            accepts(spec,"uuid",split.getId().toString());rejects(spec,"uuid",split.getRightHalfCard().getId().toString());
        }
    }

    private static void orderingMetadata() {
        EntersBattlefieldTriggeredAbility trigger=new EntersBattlefieldTriggeredAbility(new GainLifeEffect(1));
        trigger.setSourceId(PLAYER);trigger.setControllerId(PLAYER);
        DecisionSpec spec=encode(PlayerQueryEvent.targetEvent(PLAYER,"Pick triggered ability (goes to the stack first)",List.of(trigger)));
        eq(spec.kind,"PICK_ABILITY");eq(spec.payload.get("message"),"Pick triggered ability (goes to the stack first)");
        Map<String,Object> row=Json.object(Json.array(spec.payload.get("abilities")).get(0));
        eq(row.get("originalId"),trigger.getOriginalId().toString());accepts(spec,"uuid",trigger.getId().toString());
        rejects(spec,"boolean",false);
        Card card=new GrizzlyBears(PLAYER,info("Grizzly Bears","LEA","202"));
        CardView view=new CardView(card);
        spec=encode(PlayerQueryEvent.targetEvent(PLAYER,"Last one chosen will be topmost",new HashSet<>(List.of(card.getId())),true,
            options("secondMessage","Library order","hintText","Keep this order","orderedViews",new ArrayList<>(List.of(view)))));
        eq(option(spec,"secondMessage"),"Library order");eq(option(spec,"hintText"),"Keep this order");
        eq(Json.object(Json.array(option(spec,"orderedViews")).get(0)).get("id"),card.getId().toString());
        // Arbitrary engine objects must fail explicitly, never be dropped or serialized reflectively.
        expectCode("unsupported_metadata",()->encode(PlayerQueryEvent.selectEvent(PLAYER,"Bad metadata",options("rawCard",card))));
    }

    private static void libraryOrder() {
        try(Fixture f=new Fixture()) {
            Card a=f.bear(),b=f.bear(),c=f.bear();
            Cards cards=new CardsImpl();cards.add(a);cards.add(b);cards.add(c);
            f.answer(s->{check(Json.requiredString(s.payload,"message").contains("last one chosen will be topmost"),"upstream ordering instruction retained");return answer("uuid",b.getId());});
            f.answer(s->answer("uuid",a.getId()));
            check(f.player.putCardsOnTopOfLibrary(cards,f.game,null,true),"real library ordering finished");
            eq(f.player.getLibrary().getCardList(),List.of(c.getId(),a.getId(),b.getId()));f.drained();
        }
    }

    private static final class Fixture implements AutoCloseable {
        final MobileCommanderGame game=new MobileCommanderGame();
        final MobileHumanPlayer player=new MobileHumanPlayer("Query test player");
        final Deque<Function<DecisionSpec,Map<String,Object>>> replies=new ArrayDeque<>();
        Fixture() {
            game.getState().addPlayer(player);
            player.updateRange(game);
            game.addPlayerQueryEventListener(event->{
                if(event.getQueryType()==PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) return;
                check(!replies.isEmpty(),"Unexpected/repeated prompt: "+event.getQueryType()+" "+event.getMessage());
                DecisionSpec spec=QueryEncoder.encode(event,game);
                player.offer(spec.validate(replies.remove().apply(spec)));
            });
        }
        Card bear() {Card c=new GrizzlyBears(player.getId(),info("Grizzly Bears","LEA","202"));hand(c);return c;}
        void hand(Card card) {game.loadCards(new HashSet<>(List.of(card)),player.getId());card.setZone(Zone.HAND,game);player.getHand().add(card);}
        void answer(Function<DecisionSpec,Map<String,Object>> reply) {replies.add(reply);}
        void drained() {check(replies.isEmpty(),"All scripted real queries consumed");}
        @Override public void close() {player.closeChannel();}
    }

    private static CardSetInfo info(String name,String set,String number) {return new CardSetInfo(name,set,number,Rarity.COMMON);}
    private static DecisionSpec encode(PlayerQueryEvent event) {return QueryEncoder.encode(event,null);}
    private static Map<String,Serializable> options(Object... pairs) {
        Map<String,Serializable> result=new LinkedHashMap<>();
        for(int i=0;i<pairs.length;i+=2) result.put((String)pairs[i],(Serializable)pairs[i+1]);
        return result;
    }
    private static Object option(DecisionSpec spec,String key) {return Json.object(spec.payload.get("options")).get(key);}
    private static Map<String,Object> answer(String kind,Object value) {return Json.map("kind",kind,"value",value instanceof UUID?value.toString():value);}
    private static void accepts(DecisionSpec spec,String kind,Object value) {eq(spec.validate(answer(kind,value)),answer(kind,value));}
    private static void rejects(DecisionSpec spec,String kind,Object value) {expectCode("invalid_response",()->spec.validate(answer(kind,value)));}
    private static void expectCode(String code,Runnable action) {
        try {action.run();} catch(BridgeException e) {eq(e.code(),code);return;}
        throw new AssertionError("Expected "+code);
    }
    private static void check(boolean condition,String message) {if(!condition) throw new AssertionError(message);}
    private static void eq(Object actual,Object expected) {if(!Objects.equals(actual,expected)) throw new AssertionError("Expected "+expected+", got "+actual);}
    private static void run(String name,Runnable test) {
        try {test.run();passed++;System.out.println("PASS "+name);}
        catch(Throwable e) {failed++;System.err.println("FAIL "+name);e.printStackTrace();}
    }
}
