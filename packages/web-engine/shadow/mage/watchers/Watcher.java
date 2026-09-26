// SPIKE ONLY (web engine, CheerpJ). Web-only shadow of upstream XMage mage/watchers/Watcher.java
// at the pinned commit (MIT, magefree/mage). build_web.sh compiles it into magicmobile-engine.jar,
// which is first on the browser classpath, so it replaces the upstream class in the web bundle only.
// iOS, Android and the JVM baseline keep the upstream class.
//
// Why: CheerpJ 4.3's Java 17 runtime lacks the jdk.internal.misc.Unsafe
// get/put{Boolean,Byte,Short,Char,Float,Double}Volatile natives. JDK 17 core reflection uses them for
// every final field (UnsafeQualified*FieldAccessorImpl), and copy() reflects over final primitive
// fields on every game copy, so the first snapshot died with UnsatisfiedLinkError. Implementing the
// natives in JavaScript does not work either: they must call back into Java, and CheerpJ rejects
// that re-entry ("Java code still running"). A cached method-handle version also still reached
// getBooleanVolatile (not isolated whether through the handles or a failed-handle fallback).
// Only copy() differs from upstream: same constructor rule, same fields, same deep copy, but field
// values move through sun.misc.Unsafe's plain accessors (cached offsets per watcher class). Falls
// back to upstream reflection if Unsafe is unavailable.
package mage.watchers;

import mage.constants.WatcherScope;
import mage.game.Game;
import mage.game.events.GameEvent;
import mage.util.CardUtil;
import org.apache.log4j.Logger;

import java.io.Serializable;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * watches for certain game events to occur and flags condition
 *
 * @author BetaSteward_at_googlemail.com
 */
public abstract class Watcher implements Serializable {

    private static final Logger logger = Logger.getLogger(Watcher.class);

    protected UUID controllerId;
    protected UUID sourceId;
    protected boolean condition;
    protected final WatcherScope scope;

    public Watcher(WatcherScope scope) {
        this.scope = scope;
    }

    protected Watcher(final Watcher watcher) {
        this.condition = watcher.condition;
        this.controllerId = watcher.controllerId;
        this.sourceId = watcher.sourceId;
        this.scope = watcher.scope;
    }

    public UUID getControllerId() {
        return controllerId;
    }

    public void setControllerId(UUID controllerId) {
        this.controllerId = controllerId;
    }

    public UUID getSourceId() {
        return sourceId;
    }

    public void setSourceId(UUID sourceId) {
        this.sourceId = sourceId;
    }

    public String getKey() {
        switch (scope) {
            case GAME:
                return getBasicKey();
            case PLAYER:
                return controllerId + getBasicKey();
            case CARD:
                return sourceId + getBasicKey();
            default:
                throw new IllegalArgumentException("Unknown watcher scope: " + this.getClass().getSimpleName() + " - " + scope);
        }
    }

    public boolean conditionMet() {
        return condition;
    }

    public void reset() {
        condition = false;
    }

    protected String getBasicKey() {
        return getClass().getSimpleName();
    }

    public abstract void watch(GameEvent event, Game game);

    /** Per watcher class: constructor arguments, and field offsets with their JVM type letter. */
    private static final class CopyPlan {
        final Constructor<?> constructor;
        final Object[] args;
        final long[] offsets;
        final char[] kinds;

        CopyPlan(Constructor<?> constructor, Object[] args, long[] offsets, char[] kinds) {
            this.constructor = constructor;
            this.args = args;
            this.offsets = offsets;
            this.kinds = kinds;
        }
    }

    private static final Map<Class<?>, CopyPlan> COPY_PLANS = new ConcurrentHashMap<>();
    private static final sun.misc.Unsafe UNSAFE = loadUnsafe();

    private static sun.misc.Unsafe loadUnsafe() {
        try {
            Field theUnsafe = sun.misc.Unsafe.class.getDeclaredField("theUnsafe");
            theUnsafe.setAccessible(true);
            return (sun.misc.Unsafe) theUnsafe.get(null);
        } catch (ReflectiveOperationException | RuntimeException | LinkageError e) {
            System.err.println("[web-shadow] Watcher.copy: sun.misc.Unsafe unavailable, using reflection: " + e);
            return null;
        }
    }

    private static Object[] constructorArgs(Constructor<?> constructor) {
        Object[] args = new Object[constructor.getParameterCount()];
        for (int index = 0; index < constructor.getParameterTypes().length; index++) {
            Class<?> parameterType = constructor.getParameterTypes()[index];
            if (parameterType.isPrimitive()) {
                if (parameterType.getSimpleName().equalsIgnoreCase("boolean")) {
                    args[index] = false;
                }
            } else {
                args[index] = null;
            }
        }
        return args;
    }

    private static List<Field> copiedFields(Class<?> type) {
        List<Field> allFields = new ArrayList<>();
        allFields.addAll(Arrays.asList(type.getDeclaredFields()));
        allFields.addAll(Arrays.asList(type.getSuperclass().getDeclaredFields()));
        List<Field> copied = new ArrayList<>();
        for (Field field : allFields) {
            if (!Modifier.isStatic(field.getModifiers())) {
                field.setAccessible(true);
                copied.add(field);
            }
        }
        return copied;
    }

    private static char kind(Class<?> type) {
        if (!type.isPrimitive()) return 'L';
        if (type == boolean.class) return 'Z';
        if (type == byte.class) return 'B';
        if (type == short.class) return 'S';
        if (type == char.class) return 'C';
        if (type == int.class) return 'I';
        if (type == long.class) return 'J';
        if (type == float.class) return 'F';
        return 'D';
    }

    private static CopyPlan plan(Class<?> type, Constructor<?> constructor) {
        return COPY_PLANS.computeIfAbsent(type, key -> {
            if (UNSAFE == null) return new CopyPlan(constructor, constructorArgs(constructor), null, null);
            try {
                List<Field> fields = copiedFields(key);
                long[] offsets = new long[fields.size()];
                char[] kinds = new char[fields.size()];
                for (int i = 0; i < fields.size(); i++) {
                    offsets[i] = UNSAFE.objectFieldOffset(fields.get(i));
                    kinds[i] = kind(fields.get(i).getType());
                }
                return new CopyPlan(constructor, constructorArgs(constructor), offsets, kinds);
            } catch (RuntimeException e) {
                System.err.println("[web-shadow] Watcher.copy: no field offsets for " + key.getName() + ", using reflection: " + e);
                return new CopyPlan(constructor, constructorArgs(constructor), null, null);
            }
        });
    }

    private static void copyField(Object from, Object to, long offset, char kind) {
        sun.misc.Unsafe u = UNSAFE;
        switch (kind) {
            case 'Z': u.putBoolean(to, offset, u.getBoolean(from, offset)); break;
            case 'B': u.putByte(to, offset, u.getByte(from, offset)); break;
            case 'S': u.putShort(to, offset, u.getShort(from, offset)); break;
            case 'C': u.putChar(to, offset, u.getChar(from, offset)); break;
            case 'I': u.putInt(to, offset, u.getInt(from, offset)); break;
            case 'J': u.putLong(to, offset, u.getLong(from, offset)); break;
            case 'F': u.putFloat(to, offset, u.getFloat(from, offset)); break;
            case 'D': u.putDouble(to, offset, u.getDouble(from, offset)); break;
            default: u.putObject(to, offset, CardUtil.deepCopyObject(u.getObject(from, offset)));
        }
    }

    public <T extends Watcher> T copy() {
        try {
            //use getDeclaredConstructors to allow for package-private constructors (i.e. omit public)
            List<?> constructors = Arrays.asList(this.getClass().getDeclaredConstructors());
            if (constructors.size() > 1) {
                logger.error(getClass().getSimpleName() + " has multiple constructors");
                return null;
            }

            Constructor<? extends Watcher> constructor = (Constructor<? extends Watcher>) constructors.get(0);
            constructor.setAccessible(true);
            CopyPlan plan = plan(getClass(), constructor);
            T watcher = (T) plan.constructor.newInstance(plan.args.clone());
            if (plan.offsets != null) {
                for (int i = 0; i < plan.offsets.length; i++) {
                    copyField(this, watcher, plan.offsets[i], plan.kinds[i]);
                }
                return watcher;
            }
            // upstream path (hits the missing natives for final primitive fields under CheerpJ)
            for (Field field : copiedFields(getClass())) {
                field.set(watcher, CardUtil.deepCopyObject(field.get(this)));
            }
            return watcher;
        } catch (InstantiationException | IllegalAccessException | InvocationTargetException e) {
            logger.error("Can't copy watcher: " + e.getMessage(), e);
        }
        return null;
    }

    public WatcherScope getScope() {
        return scope;
    }
}
