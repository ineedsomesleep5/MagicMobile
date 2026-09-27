package jdk.internal.reflect;

/**
 * Native-image build input only, never on an application classpath. CheckpointSerializationFeature
 * compiles this against java.base and defines it in jdk.internal.reflect while the image is built,
 * because SerializationConstructorAccessorImpl is package-private.
 *
 * One instance per checkpoint class whose first non-Serializable superclass is java.lang.Object.
 * Java serialization would allocate the class and run Object(), which does nothing, so allocation
 * alone is the same object. GraalVM 22.1 otherwise generates one accessor class per class: 43,000
 * extra classes for the checkpoint types, which exhausted the 10 GB builder heap
 * (docs/NATIVE_METADATA.md). Classes with another non-Serializable superclass keep GraalVM's
 * generated accessor, which runs that constructor.
 */
final class MobileCheckpointConstructorAccessor extends SerializationConstructorAccessorImpl {
    private final Class<?> type;

    private MobileCheckpointConstructorAccessor(Class<?> type) {
        this.type = java.util.Objects.requireNonNull(type);
    }

    /**
     * Called reflectively by the feature. Not Constructor.newInstance: for ConstructorAccessorImpl
     * subclasses the JDK only allocates (BootstrapConstructorAccessorImpl) and never runs the
     * constructor, which would leave type null.
     */
    static MobileCheckpointConstructorAccessor create(Class<?> type) {
        return new MobileCheckpointConstructorAccessor(type);
    }

    @Override
    public Object newInstance(Object[] args) throws InstantiationException {
        if (args != null && args.length != 0) {
            throw new IllegalArgumentException("Serialization constructors take no arguments");
        }
        return jdk.internal.misc.Unsafe.getUnsafe().allocateInstance(type);
    }
}
