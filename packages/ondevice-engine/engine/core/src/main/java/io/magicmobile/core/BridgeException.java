package io.magicmobile.core;

/** Stable machine-readable errors; never silently route to a mock engine. */
public final class BridgeException extends RuntimeException {
    private static final long serialVersionUID=1L;
    private final String code;
    private final transient java.util.Map<String,Object> details;
    public BridgeException(String code, String message) { this(code,message,null); }
    public BridgeException(String code, String message, java.util.Map<String,Object> details) {
        super(message); this.code = code; this.details = details;
    }
    public String code() { return code; }
    public java.util.Map<String,Object> envelope() {
        java.util.Map<String,Object> value=Json.map("code",code,"message",getMessage());
        if(details!=null) value.put("details",details);
        return value;
    }
}
