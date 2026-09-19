package io.magicmobile.xmage;

import io.magicmobile.core.*;
import mage.cards.decks.*;
import mage.deck.Commander;
import java.util.*;

/** Actual upstream validator and production loader; no native-runtime or phone claim. */
public final class RealDeckValidationTests {
    public static void main(String[] args) {
        Commander validator=new Commander();
        if(validator.validate(new Deck())) throw new AssertionError("Empty deck unexpectedly valid");
        List<Object> expected=new ArrayList<>();
        for(DeckValidatorError issue:validator.getErrorsList()) {
            expected.add(Json.map("type",issue.getErrorType().name(),"group",issue.getGroup(),
                "message",issue.getMessage(),"cardName",issue.getCardName()));
        }
        Map<String,Object> empty=Json.map("main",List.of(),"commanders",List.of());
        try {
            DeckLoader.load(empty);
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
        try(EngineService service=new EngineService(new XmageEngine("jvm"))) {
            for(int attempt=0;attempt<2;attempt++) {
                Map<String,Object> response=Json.parseObject(service.request(Json.write(Json.map("protocol",1,"op","validateDeck","deck",empty))));
                if(!Boolean.FALSE.equals(response.get("ok"))) throw new AssertionError("Empty deck cannot validate");
                Map<String,Object> error=Json.object(response.get("error"));
                if(!"invalid_deck".equals(error.get("code")) || !expected.equals(Json.object(error.get("details")).get("issues")))
                    throw new AssertionError("Standalone validation must preserve exact upstream errors");
            }
            Map<String,Object> bad=Json.parseObject(service.request(Json.write(Json.map("protocol",1,"op","validateDeck","deck",empty,"viewerId","peer"))));
            if(!"invalid_request".equals(Json.object(bad.get("error")).get("code"))) throw new AssertionError("Unexpected fields accepted");
        }
        System.out.println("PASS: exact pinned Commander issues, repeated standalone validation, strict schema and local incident");
    }
}
