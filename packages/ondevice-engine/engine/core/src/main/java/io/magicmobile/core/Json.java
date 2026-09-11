package io.magicmobile.core;

import java.math.BigDecimal;
import java.util.*;

/** Small, strict JSON codec for the C/Swift boundary. No reflection or serialization. */
public final class Json {
    public static final int MAX_TEXT = 4 * 1024 * 1024;
    private static final int MAX_DEPTH = 64;
    private Json() {}

    public static Object parse(String text) {
        if (text == null || text.length() > MAX_TEXT) fail("JSON exceeds size limit or is null");
        Parser p = new Parser(text);
        Object v = p.value(0);
        p.ws();
        if (p.i != text.length()) fail("Trailing JSON content");
        return v;
    }
    public static Map<String,Object> parseObject(String text) { return object(parse(text)); }
    @SuppressWarnings("unchecked")
    public static Map<String,Object> object(Object v) {
        if (!(v instanceof Map)) throw new BridgeException("invalid_json", "Expected object");
        Map<?,?> map = (Map<?,?>) v;
        if (map.keySet().stream().anyMatch(k -> !(k instanceof String))) fail("Non-string object key");
        return (Map<String,Object>) map;
    }
    @SuppressWarnings("unchecked")
    public static List<Object> array(Object v) {
        if (!(v instanceof List)) throw new BridgeException("invalid_json", "Expected array");
        return (List<Object>) v;
    }
    public static String string(Object v) {
        if (!(v instanceof String)) throw new BridgeException("invalid_json", "Expected string");
        return (String) v;
    }
    public static long integer(Object v) {
        if (v instanceof Long || v instanceof Integer) return ((Number)v).longValue();
        if (v instanceof BigDecimal) try { return ((BigDecimal)v).longValueExact(); }
        catch (ArithmeticException e) { throw new BridgeException("invalid_json", "Integer out of range"); }
        throw new BridgeException("invalid_json", "Expected integer");
    }
    public static boolean bool(Object v) {
        if (!(v instanceof Boolean)) throw new BridgeException("invalid_json", "Expected boolean");
        return (Boolean) v;
    }
    public static String requiredString(Map<String,Object> v, String key) { return string(v.get(key)); }
    public static String optionalString(Map<String,Object> v, String key, String fallback) {
        return v.containsKey(key) ? string(v.get(key)) : fallback;
    }
    public static void onlyKeys(Map<String,Object> object, Set<String> allowed) {
        if (!allowed.containsAll(object.keySet()))
            throw new BridgeException("invalid_request", "Unexpected object fields");
    }
    public static Map<String,Object> map(Object... pairs) {
        if (pairs.length % 2 != 0) throw new IllegalArgumentException("Odd key/value count");
        Map<String,Object> m = new LinkedHashMap<>();
        for (int i=0; i<pairs.length; i+=2) {
            String key = string(pairs[i]);
            if (m.containsKey(key)) throw new IllegalArgumentException("Duplicate key: " + key);
            m.put(key, pairs[i+1]);
        }
        return m;
    }
    public static Object freeze(Object value) { return freeze(value,0); }
    private static Object freeze(Object value,int depth) {
        if(depth>MAX_DEPTH) fail("JSON nesting too deep");
        if (value instanceof Map) {
            Map<String,Object> out = new LinkedHashMap<>();
            object(value).forEach((k,v) -> out.put(k, freeze(v,depth+1)));
            return Collections.unmodifiableMap(out);
        }
        if (value instanceof List) {
            List<Object> out = new ArrayList<>();
            for (Object v : array(value)) out.add(freeze(v,depth+1));
            return Collections.unmodifiableList(out);
        }
        if (value == null || value instanceof String || value instanceof Boolean
                || value instanceof Integer || value instanceof Long || value instanceof BigDecimal) return value;
        throw new BridgeException("invalid_json", "Non-JSON value: " + value.getClass().getName());
    }
    public static String write(Object value) {
        StringBuilder b = new StringBuilder();
        append(b, value, 0);
        if (b.length() > MAX_TEXT) fail("JSON exceeds size limit");
        return b.toString();
    }
    private static void append(StringBuilder b, Object v, int depth) {
        if (depth > MAX_DEPTH) fail("JSON nesting too deep");
        if (v == null) b.append("null");
        else if (v instanceof String) quote(b, (String)v);
        else if (v instanceof Boolean || v instanceof Integer || v instanceof Long || v instanceof BigDecimal) b.append(v);
        else if (v instanceof Map) {
            b.append('{'); boolean first = true;
            // Canonical key order makes command idempotency independent of input key order.
            for (String k : new TreeSet<>(object(v).keySet())) {
                if (!first) b.append(','); first = false;
                quote(b,k); b.append(':'); append(b,object(v).get(k),depth+1);
            }
            b.append('}');
        } else if (v instanceof List) {
            b.append('['); boolean first = true;
            for (Object x : array(v)) { if (!first) b.append(','); first=false; append(b,x,depth+1); }
            b.append(']');
        } else fail("Unsupported JSON value: " + v.getClass().getName());
    }
    private static void quote(StringBuilder b, String s) {
        validateUnicode(s);
        b.append('"');
        for (int i=0;i<s.length();i++) {
            char c=s.charAt(i);
            switch(c) {
                case '"': b.append("\\\""); break;
                case '\\': b.append("\\\\"); break;
                case '\b': b.append("\\b"); break;
                case '\f': b.append("\\f"); break;
                case '\n': b.append("\\n"); break;
                case '\r': b.append("\\r"); break;
                case '\t': b.append("\\t"); break;
                default:
                    if (c<32) b.append(String.format(Locale.ROOT,"\\u%04x",(int)c));
                    else b.append(c);
            }
        }
        b.append('"');
    }
    private static void validateUnicode(String s) {
        for (int i=0;i<s.length();i++) {
            char c=s.charAt(i);
            if (Character.isHighSurrogate(c)) {
                if (++i>=s.length() || !Character.isLowSurrogate(s.charAt(i))) fail("Unpaired surrogate");
            } else if (Character.isLowSurrogate(c)) fail("Unpaired surrogate");
        }
    }
    private static void fail(String s) { throw new BridgeException("invalid_json",s); }
    private static final class Parser {
        final String s; int i;
        Parser(String s) { this.s=s; }
        void ws() { while(i<s.length() && " \n\r\t".indexOf(s.charAt(i))>=0) i++; }
        boolean take(char c) { ws(); if(i<s.length() && s.charAt(i)==c) { i++; return true; } return false; }
        void require(char c) { if(!take(c)) fail("Expected '"+c+"' at "+i); }
        Object value(int d) {
            ws(); if(d>MAX_DEPTH || i>=s.length()) { fail("Invalid or deeply nested JSON"); }
            char c=s.charAt(i);
            if(c=='"') return str();
            if(c=='{') {
                i++; Map<String,Object> m=new LinkedHashMap<>();
                if(take('}')) return m;
                do {
                    ws(); if(i>=s.length() || s.charAt(i)!='"') fail("Expected object key");
                    String k=str(); if(m.containsKey(k)) fail("Duplicate object key: "+k);
                    require(':'); m.put(k,value(d+1));
                } while(take(','));
                require('}'); return m;
            }
            if(c=='[') {
                i++; List<Object> a=new ArrayList<>(); if(take(']')) return a;
                do { a.add(value(d+1)); } while(take(',')); require(']'); return a;
            }
            if(s.startsWith("true",i)) { i+=4; return true; }
            if(s.startsWith("false",i)) { i+=5; return false; }
            if(s.startsWith("null",i)) { i+=4; return null; }
            return number();
        }
        String str() {
            require('"'); StringBuilder b=new StringBuilder(); boolean ended=false;
            while(i<s.length()) {
                char c=s.charAt(i++);
                if(c=='"') { ended=true; break; }
                if(c<32) fail("Unescaped control character");
                if(c!='\\') { b.append(c); continue; }
                if(i>=s.length()) fail("Unfinished escape");
                c=s.charAt(i++);
                switch(c) {
                    case '"': case '\\': case '/': b.append(c); break;
                    case 'b': b.append('\b'); break; case 'f': b.append('\f'); break;
                    case 'n': b.append('\n'); break; case 'r': b.append('\r'); break; case 't': b.append('\t'); break;
                    case 'u':
                        if(i+4>s.length()) fail("Short Unicode escape");
                        for(int j=i;j<i+4;j++) {
                            char h=s.charAt(j);
                            if(!((h>='0'&&h<='9')||(h>='a'&&h<='f')||(h>='A'&&h<='F'))) fail("Bad Unicode escape");
                        }
                        try { b.append((char)Integer.parseInt(s.substring(i,i+4),16)); }
                        catch(NumberFormatException e) { fail("Bad Unicode escape"); }
                        i+=4; break;
                    default: fail("Unknown escape");
                }
            }
            if(!ended) fail("Unclosed string");
            String out=b.toString(); validateUnicode(out); return out;
        }
        Object number() {
            int start=i;
            if(i<s.length() && s.charAt(i)=='-') i++;
            if(i>=s.length()) fail("Missing number");
            if(s.charAt(i)=='0') i++;
            else {
                if(s.charAt(i)<'1' || s.charAt(i)>'9') fail("Bad number");
                while(i<s.length() && digit(s.charAt(i))) i++;
            }
            boolean decimal=false;
            if(i<s.length() && s.charAt(i)=='.') {
                decimal=true; i++; int j=i;
                while(i<s.length() && digit(s.charAt(i))) i++;
                if(j==i) fail("Missing fractional digits");
            }
            if(i<s.length() && (s.charAt(i)=='e' || s.charAt(i)=='E')) {
                decimal=true; i++;
                if(i<s.length() && (s.charAt(i)=='+' || s.charAt(i)=='-')) i++;
                int j=i; while(i<s.length() && digit(s.charAt(i))) i++;
                if(j==i) fail("Missing exponent");
            }
            if(i-start>128) fail("Number too long");
            try {
                String n=s.substring(start,i);
                return decimal ? new BigDecimal(n) : Long.valueOf(n);
            } catch(NumberFormatException e) { fail("Invalid or out-of-range number"); return null; }
        }
        boolean digit(char c) { return c>='0' && c<='9'; }
    }
}
