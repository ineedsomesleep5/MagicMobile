import io.magicmobile.core.Json;
import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;
import java.util.stream.*;

/** Build-time native metadata diagnostic. Never changes the full static card factory inventory. */
public final class NativeReflectionExporter {
    private static final Map<String,Map<String,Object>> entries=new TreeMap<>();
    private static final Set<Type> seenTypes=new HashSet<>();
    private static final Set<String> dtoTypes=new TreeSet<>();

    public static void main(String[] args) throws Exception {
        if(args.length<2) throw new IllegalArgumentException("OUTPUT_DIR CLASSES_DIR...");
        Set<String> names=new TreeSet<>();
        for(int i=1;i<args.length;i++) {
            Path root=Path.of(args[i]);
            try(Stream<Path> paths=Files.walk(root)) {
                paths.filter(p->p.toString().endsWith(".class")).forEach(p->{
                    String name=root.relativize(p).toString().replace(java.io.File.separatorChar,'.');
                    if(name.startsWith("mage.")) names.add(name.substring(0,name.length()-6));
                });
            }
        }
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
        Map<String,Object> report=Json.map("scope","experimental-reflection-metadata-not-native-compatibility-proof",
            "inventoryClasses",names.size(),"cardTypesInspected",cardClasses,"watcherTypes",watchers,
            "dynamicTokenPlaneEmblemTypes",dynamicObjects,"dtoTypes",new ArrayList<>(dtoTypes),
            "reflectionEntries",entries.size(),"staticCardRegistryChanged",false,
            "serverSessionRooted",false,"limitations",List.of("Runtime native tests still required",
                "Serialization and external-library native metadata remain separate gates"));
        Files.writeString(output.resolve("report.json"),Json.write(report)+"\n");
        System.out.println(Json.write(report));
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
