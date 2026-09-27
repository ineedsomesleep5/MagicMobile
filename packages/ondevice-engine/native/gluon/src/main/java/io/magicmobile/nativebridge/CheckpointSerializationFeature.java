package io.magicmobile.nativebridge;

import java.io.Externalizable;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.ObjectStreamClass;
import java.io.Serializable;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.graalvm.nativeimage.ImageSingletons;
import org.graalvm.nativeimage.hosted.Feature;
import org.graalvm.nativeimage.hosted.RuntimeReflection;

/**
 * Build-time registration of the save/resume checkpoint classes (docs/NATIVE_METADATA.md).
 *
 * GraalVM 22.1's own serialization configuration also registers every declared constructor and
 * method of each class as reflectively invocable, and compiles an invocation stub for each: about
 * 290,000 for the 48,730 checkpoint types, which kept analysis running past the two-hour CI limit.
 * Java serialization needs much less, so this feature registers, for each listed class and its
 * Serializable superclasses, only what ObjectStreamClass and ReflectionFactory use at run time:
 * the class, its declared fields (default and persistent serial fields, serialVersionUID, unsafe
 * offsets), its declared constructors as queried (the accessible-superclass-constructor check),
 * the writeObject/readObject/readObjectNoData/writeReplace/readResolve hooks it declares as
 * invocable, and the serialization constructor accessor that GraalVM itself generates (through
 * its SerializationBuilder, as for a configuration entry). Default serialVersionUIDs are then
 * computed from this metadata; a checkpoint is only ever read by the build that wrote it.
 *
 * Reads the exporter's serialization-config.json from -Dmagicmobile.checkpoint.serialization.
 * A missing class fails the build; there is no fallback.
 */
public final class CheckpointSerializationFeature implements Feature {
    static final String PROPERTY = "magicmobile.checkpoint.serialization";
    private static final Pattern NAME = Pattern.compile("\"name\"\\s*:\\s*\"([^\"]+)\"");
    private static final Pattern TYPES = Pattern.compile("\"types\"\\s*:\\s*\\[");
    private static final Pattern EMPTY_LAMBDAS = Pattern.compile("\"lambdaCapturingTypes\"\\s*:\\s*\\[\\s*\\]");

    @Override
    public void beforeAnalysis(BeforeAnalysisAccess access) {
        String config = System.getProperty(PROPERTY, "");
        if (config.isEmpty()) {
            throw new IllegalStateException(PROPERTY + " must name the checkpoint serialization-config.json");
        }
        try {
            List<String> names = typeNames(Files.readString(Path.of(config)));
            // SerializationBuilder is GraalVM's registry behind serialization configuration files.
            Object builder = ImageSingletons.lookup(runtimeSerializationSupport());
            Method accessor = builder.getClass().getDeclaredMethod("addConstructorAccessor", Class.class, Class.class);
            accessor.setAccessible(true);
            Set<Class<?>> registered = new LinkedHashSet<>();
            int hooks = 0, fields = 0, accessors = 0;
            for (String name : names) {
                Class<?> listed = access.findClassByName(name);
                if (listed == null) {
                    throw new IllegalStateException("Checkpoint serialization class not found: " + name);
                }
                for (Class<?> type = listed; type != null && Serializable.class.isAssignableFrom(type); type = type.getSuperclass()) {
                    if (!registered.add(type)) {
                        break; // Its Serializable superclasses were registered with it.
                    }
                    RuntimeReflection.register(type);
                    if (type.isArray()) {
                        continue;
                    }
                    Class<?> constructorClass = (Class<?>) accessor.invoke(builder, type, null);
                    if (constructorClass != null) {
                        RuntimeReflection.register(constructorClass.getDeclaredConstructor());
                        accessors++;
                    }
                    if (Externalizable.class.isAssignableFrom(type) && !type.isInterface()) {
                        RuntimeReflection.register(type.getConstructor());
                    }
                    RuntimeReflection.registerAsQueried(type.getDeclaredConstructors());
                    RuntimeReflection.register(type.getDeclaredFields());
                    fields += type.getDeclaredFields().length;
                    for (Method method : type.getDeclaredMethods()) {
                        if (isSerializationHook(method)) {
                            RuntimeReflection.register(method);
                            hooks++;
                        }
                    }
                }
            }
            // Mirrors GraalVM's own serialization registration.
            RuntimeReflection.register(ObjectStreamClass.class.getDeclaredMethod("computeDefaultSUID", Class.class));
            System.out.println("Checkpoint serialization: " + names.size() + " listed types, " + registered.size()
                            + " classes with Serializable superclasses, " + accessors + " constructor accessors, "
                            + fields + " fields, " + hooks + " serialization hooks; no other methods registered");
        } catch (ReflectiveOperationException | java.io.IOException e) {
            throw new IllegalStateException("Checkpoint serialization registration failed", e);
        }
    }

    static List<String> typeNames(String json) {
        // With no lambda capturing types, every "name" in the exporter's file is a type entry.
        if (!EMPTY_LAMBDAS.matcher(json).find() || !TYPES.matcher(json).find()) {
            throw new IllegalStateException("Expected exporter serialization-config.json with an empty lambdaCapturingTypes");
        }
        List<String> names = new ArrayList<>();
        Matcher matcher = NAME.matcher(json);
        while (matcher.find()) {
            names.add(matcher.group(1));
        }
        return names;
    }

    private static boolean isSerializationHook(Method method) {
        List<Class<?>> parameters = Arrays.asList(method.getParameterTypes());
        switch (method.getName()) {
            case "writeObject":
                return parameters.equals(List.of(ObjectOutputStream.class));
            case "readObject":
                return parameters.equals(List.of(ObjectInputStream.class));
            case "readObjectNoData":
            case "writeReplace":
            case "readResolve":
                return parameters.isEmpty();
            default:
                return false;
        }
    }

    @SuppressWarnings("unchecked")
    private static Class<Object> runtimeSerializationSupport() throws ClassNotFoundException {
        return (Class<Object>) Class.forName("org.graalvm.nativeimage.impl.RuntimeSerializationSupport");
    }
}
