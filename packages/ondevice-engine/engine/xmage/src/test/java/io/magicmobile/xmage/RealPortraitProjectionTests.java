package io.magicmobile.xmage;

import io.magicmobile.core.Json;
import com.google.gson.Gson;
import io.magicmobile.generated.GeneratedCardFactory;
import io.magicmobile.generated.GeneratedSetRegistry;
import mage.Mana;
import mage.ObjectColor;
import mage.abilities.SpellAbility;
import mage.cards.Card;
import mage.cards.CardSetInfo;
import mage.cards.ExpansionSet;
import mage.cards.MobileCardFactories;
import mage.cards.Sets;
import mage.cards.d.DelverOfSecrets;
import mage.cards.decks.Deck;
import mage.cards.i.IsamaruHoundOfKonda;
import mage.cards.r.RaiseTheAlarm;
import mage.constants.Rarity;
import mage.constants.SubType;
import mage.constants.Zone;
import mage.game.Game;
import mage.game.permanent.PermanentToken;
import mage.game.permanent.token.Token;
import mage.game.events.PlayerQueryEvent;
import mage.game.turn.PreCombatMainPhase;
import mage.game.turn.PreCombatMainStep;
import mage.view.GameView;
import mage.view.SimpleCardView;
import mage.view.SimpleCardsView;
import mage.util.functions.CopyTokenFunction;
import mage.watchers.common.CommanderInfoWatcher;
import mage.watchers.common.CommanderPlaysCountWatcher;

import java.util.*;

/** Real pinned upstream actions on seeded fixtures; not native, full-match, or device evidence. */
public final class RealPortraitProjectionTests {
    public static void main(String[] args) {
        MobileCardFactories.install(GeneratedCardFactory::create);
        GeneratedSetRegistry.install();
        Map<String,Runnable> tests = new LinkedHashMap<>();
        tests.put("stack", RealPortraitProjectionTests::stackOrder);
        tests.put("commanders", RealPortraitProjectionTests::commanders);
        tests.put("unknown", RealPortraitProjectionTests::unknownWatchers);
        tests.put("outcome", RealPortraitProjectionTests::outcome);
        tests.put("named-exiles", RealPortraitProjectionTests::namedExiles);
        tests.put("printing-authority", RealPortraitProjectionTests::printingAuthority);
        tests.put("static-faces", RealPortraitProjectionTests::staticFaces);
        tests.put("control-presentation", RealPortraitProjectionTests::controlPresentation);
        tests.put("revealed-companion", RealPortraitProjectionTests::revealedCompanion);
        tests.put("copy-token-art", RealPortraitProjectionTests::copyTokenArtworkIdentity);
        int passed = 0;
        for (Map.Entry<String,Runnable> test : tests.entrySet()) {
            if (args.length > 0 && !args[0].equals(test.getKey())) continue;
            try {
                test.getValue().run();
                passed++;
                System.out.println("PASS " + test.getKey());
            } catch (RuntimeException | AssertionError e) {
                System.err.println("FAIL " + test.getKey());
                throw e;
            }
        }
        System.out.println("RealPortraitProjectionTests: " + passed + " passed");
    }

    private static void stackOrder() {
        try (Fixture f = new Fixture()) {
            Card first = f.instant(), second = f.instant();
            f.cast(first, Zone.HAND, 2);
            UUID bottom = f.game.getStack().peek().getId();
            f.cast(second, Zone.HAND, 2);
            UUID top = f.game.getStack().peek().getId();
            check(!top.equals(bottom), "two distinct real stack objects");
            eq(f.game.getStack().size(), 2);
            Game copied = f.game.copy();
            for (Map.Entry<String,MobileHumanPlayer> seat : f.seats.entrySet()) {
                GameView expected = new GameView(copied.getState(), copied, seat.getValue().getId(), null);
                List<String> order = expected.getStack().keySet().stream().map(UUID::toString).toList();
                eq(order, List.of(top.toString(), bottom.toString()));
                Map<String,Object> snapshot = f.snapshot(seat.getKey());
                eq(snapshot.get("schema"), "xmage-gameview-v1");
                eq(snapshot.get("enginePlayerId"), seat.getValue().getId().toString());
                check(snapshot.containsKey("controlledPlayerViews"), "existing controlled view retained");
                eq(snapshot.get("stackOrder"), order);
                eq(Json.object(Json.object(snapshot.get("gameView")).get("stack")).keySet(), new HashSet<>(order));
            }
            f.game.getStack().resolve(f.game);
            eq(f.snapshot("owner").get("stackOrder"), List.of(bottom.toString()));
            f.game.getStack().resolve(f.game);
            eq(f.snapshot("owner").get("stackOrder"), List.of());
        }
    }
    private static void copyTokenArtworkIdentity() {
        try (Fixture f = new Fixture()) {
            Card source = f.commander();
            Token token = CopyTokenFunction.createTokenCopy(source, f.game);
            PermanentToken permanent = new PermanentToken(token, f.owner.getId(), f.game);
            Map<String,Object> visible = Json.map("name", "Isamaru, Hound of Konda",
                "displayName", "Isamaru, Hound of Konda", "isToken", true);
            eq(ViewProjector.copySourceArtworkName(visible, permanent, f.game), "Isamaru, Hound of Konda");
            visible.put("hideInfo", true);
            eq(ViewProjector.copySourceArtworkName(visible, permanent, f.game), null);
            visible.remove("hideInfo"); visible.put("displayName", "Face-down card");
            eq(ViewProjector.copySourceArtworkName(visible, permanent, f.game), null);
            visible.put("displayName", "Isamaru, Hound of Konda"); visible.put("isToken", false);
            eq(ViewProjector.copySourceArtworkName(visible, permanent, f.game), null);
            visible.put("isToken", true); token.setCopySourceCard(null);
            PermanentToken plain = new PermanentToken(token, f.owner.getId(), f.game);
            eq(ViewProjector.copySourceArtworkName(visible, plain, f.game), null);

            // Real seat-scoped GameView -> projector path, with Scarab-style
            // copiable exceptions. The copied card's art remains Isamaru while
            // live type/color/P/T belong to the 4/4 black Zombie token.
            Token zombie = CopyTokenFunction.createTokenCopy(source, f.game);
            zombie.removeAllCreatureTypes(); zombie.addSubType(SubType.ZOMBIE);
            zombie.setPower(4); zombie.setToughness(4); zombie.setColor(ObjectColor.BLACK);
            check(zombie.putOntoBattlefield(1, f.game, source.getSpellAbility(), f.owner.getId()), "copy token enters");
            UUID tokenId = zombie.getLastAddedTokenIds().get(0);
            for (String seat : f.seats.keySet()) {
                Map<String,Object> projected = Json.object(f.snapshot(seat).get("gameView"));
                Map<String,Object> player = Json.array(projected.get("players")).stream().map(Json::object)
                    .filter(p -> f.owner.getId().toString().equals(p.get("playerId"))).findFirst().orElseThrow();
                Map<String,Object> shown = Json.object(Json.object(player.get("battlefield")).get(tokenId.toString()));
                eq(shown.get("copy"), true);
                eq(shown.get("isToken"), true);
                eq(shown.get("copySourceArtworkName"), "Isamaru, Hound of Konda");
                eq(shown.get("power"), "4"); eq(shown.get("toughness"), "4");
                check(Json.array(shown.get("subTypes")).contains("ZOMBIE"), "live Zombie type retained");
                Map<String,Object> art=Json.object(shown.get("tokenArtwork"));
                eq(art.get("name"), "Isamaru, Hound of Konda");
                eq(art.get("power"), "4"); eq(art.get("toughness"), "4");
                check(Json.array(art.get("subTypes")).contains("ZOMBIE"), "base token type retained");
                Map<String,Object> baseColor=Json.object(art.get("color"));
                eq(baseColor.get("black"), true); eq(baseColor.get("white"), false);
            }
        }
    }

    private static void commanders() {
        try (Fixture f = new Fixture()) {
            // Seed two commander definitions, as in RealCommanderRulesTests; no partner deck legality claim.
            Card first = f.commander(), second = f.commander();
            for (Card card : List.of(first, second)) f.stats(card, 0, 0, Map.of());
            f.cast(first, Zone.COMMAND, 1);
            f.game.getStack().resolve(f.game);
            f.damage(first, 7, true);
            f.damage(first, 3, false); // Noncombat damage is not commander damage.
            f.returnToCommand(first);
            f.cast(first, Zone.COMMAND, 3);
            f.game.getStack().resolve(f.game);
            f.damage(first, 4, true);
            f.returnToCommand(first);
            f.cast(second, Zone.COMMAND, 1);
            f.game.getStack().resolve(f.game);
            f.damage(second, 5, true);
            f.stats(first, 2, 4, Map.of(f.opponent.getId().toString(), 11));
            f.stats(second, 1, 2, Map.of(f.opponent.getId().toString(), 5));
            // The commander definition remains public in a hidden zone; no location/card DTO is added.
            f.owner.offer(Json.map("kind", "boolean", "value", false));
            check(f.game.getPermanent(second.getId()).moveToZone(Zone.HAND, null, f.game, true), "return to hand");
            Map<String,Object> frozen = f.snapshot("opponent");
            f.cast(second, Zone.HAND, 1);
            f.game.getStack().resolve(f.game);
            f.damage(second, 2, true);
            f.stats(second, 1, 2, Map.of(f.opponent.getId().toString(), 7));
            eq(Json.object(Json.object(Json.object(frozen.get("commanders")).get(second.getId().toString()))
                    .get("damageToPlayers")).get(f.opponent.getId().toString()), 5L);
            Card secret = f.instant();
            Map<String,Object> projected = f.snapshot("opponent");
            eq(Json.object(projected.get("commanders")).keySet(), Set.of(first.getId().toString(), second.getId().toString()));
            check(!Json.write(projected).contains(secret.getId().toString()), "ordinary hidden cards never become commander metadata");
        }
    }

    private static void unknownWatchers() {
        try (Fixture f = new Fixture(false)) {
            Card card = f.commander();
            // The game constructor installs the count watcher; remove only it to exercise absence.
            try {
                java.lang.reflect.Field field = mage.game.GameState.class.getDeclaredField("watchers");
                field.setAccessible(true);
                ((Map<?,?>) field.get(f.game.getState())).remove(new CommanderPlaysCountWatcher().getKey());
            } catch (ReflectiveOperationException e) { throw new AssertionError(e); }
            for (String seat : f.seats.keySet()) {
                Map<String,Object> info = Json.object(Json.object(f.snapshot(seat).get("commanders")).get(card.getId().toString()));
                eq(info, Json.map("ownerPlayerId", f.owner.getId().toString(), "name", "Isamaru, Hound of Konda"));
            }
        }
    }

    private static void outcome() {
        try (Fixture f = new Fixture()) {
            f.outcome(false, List.of());
            f.opponent.lost(f.game);
            check(f.game.checkIfGameIsOver(), "real game-over check");
            check(f.owner.hasWon() && !f.opponent.hasWon() && f.game.hasEnded(), "upstream winner established");
            f.outcome(true, List.of(f.owner.getId().toString()));
        }
        try (Fixture f = new Fixture()) {
            f.owner.lost(f.game);
            check(f.game.checkIfGameIsOver(), "opposite seat wins");
            f.outcome(true, List.of(f.opponent.getId().toString()));
        }
        try (Fixture f = new Fixture()) {
            f.game.end();
            f.outcome(true, List.of()); // Ended alone is not evidence of any winner or draw.
        }
    }

    private static void namedExiles() {
        try (Fixture f = new Fixture()) {
            UUID group = UUID.randomUUID(), empty = UUID.randomUUID();
            Card publicCard = f.instant(), hidden = f.instant();
            f.game.getExile().createZone(empty, "Empty group");
            for (Card card : List.of(publicCard, hidden)) {
                f.owner.getHand().remove(card.getId()); card.setZone(Zone.EXILED, f.game);
                f.game.getExile().add(group, "Named group", card);
            }
            hidden.setFaceDown(true, f.game);
            for (String seat : f.seats.keySet()) {
                GameView original = new GameView(f.game.getState(), f.game, f.seats.get(seat).getId(), null);
                List<Object> expected = new ArrayList<>();
                original.getExile().forEach(exile -> expected.add(Json.map("id", exile.getId().toString(),
                        "name", exile.getName(), "cards", Json.parseObject(new Gson().toJson(exile)))));
                eq(f.snapshot(seat).get("namedExiles"), expected);
            }
            Map<String,Object> groupView = Json.array(f.snapshot("opponent").get("namedExiles")).stream()
                    .map(Json::object).filter(v -> v.get("id").equals(group.toString())).findFirst().orElseThrow();
            Map<String,Object> cards = Json.object(groupView.get("cards"));
            eq(Json.object(cards.get(publicCard.getId().toString())).get("name"), "Raise the Alarm");
            Map<String,Object> redacted = Json.object(cards.get(hidden.getId().toString()));
            check(!"MRD".equals(redacted.get("expansionSetCode")), "real printing stays redacted");
            check(!redacted.containsKey("secondCardFace"), "named exile preserves nested face redaction");
        }
    }

    private static void printingAuthority() {
        UUID id = UUID.randomUUID();
        SimpleCardView known = new SimpleCardView(id, "MRD", "16", false);
        known.setChoosable(true); known.setSelected(true);
        Map<String,Object> printed = print(known);
        eq(printed.get("name"), "Raise the Alarm"); eq(printed.get("id"), id.toString());
        eq(printed.get("isChoosable"), true); eq(printed.get("isSelected"), true);
        check(!Json.array(printed.get("rules")).isEmpty(), "static printed rules available");
        for (SimpleCardView unknown : List.of(new SimpleCardView(id, "", "16", false),
                new SimpleCardView(id, "MRD", "", false), new SimpleCardView(id, "missing-set", "16", false),
                new SimpleCardView(id, "MRD", "missing-number", false)))
            eq(print(unknown), Json.parseObject(new Gson().toJson(unknown)));
        ExpansionSet set = Sets.getInstance().get("MRD");
        ExpansionSet.SetCardInfo info = set.getSetCardInfo().stream().filter(c -> c.getCardNumber().equals("16")).findFirst().orElseThrow();
        set.getSetCardInfo().add(info); // Test-only catalogue ambiguity; restore before any other test.
        try { eq(print(known), Json.parseObject(new Gson().toJson(known))); }
        finally { set.getSetCardInfo().remove(set.getSetCardInfo().size() - 1); }
    }

    private static Map<String,Object> print(SimpleCardView simple) {
        SimpleCardsView cards = new SimpleCardsView(); cards.put(simple.getId(), simple);
        try {
            java.lang.reflect.Method method = ViewProjector.class.getDeclaredMethod("printedCards", SimpleCardsView.class);
            method.setAccessible(true);
            return Json.object(Json.object(method.invoke(null, cards)).get(simple.getId().toString()));
        } catch (ReflectiveOperationException e) { throw new AssertionError(e); }
    }

    private static void staticFaces() {
        try (Fixture f = new Fixture()) {
            Card delver = new DelverOfSecrets(f.owner.getId(), new CardSetInfo("Delver of Secrets", "ISD", "51", Rarity.COMMON));
            f.hand(delver);
            delver.addInfo("PRIVATE_RUNTIME", "Private runtime marker", f.game);
            Card liveBack = ((mage.cards.DoubleFacedCard) delver).getRightHalfCard();
            liveBack.setName("Private live back face");
            eq(liveBack.getName(), "Private live back face");
            delver.setFaceDown(true, f.game);
            f.game.getState().getLookedAt(f.owner.getId()).add("Authorized inspection", delver);
            Map<String,Object> snapshot = f.snapshot("owner");
            Map<String,Object> presentation = Json.object(Json.object(Json.object(snapshot.get("authorizedLookedAt"))
                    .get("Authorized inspection")).get(delver.getId().toString()));
            eq(presentation.get("name"), "Delver of Secrets"); eq(presentation.get("faceDown"), false);
            eq(Json.object(presentation.get("secondCardFace")).get("name"), "Insectile Aberration");
            check(!Json.write(presentation).contains("Private runtime marker"), "runtime info excluded recursively");
            check(!Json.write(presentation).contains("Private live back face"), "nested face uses compiled printing, not live card");
            check(!Json.write(presentation).contains(f.owner.getId().toString()), "no live owner identity in static presentation");
            eq(Json.object(f.snapshot("opponent").get("authorizedLookedAt")), Map.of());
            f.game.getState().getLookedAt(f.owner.getId()).reset();
            eq(Json.object(f.snapshot("owner").get("authorizedLookedAt")), Map.of());
        }
    }

    private static void controlPresentation() {
        try (Fixture f = new Fixture(true, true)) {
            MobileHumanPlayer observer = f.seats.get("observer");
            Card secret = new RaiseTheAlarm(f.opponent.getId(), new CardSetInfo("Raise the Alarm", "MRD", "16", Rarity.COMMON));
            f.hand(secret, f.opponent);
            for (String seat : f.seats.keySet()) eq(Json.object(f.snapshot(seat).get("authorizedOpponentHands")), Map.of());
            check(f.owner.controlPlayersTurn(f.game, f.opponent.getId(), "test"), "real turn control");
            Map<String,Object> during = Json.object(f.snapshot("owner").get("authorizedOpponentHands"));
            eq(during.keySet(), Set.of(f.opponent.getName()));
            Map<String,Object> cards = Json.object(during.get(f.opponent.getName()));
            eq(cards.keySet(), Set.of(secret.getId().toString()));
            eq(Json.object(cards.get(secret.getId().toString())).get("name"), "Raise the Alarm");
            eq(Json.object(f.snapshot("observer").get("authorizedOpponentHands")), Map.of());
            check(observer.controlPlayersTurn(f.game, f.opponent.getId(), "test"), "replace controller");
            check(f.owner.getPlayersUnderYourControl().contains(f.opponent.getId()), "upstream stale reverse set");
            eq(Json.object(f.snapshot("owner").get("authorizedOpponentHands")), Map.of());
            eq(Json.object(f.snapshot("observer").get("authorizedOpponentHands")), during);
            f.opponent.setGameUnderYourControl(f.game, true);
            for (String seat : f.seats.keySet()) eq(Json.object(f.snapshot(seat).get("authorizedOpponentHands")), Map.of());
        }
    }

    private static void revealedCompanion() {
        try (Fixture f = new Fixture()) {
            Card revealed = f.instant();
            Card companion = new mage.cards.l.LurrusOfTheDreamDen(f.owner.getId(),
                    new CardSetInfo("Lurrus of the Dream-Den", "IKO", "226", Rarity.RARE));
            f.game.loadCards(new HashSet<>(List.of(companion)), f.owner.getId());
            companion.setZone(Zone.OUTSIDE, f.game); f.owner.getSideboard().add(companion);
            f.game.getState().getRevealed().put("Public reveal", new mage.cards.CardsImpl(revealed));
            // Seed an announced real companion; this checks projection, not companion deck legality.
            f.game.getState().getCompanion().put("Announced companion", new mage.cards.CardsImpl(companion));
            for (String seat : f.seats.keySet()) {
                GameView original = new GameView(f.game.getState(), f.game, f.seats.get(seat).getId(), null);
                Map<String,Object> expected = Json.parseObject(original.toJson());
                Map<String,Object> actual = Json.object(f.snapshot(seat).get("gameView"));
                for (String field : List.of("revealed", "companion")) {
                    eq(actual.get(field), expected.get(field));
                    Map<String,Object> group = Json.object(Json.array(actual.get(field)).get(0));
                    String id = (field.equals("revealed") ? revealed : companion).getId().toString();
                    Map<String,Object> card = Json.object(Json.object(group.get("cards")).get(id));
                    eq(card.get("name"), field.equals("revealed") ? "Raise the Alarm" : "Lurrus of the Dream-Den");
                    check(!Json.array(card.get("rules")).isEmpty(), "original full printed rules retained");
                }
            }
            f.owner.getSideboard().remove(companion.getId());
            companion.setZone(Zone.HAND, f.game); f.owner.getHand().add(companion);
            f.game.getState().getRevealed().clear();
            for (String seat : f.seats.keySet()) {
                Map<String,Object> view = Json.object(f.snapshot(seat).get("gameView"));
                eq(view.get("companion"), List.of()); eq(view.get("revealed"), List.of());
            }
        }
    }

    private static final class Fixture implements AutoCloseable {
        final MobileCommanderGame game;
        final MobileHumanPlayer owner = new MobileHumanPlayer("Owner");
        final MobileHumanPlayer opponent = new MobileHumanPlayer("Opponent");
        final Map<String,MobileHumanPlayer> seats = new LinkedHashMap<>();
        final boolean initializeWatchers;

        Fixture() { this(true, false); }
        Fixture(boolean initializeWatchers) { this(initializeWatchers, false); }
        Fixture(boolean initializeWatchers, boolean observer) {
            this.initializeWatchers = initializeWatchers;
            seats.put("owner", owner); seats.put("opponent", opponent);
            if (observer) seats.put("observer", new MobileHumanPlayer("Observer"));
            MobileCommanderMatch match = new MobileCommanderMatch();
            for (MobileHumanPlayer player : seats.values()) match.addPlayer(player, new Deck());
            match.startMatch();
            try { match.startGame(); }
            catch (mage.game.GameException e) { throw new AssertionError("match fixture initialization", e); }
            game = (MobileCommanderGame) match.getGame();
            for (MobileHumanPlayer player : seats.values()) {
                player.updateRange(game);
                player.setLife(40, game, null);
            }
            game.getState().setActivePlayerId(owner.getId());
            game.getState().setPriorityPlayerId(owner.getId());
            PreCombatMainPhase phase = new PreCombatMainPhase();
            phase.setStep(new PreCombatMainStep()); game.getTurn().setPhase(phase);
            if (initializeWatchers) game.getState().addWatcher(new CommanderPlaysCountWatcher());
            owner.getManaPool().setAutoPayment(true);
            owner.getManaPool().setAutoPaymentRestricted(false);
            game.addPlayerQueryEventListener(event -> {
                if (event.getQueryType() == PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) return;
                check(event.getQueryType() == PlayerQueryEvent.QueryType.ASK
                        && event.getMessage().contains("command zone"), "unexpected query: " + event.getMessage());
            });
        }
        Card commander() {
            Card card = new IsamaruHoundOfKonda(owner.getId(), new CardSetInfo("Isamaru, Hound of Konda", "CHK", "19", Rarity.RARE));
            hand(card); game.addCommander(card, owner);
            if (initializeWatchers) {
                game.initCommander(card, owner);
                check(game.getState().getWatcher(CommanderInfoWatcher.class, card.getId()) != null, "real card-scoped watcher");
            }
            return card;
        }
        Card instant() {
            Card card = new RaiseTheAlarm(owner.getId(), new CardSetInfo("Raise the Alarm", "MRD", "16", Rarity.COMMON));
            hand(card); return card;
        }
        void hand(Card card) {
            hand(card, owner);
        }
        void hand(Card card, MobileHumanPlayer player) {
            game.loadCards(new HashSet<>(List.of(card)), player.getId());
            card.setZone(Zone.HAND, game); player.getHand().add(card);
        }
        void cast(Card card, Zone zone, int cost) {
            int before = owner.getManaPool().getMana().count();
            owner.getManaPool().addMana(new Mana(10, 0, 0, 0, 0, 0, 0, 0), game, card.getSpellAbility());
            SpellAbility ability = zone == Zone.COMMAND ? (SpellAbility) card.getSpellAbility().copyWithZone(zone) : card.getSpellAbility();
            check(owner.cast(ability, game, false, null), "upstream paid cast");
            eq(before + 10 - owner.getManaPool().getMana().count(), cost);
        }
        void returnToCommand(Card card) {
            check(game.getPermanent(card.getId()).moveToZone(Zone.COMMAND, null, game, true), "real command-zone return");
        }
        void damage(Card card, int amount, boolean combat) {
            eq(opponent.damage(amount, card.getId(), null, game, combat, true), amount);
        }
        Map<String,Object> snapshot(String seat) {
            // Exercise the actual canonical wire codec, which sorts object keys but preserves arrays.
            return Json.parseObject(Json.write(ViewProjector.project(game, seats).get(seat)));
        }
        void stats(Card card, int casts, int tax, Map<String,Integer> damage) {
            Map<String,Object> expected = Json.map("ownerPlayerId", owner.getId().toString(),
                    "name", "Isamaru, Hound of Konda", "castsFromCommandZone", casts, "commanderTax", tax, "damageToPlayers", damage);
            for (String seat : seats.keySet())
                eq(Json.write(Json.object(snapshot(seat).get("commanders")).get(card.getId().toString())), Json.write(expected));
        }
        void outcome(boolean ended, List<String> winners) {
            for (String seat : seats.keySet())
                eq(snapshot(seat).get("outcome"), Json.map("ended", ended, "winnerPlayerIds", winners));
        }
        public void close() { seats.values().forEach(MobileHumanPlayer::closeChannel); }
    }
    private static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
    private static void eq(Object actual, Object expected) {
        if (!Objects.equals(actual, expected)) throw new AssertionError("Expected " + expected + ", got " + actual);
    }
}
