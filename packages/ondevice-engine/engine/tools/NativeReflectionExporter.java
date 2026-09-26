import io.magicmobile.core.Json;
import java.io.Serializable;
import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;
import java.util.stream.*;

/**
 * Build-time native metadata. Never changes the full static card factory inventory.
 *
 * NativeReflectionExporter OUTPUT_DIR CLASSES_DIR... [--serialization EXTRA_CLASSES_DIR...]
 *
 * reflect-config.json: targeted reflection for the CLASSES_DIRs (unchanged scope).
 * serialization-config.json: every Serializable class of the CLASSES_DIRs and EXTRA dirs in the
 * packages save/resume checkpoints accept, plus the JDK types io.magicmobile.xmage.Checkpoints
 * allows, so a native image can write and read any game state (docs/PROTOCOL.md).
 */
public final class NativeReflectionExporter {
    private static final Map<String,Map<String,Object>> entries=new TreeMap<>();
    private static final Set<Type> seenTypes=new HashSet<>();
    private static final Set<String> dtoTypes=new TreeSet<>();
    private static final String[] CHECKPOINT_PACKAGES={"mage.","io.magicmobile.xmage."};

    public static void main(String[] args) throws Exception {
        List<String> arguments=new ArrayList<>(Arrays.asList(args));
        List<String> extra=new ArrayList<>();
        int split=arguments.indexOf("--serialization");
        if(split>=0) { extra.addAll(arguments.subList(split+1,arguments.size()));arguments=arguments.subList(0,split); }
        if(arguments.size()<2) throw new IllegalArgumentException("OUTPUT_DIR CLASSES_DIR... [--serialization CLASSES_DIR...]");
        Set<String> names=new TreeSet<>();
        for(String root:arguments.subList(1,arguments.size())) names.addAll(classNames(Path.of(root),"mage."));
        ClassLoader loader=NativeReflectionExporter.class.getClassLoader();
        Class<?> watcher=Class.forName("mage.watchers.Watcher",false,loader);
        Class<?> cardView=Class.forName("mage.view.CardView",false,loader);
        Class<?> commandView=Class.forName("mage.view.CommandObjectView",false,loader);
        Class<?> token=Class.forName("mage.game.permanent.token.Token",false,loader);
        Class<?> plane=Class.forName("mage.game.command.Plane",false,loader);
        Class<?> emblem=Class.forName("mage.game.command.Emblem",false,loader);
        int watchers=0,dynamicObjects=0,cardClasses=0;
        Class<?> card=Class.forName("mage.cards.Card",false,loader);
        for(String name:names) {
            // Linkage failures must remain fatal; no missing-class filtering.
            Class<?> type=Class.forName(name,false,loader);
            if(card.isAssignableFrom(type))cardClasses++;
            if(watcher.isAssignableFrom(type)) {
                watchers++;
                for(Class<?> c=type;c!=null && c.getName().startsWith("mage.");c=c.getSuperclass())
                    entry(c).put("allDeclaredFields",true);
                if(!Modifier.isAbstract(type.getModifiers()))entry(type).put("allDeclaredConstructors",true);
            }
            if(!type.isInterface() && !Modifier.isAbstract(type.getModifiers())
                    && (token.isAssignableFrom(type)||plane.isAssignableFrom(type)||emblem.isAssignableFrom(type))) {
                dynamicObjects++;entry(type).put("allDeclaredConstructors",true);
            }
            // Include runtime DTO subclasses as well as their declared generic field graph.
            if(cardView.isAssignableFrom(type)||commandView.isAssignableFrom(type))visit(type);
        }
        for(String root:List.of("mage.view.GameView","mage.view.AbilityPickerView"))
            visit(Class.forName(root,false,loader));
        // Bundled immutable metadata is decoded and defensively copied, never exposed as game state.
        Class<?> metadata=Class.forName("mage.cards.repository.CardInfo",false,loader);
        visit(metadata);entry(metadata).put("methods",List.of(Json.map("name","<init>","parameterTypes",List.of())));
        if(entries.containsKey("mage.remote.SessionImpl") || entries.containsKey("mage.game.GameState"))
            throw new IllegalStateException("Client DTO graph unexpectedly roots server/private engine state");
        if(cardClasses<30000 || watchers==0 || dynamicObjects==0)
            throw new IllegalStateException("Expected the full pinned upstream inventory");
        Path output=Path.of(args[0]);Files.createDirectories(output);
        Files.writeString(output.resolve("reflect-config.json"),Json.write(new ArrayList<>(entries.values()))+"\n");
        // Without --serialization (diagnostic probes) no serialization metadata is produced.
        Map<String,Object> serialization=split<0?null:serialization(arguments.subList(1,arguments.size()),extra,loader,output);
        Map<String,Object> report=Json.map("scope","experimental-reflection-metadata-not-native-compatibility-proof",
            "inventoryClasses",names.size(),"cardTypesInspected",cardClasses,"watcherTypes",watchers,
            "dynamicTokenPlaneEmblemTypes",dynamicObjects,"dtoTypes",new ArrayList<>(dtoTypes),
            "reflectionEntries",entries.size(),"staticCardRegistryChanged",false,
            "serverSessionRooted",false,"serialization",serialization,"limitations",List.of("Runtime native tests still required",
                "Serialization metadata covers checkpoint classes; external-library metadata remains a separate gate"));
        Files.writeString(output.resolve("report.json"),Json.write(report)+"\n");
        System.out.println(Json.write(report));
    }

    /**
     * Save/resume streams may hold any Serializable engine, card, ability, effect, watcher, filter,
     * target or token class, so every one is registered (not only those one game used). The JDK
     * list is the checkpoint allowlist itself. Serializable lambdas (upstream Condition method
     * references) are registered through their capturing classes; proxies are refused by the
     * checkpoint writer, so none are registered. Uses the object form with "types" and
     * "lambdaCapturingTypes" that GraalVM 21.3+ (including the pinned 22.1) parses.
     */
    private static Map<String,Object> serialization(List<String> roots,List<String> extra,ClassLoader loader,Path output) throws Exception {
        Set<String> names=new TreeSet<>();
        for(String root:roots) for(String prefix:CHECKPOINT_PACKAGES) names.addAll(classNames(Path.of(root),prefix));
        for(String root:extra) for(String prefix:CHECKPOINT_PACKAGES) names.addAll(classNames(Path.of(root),prefix));
        Method jdk=Class.forName("io.magicmobile.xmage.Checkpoints",false,loader).getDeclaredMethod("jdkTypes");
        jdk.setAccessible(true);
        @SuppressWarnings("unchecked") Set<String> jdkTypes=new TreeSet<>((Set<String>)jdk.invoke(null));
        Set<String> types=new TreeSet<>(),arrays=new TreeSet<>();
        int concrete=0,withoutUid=0,members=0;Set<String> lambdaHosts=new TreeSet<>();
        for(String name:names) {
            Class<?> type=Class.forName(name,false,loader);
            Method[] methods=type.getDeclaredMethods();
            for(Method method:methods) if(method.getName().equals("$deserializeLambda$")) lambdaHosts.add(name);
            if(type.isInterface() || type.isSynthetic() || !Serializable.class.isAssignableFrom(type)) continue;
            types.add(name);
            if(!Modifier.isAbstract(type.getModifiers())) concrete++;
            boolean uid=false;
            for(Field field:type.getDeclaredFields()) {
                if(field.getName().equals("serialVersionUID") && Modifier.isStatic(field.getModifiers())) uid=true;
                if(!Modifier.isStatic(field.getModifiers()) && !Modifier.isTransient(field.getModifiers()) && field.getType().isArray())
                    arrays.add(field.getType().getName());
                members++;
            }
            members+=type.getDeclaredConstructors().length+methods.length;
            if(!uid) withoutUid++;
        }
        for(String name:new ArrayList<>(jdkTypes)) {
            Class<?> type=Class.forName(name,false,loader); // A missing JDK type must fail the build.
            // Object[] and Map.Entry[] are only pre-checked by JDK collections; they never have stream classes.
            if(type==Object.class || type.isInterface()) { jdkTypes.remove(name);continue; }
            if(!Serializable.class.isAssignableFrom(type)) throw new IllegalStateException("Not serializable: "+name);
        }
        // Array streams need the array class itself (Object[] from Arrays$ArrayList and CollSer,
        // Segment[] from ConcurrentHashMap).
        arrays.addAll(List.of("[Ljava.lang.Object;","[Ljava.util.concurrent.ConcurrentHashMap$Segment;"));
        int engineClasses=types.size();
        types.addAll(jdkTypes);
        List<Object> registered=new ArrayList<>(),capturing=new ArrayList<>();
        for(String name:types) registered.add(Json.map("name",name));
        for(String name:arrays) registered.add(Json.map("name",name));
        for(String name:lambdaHosts) capturing.add(Json.map("name",name));
        Files.writeString(output.resolve("serialization-config.json"),
            Json.write(Json.map("types",registered,"lambdaCapturingTypes",capturing))+"\n");
        if(concrete<30000 || !types.contains("io.magicmobile.xmage.Checkpoints$Payload")
                || !types.contains("io.magicmobile.xmage.MobileHumanPlayer") || !types.contains("mage.player.ai.ComputerPlayer7")
                || !lambdaHosts.contains("io.magicmobile.xmage.Checkpoints"))
            throw new IllegalStateException("Serialization inventory is missing checkpoint classes; pass the plugin and engine class directories");
        return Json.map("entries",registered.size(),"engineClasses",engineClasses,"concreteEngineClasses",concrete,
            "jdkTypes",jdkTypes.size(),"arrayTypes",arrays.size(),"classesWithoutSerialVersionUID",withoutUid,
            "declaredMembersOfRegisteredEngineClasses",members,"lambdaCapturingTypes",new ArrayList<>(lambdaHosts),"proxies",0);
    }
    private static Set<String> classNames(Path root,String prefix) throws Exception {
        Set<String> names=new TreeSet<>();
        try(Stream<Path> paths=Files.walk(root)) {
            paths.filter(p->p.toString().endsWith(".class")).forEach(p->{
                String name=root.relativize(p).toString().replace(java.io.File.separatorChar,'.');
                if(name.startsWith(prefix) && !name.equals("module-info.class")) names.add(name.substring(0,name.length()-6));
            });
        }
        return names;
    }

    private static Map<String,Object> entry(Class<?> type) {
        return entries.computeIfAbsent(type.getName(),name->Json.map("name",name));
    }
    private static void visit(Type type) {
        if(type==null || !seenTypes.add(type))return;
        if(type instanceof ParameterizedType) {
            ParameterizedType p=(ParameterizedType)type;visit(p.getRawType());
            for(Type t:p.getActualTypeArguments())visit(t);
        } else if(type instanceof GenericArrayType) {
            visit(((GenericArrayType)type).getGenericComponentType());
        } else if(type instanceof WildcardType) {
            for(Type t:((WildcardType)type).getUpperBounds())visit(t);
        } else if(type instanceof TypeVariable<?>) {
            for(Type t:((TypeVariable<?>)type).getBounds())visit(t);
        } else if(type instanceof Class<?>) {
            Class<?> c=(Class<?>)type;
            if(c.isArray()){visit(c.getComponentType());return;}
            if(!c.getName().startsWith("mage."))return; // Gson's standard JDK adapters own those types.
            dtoTypes.add(c.getName());entry(c).put("allDeclaredFields",true);
            visit(c.getGenericSuperclass());
            for(Type parent:c.getGenericInterfaces())visit(parent);
            if(!c.isEnum())for(Field field:c.getDeclaredFields())
                if(!Modifier.isStatic(field.getModifiers())&&!Modifier.isTransient(field.getModifiers()))
                    visit(field.getGenericType());
        }
    }
}
