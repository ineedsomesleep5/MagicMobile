package io.magicmobile.core;

/** Stable machine-readable errors; never silently route to a mock engine. */
public final class BridgeException extends RuntimeException {
    private static final long serialVersionUID=1L;
    private final String code;
    public BridgeException(String code, String message) { super(message); this.code = code; }
    public String code() { return code; }
}
