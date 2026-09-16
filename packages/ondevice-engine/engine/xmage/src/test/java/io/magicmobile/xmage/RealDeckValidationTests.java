package io.magicmobile.xmage;

import io.magicmobile.core.*;
import mage.cards.decks.*;
import mage.deck.Commander;
import java.util.*;

/** Pinned upstream validator and production loader; no native runtime or phone claims. */
public final class RealDeckValidationTests {
    public static void main(String[] args) {
        Commander validator=new Commander();
        if(validator.validate(new Deck())) throw new AssertionError("Empty deck unexpectedly valid");
        List<Object> expected=new ArrayList<>();
        for(DeckValidatorError issue:validator.getErrorsList()) {
            expected.add(Json.map("type",issue.getErrorType().name(),"group",issue.getGroup(),
                "message",issue.getMessage(),"cardName",issue.getCardName()));
        }
        try {
            DeckLoader.load(Json.map("main",List.of(),"commanders",List.of()));
            throw new AssertionError("Expected invalid deck");
        } catch(BridgeException failure) {
            if(!failure.code().equals("invalid_deck")) throw new AssertionError(failure);
            Object actual=Json.object(failure.envelope().get("details")).get("issues");
            if(!expected.equals(actual) || expected.isEmpty()) throw new AssertionError("Upstream issues changed: "+actual);
            EngineDiagnostics.captureIncident("validation",failure);
            String report=(String)EngineDiagnostics.read().get("report");
            if(!report.contains("Occurred:") || report.contains("  at ") || !report.contains(Json.write(expected)))
                throw new AssertionError("Expected timestamped issue report without Java stack");
            if(!report.equals(EngineDiagnostics.read().get("report"))) throw new AssertionError("Read changed incident");
        }
        System.out.println("PASS: exact pinned Commander issues and local stack-free incident");
    }
}
