package io.magicmobile.xmage;

import io.magicmobile.core.*;
import java.nio.file.*;
import java.util.*;

/** Full generated cards + actual Commander validator; no simulated validator. */
public final class RealStandaloneValidationLifecycleTests {
    public static void main(String[] args) throws Exception {
        Map<String,Object> config=Json.parseObject(Files.readString(Path.of(args[0])));
        Map<String,Object> deck=Json.object(Json.object(Json.array(config.get("seats")).get(0)).get("deck"));
        String original=Json.write(deck);
        XmageEngine engine=new XmageEngine("jvm");
        for(int i=0;i<3;i++) {
            Map<String,Object> result=engine.validateDeck(deck);
            if(!Boolean.TRUE.equals(result.get("valid")) || !"Commander".equals(result.get("validator"))
                || !Json.array(result.get("issues")).isEmpty() || !original.equals(Json.write(deck)))
                throw new AssertionError("Valid standalone check mutated the input or lost its receipt");
        }
        String match=Json.requiredString(engine.create(config),"matchId");
        try { engine.validateDeck(deck);throw new AssertionError("Validation entered an active game"); }
        catch(BridgeException expected) { if(!"engine_busy".equals(expected.code())) throw expected; }
        boolean destroyed=false;
        for(int i=0;i<30 && !destroyed;i++) {
            try { engine.destroy(match);destroyed=true; }
            catch(BridgeException pending) {
                if(!"engine_busy_shutdown".equals(pending.code())) throw pending;
                Thread.sleep(100);
            }
        }
        if(!destroyed) throw new AssertionError("Game failed to quiesce after validation");
        if(!Boolean.TRUE.equals(engine.validateDeck(deck).get("valid"))) throw new AssertionError("Validation after game cleanup failed");
        engine.close();
        try { engine.validateDeck(deck);throw new AssertionError("Closed validator accepted a request"); }
        catch(BridgeException expected) { if(!"engine_closed".equals(expected.code())) throw expected; }
        System.out.println("PASS: real valid-deck receipts, no mutation, active-game exclusion, repeated validation, game cleanup and closed rejection");
    }
}
