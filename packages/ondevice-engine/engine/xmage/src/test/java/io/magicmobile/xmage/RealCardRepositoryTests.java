package io.magicmobile.xmage;

import io.magicmobile.core.Json;
import mage.abilities.effects.common.ChooseACardNameEffect;
import mage.cards.Card;
import mage.cards.repository.*;
import mage.constants.CardType;
import mage.constants.Rarity;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;

/** Real catalogue/factory tests in a fresh working directory, not phone acceptance. */
public final class RealCardRepositoryTests {
    public static void main(String[] args) {
        check(!Files.exists(Path.of("db")), "test requires an isolated empty working directory");
        new XmageEngine("jvm");
        // This exact path previously initialized an empty desktop database and threw.
        Set<String> all = ChooseACardNameEffect.TypeOfName.ALL.makeChoiceObject().getChoices();
        check(all.size() > 30000, "full pinned card-name inventory");
        for (String name : List.of("Pithing Needle", "Brain Pry", "Fire", "Ice", "Insectile Aberration"))
            check(all.contains(name), "name available: " + name);
        check(CardRepository.instance.getLandNames().contains("Island"), "land names");
        check(!CardRepository.instance.getNonLandNames().contains("Island"), "nonland exclusion");
        check(!CardRepository.instance.getNotBasicLandNames().contains("Island"), "basic exclusion");
        check(CardRepository.instance.getArtifactNames().contains("Pithing Needle"), "artifact names");
        check(CardRepository.instance.getCreatureNames().contains("Silvercoat Lion"), "creature names");
        all.clear();
        check(CardRepository.instance.getNames().contains("Pithing Needle"), "choice mutation cannot corrupt catalogue");
        for (String name : List.of("Pithing Needle", "Brain Pry")) {
            CardInfo info = CardRepository.instance.findCard(name);
            check(info != null, "metadata exists: " + name);
            Card card = info.createCard();
            check(card != null && card.getName().equals(name), "real card factory: " + name);
        }
        CardInfo needle = CardRepository.instance.findCard("pItHiNg NeEdLe", true);
        check(needle != null && needle.getName().equals("Pithing Needle"), "H2 case-insensitive names retained");
        check(CardRepository.instance.findCard(needle.getSetCode().toLowerCase(), needle.getCardNumber()) != null,
                "case-insensitive printing lookup");
        CardInfo split = CardRepository.instance.findCardWithPreferredSetAndNumber("Fire", null, null);
        check(split != null && split.isSplitCard() && split.getName().equals("Fire // Ice"), "split half resolves full card");
        CardInfo half = CardRepository.instance.findCardWithPreferredSetAndNumber("Fire", split.getSetCode(), split.getCardNumber(), true);
        check(half != null && half.isSplitCardHalf() && half.getName().equals("Fire"), "explicit split-half metadata");
        check(!CardRepository.instance.findCards("Bala Ged Recovery // Bala Ged Sanctuary").isEmpty(), "MDFC combined-name lookup");
        check(!CardRepository.instance.findCards("Insectile Aberration").isEmpty(), "transform face lookup");
        List<CardInfo> islands = CardRepository.instance.findCards(new CardCriteria().name("island").types(CardType.LAND));
        check(!islands.isEmpty() && islands.stream().allMatch(card -> card.getName().equals("Island")), "real criteria query");
        CardInfo copy = islands.get(0);
        copy.setTypes(List.of(CardType.ARTIFACT));
        check(CardRepository.instance.findCards(new CardCriteria().name("Island").types(CardType.LAND)).size() == islands.size(),
                "query mutation cannot corrupt bundled metadata");
        check(ExpansionRepository.instance.getSetByCode(needle.getSetCode()) != null, "expansion lookup without H2");
        check(!ExpansionRepository.instance.getAll().isEmpty(), "expansion inventory");
        check(CardRepository.instance.findCards(new CardCriteria().rarities(Rarity.MYTHIC).count(3L)).size() == 3,
                "rarity and pagination");
        // Large but bounded naming prompts must still fit the existing wire JSON limit.
        Set<String> names = CardRepository.instance.getNames();
        java.util.Map<String, String> choices = new java.util.LinkedHashMap<>();
        names.forEach(name -> choices.put(name, name));
        String encoded = Json.write(Json.map("choices", choices, "choiceOrder", new java.util.ArrayList<>(names)));
        check(encoded.length() < Json.MAX_TEXT, "complete naming choices fit existing wire bound");
        check(!Files.exists(Path.of("db")), "mobile catalogue never created a desktop database");
        System.out.println("PASS real card-name choices, split/faced lookups, factories, filters and immutable data; names=" + names.size());
    }
    private static void check(boolean value, String message) {if (!value) throw new AssertionError(message);}
}
