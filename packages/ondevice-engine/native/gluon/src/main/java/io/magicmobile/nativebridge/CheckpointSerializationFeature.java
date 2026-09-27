package io.magicmobile.nativebridge;

import java.io.Externalizable;
import java.io.InputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.ObjectStreamClass;
import java.io.Serializable;
import java.lang.invoke.MethodHandles;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
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
 * GraalVM 22.1's serialization configuration costs too much for the 48,723 checkpoint types:
 * it makes every declared constructor and method invocable (a compiled stub for each), and it
 * generates one serialization-constructor accessor class per class. Either exhausted the CI
 * builder. This feature registers, for each listed class and its Serializable superclasses, only
 * what ObjectStreamClass and ReflectionFactory use at run time:
 * <ul>
 * <li>the class, its serializable instance fields (non-static, non-transient; all instance fields
 * when it declares serialPersistentFields) and its serialVersionUID/serialPersistentFields;</li>
 * <li>the writeObject/readObject/readObjectNoData/writeReplace/readResolve hooks it declares;</li>
 * <li>as queried, the constructors of every direct superclass (the accessible-superclass-constructor
 * check), and the no-argument constructor serialization runs;</li>
 * <li>a serialization constructor accessor: for a concrete class whose first non-Serializable
 * superclass is Object, an instance of the one MobileCheckpointConstructorAccessor class (compiled
 * against java.base, defined here); otherwise GraalVM's own SerializationBuilder, as for a
 * configuration entry (abstract classes share its single stub accessor).</li>
 * </ul>
 * Default serialVersionUIDs are then computed from this metadata; a checkpoint is only read by the
 * build that wrote it. Reads the exporter's serialization-config.json from
 * -Dmagicmobile.checkpoint.serialization. A missing class fails the build; there is no fallback.
 */
public final class CheckpointSerializationFeature implements Feature {
    static final String PROPERTY = "magicmobile.checkpoint.serialization";
    static final String ACCESSOR_BYTES = "checkpoint-constructor-accessor.bin";
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
            Set<Class<?>> classes = new LinkedHashSet<>();
            for (String name : names) {
                Class<?> listed = access.findClassByName(name);
                if (listed == null) {
                    throw new IllegalStateException("Checkpoint serialization class not found: " + name);
                }
                for (Class<?> type = listed; type != null && Serializable.class.isAssignableFrom(type); type = type.getSuperclass()) {
                    if (type.getName().startsWith("java.awt.") || type.getName().startsWith("javax.swing.")) {
                        // The exporter leaves out desktop UI classes; AWT would pull X11 into the image.
                        throw new IllegalStateException("Desktop UI class in checkpoint serialization: " + listed.getName());
                    }
                    if (!classes.add(type)) {
                        break; // Its Serializable superclasses were added with it.
                    }
                }
            }
            // GraalVM's registries behind serialization configuration files.
            Object builder = ImageSingletons.lookup(singletonKey("org.graalvm.nativeimage.impl.RuntimeSerializationSupport"));
            Method generated = builder.getClass().getDeclaredMethod("addConstructorAccessor", Class.class, Class.class);
            generated.setAccessible(true);
            Object registry = ImageSingletons.lookup(singletonKey("com.oracle.svm.reflect.serialize.SerializationRegistry"));
            Method add = registry.getClass().getMethod("addConstructorAccessor", Class.class, Class.class, Object.class);
            Method allocating = allocatingAccessor();

            Set<Class<?>> superclasses = new LinkedHashSet<>();
            int shared = 0, own = 0, fields = 0, hooks = 0;
            for (Class<?> type : classes) {
                RuntimeReflection.register(type);
                if (type.isArray()) {
                    continue;
                }
                superclasses.add(type.getSuperclass());
                if (!Enum.class.isAssignableFrom(type)) {
                    Class<?> constructorClass;
                    if (!Modifier.isAbstract(type.getModifiers()) && !Externalizable.class.isAssignableFrom(type)
                                    && firstNonSerializableSuperclass(type) == Object.class) {
                        add.invoke(registry, type, Object.class, allocating.invoke(null, type));
                        constructorClass = Object.class;
                        shared++;
                    } else {
                        constructorClass = (Class<?>) generated.invoke(builder, type, null);
                        own++;
                    }
                    if (constructorClass != null) {
                        RuntimeReflection.register(constructorClass.getDeclaredConstructor());
                    }
                    if (Externalizable.class.isAssignableFrom(type)) {
                        RuntimeReflection.register(type.getConstructor());
                    }
                }
                for (Field field : serialFields(type)) {
                    RuntimeReflection.register(field);
                    fields++;
                }
                for (Method method : type.getDeclaredMethods()) {
                    if (isSerializationHook(method)) {
                        RuntimeReflection.register(method);
                        hooks++;
                    }
                }
            }
            for (Class<?> superclass : superclasses) {
                RuntimeReflection.registerAsQueried(superclass.getDeclaredConstructors());
            }
            // Mirrors GraalVM's own serialization registration.
            RuntimeReflection.register(ObjectStreamClass.class.getDeclaredMethod("computeDefaultSUID", Class.class));
            System.out.println("Checkpoint serialization: " + names.size() + " listed types, " + classes.size()
                            + " classes with Serializable superclasses, " + shared + " shared allocating accessors, "
                            + own + " GraalVM accessors, " + fields + " fields, " + hooks + " serialization hooks, "
                            + superclasses.size() + " superclasses with queried constructors");
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

    /** Defines MobileCheckpointConstructorAccessor in jdk.internal.reflect (needs --add-opens). */
    static Method allocatingAccessor() throws ReflectiveOperationException, java.io.IOException {
        byte[] bytes;
        try (InputStream in = CheckpointSerializationFeature.class.getResourceAsStream(ACCESSOR_BYTES)) {
            if (in == null) {
                throw new IllegalStateException("Missing compiled " + ACCESSOR_BYTES + " next to " + CheckpointSerializationFeature.class.getName());
            }
            bytes = in.readAllBytes();
        }
        Class<?> base = Class.forName("jdk.internal.reflect.SerializationConstructorAccessorImpl");
        Class<?> accessor = MethodHandles.privateLookupIn(base, MethodHandles.lookup()).defineClass(bytes);
        if (!base.isAssignableFrom(accessor) || !accessor.getName().equals("jdk.internal.reflect.MobileCheckpointConstructorAccessor")) {
            throw new IllegalStateException("Unexpected checkpoint accessor class " + accessor);
        }
        Method create = accessor.getDeclaredMethod("create", Class.class);
        create.setAccessible(true);
        return create;
    }

    static Class<?> firstNonSerializableSuperclass(Class<?> type) {
        Class<?> current = type;
        while (current != null && Serializable.class.isAssignableFrom(current)) {
            current = current.getSuperclass();
        }
        return current;
    }

    /** What ObjectStreamClass reads reflectively or through unsafe offsets; never other static fields. */
    static List<Field> serialFields(Class<?> type) {
        List<Field> result = new ArrayList<>();
        boolean persistent = false;
        for (Field field : type.getDeclaredFields()) {
            if (Modifier.isStatic(field.getModifiers())) {
                if (field.getName().equals("serialVersionUID") || field.getName().equals("serialPersistentFields")) {
                    result.add(field);
                    persistent |= field.getName().equals("serialPersistentFields");
                }
            } else if (!Modifier.isTransient(field.getModifiers())) {
                result.add(field);
            }
        }
        if (persistent) { // Persistent fields may name transient fields.
            for (Field field : type.getDeclaredFields()) {
                if (!Modifier.isStatic(field.getModifiers()) && Modifier.isTransient(field.getModifiers())) {
                    result.add(field);
                }
            }
        }
        return result;
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
    private static Class<Object> singletonKey(String name) throws ClassNotFoundException {
        return (Class<Object>) Class.forName(name);
    }
}
