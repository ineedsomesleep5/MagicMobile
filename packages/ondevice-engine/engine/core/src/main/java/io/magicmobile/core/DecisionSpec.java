package io.magicmobile.core;

import java.util.*;

/** An immutable description of an XMage decision, not a second rules implementation. */
public final class DecisionSpec {
    public final String kind;
    public final Map<String,Object> payload;
    private final Set<String> types;
    private final Set<String> allowedUUIDs;
    private final Set<String> allowedStrings;
    private final long min, max;
    private final List<long[]> allocations;

    public DecisionSpec(String kind, Map<String,Object> payload, Set<String> types,
                        Set<String> allowedUUIDs, Set<String> allowedStrings,
                        long min, long max, List<long[]> allocations) {
        this.kind=Objects.requireNonNull(kind);
        this.payload=Json.object(Json.freeze(payload));
        this.types=Collections.unmodifiableSet(new HashSet<>(types));
        this.allowedUUIDs=allowedUUIDs==null ? null : Set.copyOf(allowedUUIDs);
        this.allowedStrings=allowedStrings==null ? null : Set.copyOf(allowedStrings);
        this.min=min; this.max=max;
        this.allocations=new ArrayList<>();
        if(allocations!=null) for(long[] bounds:allocations) this.allocations.add(bounds.clone());
    }
    public Map<String,Object> describe() {
        return Json.map("kind",kind,"payload",payload,"responseTypes",new ArrayList<>(new TreeSet<>(types)),
                "min",min,"max",max);
    }
    public Map<String,Object> validate(Map<String,Object> answer) {
        if(!answer.keySet().equals(Set.of("kind","value"))) reject("Expected exactly kind and value");
        String type=Json.requiredString(answer,"kind"); Object value=answer.get("value");
        if(!types.contains(type)) reject("Response type is not accepted by this prompt: "+type);
        switch(type) {
            case "boolean": Json.bool(value); break;
            case "uuid": {
                String id=Json.string(value);
                try { if(!UUID.fromString(id).toString().equalsIgnoreCase(id)) reject("Noncanonical UUID"); }
                catch(IllegalArgumentException ex) { reject("Invalid UUID"); }
                if(allowedUUIDs!=null && !allowedUUIDs.contains(id)) reject("Object is not a candidate");
                break;
            }
            case "string": {
                if(value==null) {
                    if(!kind.equals("CHOOSE_CHOICE") || !Boolean.TRUE.equals(payload.get("specialEnabled"))
                            || !Boolean.TRUE.equals(payload.get("specialCanBeEmpty"))) reject("This prompt does not accept an empty special choice");
                    break;
                }
                String s=Json.string(value);
                if(s.length()>8192) reject("Response string too long");
                if(allowedStrings!=null && !allowedStrings.contains(s)) reject("Choice is not a candidate");
                break;
            }
            case "integer": {
                long n=Json.integer(value);
                if(n<min || n>max || n<Integer.MIN_VALUE || n>Integer.MAX_VALUE) reject("Amount out of range");
                break;
            }
            case "mana": {
                Map<String,Object> mana=Json.object(value);
                if(!mana.keySet().equals(Set.of("playerId","manaType"))) reject("Malformed mana response");
                UUID.fromString(Json.requiredString(mana,"playerId"));
                if(!Set.of("WHITE","BLUE","BLACK","RED","GREEN","COLORLESS","GENERIC").contains(Json.requiredString(mana,"manaType"))) reject("Unknown mana type");
                break;
            }
            case "integers": {
                List<Object> values=Json.array(value);
                if(values.size()!=allocations.size()) reject("Allocation count mismatch");
                long total=0;
                for(int i=0;i<values.size();i++) {
                    long n=Json.integer(values.get(i)); long[] b=allocations.get(i);
                    if(n<b[0] || n>b[1] || n<Integer.MIN_VALUE || n>Integer.MAX_VALUE) reject("Allocation out of range");
                    try { total=Math.addExact(total,n); } catch(ArithmeticException ex) { reject("Allocation overflow"); }
                }
                if(total<min || total>max) reject("Allocation total out of range");
                break;
            }
            default: reject("Unimplemented response encoder: "+type);
        }
        return Json.object(Json.freeze(answer));
    }
    private static void reject(String s) { throw new BridgeException("invalid_response",s); }
}
