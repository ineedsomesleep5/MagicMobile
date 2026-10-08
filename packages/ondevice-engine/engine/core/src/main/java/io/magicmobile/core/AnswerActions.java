package io.magicmobile.core;

import java.util.*;

/**
 * Optional standing instructions sent with an answer (docs/PROTOCOL.md, "Answer actions"). Each maps to an XMage
 * desktop player action that HumanPlayer already implements: remembered yes/no answers, a remembered trigger order,
 * passing until the stack resolves, and passing priority after casting. They change only how this seat answers its own
 * future questions; none decides a rule or answers for another player.
 *
 * Keys come from the pending prompt, never from the client: a remembered answer is stored under the prompt's own
 * {@code originalId} and {@code autoAnswerMessage} options, exactly as the desktop client would send them.
 */
public final class AnswerActions {
    public static final List<String> TYPES=List.of("rememberAnswer","rememberTriggerFirst","passUntilStackResolved",
        "resetRememberedAnswers","resetTriggerOrder","autoPassAfterCast");
    private static final int MAX_ACTIONS=TYPES.size();
    private AnswerActions() {}

    /** Validates client actions for this prompt and answer, and returns them normalized with engine-derived keys. */
    static List<Object> validate(DecisionSpec spec,String answerKind,Object answerValue,Object raw) {
        List<Object> actions=Json.array(raw);
        if(actions.isEmpty() || actions.size()>MAX_ACTIONS) reject("Answer actions must list 1 to "+MAX_ACTIONS+" actions");
        Set<String> seen=new HashSet<>();
        List<Object> out=new ArrayList<>();
        for(Object item:actions) {
            Map<String,Object> action=Json.object(item);
            String type=Json.requiredString(action,"type");
            if(!TYPES.contains(type)) reject("Unknown answer action: "+type);
            if(!seen.add(type)) reject("Duplicate answer action: "+type);
            switch(type) {
                case "rememberAnswer": {
                    only(action,"type","scope");
                    String scope=Json.requiredString(action,"scope");
                    if(!scope.equals("ability") && !scope.equals("text")) reject("rememberAnswer scope must be ability or text");
                    if(!spec.kind.equals("ASK") || !answerKind.equals("boolean")) reject("Only a yes/no answer can be remembered");
                    Map<String,Object> options=Json.object(spec.payload.get("options"));
                    Object message=options.get("autoAnswerMessage");
                    if(!(message instanceof String) || ((String)message).isEmpty() || ((String)message).length()>8192)
                        reject("This question cannot be remembered");
                    String key=(String)message;
                    if(scope.equals("ability")) {
                        Object original=options.get("originalId");
                        if(!(original instanceof String)) reject("This question has no source ability to remember");
                        try { UUID.fromString((String)original); } catch(IllegalArgumentException e) { reject("Malformed source ability"); }
                        key=original+"#"+key;
                    }
                    out.add(Json.map("type",type,"scope",scope,"key",key,"answer",Json.bool(answerValue)));
                    break;
                }
                case "rememberTriggerFirst":
                    only(action,"type");
                    if(!spec.kind.equals("PICK_ABILITY") || !answerKind.equals("uuid")) reject("Only a triggered ability choice can be remembered as first");
                    out.add(Json.map("type",type,"abilityId",Json.string(answerValue)));
                    break;
                case "passUntilStackResolved":
                    only(action,"type");
                    if(!spec.kind.equals("SELECT") || !"priority".equals(spec.payload.get("selectMode")) || !answerKind.equals("boolean"))
                        reject("Passing until the stack resolves needs a priority pass");
                    out.add(Json.map("type",type));
                    break;
                case "autoPassAfterCast":
                    only(action,"type","enabled");
                    out.add(Json.map("type",type,"enabled",Json.bool(action.get("enabled"))));
                    break;
                default: // the two resets
                    only(action,"type");
                    out.add(Json.map("type",type));
            }
        }
        // Resets apply before anything remembered in the same answer.
        out.sort(Comparator.comparingInt(a->Json.requiredString(Json.object(a),"type").startsWith("reset")?0:1));
        return out;
    }
    private static void only(Map<String,Object> action,String... keys) {
        if(!action.keySet().equals(Set.of(keys))) reject("Unexpected answer action fields");
    }
    private static void reject(String s) { throw new BridgeException("invalid_response",s); }
}
